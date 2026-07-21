provider "vultr" {
  # Reads var.vultr_api_key, or the VULTR_API_KEY environment variable when null.
  api_key = var.vultr_api_key
}

locals {
  is_country = var.deploy_scope == "country"

  # Auto-size/label from deploy_scope unless the caller passes an explicit
  # override — hostname/instance_plan stay nullable for exactly this.
  effective_hostname = coalesce(
    var.hostname,
    local.is_country ? "flckd-us" : "flckd-${lower(coalesce(var.state_code, "state"))}",
  )

  effective_instance_plan = coalesce(
    var.instance_plan,
    local.is_country ? "vhp-8c-16gb-amd" : "vc2-4c-8gb",
  )

  # The whole-US Nominatim import (250-350 GB) needs the dedicated NVMe block
  # volume; a single state's substrate (a few hundred MB-GB) fits the bundled
  # disk on the smaller "state" plan (docs/runbooks/cheap-deploy.md), so the
  # volume — and the boot-time mount script that wires it up — only apply to
  # deploy_scope = "country".
  use_block_storage = local.is_country
}

# SSH key injected for root. bootstrap-host.sh later creates the non-root deploy
# user that Kamal uses.
resource "vultr_ssh_key" "deploy" {
  name    = "${local.effective_hostname}-deploy"
  ssh_key = var.ssh_public_key
}

# Firewall: SSH is restricted to admin/CI CIDRs; 80/443 are open for the
# Kamal-proxy / Caddy edge (ACME + app traffic). No other ports are exposed —
# every geo accessory binds to 127.0.0.1 (see backend/config/deploy.yml).
resource "vultr_firewall_group" "flckd" {
  description = "flckd ${var.deploy_scope} host (${local.effective_hostname})"
}

resource "vultr_firewall_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  firewall_group_id = vultr_firewall_group.flckd.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = split("/", each.value)[0]
  subnet_size       = tonumber(split("/", each.value)[1])
  port              = "22"
  notes             = "SSH (admin/CI)"
}

resource "vultr_firewall_rule" "http" {
  firewall_group_id = vultr_firewall_group.flckd.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
  notes             = "HTTP (ACME challenge + https redirect)"
}

resource "vultr_firewall_rule" "https" {
  firewall_group_id = vultr_firewall_group.flckd.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
  notes             = "HTTPS"
}

# Boot-time script. Vultr attaches exactly ONE startup script per instance, so we
# assemble every boot-time concern into a single script here:
#   1. mount-docker-volume.sh — format + mount the NVMe block volume and point
#      Docker's data-root at it BEFORE Docker is installed, so the whole-US
#      Nominatim import (250-350 GB) lands on the big NVMe, not the small bundled
#      disk.
#   2. harden-host.sh — OS-level hardening (sshd key-only, fail2ban, unattended
#      security upgrades, sysctl) complementing the Vultr firewall group. Gated by
#      var.enable_hardening.
#
# Each phase is wrapped in a `( … )` subshell so its `set -euo pipefail`/`exit`
# is isolated and one phase's failure cannot abort the others. Both scripts are
# idempotent (boot scripts re-run every boot) and never destroy existing data.
# Provider requires the script base64-encoded.
locals {
  boot_phases = compact([
    local.use_block_storage ? file("${path.module}/scripts/mount-docker-volume.sh") : "",
    var.enable_hardening ? file("${path.module}/scripts/harden-host.sh") : "",
  ])

  boot_script = join("\n", concat(
    [
      "#!/usr/bin/env bash",
      "# Assembled by Terraform (infra/terraform/main.tf). Do not edit on the host.",
      "set +e",
    ],
    flatten([for phase in local.boot_phases : ["(", phase, ")"]]),
  ))
}

resource "vultr_startup_script" "boot" {
  name   = "${local.effective_hostname}-boot"
  type   = "boot"
  script = base64encode(local.boot_script)
}

resource "vultr_instance" "flckd" {
  region            = var.region
  plan              = local.effective_instance_plan
  os_id             = var.os_id
  label             = local.effective_hostname
  hostname          = local.effective_hostname
  enable_ipv6       = true
  backups           = var.enable_backups
  ssh_key_ids       = [vultr_ssh_key.deploy.id]
  firewall_group_id = vultr_firewall_group.flckd.id
  script_id         = vultr_startup_script.boot.id

  lifecycle {
    precondition {
      condition     = var.deploy_scope != "state" || var.state_code != null
      error_message = "state_code is required when deploy_scope = \"state\" (e.g. state_code = \"IA\"). Set deploy_scope = \"country\" instead for a whole-US host."
    }
  }

  # NOTE: Vultr plan resizes are UPGRADE-ONLY and reboot the box. Upgrading a
  # country box to Option A is just instance_plan = "vhp-8c-32gb-amd" + apply
  # (see README). A state box that outgrows "vc2-4c-8gb" can override the same way.
}

# Country mode's defining piece: a dedicated NVMe block volume that becomes
# Docker's data-root, so images + every named volume (nominatim-data,
# routing-data, tiles-data, app Postgres) live on the big disk with zero
# deploy.yml edits. Not created for deploy_scope = "state" — a single state's
# geo substrate fits the bundled disk on the smaller plan.
resource "vultr_block_storage" "docker" {
  count = local.use_block_storage ? 1 : 0

  region               = var.region
  size_gb              = var.block_storage_gb
  label                = "${local.effective_hostname}-docker-data"
  block_type           = "high_perf" # NVMe. NEVER "storage_opt" (HDD) — IOPS matters.
  attached_to_instance = vultr_instance.flckd.id
}

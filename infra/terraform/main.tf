provider "vultr" {
  # Reads var.vultr_api_key, or the VULTR_API_KEY environment variable when null.
  api_key = var.vultr_api_key
}

# SSH key injected for root. bootstrap-host.sh later creates the non-root deploy
# user that Kamal uses.
resource "vultr_ssh_key" "deploy" {
  name    = "${var.hostname}-deploy"
  ssh_key = var.ssh_public_key
}

# Firewall: SSH is restricted to admin/CI CIDRs; 80/443 are open for the
# Kamal-proxy / Caddy edge (ACME + app traffic). No other ports are exposed —
# every geo accessory binds to 127.0.0.1 (see backend/config/deploy.yml).
resource "vultr_firewall_group" "flckd" {
  description = "flckd whole-US host"
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
    file("${path.module}/scripts/mount-docker-volume.sh"),
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
  name   = "${var.hostname}-boot"
  type   = "boot"
  script = base64encode(local.boot_script)
}

resource "vultr_instance" "flckd" {
  region            = var.region
  plan              = var.instance_plan
  os_id             = var.os_id
  label             = var.hostname
  hostname          = var.hostname
  enable_ipv6       = true
  backups           = var.enable_backups
  ssh_key_ids       = [vultr_ssh_key.deploy.id]
  firewall_group_id = vultr_firewall_group.flckd.id
  script_id         = vultr_startup_script.boot.id

  # NOTE: Vultr plan resizes are UPGRADE-ONLY and reboot the box. Upgrading to
  # Option A is just var.instance_plan = "vhp-8c-32gb-amd" + apply (see README).
}

# Option B's defining piece: a dedicated NVMe block volume that becomes Docker's
# data-root, so images + every named volume (nominatim-data, routing-data,
# tiles-data, app Postgres) live on the big disk with zero deploy.yml edits.
resource "vultr_block_storage" "docker" {
  region               = var.region
  size_gb              = var.block_storage_gb
  label                = "${var.hostname}-docker-data"
  block_type           = "high_perf" # NVMe. NEVER "storage_opt" (HDD) — IOPS matters.
  attached_to_instance = vultr_instance.flckd.id
}

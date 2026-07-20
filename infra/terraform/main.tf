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

# Boot-time script: format + mount the NVMe block volume and point Docker's
# data-root at it BEFORE Docker is installed, so the whole-US Nominatim import
# (250-350 GB) lands on the big NVMe instead of the small bundled disk. It is
# idempotent (boot scripts re-run every boot) and never reformats a volume that
# already holds data. Provider requires the script base64-encoded.
resource "vultr_startup_script" "mount_docker_volume" {
  name   = "${var.hostname}-mount-docker-volume"
  type   = "boot"
  script = base64encode(file("${path.module}/scripts/mount-docker-volume.sh"))
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
  script_id         = vultr_startup_script.mount_docker_volume.id

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

variable "vultr_api_key" {
  description = "Vultr API v2 personal access token. Prefer the VULTR_API_KEY env var over a file. Remember to add your IP to the API access-control list in the Vultr portal (Account -> API)."
  type        = string
  sensitive   = true
  default     = null # falls back to the VULTR_API_KEY environment variable
}

variable "region" {
  description = "Vultr region code. MUST be one that offers both High Performance NVMe compute AND NVMe block storage (e.g. ewr, ord, lax, atl). Verify on Vultr's pricing page."
  type        = string
  default     = "ewr"
}

variable "instance_plan" {
  description = <<-EOT
    Vultr plan ID.

    DEFAULT = Option B: 4 vCPU / 16 GB RAM High Performance (~320 GB bundled NVMe),
    ~$96/mo. Hits the 16 GB RAM floor; the separate NVMe block volume (below) carries
    the heavy geo data so we do not pay for a 32 GB tier just to get disk.

    VERIFY the exact plan ID and its bundled-disk size on Vultr's pricing page before
    apply — bundled disk varies by plan and region.

    Upgrade path -> Option A (32 GB single disk, ~$190/mo): set "vhp-8c-32gb-amd".
    See README.md "Upgrading to Option A".
  EOT
  type        = string
  default     = "vhp-4c-16gb-amd"
}

variable "os_id" {
  description = "Vultr OS ID for the host image. 1743 = Ubuntu 22.04 LTS x64 (matches the runbook's 'Ubuntu LTS'). Alternatives: 2136 = Ubuntu 24.04, 2104 = Debian 12. Confirm with `vultr-cli os list`."
  type        = number
  default     = 1743
}

variable "block_storage_gb" {
  description = "NVMe block volume size (GB) for Docker's data-root. 200 clears the ~350-400 GB whole-US import peak alongside the ~320 GB bundled disk. Always NVMe (high_perf), never HDD — the Nominatim import saturates IOPS."
  type        = number
  default     = 200

  validation {
    condition     = var.block_storage_gb >= 40
    error_message = "block_storage_gb must be >= 40 (Vultr NVMe block minimum; 200 recommended for whole-US)."
  }
}

variable "hostname" {
  description = "Instance label + hostname."
  type        = string
  default     = "flckd-us"
}

variable "ssh_public_key" {
  description = "SSH public key material (contents of e.g. ~/.ssh/id_ed25519.pub). Injected for root; the deploy user is created later by infra/scripts/bootstrap-host.sh."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach SSH (port 22). Lock to your admin + CI IPs. Example: [\"203.0.113.5/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Set ssh_allowed_cidrs to specific admin/CI CIDRs; refusing an empty list or 0.0.0.0/0 (open SSH)."
  }
}

variable "enable_backups" {
  description = "Vultr automatic INSTANCE backups. Off by default (runbook §4): back up the app Postgres, not the 350 GB Nominatim index — rebuild geo from CI. 'enabled' | 'disabled'."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["enabled", "disabled"], var.enable_backups)
    error_message = "enable_backups must be \"enabled\" or \"disabled\"."
  }
}

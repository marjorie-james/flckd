variable "vultr_api_key" {
  description = "Vultr API v2 personal access token. Prefer the VULTR_API_KEY env var over a file. Remember to add your IP to the API access-control list in the Vultr portal (Account -> API)."
  type        = string
  sensitive   = true
  default     = null # falls back to the VULTR_API_KEY environment variable
}

variable "region" {
  description = "Vultr region code. For deploy_scope = \"country\", MUST also offer NVMe block storage (e.g. ewr, ord, lax, atl). Verify on Vultr's pricing page."
  type        = string
  default     = "ewr"
}

variable "deploy_scope" {
  description = <<-EOT
    Provisioning profile for the box this config creates:

      "state"   (default) — a small single-state host sized to match
                 docs/runbooks/cheap-deploy.md (4 vCPU / 8 GB, bundled disk
                 only, no extra NVMe block volume — a state's geo substrate is
                 a few hundred MB to a few GB). Requires state_code.

      "country" — the whole-US host from docs/runbooks/vultr-whole-us.md
                 (8 vCPU / 16 GB High Performance + a dedicated 200 GB NVMe
                 block volume for the 250-350 GB Nominatim import).

    This variable only sizes/labels the VPS. What geo data actually gets BUILT
    on the box is a separate, later choice made via backend/.kamal/geo.env
    (GEO_REGION_URL/GEO_REGION_LABEL for a state, or GEO_COUNTRY for the whole
    country — see infra/scripts/deploy-scope-env.sh). Keep the two in sync: a
    "state"-sized box pointed at a whole-country geo.env will run out of disk
    and/or RAM during the Nominatim import.
  EOT
  type        = string
  default     = "state"

  validation {
    condition     = contains(["state", "country"], var.deploy_scope)
    error_message = "deploy_scope must be \"state\" or \"country\"."
  }
}

variable "state_code" {
  description = <<-EOT
    USPS 2-letter code of the US state this host is for (e.g. "IA"). Required
    when deploy_scope = "state" (ignored for "country"). Only sizes the
    hostname/label here — the state actually BUILT on the box is chosen
    separately via backend/.kamal/geo.env (GEO_REGION_URL/GEO_REGION_LABEL).
    Must match a code in infra/scripts/state-registry.sh, the single source of
    truth for supported states (not cross-checked by Terraform — verify
    against that file).
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.state_code == null || can(regex("^[A-Za-z]{2}$", var.state_code))
    error_message = "state_code must be a 2-letter USPS state code (e.g. \"IA\"), or left unset for deploy_scope = \"country\"."
  }
}

variable "instance_plan" {
  description = <<-EOT
    Vultr plan ID override. Leave unset (null) to size automatically from
    deploy_scope:

      "state"   -> "vc2-4c-8gb"      4 vCPU / 8 GB regular Cloud Compute —
                   docs/runbooks/cheap-deploy.md sizing for one state,
                   everything (app + Postgres + routing + geocoder + tiles)
                   co-located on the bundled disk.
      "country" -> "vhp-8c-16gb-amd" 8 vCPU / 16 GB High Performance (350 GB
                   bundled NVMe), $96/mo. The separate NVMe block volume
                   carries the heavy whole-US geo data so we don't pay for a
                   32 GB tier just to get disk.

    VERIFY the exact plan ID and its bundled-disk size on Vultr's pricing page
    before apply — bundled disk varies by plan and region.

    Country upgrade path -> Option A (32 GB single disk, ~$190/mo): set
    "vhp-8c-32gb-amd". See README.md "Upgrading to Option A". A big state (CA,
    TX, ...) that outgrows the state default can likewise just override this.
  EOT
  type        = string
  default     = null
}

variable "os_id" {
  description = "Vultr OS ID for the host image. 1743 = Ubuntu 22.04 LTS x64 (matches the runbook's 'Ubuntu LTS'). Alternatives: 2136 = Ubuntu 24.04, 2104 = Debian 12. Confirm with `vultr-cli os list`."
  type        = number
  default     = 1743
}

variable "block_storage_gb" {
  description = "NVMe block volume size (GB) for Docker's data-root. Only used when deploy_scope = \"country\" (a single state's substrate fits the bundled disk — see instance_plan). 200 clears the ~350-400 GB whole-US import peak alongside the ~320 GB bundled disk. Always NVMe (high_perf), never HDD — the Nominatim import saturates IOPS."
  type        = number
  default     = 200

  validation {
    condition     = var.block_storage_gb >= 40
    error_message = "block_storage_gb must be >= 40 (Vultr NVMe block minimum; 200 recommended for whole-US)."
  }
}

variable "hostname" {
  description = "Instance label + hostname override. Leave unset (null) to derive one from deploy_scope: \"flckd-<state_code lowercased>\" for a state box (e.g. \"flckd-ia\"), \"flckd-us\" for a country box."
  type        = string
  default     = null
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

variable "enable_hardening" {
  description = <<-EOT
    Fold infra/terraform/scripts/harden-host.sh into the boot startup script:
    sshd key-only auth (root stays reachable BY KEY for the bootstrap flow),
    fail2ban, unattended security upgrades, and sysctl network hardening. This
    COMPLEMENTS the Vultr firewall group; it does not enable a host firewall.
    Idempotent + boot-safe. Default true. Set false only to debug a bare host.
  EOT
  type        = bool
  default     = true
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

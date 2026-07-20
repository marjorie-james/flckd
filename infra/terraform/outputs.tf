output "instance_ip" {
  description = "Public IPv4 of the host. Point every <…_HOST> in backend/config/deploy.yml at this."
  value       = vultr_instance.flckd.main_ip
}

output "instance_id" {
  description = "Vultr instance id."
  value       = vultr_instance.flckd.id
}

output "deploy_scope" {
  description = "Resolved provisioning profile (\"state\" or \"country\") and, for a state box, the state it's labeled for."
  value       = local.is_country ? "country (whole-US)" : "state (${upper(coalesce(var.state_code, "?"))})"
}

output "block_volume_id" {
  description = "Vultr NVMe block volume id (Docker data-root). null for deploy_scope = \"state\" (no block volume is created)."
  value       = try(vultr_block_storage.docker[0].id, null)
}

output "ssh_root" {
  description = "Initial SSH (root). Then run infra/scripts/bootstrap-host.sh to create the deploy user."
  value       = "ssh root@${vultr_instance.flckd.main_ip}"
}

locals {
  next_steps_country = <<-EOT
    1. Reboot once if the block volume attached after first boot, so the boot
       script mounts it:  ssh root@${vultr_instance.flckd.main_ip} 'reboot'
       Verify:  ssh root@${vultr_instance.flckd.main_ip} 'docker info | grep "Docker Root Dir"'  (once Docker is installed)
       Expect:  /mnt/blockstore/docker
    2. Bootstrap the host (deploy user + Docker DNS):
         infra/scripts/bootstrap-host.sh deploy@${vultr_instance.flckd.main_ip}
    3. Point backend/config/deploy.yml <…_HOST> at ${vultr_instance.flckd.main_ip}, set
       backend/.kamal/geo.env to GEO_COUNTRY=us, then kamal setup (see
       docs/runbooks/vultr-whole-us.md §3 for whole-US tuning knobs).
  EOT

  next_steps_state = <<-EOT
    1. Bootstrap the host (deploy user + Docker DNS):
         infra/scripts/bootstrap-host.sh deploy@${vultr_instance.flckd.main_ip}
    2. Point backend/config/deploy.yml <…_HOST> at ${vultr_instance.flckd.main_ip}
       (docs/runbooks/cheap-deploy.md §2 — co-locate every role on this one box).
    3. Set backend/.kamal/geo.env so the box builds the ${upper(coalesce(var.state_code, "?"))}
       extract — GEO_REGION_URL/GEO_REGION_LABEL (infra/scripts/state-registry.sh
       has the Geofabrik slug + label for every state) — then kamal setup (see
       docs/runbooks/cheap-deploy.md).
  EOT
}

output "next_steps" {
  description = "Post-apply checklist."
  value       = local.is_country ? local.next_steps_country : local.next_steps_state
}

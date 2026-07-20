output "instance_ip" {
  description = "Public IPv4 of the host. Point every <…_HOST> in backend/config/deploy.yml at this."
  value       = vultr_instance.flckd.main_ip
}

output "instance_id" {
  description = "Vultr instance id."
  value       = vultr_instance.flckd.id
}

output "block_volume_id" {
  description = "Vultr NVMe block volume id (Docker data-root)."
  value       = vultr_block_storage.docker.id
}

output "ssh_root" {
  description = "Initial SSH (root). Then run infra/scripts/bootstrap-host.sh to create the deploy user."
  value       = "ssh root@${vultr_instance.flckd.main_ip}"
}

output "next_steps" {
  description = "Post-apply checklist."
  value       = <<-EOT
    1. Reboot once if the block volume attached after first boot, so the boot
       script mounts it:  ssh root@${vultr_instance.flckd.main_ip} 'reboot'
       Verify:  ssh root@${vultr_instance.flckd.main_ip} 'docker info | grep "Docker Root Dir"'  (once Docker is installed)
       Expect:  /mnt/blockstore/docker
    2. Bootstrap the host (deploy user + Docker DNS):
         infra/scripts/bootstrap-host.sh deploy@${vultr_instance.flckd.main_ip}
    3. Point backend/config/deploy.yml <…_HOST> at ${vultr_instance.flckd.main_ip}, then
       kamal setup (see docs/runbooks/vultr-whole-us.md §3 for whole-US tuning knobs).
  EOT
}

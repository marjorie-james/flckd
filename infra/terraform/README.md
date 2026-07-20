# Terraform — whole-US Vultr host (Option B)

Provisions the single Vultr host for the whole-US flckd deployment described in
[`docs/runbooks/vultr-whole-us.md`](../../docs/runbooks/vultr-whole-us.md), as
**Option B — 16 GB Cloud Compute + NVMe Block Storage (~$116/mo)**:

- a **4 vCPU / 16 GB RAM** High Performance instance (~320 GB bundled NVMe),
- a **200 GB NVMe block volume** that becomes Docker's `data-root`, so the heavy
  geo data (Nominatim ~250–350 GB during import, routing graph, tiles, app
  Postgres) lands on the big disk and never fills the small bundled one,
- a firewall (SSH locked to your CIDRs; 80/443 open for the Kamal-proxy edge),
- a boot script that formats + mounts the volume and points Docker at it.

Terraform provisions **infrastructure only**. Kamal deploys the app onto it, and
CI builds the geo artifacts — see the runbook.

## Prerequisites

- Terraform ≥ 1.5
- A Vultr **API v2** token: `export VULTR_API_KEY=...`
  (add your IP to the token's access-control list in the Vultr portal → Account → API)
- An SSH keypair

## Usage

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: ssh_public_key, ssh_allowed_cidrs, region

terraform init
terraform plan      # review before touching anything
terraform apply
```

After apply, follow the `next_steps` output:

1. **If the block volume attached after first boot, reboot once** so the boot
   script mounts it (it's idempotent):
   ```bash
   ssh root@<instance_ip> 'reboot'
   # later, once Docker is installed, verify the data-root moved:
   ssh root@<instance_ip> 'docker info | grep "Docker Root Dir"'   # → /mnt/blockstore/docker
   ```
2. **Bootstrap** the host (creates the deploy user + Docker DNS fix; merge-preserves
   the `data-root` this script set):
   ```bash
   ../scripts/bootstrap-host.sh deploy@<instance_ip>
   ```
3. Point `backend/config/deploy.yml` `<…_HOST>` at the IP and run `kamal setup`.
   Set the whole-US tuning knobs (`NOMINATIM_SHM=4gb`, `PLANETILER_XMX=16g`, …)
   from the runbook **before** the first geo import.

## Verify plan IDs before you buy

Vultr bundles NVMe by RAM tier and the bundled-disk size varies by plan/region.
Confirm the exact plan ID and its disk on Vultr's pricing page (or
`vultr-cli plans list`) before `apply`. Defaults here:

| Variable | Default | Meaning |
|---|---|---|
| `instance_plan` | `vhp-4c-16gb-amd` | Option B instance (16 GB) |
| `block_storage_gb` | `200` | NVMe block volume (Docker data-root) |
| `os_id` | `1743` | Ubuntu 22.04 LTS x64 |
| `region` | `ewr` | must offer HP NVMe **and** NVMe block storage |

## Upgrading to Option A (if the site starts to crap out)

Option B is the budget floor. If steady-state gets tight — the box is thrashing
under load, disk pressure returns, or the import keeps bumping the 16 GB RAM
ceiling — move to **Option A: one 32 GB single-disk instance (~$190/mo)** whose
bundled ~512 GB+ NVMe covers the whole footprint with headroom (more cores, more
build-spike room, no second volume to babysit).

It's a near one-line change, because the plan is a variable:

```hcl
# terraform.tfvars
instance_plan = "vhp-8c-32gb-amd"   # 32 GB / ~8 vCPU
```

```bash
terraform plan    # confirm it's an in-place update (resize), not a replace
terraform apply
```

Notes / gotchas:

- **Vultr plan resizes are upgrade-only and reboot the box.** Going 16 GB → 32 GB
  is a valid in-place upgrade; you cannot downsize back the same way.
- **Always `terraform plan` first.** If the plan shows a *replacement* (destroy +
  recreate) rather than an in-place resize, stop — a recreate wipes the instance.
  In that case do a manual Vultr resize (portal/`vultr-cli`) and reconcile state
  with `terraform apply -refresh-only`, or plan a rebuild + `kamal setup`.
- **The block volume can stay attached** as bonus disk on Option A (harmless — the
  boot script still just mounts it and keeps Docker's data-root there). If you want
  to drop it, detach and delete it deliberately in a *separate* step, only after
  confirming the 32 GB bundled disk has enough free space to hold the geo data —
  otherwise you reintroduce the exact disk-short failure Option B was avoiding.
- The one-time-spike trick still applies: you can provision Option A big for the
  hours-long import, then resize down is **not** available — so if cost matters,
  keep Option B and only jump to A when steady-state genuinely demands it.

## What this does NOT manage

- The deploy user, Docker install, app containers — that's `bootstrap-host.sh` + Kamal.
- Geo artifacts — built on free CI (`build-geo.yml`), never on the paid box.
- DNS records, backups of app Postgres — out of scope here (see the runbooks).

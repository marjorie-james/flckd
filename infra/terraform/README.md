# Terraform — flckd host (single state or whole-US)

Provisions the one Vultr host a self-hosted flckd production deploy needs.
One config, two sizing profiles via `deploy_scope`:

| `deploy_scope` | Default when | Sizing | Geo footprint | Runbook |
|---|---|---|---|---|
| `"state"` (**default**) | you're standing up one US state | 4 vCPU / 8 GB (`vc2-4c-8gb`), bundled disk only, no NVMe block volume | a few hundred MB–GB | [`docs/runbooks/cheap-deploy.md`](../../docs/runbooks/cheap-deploy.md) |
| `"country"` | you specifically want the whole US | 8 vCPU / 16 GB HP (`vhp-8c-16gb-amd`) + a 200 GB NVMe block volume | 250–350 GB (Nominatim import) | [`docs/runbooks/vultr-whole-us.md`](../../docs/runbooks/vultr-whole-us.md) |

Either way this config provisions:

- the compute instance (sized per the table above),
- a firewall (SSH locked to your CIDRs; 80/443 open for the Kamal-proxy edge),
- host hardening (sshd key-only, fail2ban, unattended upgrades, sysctl),
- for `"country"` only: a dedicated NVMe block volume that becomes Docker's
  `data-root`, plus the boot script that mounts it.

Terraform provisions **infrastructure only**. Kamal deploys the app onto it,
and CI builds the geo artifacts — see the linked runbook for your scope.

**`deploy_scope` only sizes/labels the box.** What geo data actually gets
*built* there is chosen separately, on the host, via
`backend/.kamal/geo.env` (`GEO_REGION_URL`/`GEO_REGION_LABEL` for a state, or
`GEO_COUNTRY=us` for the whole country — see
[`infra/scripts/deploy-scope-env.sh`](../scripts/deploy-scope-env.sh)). Keep
the two in sync: a `"state"`-sized box pointed at a whole-country `geo.env`
will run out of disk/RAM during the Nominatim import.

## Prerequisites

- Terraform ≥ 1.5
- A Vultr **API v2** token: `export VULTR_API_KEY=...`
  (add your IP to the token's access-control list in the Vultr portal → Account → API)
- An SSH keypair

## Usage — single state (default)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: ssh_public_key, ssh_allowed_cidrs, region, state_code

terraform init
terraform plan      # review before touching anything
terraform apply
```

`state_code` is the USPS 2-letter code (e.g. `"IA"`) — see
[`infra/scripts/state-registry.sh`](../scripts/state-registry.sh) for every
supported state and its Geofabrik slug. The hostname/label (`flckd-<code>`)
is derived automatically unless you set `hostname` explicitly.

## Usage — whole US

Set `deploy_scope = "country"` in `terraform.tfvars` (and drop `state_code` —
it's ignored for this scope):

```hcl
deploy_scope = "country"
```

then `terraform init && terraform plan && terraform apply` as above. See
[`docs/runbooks/vultr-whole-us.md`](../../docs/runbooks/vultr-whole-us.md) for
the full whole-US bring-up (tuning knobs, the multi-hour Nominatim import,
disk sizing).

## After apply, follow the `next_steps` output

It differs by scope, but broadly:

1. **Country scope only** — if the block volume attached after first boot,
   reboot once so the boot script mounts it (it's idempotent):
   ```bash
   ssh root@<instance_ip> 'reboot'
   # later, once Docker is installed, verify the data-root moved:
   ssh root@<instance_ip> 'docker info | grep "Docker Root Dir"'   # → /mnt/blockstore/docker
   ```
2. **Bootstrap** the host (creates the deploy user + Docker DNS fix; merge-preserves
   the `data-root` this script set, when present):
   ```bash
   ../scripts/bootstrap-host.sh deploy@<instance_ip>
   ```
3. Point `backend/config/deploy.yml` `<…_HOST>` at the IP, set
   `backend/.kamal/geo.env` for your scope (state: `GEO_REGION_URL`/
   `GEO_REGION_LABEL`; country: `GEO_COUNTRY=us` + the whole-US tuning knobs
   from the runbook), and run `kamal setup`.

## Verify plan IDs before you buy

Vultr bundles disk by plan/region and catalog IDs change over time. Confirm
the exact plan ID and its bundled-disk size on Vultr's pricing page (or
`vultr-cli plans list`) before `apply`. Defaults here:

| Variable | Default | Meaning |
|---|---|---|
| `deploy_scope` | `"state"` | `"state"` (small, one US state) or `"country"` (whole-US) |
| `state_code` | *(none — required for `"state"`)* | USPS 2-letter code, e.g. `"IA"` |
| `instance_plan` | `"vc2-4c-8gb"` (state) / `"vhp-8c-16gb-amd"` (country) | Vultr plan ID; override either scope's default |
| `block_storage_gb` | `200` | NVMe block volume (country scope only) |
| `os_id` | `1743` | Ubuntu 22.04 LTS x64 |
| `region` | `ewr` | for country scope, must offer HP NVMe **and** NVMe block storage |

## Upgrading a country box to Option A (if the site starts to crap out)

The country-scope default is the budget floor (Option B: 16 GB + block
volume). If steady-state gets tight — the box is thrashing under load, disk
pressure returns, or the import keeps bumping the 16 GB RAM ceiling — move to
**Option A: one 32 GB single-disk instance (~$190/mo)** whose bundled ~512 GB+
NVMe covers the whole footprint with headroom (more cores, more build-spike
room, no second volume to babysit).

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

A state box that outgrows its default (a big state like CA/TX) can likewise
just override `instance_plan` to something larger — no block volume needed
unless you also flip it to `deploy_scope = "country"`.

## What this does NOT manage

- The deploy user, Docker install, app containers — that's `bootstrap-host.sh` + Kamal.
- Geo artifacts — built on free CI (`build-geo.yml`) for a state, on-host for
  whole-US (`kamal setup` → `provision-geo-host.sh`; see the runbook).
- Which state/country actually gets built on the host — that's
  `backend/.kamal/geo.env`, a separate, later choice (see above).
- DNS records, backups of app Postgres — out of scope here (see the runbooks).

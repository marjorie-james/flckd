# Runbook: Provisioning production infrastructure

Everything in this repo is automated *up to the point where real machines,
secrets, and DNS are needed*. This is the one-time setup to stand those up so the
deploy workflows (`deploy.yml`, `deploy-geo.yml`) and the build pipeline
(`build-geo.yml`) actually run. Do it once; after that, deploys are push-button.

Anonymity reminder: every host below is **our own** infrastructure. Routing,
geocoding, and tiles run as private Kamal accessories — no user origin /
destination / route ever leaves this boundary (FR-012a).

## 1. Topology

Six roles. Co-locate freely to start (e.g. one big box runs everything); split as
load grows. Kamal addresses each by host.

| Role | Kamal name | Notes / sizing |
|------|-----------|----------------|
| Web (Puma+Thruster) | `web` / `<WEB_HOST_1>` | Small. Terminates TLS via Kamal proxy. |
| Jobs (Solid Queue) | `job` / `<JOB_HOST_1>` | Small; runs the refresh + staleness jobs. |
| Postgres + PostGIS | `postgres` / `<DB_HOST>` | The only stateful tier — back it up (see backups.md). |
| Routing (Valhalla) | `routing` / `<ROUTING_HOST>` | RAM/disk scale with region; Iowa is small, full-US large. |
| Geocoder (Nominatim) | `geocoder` / `<GEOCODER_HOST>` | Imports the OSM extract on first boot (slow); needs disk. |
| Tiles (go-pmtiles) | `tiles` / `<TILES_HOST>` | Modest; serves the `.pmtiles` file. |

## 2. Prerequisites (per host)

- **Docker** installed and running (Kamal drives Docker over SSH).
- **SSH access** for a single deploy key — the **public** key in each host's
  `~/.ssh/authorized_keys`; the **private** key goes to GitHub (step 5).
- **Outbound network** so hosts can pull images from your registry.
- **Container DNS that works.** Some providers (seen on Vultr) ship
  `/etc/resolv.conf` with an **IPv6-only upstream resolver** that Docker containers
  cannot reach. This breaks `kamal setup` in a maddening way: it fails with
  `target failed to become healthy`, the app looks perfectly fine, and only the
  kamal-proxy logs show the truth — `Healthcheck failed ... lookup <container> on
  [2001:…::6]:53: ... network is unreachable` (kamal-proxy can't resolve the app
  container because its DNS escapes to an unreachable upstream). Pin Docker to a
  reachable IPv4 resolver before the first setup — run the bootstrap script, or do
  it by hand:

  ```bash
  # automated (idempotent; restarts Docker only if it changed):
  infra/scripts/bootstrap-host.sh deploy@<HOST>

  # or by hand on the host (needs sudo):
  echo '{ "dns": ["1.1.1.1", "8.8.8.8"] }' | sudo tee /etc/docker/daemon.json
  sudo systemctl restart docker
  ```

  `infra/scripts/preflight-host.sh` (also run automatically by `bin/kamal-docker`
  before setup/deploy) detects this condition and points you here, so you don't
  burn a 30s health timeout chasing a ghost.
- **DNS**: an `A`/`AAAA` record for your API domain → the web host. Kamal's proxy
  obtains a Let's Encrypt cert for it automatically.
- A **container registry** you control (GHCR, Docker Hub, ECR, …) + a
  username/token that can push and pull.

## 3. Generate secrets

```bash
cd backend
# Rails credentials key (commit config/credentials.yml.enc, NEVER the key):
bin/rails credentials:edit   # creates config/master.key if missing
# Strong passwords (DATABASE_PASSWORD must equal POSTGRES_PASSWORD — same DB):
openssl rand -hex 32   # DATABASE_PASSWORD / POSTGRES_PASSWORD
openssl rand -hex 32   # NOMINATIM_PASSWORD
# A dedicated deploy SSH keypair:
ssh-keygen -t ed25519 -f kamal_deploy -C flckd-deploy   # add kamal_deploy.pub to hosts
```

## 4. Fill the deploy config

- Copy the tracked template to your real (gitignored) config, then edit *that*:
  ```bash
  cp backend/config/deploy.example.yml backend/config/deploy.yml
  ```
  `deploy.yml` is gitignored so your host IPs / API domain / registry path never
  get committed; `deploy.example.yml` stays the tracked template. Kamal reads
  `config/deploy.yml` by default.
- In `backend/config/deploy.yml`, replace every `<PLACEHOLDER>` —
  `<REGISTRY_HOST>`, `<WEB_HOST_1>`, `<JOB_HOST_1>`, `<API_DOMAIN>`, `<DB_HOST>`,
  `<ROUTING_HOST>`, `<GEOCODER_HOST>`, `<TILES_HOST>`.
- Create `backend/.kamal/secrets` from the template and fill it (it's gitignored;
  the `.example` is tracked):
  ```bash
  cp backend/.kamal/secrets.example backend/.kamal/secrets
  ```
  It supplies the `secret:` entries deploy.yml references: `RAILS_MASTER_KEY`,
  `DATABASE_PASSWORD`, `POSTGRES_PASSWORD`, `NOMINATIM_PASSWORD`,
  `KAMAL_REGISTRY_USERNAME`, `KAMAL_REGISTRY_PASSWORD`. It also carries
  `GEOCODER_REGION_STATE` + `GEOCODER_VIEWBOX`, but you do **not** fill those —
  `bin/kamal-docker` resolves them from the deploy scope (`backend/.kamal/geo.env`)
  into `.kamal/deploy-scope.env`, which the example reads automatically (empty for a
  whole-country deploy). These come from the wrapper, so deploying via plain
  `kamal deploy` (e.g. the `deploy.yml` GitHub Actions template) would not set them —
  use `bin/kamal-docker`.

## 5. Configure GitHub Actions (for the deploy workflows)

The workflows run deploys from CI, so the same secrets/vars live in GitHub.
**Settings → Secrets and variables → Actions.**

**Secrets** (used by `deploy.yml` and/or `deploy-geo.yml`):

| Secret | Used by | Value |
|--------|---------|-------|
| `SSH_PRIVATE_KEY` | both | the `kamal_deploy` private key from step 3 |
| `KAMAL_REGISTRY_PASSWORD` | app deploy | registry push/pull token |
| `RAILS_MASTER_KEY` | app deploy | contents of `config/master.key` |
| `DATABASE_PASSWORD` | app deploy | DB password (= `POSTGRES_PASSWORD`) |
| `POSTGRES_PASSWORD` | app deploy | Postgres password |
| `NOMINATIM_PASSWORD` | app deploy | geocoder DB password |

**Variables**:

`config/deploy.yml` is gitignored (no real hosts in git), so CI rebuilds it from
the tracked template `config/deploy.example.yml` via `backend/bin/render-deploy-yml`,
filling these variables in. Set them all (a single co-located box uses the same
`user@addr` for every `*_HOST`):

| Variable | Used by | Value |
|----------|---------|-------|
| `REGISTRY_HOST` | render | registry host, e.g. `ghcr.io` |
| `REGISTRY_NAMESPACE` | render | image namespace, e.g. your GitHub user/org |
| `API_DOMAIN` | render + app deploy smoke test | e.g. `api.flckd.example` |
| `WEB_HOST` / `JOB_HOST` / `DB_HOST` | render | `user@addr` of each role's host |
| `ROUTING_HOST` / `TILES_HOST` / `GEOCODER_HOST` | render + geo deploy | `user@addr` of each geo host |
| `ROUTING_DATA_PATH` / `TILES_DATA_PATH` / `GEOCODER_IMPORT_PATH` | geo deploy | on-host dir backing each accessory volume — see step 7 |

`render-deploy-yml` fails the deploy if any variable is unset or any `<PLACEHOLDER>`
survives, so a missing value is caught before Kamal runs. (Local deploys don't use
this — you copy the template and edit `config/deploy.yml` by hand; see step 4.)

Also set the GitHub **environment** named `production` (both deploy workflows use
it) and, optionally, add required reviewers there as a deploy gate.

## 6. First bring-up (in order)

```bash
cd backend
gem install kamal -v "~> 2.0"

# (a) App + DB + (empty) geo accessories. First run also installs the Kamal proxy.
kamal setup            # builds, pushes, boots web/job + all accessories

# (b) Database schema (structure.sql is loaded; PostGIS extension included):
kamal app exec 'bin/rails db:prepare'
```

The routing/tiles accessories are now up but **empty** — they have no graph/tiles
yet. Routing **fails soft** (the accessory generates a default `valhalla.json` and
stays up instead of crash-looping) until the substrate is provisioned. The
geocoder begins importing its OSM extract on first boot once the extract is in
place.

There are two ways to fill the substrate:

**Automated (single co-located box).** If you deploy with the `bin/kamal-docker`
wrapper, it runs `infra/scripts/provision-geo-host.sh` after a successful
`setup`/`deploy`. The script downloads the extract locally (Geofabrik throttles
datacenter IPs, so it does *not* rely on the host reaching Geofabrik), streams it
to the host, builds the routing graph + vector tiles **on the host** (native
amd64) straight into the accessory dirs, places the geocoder extract, and reboots
each accessory. It is **idempotent** — a no-op once each stage has completed
(tracked via build-completion markers + geocoder readiness) — so it is safe on
every deploy. Skip it with `GEO_PROVISION=skip`; run it standalone with
`infra/scripts/provision-geo-host.sh [user@host]`. See
[geo-provisioning.md](geo-provisioning.md) for the full rationale (why we build on
the host, download locally, etc.) and caveats.

The **deploy scope is independent of your local dev scope** (`infra/.region`): set
it in `backend/.kamal/geo.env` (gitignored; copy `geo.env.example`) or per
invocation, so you can develop against one state and deploy a different state or
the whole US:

```bash
GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf bin/kamal-docker deploy
GEO_COUNTRY=us bin/kamal-docker setup        # whole-US substrate
```

That scope also drives the deployed **app**: `bin/kamal-docker` writes the resolved state
into `backend/.kamal/deploy-scope.env`, which `.kamal/secrets` injects as
`GEOCODER_REGION_STATE` + `GEOCODER_VIEWBOX` (declared under `env.secret` in `deploy.yml`),
so a single-state deploy **frames the map on — and geocodes within — that state** instead of
the whole US. See [geo-provisioning.md](geo-provisioning.md).

**Release-based (multi-host / CI).** Build a versioned substrate and roll it out:

```bash
# (c) Build the geo substrate (produces a geo-<region>-<date>-<run> Release):
#     run the "Build geo artifacts" workflow (workflow_dispatch), or locally:
#       infra/scripts/build-geo.sh && gh release create ...
# (d) Deploy that build onto the hosts:
#     run the "Deploy geo artifacts" workflow with the release tag.
```

`deploy-geo.yml` downloads the release, `geo-manifest.sh verify`s it, scp's the
artifacts into the accessory volumes (the `*_DATA_PATH` vars), and reboots the
accessories. Nominatim re-imports if the extract changed (slow; one-time).

```bash
# (e) Verify end to end:
curl -fsS "https://${API_DOMAIN}/api/v1/health"      # expect {"status":"ok"...}
curl -fsS "https://${API_DOMAIN}/api/v1/routes" -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":41.6611,"lng":-91.5302},
       "locale":"en"}}'
```

## 7. Finding the accessory data paths (for the `*_DATA_PATH` vars)

Kamal mounts each accessory's `directories:` entry to a host path. After the
accessories are booted, read the actual bind source on each host:

```bash
# On the routing host (repeat for tiles / geocoder):
docker inspect flckd-backend-routing \
  --format '{{range .Mounts}}{{.Destination}} -> {{.Source}}{{"\n"}}{{end}}'
```

Use the `.Source` for `/data` (routing/tiles) and `/nominatim/import` (geocoder)
as `ROUTING_DATA_PATH` / `TILES_DATA_PATH` / `GEOCODER_IMPORT_PATH`.

## 8. Optional: error tracking

The `Telemetry` seam (refresh-run + staleness alerts) logs by default and
auto-detects Sentry. To wire it, add the Sentry SDK + DSN; no call sites change.

## 9. After setup — ongoing

- **App deploys:** run `deploy.yml` (or `kamal deploy`).
- **Geo refresh:** `build-geo.yml` (on-demand) → `deploy-geo.yml`, run when the
  weekly `GeoStalenessJob` alerts that the substrate is stale. See
  [geo-stack.md](geo-stack.md).
- **Camera refresh ops:** [refresh-ops.md](refresh-ops.md).
- **Backups / restore:** [backups.md](backups.md) (do this *now* — Postgres is the
  only irreplaceable state).
- **Incidents:** [incident-response.md](incident-response.md).

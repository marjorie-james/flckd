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

- Edit `backend/config/deploy.yml`: replace every `<PLACEHOLDER>` —
  `<REGISTRY_HOST>`, `<WEB_HOST_1>`, `<JOB_HOST_1>`, `<API_DOMAIN>`, `<DB_HOST>`,
  `<ROUTING_HOST>`, `<GEOCODER_HOST>`, `<TILES_HOST>`.
- Create `backend/.kamal/secrets` from the template and fill it (it's gitignored;
  the `.example` is tracked):
  ```bash
  cp backend/.kamal/secrets.example backend/.kamal/secrets
  ```
  It supplies the `secret:` entries deploy.yml references: `RAILS_MASTER_KEY`,
  `DATABASE_PASSWORD`, `POSTGRES_PASSWORD`, `NOMINATIM_PASSWORD`,
  `KAMAL_REGISTRY_USERNAME`, `KAMAL_REGISTRY_PASSWORD`.

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

| Variable | Used by | Value |
|----------|---------|-------|
| `API_DOMAIN` | app deploy smoke test | e.g. `api.flckd.example` |
| `ROUTING_HOST` / `TILES_HOST` / `GEOCODER_HOST` | geo deploy | `user@addr` of each geo host |
| `ROUTING_DATA_PATH` / `TILES_DATA_PATH` / `GEOCODER_IMPORT_PATH` | geo deploy | on-host dir backing each accessory volume — see step 7 |

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
yet, so routing will fail soft until step (d). The geocoder begins importing its
OSM extract on first boot once the extract is in place.

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
       "aggressiveness":"completely_avoid","locale":"en"}}'
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

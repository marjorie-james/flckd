# Deploy prep sheet — inexpensive single-host deploy

The cheapest viable production deploy: **one VPS** running all six Kamal roles
(web, job, postgres, routing, geocoder, tiles) co-located on the private Docker
network. This is explicitly supported — "co-locate freely to start (e.g. one big
box runs everything); split as load grows" ([provisioning.md](provisioning.md) §1).

Use this when launching the **Iowa** region. Iowa's geo substrate is small (graph
+ tiles are a few hundred MB), so one box is enough. Full-US is *not* cheap — see
[geo-stack.md](geo-stack.md) and revisit sizing before expanding regions.

> Doing this on **AWS specifically?** [aws-deploy.md](aws-deploy.md) is this same
> single-host plan with concrete EC2 / ECR / Route 53 / S3 steps and commands.

Anonymity holds on one box just as on six: routing/geocoder/tiles are private
accessories on the Docker network, reached by service name. Nothing here changes
FR-012a — no user origin/destination/route leaves the box.

---

## 1. What "inexpensive" means here

| Cost lever | Cheap choice | Why it's safe for Iowa launch |
|---|---|---|
| Hosts | **1 VPS**, all roles co-located | Kamal addresses roles by host; point them all at the same box. |
| Sizing | 4 vCPU / 8 GB RAM / ~80 GB SSD | Nominatim import is the RAM/disk pressure point; everything else is light at Iowa scale. |
| Registry | **GHCR** (free for your images) | `registry.server: ghcr.io`; push/pull with a PAT. |
| TLS | Kamal proxy + **Let's Encrypt** (free) | Already configured (`proxy.ssl: true`). |
| Geo build | **GitHub Actions** `build-geo.yml` (free minutes) | Don't build the graph/tiles on the paid VPS. |
| Backups | `pg_dump` → cheap object storage | Postgres is the only irreplaceable state ([backups.md](backups.md)). |

**Rough budget:** one 4 vCPU / 8 GB VPS (~$24–48/mo on Hetzner/DigitalOcean/Vultr)
+ object storage for backups (a few $/mo). Registry, CI, and TLS are free.

> Sizing caveat: 8 GB comfortably runs the app + Postgres + routing + tiles. The
> **Nominatim first-boot import** is the spike. If the import OOMs, either build on
> a temporarily-resized box then scale down, or import once on CI/locally and ship
> the prebuilt `nominatim-data` volume. Don't undersize below 8 GB for the import.

---

## 2. Single-host overrides to `deploy.yml`

Point every `<…_HOST>` placeholder at the **same** machine. With everything
co-located, the accessory ports already bind to `127.0.0.1` (see `deploy.yml`),
so they're only reachable over the private network — good.

First copy the tracked template to your real (gitignored) config — edit `deploy.yml`,
never the `.example` (Kamal reads `config/deploy.yml` by default):

```bash
cp backend/config/deploy.example.yml backend/config/deploy.yml
```

Then replace the placeholders in [`backend/config/deploy.yml`](../../backend/config/deploy.yml):

| Placeholder | Single-host value |
|---|---|
| `<REGISTRY_HOST>` | `ghcr.io` (and image `ghcr.io/<you>/flckd-backend`) |
| `<WEB_HOST_1>` | `deploy@<VPS_IP>` |
| `<JOB_HOST_1>` | `deploy@<VPS_IP>` (same box) |
| `<DB_HOST>` | `deploy@<VPS_IP>` |
| `<ROUTING_HOST>` | `deploy@<VPS_IP>` |
| `<GEOCODER_HOST>` | `deploy@<VPS_IP>` |
| `<TILES_HOST>` | `deploy@<VPS_IP>` |
| `<API_DOMAIN>` | your DNS name, e.g. `api.flckd.example` |

Keep `WEB_CONCURRENCY: 2` and `SOLID_QUEUE_IN_PUMA: false` as-is — the dedicated
`job` host is just another container on the same box, which is fine and keeps the
worker isolated from web request load.

> Cheapest-possible variant: if you want to drop the separate worker container,
> set `SOLID_QUEUE_IN_PUMA: true` and remove the `job` server block so Solid Queue
> runs inside Puma. Saves one container's overhead; costs you worker isolation.
> Fine for launch traffic, revisit if refresh jobs start contending with requests.

---

## 3. Pre-flight checklist

Work top to bottom. Don't start `kamal setup` until every box is ticked.

### Accounts & access
- [ ] VPS provisioned (4 vCPU / 8 GB / ~80 GB SSD), Ubuntu LTS or similar.
- [ ] **Docker** installed and running on the VPS.
- [ ] Non-root `deploy` user with Docker access; SSH key-only login.
- [ ] GHCR (or other) registry account + **PAT** with `write:packages`.
- [ ] DNS `A`/`AAAA` record: `API_DOMAIN` → VPS IP (so Let's Encrypt can issue).
- [ ] Outbound network open so the VPS can pull images from the registry.

### Secrets (generate per [provisioning.md](provisioning.md) §3)
- [ ] `config/master.key` exists (`bin/rails credentials:edit`).
- [ ] `DATABASE_PASSWORD` = `POSTGRES_PASSWORD` (same DB) — `openssl rand -hex 32`.
- [ ] `NOMINATIM_PASSWORD` — `openssl rand -hex 32`.
- [ ] Deploy SSH keypair generated; **public** key in the VPS's `authorized_keys`.
- [ ] `backend/.kamal/secrets` created from `.kamal/secrets.example` and filled
      (gitignored — never commit it).

### Config
- [ ] All `<…_HOST>` placeholders in `deploy.yml` point at the one VPS (§2 above).
- [ ] `image:` and `registry.server:` set to your GHCR path.
- [ ] Geo accessory images stay **pinned by digest** (don't loosen to `:latest`).

### Local tooling
- [ ] `gem install kamal -v "~> 2.0"`.
- [ ] `kamal config` parses cleanly (no unresolved placeholders / secrets).
- [ ] CI green on the commit you're shipping (`ci-backend.yml`, `ci-frontend.yml`, `ci-scripts.yml`).

### Geo artifacts (build on free CI, not the paid box)
- [ ] `build-geo.yml` run (or `infra/scripts/build-geo.sh` locally) → a
      `geo-<region>-<date>-<run>` release exists with the Iowa graph + tiles.

---

## 4. Bring-up order (single host)

```bash
cd backend

# (a) App + DB + empty geo accessories; first run installs the Kamal proxy + TLS.
kamal setup

# (b) Load schema (structure.sql; PostGIS extension included).
kamal app exec 'bin/rails db:prepare'

# (c) Geo data onto the box: run "Deploy geo artifacts" (deploy-geo.yml) with the
#     release tag from the checklist. It scp's the graph/tiles into the accessory
#     volumes and reboots them. Nominatim imports the extract on first boot (slow).
```

Until step (c) lands, routing fails soft and the geocoder is still importing —
that's expected. Find the on-host volume paths for the `*_DATA_PATH` GitHub
variables with `docker inspect` per [provisioning.md](provisioning.md) §7.

---

## 5. Smoke test

```bash
curl -fsS "https://${API_DOMAIN}/api/v1/health"      # expect {"status":"ok",...}

curl -fsS "https://${API_DOMAIN}/api/v1/routes" -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":41.6611,"lng":-91.5302},
       "locale":"en"}}'
```

- [ ] Health returns `ok`.
- [ ] A Des Moines→Iowa City route comes back (proves routing graph + DB wired).
- [ ] A geocode/autocomplete request resolves (proves Nominatim import finished).
- [ ] Map tiles load in the frontend (proves pmtiles serving + CORS).

---

## 6. Day-one essentials (don't skip on a cheap box)

A single box has no redundancy, so the operational basics matter *more*, not less:

- [ ] **Backups configured now** — Postgres is the only irreplaceable state.
      `pg_dump` → off-box object storage on a schedule ([backups.md](backups.md)).
      Verify a restore once.
- [ ] **Disk alerting** — Nominatim + Postgres + tiles share one disk; a full disk
      takes everything down. Alert at ~75%.
- [ ] **Log caps verified** — `deploy.yml` sets `max-size: 100m / max-file: 3`;
      confirm logs aren't growing unbounded (and that they redact coords/IPs).
- [ ] **Rollback is `kamal rollback`** — app image rolls back instantly; the geo
      volumes and Postgres do **not**, so a bad migration needs the DB restore path.
- [ ] Optional: wire Sentry via the `Telemetry` seam (DSN only, no code changes;
      [provisioning.md](provisioning.md) §8).

---

## 7. When to stop being cheap

Split roles off the single box (just point that role's `<…_HOST>` at a new
machine and redeploy) when any of these show up:

- Web latency rises while a refresh/import job runs → move `job` or `routing` off.
- Postgres I/O contends with Nominatim/tiles reads → give Postgres its own box.
- You add regions beyond Iowa → the routing graph and Nominatim import grow fast;
  re-check RAM/disk before expanding (full-US is a different sizing class).

Kamal makes the split mechanical: change the host, `kamal deploy`. Nothing in the
app or anonymity model changes — the accessories just move to another node on the
same private boundary.
```

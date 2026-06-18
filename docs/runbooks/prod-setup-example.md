# Runbook: Current production setup (worked example)

This is the **as-built** snapshot of the live production deployment — concrete
*choices*, not just placeholders. The other provisioning runbooks
([provisioning.md](provisioning.md), [cheap-deploy.md](cheap-deploy.md),
[vultr-whole-us.md](vultr-whole-us.md)) are the *generic* templates; this page
shows one real instantiation of them, so a new operator can see exactly how the
knobs are set in practice.

> Identifiers (the host IP, public domain, ACME email, registry namespace) are
> written as `<PLACEHOLDER>` below — the real values live only in the gitignored
> config files listed at the bottom. Don't commit them here.

> Anonymity (FR-012a) holds exactly as in the generic docs: routing, geocoding,
> and tiles are private Kamal accessories on the box's `kamal` Docker network,
> reached by container name. No user origin/destination/route leaves the box.

---

## At a glance

| Thing | Current choice |
|---|---|
| Provider | **Vultr** — single VPS, all roles co-located |
| Host | `<VPS_IP>` |
| Deploy scope | **Iowa** (single-state production deploy) |
| Public domain | `<DOMAIN>` (apex; `www` → apex redirect) |
| Edge | **Caddy** — serves the SPA + reverse-proxies same-origin `/api` and `/tiles` |
| TLS | Let's Encrypt via Caddy (ACME `<ACME_EMAIL>`) |
| App routing | **Kamal 2** proxy *behind* Caddy (zero-downtime version switch only) |
| Registry | `ghcr.io`, image `<REGISTRY_NAMESPACE>/flckd-backend` |
| Deploy command | `backend/bin/kamal-docker` (not bare `kamal`) |

This is the [cheap-deploy.md](cheap-deploy.md) single-host shape (Iowa-sized, all
six roles on one box) **plus** the [frontend-caddy.md](frontend-caddy.md)
single-origin Caddy edge.

---

## Topology

```
                    ┌──────────────── Vultr VPS  <VPS_IP> ────────────────┐
  <DOMAIN> ──443──► │  flckd-caddy  :80/:443   (auto-TLS, the only host ports) │
  www → apex        │   ├─ /api/*   → kamal-proxy:80         (Host api.<DOMAIN>)│
                    │   ├─ /tiles/* → flckd-backend-tiles:8080                  │
                    │   └─ /*       → /srv/dist  (static React SPA + /fonts +   │
                    │                 config.json + map-style.json)             │
                    │                                                           │
                    │  Behind Caddy, on the `kamal` Docker network:            │
                    │   kamal-proxy ─► web (Puma+Thruster)   ┐                  │
                    │                  job (Solid Queue)     │ app roles        │
                    │   accessories: postgres (PostGIS)      ┘                  │
                    │               routing  (Valhalla)   127.0.0.1:8002        │
                    │               geocoder (Nominatim)  127.0.0.1:8081        │
                    │               tiles    (go-pmtiles) 127.0.0.1:8080        │
                    └──────────────────────────────────────────────────────────┘
   Only Caddy publishes host ports (:80/:443). Everything else binds 127.0.0.1
   or is reachable only by container name over the `kamal` network.
```

Six Kamal roles (`web`, `job`, `postgres`, `routing`, `geocoder`, `tiles`) all
point at the one VPS — see [`backend/config/deploy.yml`](../../backend/config/deploy.yml).

---

## The Caddy edge

Defined in [`infra/caddy/Caddyfile`](../../infra/caddy/Caddyfile); deployed by
[`infra/scripts/deploy-frontend.sh`](../../infra/scripts/deploy-frontend.sh) as a
standalone container on the `kamal` network (deliberately decoupled from the app
deploy). It does three things from one origin:

1. **Static SPA** — serves `frontend/dist` from a host bind mount (`/srv/dist`).
   A frontend-only change is a re-sync + `caddy reload`, no container rebuild.
2. **`/api/*` → `kamal-proxy:80`**, rewriting the upstream `Host` to
   `api.<DOMAIN>` (the label kamal-proxy routes the app on).
3. **`/tiles/*` → `flckd-backend-tiles:8080`** (self-hosted PMTiles).

Single origin ⇒ no CORS, nothing cross-site, and
`frontend/public/config.json` stays `apiBase:""` / `tilesBase:""`.

Edge config lives in [`backend/.kamal/frontend.env`](../../backend/.kamal/frontend.env)
(gitignored), consumed by `deploy-frontend.sh` — `FLCKD_DOMAIN`, `ACME_EMAIL`,
and `API_HOST` (the internal Host kamal-proxy routes on, `api.<DOMAIN>`).

> `api.<DOMAIN>` is **not** a public DNS record in this model — it only exists
> *inside* the box as the Host label kamal-proxy routes on. Caddy sets it on the
> upstream request. Public DNS is just `<DOMAIN>` + `www` → the VPS IP.

### Caddy ⇄ kamal-proxy coexistence (the one non-obvious bit)

Both want `:80/:443`; kamal-proxy yields them. In
[`backend/config/deploy.yml`](../../backend/config/deploy.yml):

```yaml
proxy:
  ssl: false          # Caddy terminates TLS; kamal-proxy speaks plain HTTP
  host: api.<DOMAIN>  # still routes by Host
  app_port: 80
  run:
    publish: false    # binds NO host ports — Caddy reaches it at kamal-proxy:80
```

`proxy.run.publish: false` is the durable way to express "no host ports" — Kamal
re-applies it on every proxy boot, surviving `kamal proxy remove --force`. Full
rationale and troubleshooting: [frontend-caddy.md](frontend-caddy.md).

---

## Deploy scope: Iowa

This box runs a **single-state production deploy** (Iowa), which frames the map on
and geocodes within Iowa instead of the whole US. The scope lives in
[`backend/.kamal/geo.env`](../../backend/.kamal/geo.env) (gitignored):

```
GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf
GEO_REGION_LABEL=Iowa
```

`bin/kamal-docker` resolves that into `backend/.kamal/deploy-scope.env`
(generated — don't hand-edit), which `.kamal/secrets` injects as the app's
`GEOCODER_REGION_STATE` / `GEOCODER_VIEWBOX` (Iowa + its bbox).

To move to whole-US or another state, change `geo.env` and re-provision — see
[geo-provisioning.md](geo-provisioning.md). (Whole-US is a different sizing class;
this box is sized for Iowa. See [vultr-whole-us.md](vultr-whole-us.md) before scaling.)

> The **deploy scope is independent of the local dev scope** in
> [`infra/.region`](../../infra/.region) / `infra/.env` — they happen to both say
> Iowa here, but they don't have to match.

---

## Accessories (pinned, on the private network)

From [`backend/config/deploy.yml`](../../backend/config/deploy.yml) — geo images
are pinned by digest and match the dev `docker-compose.yml` exactly (no dev/prod
drift). The app reaches each by container name:

| Accessory | Image | App reaches it via |
|---|---|---|
| `postgres` | `postgis/postgis:17-3.4` | `DATABASE_HOST=flckd-backend-postgres` |
| `routing` (Valhalla) | `ghcr.io/valhalla/valhalla@sha256:…` | `ROUTING_URL=http://flckd-backend-routing:8002` |
| `geocoder` (Nominatim) | `mediagis/nominatim:4.4@sha256:…` | `GEOCODER_URL=http://flckd-backend-geocoder:8080` |
| `tiles` (go-pmtiles) | `protomaps/go-pmtiles@sha256:…` | `TILES_URL=http://flckd-backend-tiles:8080` |

The camera dataset GeoJSON lives on a persistent named volume
(`flckd-cameras:/rails/camera-data:ro`, `CAMERA_OSM_GEOJSON_PATH`) shared by the
`web` + `job` roles so it survives deploys.

---

## How to deploy this box

**App** — always via the wrapper (it runs the host preflight, resolves the deploy
scope, and runs geo provisioning on `setup`):

```bash
cd backend
bin/kamal-docker deploy          # routine app image swap
bin/kamal-docker setup           # first bring-up (also provisions geo on the host)
```

Why the wrapper and not bare `kamal`: it resolves `geo.env` → `deploy-scope.env`
(so the app frames Iowa) and runs `infra/scripts/provision-geo-host.sh` after a
`setup`. Bare `kamal deploy` would skip the scope wiring. See
[provisioning.md §6](provisioning.md).

**Frontend / Caddy** — separate, no container rebuild:

```bash
infra/scripts/deploy-frontend.sh                 # sync dist/ + Caddyfile, reload Caddy
FORCE_BUILD=1 infra/scripts/deploy-frontend.sh   # rebuild the bundle first
```

**Smoke test:**

```bash
curl -fsS https://<DOMAIN>/api/v1/health         # {"status":"ok",...}
curl -fsS https://<DOMAIN>/api/v1/routes -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":41.6611,"lng":-91.5302},"locale":"en"}}'
```

---

## Vultr-specific gotcha (bit us here)

Vultr ships `/etc/resolv.conf` with an **IPv6-only upstream resolver** that Docker
containers can't reach, which makes `kamal setup` fail with `target failed to
become healthy` while the app looks fine. Fix before first setup:

```bash
infra/scripts/bootstrap-host.sh deploy@<VPS_IP>   # idempotent; pins Docker to 1.1.1.1/8.8.8.8
```

`infra/scripts/preflight-host.sh` (run automatically by `bin/kamal-docker`)
detects this. Full detail: [provisioning.md §2](provisioning.md) and
[frontend-caddy.md](frontend-caddy.md#troubleshooting).

---

## Config files for this deploy (all gitignored; copy from the tracked `.example`)

The real identifiers live **only** in these files, never in tracked docs:

| File | Source template | Holds |
|---|---|---|
| `backend/config/deploy.yml` | `deploy.caddy.example.yml` | hosts, registry, accessories, `proxy.ssl:false` |
| `backend/.kamal/secrets` | `.kamal/secrets.example` | `RAILS_MASTER_KEY`, DB/Nominatim passwords, registry token |
| `backend/.kamal/geo.env` | `.kamal/geo.env.example` | deploy scope (Iowa) |
| `backend/.kamal/frontend.env` | `.kamal/frontend.env.example` | Caddy domain / ACME email / API host |
| `infra/caddy/Caddyfile` | (tracked) | the single-origin edge config (reads env, no literals) |

Secrets (`RAILS_MASTER_KEY`, `DATABASE_PASSWORD` = `POSTGRES_PASSWORD`,
`NOMINATIM_PASSWORD`, GHCR token) are generated per [provisioning.md §3](provisioning.md).

---

## See also

- [provisioning.md](provisioning.md) — the generic one-time setup this instantiates.
- [cheap-deploy.md](cheap-deploy.md) — the single-host Iowa shape, templated.
- [frontend-caddy.md](frontend-caddy.md) — the Caddy edge in depth.
- [geo-provisioning.md](geo-provisioning.md) — deploy scope / geo substrate.
- [vultr-whole-us.md](vultr-whole-us.md) — sizing if/when this grows to whole-US.
- [backups.md](backups.md) · [incident-response.md](incident-response.md) — day-2 ops.

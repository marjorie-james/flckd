# flckd

An **anonymous, camera-avoiding route planner**. Plan a driving route that
routes *around* known ALPR / Flock automated license-plate-reader cameras by
excluding the specific monitored road segment(s) — not a radius. Strict
anonymity is non-negotiable: no accounts, no PII, no persistent identifiers; no
third party ever receives a user's origin, destination, or route; logs never
retain route coordinates or client IPs. The only outbound handoff is an explicit,
user-initiated "open in Apple/Google Maps" (with a warning).

The whole geo stack is **self-hosted** (Valhalla routing, Nominatim geocoding,
self-hosted vector tiles) so user route data stays on our own infrastructure.

## TL;DR — get it running

You only need **[Docker Desktop](https://docs.docker.com/get-docker/)** (give it
≥ 6 GB memory and ~10 GB free disk), **git**, and **curl**. Everything else runs in
containers — no Ruby, Node, or Postgres to install.

1. **Get the code:**

   ```bash
   git clone https://github.com/marjorie-james/flckd.git
   cd flckd
   ```

2. **Run the one-time setup wizard** (downloads map data and starts everything;
   takes ~25–30 min, mostly unattended). Run it from the repo root:

   | OS | Command |
   |---|---|
   | **macOS** | `./setup.sh` |
   | **Linux** | `./setup.sh` |
   | **Windows** | Open **WSL2** (Ubuntu), `cd` into the repo, then `./setup.sh` |

   It's safe to re-run if a step fails — completed work is reused.

3. **Open the app:** when the wizard finishes it prints the URLs. Visit
   **<http://localhost:5173>** in your browser.

**Coming back later?** You don't re-run setup. Just start the services:

```bash
docker compose -f infra/docker-compose.yml up -d
```

That's it. The rest of this README covers the details.

## Stack

| Layer | Technology | Version |
|---|---|---|
| Backend language | Ruby | 3.4.x |
| Backend framework | Rails (API mode) | ~8.1.3 |
| Background jobs | Solid Queue | (Rails 8.1 built-in) |
| Cache | Solid Cache | (Rails 8.1 built-in) |
| Database | PostgreSQL + PostGIS | 17 / 3.4 |
| Frontend language | TypeScript | ~6.0 |
| Frontend framework | React | ^19 |
| Frontend build | Vite | ^8 |
| Package manager | pnpm | 11.x |
| Routing engine | Valhalla | self-hosted (pinned digest) |
| Geocoder | Nominatim | 4.4 (self-hosted, pinned digest) |
| Vector tiles | Protomaps go-pmtiles | self-hosted (pinned digest) |
| Node.js (CI / frontend) | Node.js | 22.x |
| Infra scripting | Bash | 3.2+ (macOS-compatible) |
| Infra script tests | bats/bats (Docker) | 1.11 |
| Container runtime | Docker Compose | v2 |
| Deploy | Kamal 2 + Thruster | (Rails 8.1 built-in) |

## Layout

- **`backend/`** — Ruby 3.4 + Rails 8.1 API (API-only, no auth by design).
  Routing/geocoding clients, the camera-data aggregation pipeline, Solid Queue
  jobs, PostGIS models (`cameras` source-of-truth).
- **`frontend/`** — TypeScript + React 19 (Vite, MapLibre GL JS) SPA. Renders
  self-hosted tiles only — zero third-party requests.
- **`infra/`** — Docker Compose dev stack and the scripts that build the geo data
  from a public OSM extract. See [infra/README.md](infra/README.md).
- **`test/infra/`** — bats-core behavioral tests for the infra shell scripts.

## Prerequisites

Everything runs in Docker — you do **not** need to install Ruby, Node, pnpm, or
PostgreSQL on your machine. The versions in the Stack table above are
informational (they're what the containers use). All you need on the host is:

- **[Docker Desktop](https://docs.docker.com/get-docker/)** (Compose v2), configured
  with **≥ 6 GB of memory** and **~10 GB of free disk**. The first-run geo build runs
  Nominatim, Planetiler, Valhalla, and Postgres at once; below ~6 GB one of them gets
  OOM-killed mid-import. Raise it in *Docker Desktop → Settings → Resources → Memory*.
- **git** and **curl** (both ship with macOS; on Linux install via your package manager).
- **Windows:** run everything inside **WSL2** (the setup script is bash).

## Quick start (local)

Local dev is **Docker-only** for the backend (host Ruby native extensions are
broken). Run from the repo root.

**First time?** The setup wizard handles everything end-to-end — prerequisites,
region selection, geo build, database, sample camera data, services, and
house-number geocoding (~25–30 min total; most of that is the Nominatim OSM
import running in the background):

```bash
./setup.sh
```

(`./setup.sh` is a thin wrapper around `infra/scripts/setup.sh` — either works,
and both accept the same flags, e.g. `-v` for verbose or `--region CA` to skip
the state prompt.) It's safe to re-run: if a step fails (e.g. the geocoder
import times out), fix the cause and run it again — completed work is reused.

The wizard writes `infra/.region` (gitignored), runs `infra/scripts/build-geo.sh`,
then automatically prepares the database, imports fixture cameras, starts all
services, waits for the geocoder, and loads TIGER/Line address data. When it
finishes, the app is ready at the URLs it prints.

**Day-to-day** (after the first run — bringing services back up):

```bash
docker compose -f infra/docker-compose.yml up -d
```

**Schema changes** (after a `git pull` that includes new migrations):

```bash
docker compose -f infra/docker-compose.yml run --rm backend bin/rails db:prepare
```

**Starting individual services** (if you need a subset):

```bash
docker compose -f infra/docker-compose.yml up -d postgres
docker compose -f infra/docker-compose.yml up -d routing tileserver geocoder
docker compose -f infra/docker-compose.yml up -d backend frontend
```

Smoke-test a route:

```bash
curl -s http://localhost:3000/api/v1/routes -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":41.6611,"lng":-91.5302},
       "aggressiveness":"completely_avoid","locale":"en"}}'
```

Health check: `curl http://localhost:3000/api/v1/health` (returns 503
`degraded` when the DB is down; geo services fail soft).

## Tests

```bash
# Backend (in Docker, test env)
docker compose -f infra/docker-compose.yml run --rm \
  -e RAILS_ENV=test backend bundle exec rspec

# Frontend (Vitest)
cd frontend && pnpm test -- run

# Infra scripts (Docker — no local bats install needed)
docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/build-geocoder.bats
```

## License

Copyright (C) 2026 The flckd authors

**Code** is licensed under [AGPL-3.0-only](LICENSE). If you run a modified
version of flckd as a network service, you must make your source available to
its users.

**Data** is separate: the camera dataset is derived from OpenStreetMap and is
licensed under [ODbL-1.0](https://opendatacommons.org/licenses/odbl/1-0/), not
AGPL. See [docs/adr/0002-pbf-derived-camera-source.md](docs/adr/0002-pbf-derived-camera-source.md).

## Docs

- Feature specs & plans: [specs/](specs/)
- Operational runbooks: [docs/runbooks/](docs/runbooks/)

## Operations

- [docs/runbooks/provisioning.md](docs/runbooks/provisioning.md) — one-time
  production setup: hosts, secrets, DNS, GitHub Actions config, first bring-up.
- [docs/runbooks/refresh-ops.md](docs/runbooks/refresh-ops.md) — the daily 08:00
  UTC camera-data refresh: manual triggers, status, telemetry, stale→retire.
- [docs/runbooks/geo-stack.md](docs/runbooks/geo-stack.md) — building/rebuilding
  the self-hosted geo stack and expanding coverage beyond Iowa.
- [docs/runbooks/incident-response.md](docs/runbooks/incident-response.md) — fast
  triage for 5xx spikes, routing/geocoder/DB outages, stuck refreshes.
- [docs/runbooks/backups.md](docs/runbooks/backups.md) — PostGIS backup &
  restore (the one piece of state worth protecting).

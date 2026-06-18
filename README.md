# flckd

An **anonymous, camera-avoiding route planner**. Plan a driving route that
routes *around* known ALPR / Flock automated license-plate-reader cameras by
excluding the specific monitored road segment(s) — not a radius. Strict
anonymity is non-negotiable: no accounts, no PII, no persistent identifiers; no
third party ever receives a user's origin, destination, or route; logs never
retain route coordinates or client IPs. A route never leaves the app over the network:
the only way to take one with you is a user-initiated, fully client-side GPX export — the
file is built in your browser and saved to your own device (warned, because the file
itself holds your route).

The whole geo stack is **self-hosted** (Valhalla routing, Nominatim geocoding,
self-hosted vector tiles) so user route data stays on our own infrastructure.

## TL;DR — get it running

**Start with a single US state.** It's the fast, laptop-friendly path: a few hundred MB,
**~25–30 min**, and it runs comfortably on **≥ 6 GB RAM / ~10 GB free disk**. The setup
wizard defaults to one (**Iowa**), so you can just accept the default and go. Scaling up
to a whole country (the production scope) is a heavier, larger-machine job —
see [Whole-country / whole-US deployments](#whole-country--whole-us-deployments) below.

### The simple way (no command line)

If you're not comfortable in a terminal, this path needs **no typing**:

1. **Install [Docker Desktop](https://docs.docker.com/get-docker/)** for your OS and open
   it once. Give it **≥ 6 GB memory** (Docker Desktop → Settings → Resources → Memory).
   - **Windows only:** also install **[Git for Windows](https://git-scm.com/download/win)**
     (accept the defaults). It provides "Git Bash", which runs the wizard — this is a tiny
     one-click installer.
2. **Get the code** — click **Code → Download ZIP** on the
   [repo page](https://github.com/marjorie-james/flckd), then unzip it. *(Or `git clone`
   if you have git — that path keeps the launcher ready to double-click on macOS.)*
3. **Double-click the launcher** for your platform in the unzipped folder:

   | OS | Double-click |
   |---|---|
   | **macOS** | **`Start flckd (Mac).command`** — first time from a ZIP, right-click it → **Open** → **Open** to get past macOS's "unidentified developer" prompt (Gatekeeper, not an error). |
   | **Windows** | **`Start flckd (Windows).bat`** |
   | **Linux** | run `./setup.sh` in a terminal (see below) |

   The launcher checks Docker (and **opens the right download page / starts Docker for you**
   if needed), then runs the one-time setup. It downloads map data and starts everything —
   ~25–30 min for a state, mostly unattended. A prompt asks for a state.
4. **Open the app:** when it finishes it prints the URLs. Visit **<http://localhost:5173>**.

### The terminal way

You need **[Docker Desktop](https://docs.docker.com/get-docker/)** (≥ 6 GB memory, ~10 GB
free disk for a state), **git**, and **curl**. Everything else runs in containers — no
Ruby, Node, or Postgres to install.

1. **Get the code:**

   ```bash
   git clone https://github.com/marjorie-james/flckd.git
   cd flckd
   ```

2. **Run the one-time setup wizard** from the repo root

   | OS | Command |
   |---|---|
   | **macOS** | `./setup.sh` |
   | **Linux** | `./setup.sh` |
   | **Windows** | run `./infra/scripts/setup.sh` from **Git Bash** (Git for Windows) — no WSL2 needed |

   It's safe to re-run if a step fails — completed work is reused.

3. **Open the app:** when the wizard finishes it prints the URLs. Visit
   **<http://localhost:5173>** in your browser.

**Coming back later?** You don't re-run setup. Just start the services:

```bash
docker compose -f infra/docker-compose.yml up -d
```

That's it. The rest of this README covers the details.

## Whole-country / whole-US deployments

A single state is ideal for local dev and trying things out, but flckd's **production
scope is a whole country, defaulting to the United States** — the configured country
drives the OSM extract, routing graph, vector tiles, geocoder + whole-US TIGER house
numbers, camera gathering, and map framing. A whole-US build is **substantially
heavier** than a state and belongs on a **larger/self-hosted machine, not a laptop or a
standard CI runner**.

**Requirements for a whole-US build:**

| Resource | Single state (dev) | **Whole US (production)** |
|---|---|---|
| Memory (Docker) | ≥ 6 GB | **16 GB+** (Nominatim/Planetiler OOM below ~6 GB) |
| Free disk | ~10 GB | **~350–400 GB** — the Nominatim Postgres volume alone reaches ~250–350 GB during the whole-US import, on top of the ~10+ GB OSM extract, ~1.8 GB TIGER bundle, routing graph, and tiles |
| Build time | ~25–30 min | **hours** — the Nominatim OSM import is the long pole |
| Machine | a laptop is fine | larger/self-hosted box; fast NVMe (the import saturates disk IOPS before CPU) |

> **Disk is the most common failure.** The whole-US Nominatim import grows well past the
> raw extract size — budget **~400 GB free** and watch it; if the host disk fills, the
> import is killed mid-run and leaves a corrupt volume you must delete before retrying
> (`docker volume rm infra_nominatim_data`). On macOS, point Docker's disk image at a
> drive with that much headroom (*Docker Desktop → Settings → Resources → Advanced*).

Provision it from the same wizard (`./setup.sh`, then enter **`US`** at the prompt) or
non-interactively with `COUNTRY=us infra/scripts/build-geo.sh`. Tuning knobs for the
heavy stages — `NOMINATIM_SHM`, `PLANETILER_XMX`, `GEO_GEOCODER_TIMEOUT` — and the full
resource envelope are documented in
[docs/runbooks/geo-stack.md](docs/runbooks/geo-stack.md). Only **US** is provisioned and
validated at launch; an un-provisioned country fails fast with an actionable error.

A **single state can also be a production deployment** — a much lighter footprint than
whole-US. Set the state in `backend/.kamal/geo.env` and `bin/kamal-docker` frames the map on
(and geocodes within) that state, so the app never opens zoomed out to the whole US. See
[docs/runbooks/geo-provisioning.md](docs/runbooks/geo-provisioning.md).

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
  with **≥ 6 GB of memory** and **~10 GB of free disk** for a single-state build. The
  first-run geo build runs Nominatim, Planetiler, Valhalla, and Postgres at once; below
  ~6 GB one of them gets OOM-killed mid-import. Raise it in *Docker Desktop → Settings →
  Resources → Memory*.

  | Target | Memory | Free disk | Build time |
  |---|---|---|---|
  | **Single state** (recommended start) | ≥ 6 GB | ~10 GB | ~25–30 min |
  | **Whole US** (production scope) | **16 GB+** | **~350–400 GB** (Nominatim Postgres volume alone reaches ~250–350 GB during import) | **hours** (Nominatim import is the long pole) |

  A whole-US build belongs on a larger/self-hosted machine — see
  [Whole-country / whole-US deployments](#whole-country--whole-us-deployments) and
  [docs/runbooks/geo-stack.md](docs/runbooks/geo-stack.md) for the full resource envelope
  and tuning knobs (`NOMINATIM_SHM`, `PLANETILER_XMX`, `GEO_GEOCODER_TIMEOUT`).
- **git** and **curl** (both ship with macOS; on Linux install via your package manager).
- **Windows:** run everything inside **WSL2** (the setup script is bash).

## Quick start (local)

Local dev is **Docker-only** for the backend. Run from the repo root.

**First time?** The setup wizard handles everything end-to-end — prerequisites,
region selection, geo build, database, sample camera data, services, and house-number
geocoding (**~25–30 min for a single state**; most of that is the Nominatim OSM import
running in the background):

```bash
./setup.sh
```

At the prompt, type a **2-letter state ID**.
(`./setup.sh` is a thin wrapper around `infra/scripts/setup.sh` — either works, and both
accept the same flags, e.g. `-v` for verbose or `--region CA` to skip the prompt.) To
build the whole country instead, enter **`US`** at the prompt or pass `--region US` —
that's the heavier production path; see
[Whole-country / whole-US deployments](#whole-country--whole-us-deployments). It's safe
to re-run: if a step fails (e.g. the geocoder import times out), fix the cause and run it
again — completed work is reused.

The wizard writes `infra/.region` and `infra/.env` (both gitignored), runs
`infra/scripts/build-geo.sh`, then automatically prepares the database, imports fixture
cameras, starts all services, waits for the geocoder, and loads TIGER/Line address data
(just the selected state, or the whole-US bundle for `US`). When it finishes, the app is
ready at the URLs it prints.

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
       "locale":"en"}}'
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

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) (setup, the
project non-negotiables, and how contributions are licensed), and please follow the
[Code of Conduct](CODE_OF_CONDUCT.md). For security or privacy/anonymity issues, **do not
open a public issue** — see [SECURITY.md](SECURITY.md).

## Docs

- Feature specs & plans: [specs/](specs/)
- Operational runbooks: [docs/runbooks/](docs/runbooks/)

## Operations

- [docs/runbooks/provisioning.md](docs/runbooks/provisioning.md) — one-time
  production setup: hosts, secrets, DNS, GitHub Actions config, first bring-up.
- [docs/runbooks/refresh-ops.md](docs/runbooks/refresh-ops.md) — the daily 08:00
  UTC camera-data refresh: manual triggers, status, telemetry, stale→retire.
- [docs/runbooks/geo-stack.md](docs/runbooks/geo-stack.md) — building/rebuilding
  the self-hosted geo stack, the whole-US resource envelope, and switching country/region.
- [docs/runbooks/incident-response.md](docs/runbooks/incident-response.md) — fast
  triage for 5xx spikes, routing/geocoder/DB outages, stuck refreshes.
- [docs/runbooks/backups.md](docs/runbooks/backups.md) — PostGIS backup &
  restore (the one piece of state worth protecting).

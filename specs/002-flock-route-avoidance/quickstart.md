# Quickstart: Camera-Avoiding Route Planner

Local development brings up the Rails API, the React SPA, PostgreSQL/PostGIS, and the **self-hosted geo
stack** (routing, geocoding, tiles). Everything runs on your machine — no third-party API keys, by
design (anonymity).

## Prerequisites

- Docker + Docker Compose
- Ruby 3.4.x (3.4.9; latest stable supported by Rails 8.1) + Bundler
- Node 20+ + pnpm (or npm)
- ~A few GB disk for a regional OSM extract (start with a single US metro extract, not the whole US)

## 1. Geo stack (own infrastructure)

```bash
# Build the geo data for the launch region (Iowa); see infra/README.md.
infra/scripts/fetch-extract.sh          # Iowa OSM extract (override via REGION_URL)
infra/scripts/build-routing-graph.sh    # Valhalla graph
infra/scripts/build-tiles.sh            # Protomaps PMTiles
docker compose -f infra/docker-compose.yml up -d postgres routing tileserver
```

This starts:
- `postgres` (PostGIS) on 5432
- `routing` (Valhalla) on 8002
- `tileserver` (Protomaps PMTiles via go-pmtiles) on 8080
- `geocoder` (Pelias) — follow-up, not yet wired (see infra/README.md)

## 2. Backend (Rails API)

```bash
cd backend
bundle install
bin/rails db:create db:migrate
# Import + snap a small camera fixture set (DeFlock/OSM sample) for the same extract region:
bin/rails camera_data:import SOURCE=fixture
bin/rails server      # http://localhost:3000  (API under /api/v1)
```

## 3. Frontend (React SPA)

```bash
cd frontend
pnpm install
pnpm dev              # http://localhost:5173
```

The SPA points at the Rails API and the local tileserver; MapLibre renders self-hosted tiles only.

## 4. Smoke test the core flow (US1)

```bash
# Plan a route (POST keeps coordinates out of URLs/logs)
curl -s http://localhost:3000/api/v1/routes \
  -H 'Content-Type: application/json' \
  -d '{"origin":{"lat":39.7392,"lng":-104.9903},
       "destination":{"lat":39.7294,"lng":-104.8319},
       "avoidance_preference":"avoid","locale":"en"}' | jq
```

Expect a `Route` with `is_fully_clean`, `cameras_avoided_count`, `fastest_comparison`, and localized
`maneuvers`.

## 5. Run the tests (Constitution Principle II — must be green)

```bash
# Backend
cd backend && bundle exec rspec && bundle exec rubocop

# Frontend
cd frontend && pnpm test && pnpm lint

# End-to-end (seeded local stack)
cd frontend && pnpm e2e
```

## Mapping the build to user stories

| Story | Verify by |
|-------|-----------|
| **US1** Avoiding route (P1) | Step 4 returns a clean route where one exists; an on-path-camera fixture yields a detour |
| **US2** Anonymous (P2) | No login prompt anywhere; check logs contain no coordinates/IPs after a request; no identifying cookies |
| **US3** Multi-lingual (P3) | Set browser language / use the switcher; UI + `maneuvers` localize; in-progress input preserved |
| **US4** Avoidance control (P3) | Toggle `avoidance_preference`; `cameras_avoided_count` / `remaining_cameras` / `is_fully_clean` change |

## Anonymity checks (quick)

- `grep` the Rails log after a route request — it must contain **no** lat/lng, address, or client IP.
- DevTools → Network: every request (tiles, geocode, route) hits **your** origin only; no third-party
  domains.
- The "Open in Apple/Google Maps" button shows a warning **before** leaving the app (FR-012b).

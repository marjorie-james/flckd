# Quickstart: Aggregated Camera Data Source-of-Truth

**Feature**: `003-camera-data-aggregation`

This feature is backend-only and runs in Docker (host Ruby native extensions are broken — see feature 002
notes). All commands assume repo root.

## Prerequisites

```bash
docker compose -f infra/docker-compose.yml up -d postgres
docker compose -f infra/docker-compose.yml run --rm backend bin/rails db:migrate
docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bin/rails db:migrate
```

## Run the test suite (deterministic, no network)

External sources are stubbed with WebMock recorded fixtures; net connections are disabled in specs.

```bash
docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bundle exec rspec
docker compose -f infra/docker-compose.yml run --rm backend bundle exec rubocop   # zero warnings (Principle I)
```

## Import from one source (dev / targeted backfill)

```bash
# OSM ALPR for a bbox (south,west,north,east):
docker compose -f infra/docker-compose.yml run --rm \
  -e SOURCE=overpass -e BBOX="41.5,-93.7,41.8,-92.0" backend bin/rails camera_data:import

# DeFlock (DeFlock-curated OSM ALPR data, ODbL):
docker compose -f infra/docker-compose.yml run --rm \
  -e SOURCE=deflock -e BBOX="41.5,-93.7,41.8,-92.0" backend bin/rails camera_data:import

# An open-data / FOIA GeoJSON export, with recorded provenance + license:
docker compose -f infra/docker-compose.yml run --rm \
  -e SOURCE=geojson -e GEOJSON_PATH=/data/denver.geojson \
  -e NAME="Denver Open Data" -e URL="https://opendata.denvergov.org" -e LICENSE="CC0-1.0" \
  backend bin/rails camera_data:import
```

## Run a full aggregate refresh manually (all live sources, continental US)

```bash
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:refresh
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:refresh:status        # human table
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:refresh:status -- --json
```

Each run creates a `RefreshRun` (trigger `manual`). A source that fails is recorded `failed` while the
others still import — the run is `partial` and the failed source keeps its last-good data.

## Scheduled refresh

The daily refresh is configured in `config/recurring.yml` to fire at **08:00 UTC** (= 2am CST / 3am CDT,
fixed, no DST adjustment):

```yaml
production:
  camera_data_refresh:
    class: DataRefreshJob
    queue: default
    args: [ aggregate ]
    schedule: "0 8 * * *"
```

Solid Queue runs it in the background. Overlapping runs are prevented (concurrency key + a `running`
`RefreshRun` guard). To run a worker locally: `SOLID_QUEUE_IN_PUMA=true` or a standalone `bin/jobs`.

## Verify behavior

- **Aggregation**: after a refresh, `Camera.distinct.count` exceeds any single source's count, and every
  `Camera` has a `data_source` with a `license`.
- **Dedup**: two sources reporting a camera on the same road yield one `MonitoredSegment`-based avoidance
  target.
- **Stale/retire**: a camera missing from its source for 3 consecutive refreshes flips to
  `verification_status="removed"` (excluded from routing) unless it is `verified`.
- **Anonymity**: refresh logs contain no IPs or coordinates; no user data is sent to any source (queries are
  by US region tiles only).

## Anonymity / legitimacy notes

- Sources are queried by **geographic region tiles**, never by any user location.
- Only permissively-licensed sources are ingested; each `DataSource` records its `license` and `url` for
  attribution (OSM/DeFlock = ODbL).
- The Overpass/DeFlock client identifies the app honestly (User-Agent) and backs off on rate limits — it does
  not attempt to evade source rate limiting or terms.

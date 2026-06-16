# flckd — Backend (Rails API)

Ruby on Rails 8.1 **API-only** service for the Camera-Avoiding Route Planner. It orchestrates a
self-hosted geo stack (routing, geocoding, tiles) over a **private** network and never exposes a
user's origin, destination, or route to any third party (see the project Constitution and
[spec](../specs/002-flock-route-avoidance/spec.md)).

## Stack

- **Ruby 3.4.9** + **Rails 8.1** (API mode)
- **PostgreSQL 17 + PostGIS** (spatial: camera points, monitored segments, coverage areas)
- **Solid Queue** (DB-backed jobs — camera import / segment snapping / refresh), **Solid Cache**
- **Thruster** + **Puma** in production; **Kamal 2** for deploy
- Geo services (self-hosted, called over HTTP): Valhalla (routing), Nominatim (geocoding), PMTiles (tiles)

## Running locally (Docker — recommended)

The dev image (`Dockerfile.dev`) provides the Ruby 3.4 toolchain and native gems, avoiding host
build issues. From the **repo root**:

```bash
# 1. Start PostGIS (published on host port 5432)
docker compose -f infra/docker-compose.yml up -d postgres

# 2. Build the backend dev image
docker compose -f infra/docker-compose.yml build backend

# 3. Prepare the dev database and run the server
docker compose -f infra/docker-compose.yml run --rm backend bin/rails db:prepare
docker compose -f infra/docker-compose.yml up backend      # http://localhost:3000
```

The geo services (routing/geocoder/tileserver) are defined in
[`infra/docker-compose.yml`](../infra/docker-compose.yml) and start with `docker compose up`, but they
require pre-built OSM data — run the build scripts first (see
[`infra/scripts/`](../infra/scripts/) and [geo-stack.md](../docs/runbooks/geo-stack.md)).
In `test`, geo services are **stubbed with recorded fixtures** so the suite is deterministic and makes
no network calls.

### Configuration

Connection settings come from environment variables (defaults target the Docker stack):

| Var | Default | Notes |
|-----|---------|-------|
| `DATABASE_HOST` | `localhost` | `postgres` inside the compose network |
| `DATABASE_PORT` | `5432` | published on host `5432` for ad-hoc DB tools |
| `DATABASE_USER` / `DATABASE_PASSWORD` | `flckd` / `flckd` | |
| `DATABASE_NAME` / `TEST_DATABASE_NAME` | `flckd_development` / `flckd_test` | |
| `ROUTING_URL` / `GEOCODER_URL` | private service URLs | self-hosted only |
| `GEOCODER_VIEWBOX` | _(unset)_ | bounding box for Nominatim result ranking (lng_min,lat_max,lng_max,lat_min). Only consulted in the **single-state dev override** (`GEOCODER_REGION_STATE` set); otherwise the viewbox comes from `Geocoding::CountryRegistry` (whole-country, default US). The Iowa dev example is `"-96.7,43.6,-90.0,40.3"`. |

## Tests (Constitution Principle II — must be green to merge)

Run the full suite in the dev container against the `test` database:

```bash
docker compose -f infra/docker-compose.yml run --rm \
  -e RAILS_ENV=test -e TEST_DATABASE_NAME=flckd_test \
  backend bundle exec rspec
```

Lint (zero warnings required):

```bash
docker compose -f infra/docker-compose.yml run --rm backend bundle exec rubocop
```

Test layout under `spec/`: `models/`, `requests/`, `services/`, `jobs/`, `contract/`
(OpenAPI conformance), and `performance/` (latency budgets — route p95 < 2 s, geocode p95 < 300 ms).

> Note: `maintain_test_schema!` is intentionally disabled (PostGIS columns don't round-trip through the
> schema dumper). The test DB is migrated directly via `db:prepare` / `db:migrate`.

## Camera data pipeline

```bash
# Import + snap a sample camera fixture set for the extract region
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:import SOURCE=fixture
```

Jobs run on Solid Queue; the recurring refresh is configured in [`config/recurring.yml`](config/recurring.yml).
A camera missing from its source for `CAMERA_REFRESH_MISSING_LIMIT` refreshes is **auto-retired** (a
recoverable `auto_retired` flag — revived if the source reports it again), distinct from a terminal human
`removed`; both are excluded from routing.

## API

Versioned under `/api/v1` — contract in
[`specs/002-flock-route-avoidance/contracts/openapi.yaml`](../specs/002-flock-route-avoidance/contracts/openapi.yaml).
Endpoints: `POST /routes`, `GET /geocode/search`, `POST /geocode/reverse`, `GET /cameras`,
`GET /coverage`, `GET /coverage/bounds`, `GET /meta/locales`, `GET /health`.

`POST /routes` always avoids cameras maximally: it returns a fully camera-free route when one exists and
otherwise **automatically** returns the fewest-cameras route (`is_fully_clean: false`) — it never errors for
lack of a clean route. `RoutePlanner` picks among the fastest route, an iterative-exclusion route, and a
"quiet" surface-street route, falling back on a time-vs-camera-proximity objective when nothing is fully
clean. `GET /cameras` returns each camera's `facing_direction`, `snapped_location`, and monitored `segment`
for map rendering.

## Deployment

Kamal 2 config in [`config/deploy.yml`](config/deploy.yml) (production image: [`Dockerfile`](Dockerfile),
Thruster on port 80). The geo services deploy as Kamal **accessories** on the same private network —
our infrastructure, never third parties. Populate `<PLACEHOLDER>` hosts and `.kamal/secrets`, then:

```bash
kamal setup    # first deploy
kamal deploy   # subsequent deploys
```

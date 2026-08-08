<!-- SPECKIT START -->
**Active feature**: _none in progress_ — most recently shipped: `013-printable-directions` (below).

> **Consolidated memory**: all shipped specs (002–013) are archived into
> [`.specify/memory/`](.specify/memory/) — `spec.md` (per-feature requirements + a Superseded/Evolved
> section authoritative for the current state), `plan.md` (implemented architecture, endpoints, config,
> and a Known Issues & Gotchas digest), and `changelog.md`. Consult these for cross-feature context.

Shipped features — one line each; full detail lives in consolidated memory and each
`specs/<id>/spec.md` + `plan.md`:

- `013-printable-directions` — print-only turn-by-turn view via `window.print()` + `@media print`;
  fully client-side, no transmission. Origin/destination labels lifted `RoutePanel` → `PlanRoutePage`.
- `012-preferred-language-detection` — UI language auto-derived from environment signals, resolved
  before first paint; explicit choice wins and persists. `resolveLocale` (FE), `Api::V1::LocaleNegotiator` (BE).
- `011-country-camera-mapping` — deployment scope lifted from one US state to a whole country (default US).
- `010-responsive-layout` — map-dominant responsive layout; presentation-only.
- `009-comparison-route` · `008-viewport-cameras` · `007-zoom-to-origin` · `006-geocoder-housenumber-fix`
  · `005-parallel-tiger-download` · `004-auto-route-priority` · `003-camera-data-aggregation`
  · `002-flock-route-avoidance` (avoidance core).

Post-009 work (no spec dir): camera avoidance is **always maximal with auto-fallback** — no
aggressiveness setting; prefer a zero-camera route, else the fewest-cameras route minimizing
`duration_s + λ·proximity_cost` under a detour cap (never a 422); `RouteNotice` banner when
`is_fully_clean: false`. See `RoutePlanner`, `ProximityScorer`, `RouteCameraDetector`. Also: camera
map rendering (snapped dots, vision cones per `facing_direction`, 360° halos) and camera lifecycle
(recoverable `auto_retired` vs terminal human `removed`).

**Stack**: Ruby 3.4.x + Rails 8.1.x (latest stable, API mode) backend; TypeScript + React 19 (Vite, MapLibre GL JS)
frontend; PostgreSQL 17 + PostGIS. Rails 8.1 built-ins in use: Solid Queue (jobs, with job continuations), Solid Cache,
Kamal 2 + Thruster (deploy). No Rails auth generator (account-less by design).

**Self-hosted geo stack** (own infrastructure — never third parties): Valhalla (segment-exclusion
routing), Nominatim (forward/reverse geocoding), self-hosted vector tiles (Protomaps PMTiles via go-pmtiles).
The same engines run in dev (docker-compose) and prod (Kamal accessories) — no dev/prod geocoder/tile drift.

**Non-negotiables**:
- Strict anonymity — no third party ever receives a user's origin/destination/route; no accounts/PII;
  no persistent identifiers; logs must not retain route coordinates or client IPs. No transmission
  exception: the only way a route leaves the app is a user-initiated, fully client-side GPX export
  (the file is built in the browser and saved to the user's own device — nothing is sent anywhere —
  and the user is warned that the file itself holds their route). The old "open in Apple/Google Maps"
  handoff was removed: external apps recompute their own route (defeating camera avoidance) and the
  handoff transmitted the endpoints to a third party.
- Camera avoidance = exclude the specific monitored road segment(s) (snap-to-road), not a radius.
- Tests are required for every behavioral change (Constitution Principle II); geo services are stubbed
  with recorded fixtures so tests stay deterministic.

For full technical context, project structure, and commands, read the plan and quickstart.
<!-- SPECKIT END -->

<!-- HAND-MAINTAINED — speckit does not regenerate below this line -->

## Dev & test — Docker-only

Nothing runs on the host: never invoke `pnpm`, `bundle`, `rails`, `rspec`, or `eslint` directly.
Everything goes through `infra/docker-compose.yml`. CI is pull_request-only, so run checks locally
before opening a PR.

```sh
COMPOSE="docker compose -f infra/docker-compose.yml"
$COMPOSE up -d postgres                                                  # DB only
$COMPOSE run --rm --no-deps -e RAILS_ENV=test backend bin/rails db:prepare
$COMPOSE run --rm --no-deps -e RAILS_ENV=test backend bundle exec rspec  # + rubocop, brakeman, bundler-audit
$COMPOSE run --rm --no-deps frontend pnpm test -- run                    # + pnpm lint, pnpm exec tsc -b --noEmit
```

Gotchas:
- Always pass `--no-deps` to `compose run` for tests. The backend service `depends_on` the geo
  stack, and starting the geocoder kicks off a ~20-minute Nominatim import. Tests stub geo services.
- After any lockfile change, refresh the named dependency volumes first (`bundle_cache` and
  `frontend_node_modules` shadow the images): `$COMPOSE run --rm --no-deps backend bundle install`
  and `$COMPOSE run --rm --no-deps frontend pnpm install`.
- `-f` disables automatic `docker-compose.override.yml` loading; use an explicit second `-f` if needed.

## Layout

`backend/` Rails API · `frontend/` React + Vite · `infra/` compose, Kamal, terraform, scripts ·
`specs/` per-feature spec-kit dirs · `docs/adr/` decisions · `docs/runbooks/` ops ·
`test/infra/` bats tests for infra scripts

# flckd — Implementation Progress (ARCHIVED HISTORICAL SNAPSHOT)

> **⚠️ ARCHIVED — DO NOT TRUST THIS FILE FOR CURRENT STATE.** This is a point-in-time log from the
> 002-MVP build through the 003 implementation passes (last touched 2026-06-01). It is kept only for
> historical context. **Trust `main`, `CLAUDE.md`, and `specs/` over anything below.** The dated
> sections describe superseded mid-implementation states and contradict each other by design.
>
> **Known-false claims in the body, corrected here so nobody is misled:**
> - **Production snap-to-road WORKS.** The body (deferral notes) says the OSM road table / snapping
>   "no-ops safely." That is obsolete. Snapping runs in production via
>   `backend/app/services/camera_data/valhalla_road_lookup.rb`, which is the default `road_lookup` in
>   `backend/app/jobs/data_refresh_job.rb`. The `OsmRoadLookup` the body mentions is an unused
>   alternative path, not the live one.
> - **US3 (i18n) and US4 (avoidance-control UI) are DONE.** The body lists them as "not started." Both
>   shipped — see `frontend/src/components/` (`AvoidanceControl`, `CameraSummary`, `CameraLayer`),
>   `frontend/src/i18n/`, and `frontend/tests/` (`avoidance-control.test.tsx`, `camera-summary.test.tsx`,
>   etc.).
>
> Features 002 (route planner) and 003 (camera aggregation) have shipped to `main`, along with later
> branch-only work (review hardening, refresh ops, the 08:00 UTC schedule, refresh fan-out/checkpointing,
> geo build pipeline, deploy runbooks). See `git log` for the current picture.

**Date**: 2026-06-01

## ✅ FEATURE 003 — Aggregated Camera Data Source-of-Truth COMPLETE (2026-06-01)

`/speckit.implement` pass on feature `003-camera-data-aggregation`. tasks.md **42/42 done**. RSpec
**133 examples, 0 failures**; rubocop clean. All work runs in Docker.

- **US1 — multi-source aggregation (MVP)**: `Sources::Deflock` (DeFlock-curated OSM ALPR via Overpass, ODbL —
  DeFlock has no public camera API, so we ingest its OSM substrate, not scraping; see research R1),
  `Sources::UsTiles` (continental-US bbox grid), `Sources::Overpass` extended with a `tiles:` mode
  (sequential, rate-limit backoff). `Importer` now returns `Stats(added/updated/skipped)`, stamps
  `last_seen_in_source_at`, requires a license via `for_source` (FR-005), and skips malformed records.
  `AggregateImport` isolates per-source failures, skips licenseless sources, returns per-source counts +
  overall status, and snaps new cameras (dedup at the monitored-segment layer — one avoidance target per OSM
  way). Rake: `SOURCE=overpass|deflock|geojson|aggregate`.
- **US2 — scheduled + manual refresh**: `DataRefreshJob` repointed to run the full nationwide aggregate,
  creates a `RefreshRun`, refreshes coverage freshness; non-overlapping (Solid Queue `limits_concurrency` +
  a `running` RefreshRun guard). `config/recurring.yml` → fixed **`0 8 * * *` (08:00 UTC, per feature 006)**. Manual
  `rake camera_data:refresh`.
- **US3 — integrity + audit**: `cameras` gained `last_seen_in_source_at`, `consecutive_missing_count`,
  `stale` (migration). `Camera#seen_in_source!` / `#mark_missing!` (auto-retire at 3 misses, verified
  exempt). `StaleReconciler` (per-source, post-success only — failed source keeps last-good). `RefreshRun`
  model + table records per-source counts/status/duration (no user data). `CameraData::RefreshStatus`
  presenter + `rake camera_data:refresh:status [-- --json]`.
- **Polish**: anonymity spec (RefreshRun carries no user-data keys/columns), perf (duration_ms recorded;
  ≤60-min nationwide budget documented), rubocop zero-warnings, full suite green.

Spec-kit artifacts: `specs/003-camera-data-aggregation/` (spec, plan, research, data-model, contracts,
quickstart, tasks, checklist). Clarifications resolved: fixed 10:00 UTC; segment-layer dedup; 3-miss
auto-retire (verified exempt); v1 sources = DeFlock + OSM + open-data/FOIA file importer; nationwide extent.

⚠️ Live nationwide refresh requires a reachable Overpass endpoint (`OVERPASS_URL`, self-hostable) and the
Valhalla routing graph for snapping; both are stubbed in tests (WebMock) and best-effort no-ops in dev.

---

## ✅ US2 / US3 / US4 BACKEND + US4 FRONTEND ADDED (2026-06-01)

Second `/speckit.implement` pass. tasks.md now **62/81 done**. RSpec **39 examples, 0 failures**.

- **US2 (anonymity hardening)**: `config/initializers/anonymity_logging.rb` (filter geo params, drop client IP from log tags, coord scrubber), `content_security_policy.rb` (self-origin only), `rack_attack.rb` (coarse non-retained IP buckets), `cors.rb` (closed unless FRONTEND_ORIGIN). Spec: `spec/requests/anonymity_spec.rb` (no cookie, no PII tables, filtered params).
- **US3**: `config/locales/es.yml`; `spec/requests/i18n_spec.rb` (localized errors en/es), `locales_spec.rb`.
- **US4**: preference-passthrough spec (`routes_preference_spec.rb`), `cameras_spec.rb`; frontend `AvoidanceControl`, `CameraSummary`, `CameraLayer`, `cameraApi.ts`; PlanRoutePage recalculates on preference change (no flow restart); RoutePanel takes a `preference` prop.
- **Refactor**: extracted `Routing::Result` into `app/services/routing/result.rb` (Zeitwerk autoload — specs referencing it directly now load). Re-fixed the routes_controller 400-guard (had reverted).
- **Config**: `.github/workflows/ci.yml` (lint+test gates); Vitest infra + 2 component tests. `tsc -b --noEmit` clean.

⚠️ Frontend Vitest can't run locally (Node 22.3 < vite 8's 22.12 + rolldown native binary) — runs in CI. Backend remains Docker-only.

Remaining (19): T009 (OSM scripts), T025 (OpenAPI contract test), T026/T027/T046/T054/T055/T065 (frontend unit + Playwright E2E), T072-T077 (perf/a11y/recurring jobs/observability/Kamal), T078-T081 (TS-from-OpenAPI, READMEs, quickstart verify, security review). Live geo stack still needs OSM extracts.

---
**(earlier date: 2026-05-31 — original MVP)**
**Feature**: Camera-Avoiding Route Planner (anonymous, mobile-first, multi-lingual web app that plans driving routes avoiding Flock/ALPR cameras)

This file captures the state of the `/speckit.implement` MVP build so anyone can pick it up.

---

## ⏸️ END OF DAY 2026-05-31 — resume here tomorrow

**Status at shutdown**: Backend MVP code + RSpec specs all written. Backend boots & eager-loads in Docker (Ruby 3.4.9 / Rails 8.1.3). DBs created, PostGIS verified, **`db/structure.sql` generated (SQL schema format)**, **test DB schema loaded** (tables: cameras, monitored_segments, coverage_areas, data_sources, schema_migrations).

**Last action (incomplete)**: Was running the RSpec suite (`docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bundle exec rspec`) — **interrupted before results were captured**, so the suite has NOT been confirmed green yet.

**FIRST THING TOMORROW**:
1. `docker compose -f infra/docker-compose.yml up -d postgres`
2. `docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bundle exec rspec --format progress > /tmp/rspec.txt 2>&1` then Read /tmp/rspec.txt. Fix any failures.
3. Then continue to FRONTEND + mark tasks [X] (see NEXT STEPS below).

**Containers were shut down** (`docker compose -f infra/docker-compose.yml down`) at end of day. The `pg_data` and `bundle_cache` named volumes persist, so postgres data + installed gems survive the restart. The `infra-backend` image is built.

**Committed?**: WIP committed at end of day so nothing is lost (see Git state section — look for the latest "wip" commit on branch `002-flock-route-avoidance`).

---

## TL;DR — where we are

Spec-kit design is **complete and committed** (constitution, spec, clarifications, plan, research, data-model, contracts, tasks). We are mid-way through implementing the **MVP = Phases 1+2+3 (User Story 1)** per `specs/002-flock-route-avoidance/tasks.md`.

- ✅ **Backend (Rails 8.1.3 / Ruby 3.4.9) runs in Docker** — `BOOT_OK` verified, all code eager-loads (`EAGER_OK`), 5 migrations applied, PostGIS verified.
- ✅ **Phase 2 foundational + Phase 3 US1 backend code is written** (models, controllers, services, jobs, serializer, rake, seeds, locales).
- 🚧 **Tests not yet written/run** (RSpec is installed; geo_fakes.rb written; specs pending).
- 🚧 **Frontend** scaffolded (Vite React-TS) but **no app code or deps added yet**.
- ❌ **Nothing from this implementation session is committed yet** (user chose "MVP now, commit after").
- ❌ tasks.md checkboxes not yet marked `[X]`.

---

## CRITICAL environment facts (read before running anything)

1. **Host Ruby is BROKEN — do not use it.** macOS 26.5 (build 25F71) + Apple clang 21 produce asdf/ruby-build Rubies (3.4.9 AND 4.0.3) that **cannot load native C extensions** (`dlopen ... symbol not found in flat namespace '_ruby_global_name_punct_bits'` for ripper; `Init_msgpack` for msgpack). This affects ANY gem with a native ext. **Decision: run the backend entirely in Docker.** Do not try to `bundle`/`rails` on the host.

2. **Backend runs via Docker Compose only.** All Rails commands:
   ```
   docker compose -f infra/docker-compose.yml run --rm backend <cmd>
   # e.g. ... run --rm backend bin/rails db:migrate
   # tests: ... run --rm -e RAILS_ENV=test backend bundle exec rspec
   ```
   Postgres: `docker compose -f infra/docker-compose.yml up -d postgres` (host port **5433**, container `postgres:5432`).

3. **Frontend uses host Node toolchain** (works fine): Node 22.3.0, **pnpm 10.34.1** (installed standalone; corepack pnpm was broken). Use `$HOME/.asdf/shims/pnpm` / `npm`. Node has no native-ext issue.

4. **Inline bash stdout is flaky in this environment** — frequently returns empty. Workaround used throughout: redirect command output to `/tmp/*.txt` and `Read` the file. Keep doing this.

5. **Latest stable versions (verified via web 2026-05-31)**: Ruby 4.0.5 and Rails 8.1.3 are "latest stable", BUT **Rails 8.1.3 requires Ruby < 4.0**, and host Ruby 4.0/3.4 native exts are broken anyway. **We use Ruby 3.4.9 + Rails 8.1.3 inside the `ruby:3.4-slim` Docker image** (where native exts compile fine). `.tool-versions` pins `ruby 3.4.9` / `nodejs 22.3.0` for the host (only matters for frontend).

---

## Git state

Committed on both `main` and `002-flock-route-avoidance` (from earlier in session):
- `feb401f` constitution v1.0.0 + spec-kit git extensions (pre-existing)
- `1cc3921` align tasks-template with constitution Principle II; bump to v1.0.1
- `329f913` stop tracking spec-kit integration manifest (+ `.gitignore`)

**Uncommitted (this session's work)** — needs a commit:
- `CLAUDE.md` (SPECKIT block updated with stack + non-negotiables)
- `.tool-versions` (new)
- `specs/002-flock-route-avoidance/` (spec.md, plan.md, research.md, data-model.md, contracts/openapi.yaml, quickstart.md, tasks.md, checklists/requirements.md)
- `.specify/feature.json`
- `backend/` (entire Rails app + our code)
- `frontend/` (Vite scaffold)
- `infra/docker-compose.yml`, `backend/Dockerfile.dev`

Note: `.specify/integrations/claude.manifest.json` is gitignored (renamed reality: the tracked file is `.specify/integrations/speckit.manifest.json`). When committing, use the per-commit Co-Authored-By trailer:
```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## What was built (files created/modified this session)

### Infra
- `infra/docker-compose.yml` — postgres (postgis/postgis:16-3.4, host port 5433), backend (build from Dockerfile.dev, bind-mounts ../backend, depends on healthy postgres). Geo services (valhalla/pelias/tileserver) are commented out until OSM extracts exist.
- `backend/Dockerfile.dev` — ruby:3.4-slim + build-essential, libpq-dev, libgeos-dev, libproj-dev, libyaml-dev, postgres-client; bundles gems.

### Backend config
- `backend/Gemfile` — rewrote: rails ~>8.1.3, pg, puma, solid_cache/queue/cable, propshaft, thruster, **activerecord-postgis-adapter, rgeo, rgeo-activerecord, rgeo-geojson, rails-i18n, rack-attack, faraday, oj, rack-cors**, and dev/test: rspec-rails, factory_bot_rails, faker, simplecov, brakeman, rubocop-rails-omakase. **bootsnap REMOVED** (msgpack native-ext failure; documented in Gemfile comment).
- `backend/Gemfile.lock` — generated in-container (397 lines).
- `backend/config/database.yml` — rewritten to `adapter: postgis` + `DATABASE_*` env vars.
- `backend/config/routes.rb` — API v1 namespace: routes#create, geocode/search, geocode/reverse, coverage#show, cameras#index, meta/locales#index, api/v1/health.
- `backend/config/locales/en.yml` — error/coverage/route strings.
- `backend/.ruby-version` — `3.4.9`.

### Phase 2 — Foundational (DONE, migrated)
- Migrations (all applied): `db/migrate/20260531000001_enable_postgis.rb`, `..02_create_data_sources.rb`, `..03_create_cameras.rb` (st_point location, GiST), `..04_create_monitored_segments.rb` (line_string, GiST, osm_way_id), `..05_create_coverage_areas.rb` (multi_polygon, GiST).
- Models: `app/models/data_source.rb`, `camera.rb` (scopes `active`/`routable`, verification states), `monitored_segment.rb` (scope `for_routing`), `coverage_area.rb` (scopes `containing`/`covers?`).
- `app/controllers/api/v1/base_controller.rb` — structured localized errors `{code,message,details?}`, locale switching from `?locale=`/Accept-Language.
- `app/controllers/api/v1/health_controller.rb`.
- `app/services/geo/http_client.rb` — Faraday base + `ServiceError`.

### Phase 3 — US1 route flow (DONE writing, NOT tested)
- `app/services/geocoding/geocoder_client.rb` — Pelias autocomplete/reverse.
- `app/services/routing/routing_engine_client.rb` — Valhalla client, normalizes route+maneuvers, supports exclude_polygons + costing_options.
- `app/services/routing/segment_exclusion_builder.rb` — monitored segments in bbox → buffered exclusion polygons (PostGIS ST_Buffer/ST_AsGeoJSON).
- `app/services/routing/route_planner.rb` — **two-pass** (avoid=hard exclude → fallback penalize; balanced=penalize; fastest=none). Builds `Routing::Result` struct with cameras_avoided_count, remaining_cameras, is_fully_clean, fastest_comparison, coverage_warning.
  - ⚠️ **KNOWN GAP**: `decoded_line_ewkt` returns `nil` (polyline decoding not implemented), so `remaining_cameras_on` currently returns `[]`. Real impl needs to decode Valhalla's encoded polyline (precision 6) to a LineString for the PostGIS intersection. Tests should use fakes that supply geometry, or this needs finishing.
- `app/services/routing/maneuver_localizer.rb` — maps maneuver types → localized text.
- `app/controllers/api/v1/routes_controller.rb` (POST, permits origin/destination lat/lng + avoidance_preference + locale).
- `app/controllers/api/v1/geocoding_controller.rb`, `coverage_controller.rb`, `cameras_controller.rb`, `locales_controller.rb`.
- `app/serializers/route_serializer.rb` — matches openapi.yaml Route schema.
- `app/services/camera_data/importer.rb` — upsert by (data_source, external_ref); RGeo point.
- `app/services/camera_data/segment_snapper.rb` — snaps camera→nearest road via injected `road_lookup`.
- `app/services/camera_data/osm_road_lookup.rb` — production lookup; returns nil if `osm_roads` table absent (out of MVP scope), so snapping is a safe no-op for now.
- `app/jobs/camera_import_job.rb`, `app/jobs/segment_snap_job.rb` (Solid Queue).
- `lib/tasks/camera_data.rake` — `camera_data:import SOURCE=fixture`.
- `db/fixtures/cameras.json` — 3 Denver fixture cameras.
- `db/seeds.rb` — US coverage area + fixture cameras (idempotent).

### Tests (STARTED)
- RSpec installed (`.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`).
- `spec/support/geo_fakes.rb` — written: `FakeRoutingEngine` (clean/penalized/raise_on_exclude), `FakeGeocoder`, `sample_route` helper.
- Was about to read `spec/rails_helper.rb` to (a) require support files, (b) confirm DB/transaction config.

---

## NEXT STEPS (in order)

1. **Finish RSpec wiring**: in `spec/rails_helper.rb` uncomment/add `Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }`. Ensure `RAILS_ENV=test` DB is migrated: `docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bin/rails db:prepare`.

2. **Write specs FIRST (Constitution Principle II — REQUIRED, tests are not optional)**:
   - `spec/models/` for Camera (scopes, validations, remove!/verify!), MonitoredSegment (for_routing), CoverageArea (covers?), DataSource.
   - `spec/services/routing/route_planner_spec.rb` — inject FakeRoutingEngine + a stub exclusion builder; assert: clean route → is_fully_clean true; raise_on_exclude → minimum-exposure (is_fully_clean false); fastest pref → no exclusion. **This is the highest-value test.**
   - `spec/services/camera_data/importer_spec.rb` and `segment_snapper_spec.rb` (stub road_lookup).
   - `spec/requests/api/v1/routes_spec.rb` — POST /api/v1/routes; stub `Routing::RoutePlanner` or its routing client via the fakes. Cover the 3 acceptance scenarios.
   - `spec/requests/api/v1/coverage_spec.rb`, `cameras_spec.rb`.
   - Contract check vs `specs/002-flock-route-avoidance/contracts/openapi.yaml` (validate response keys).
   - Run: `docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bundle exec rspec` → capture to /tmp and Read.
   - **Likely fix needed**: RoutePlanner injects `RoutingEngineClient.build`/`SegmentExclusionBuilder.new` as defaults — good for DI in tests. But `remaining_cameras_on` polyline decoding gap (above) — either implement decoding or have tests assert remaining=[] for clean and rely on exclusion segment count for avoided count.

3. **Frontend (Phase 3 US1 UI)** — in `frontend/`:
   - `$HOME/.asdf/shims/pnpm add maplibre-gl @tanstack/react-query react-i18next i18next react-router` (and `pnpm add -D vitest @testing-library/react @testing-library/jest-dom jsdom @playwright/test`).
   - Write: `src/services/apiClient.ts`, `routeApi.ts`, `geocodeApi.ts`; `src/components/MapView.tsx` (MapLibre, self-hosted tiles only — no third-party), `RoutePanel.tsx` (origin/dest + geocode autocomplete), `RouteResult.tsx` (geometry + localized maneuvers + fastest comparison + camera counts), `src/hooks/useGeolocation.ts`; `src/pages/PlanRoutePage.tsx`; `src/i18n/` (en + es bundles, auto-detect + switcher); wire `App.tsx` + QueryClientProvider. Vite proxy `/api` → `http://localhost:3000`.
   - Typecheck: `pnpm build`. Add Vitest config + a couple component tests.
   - Note: Vite scaffold installed React **19** (newer than plan's React 18) — fine, or pin to 18 if strictness desired.

4. **Phase 1 leftovers**: ESLint/Prettier configs (eslint.config.js exists from Vite), Playwright config, CI workflow `.github/workflows/ci.yml` (lint+test gates), `infra/scripts/fetch-extract.sh` + routing/tile build scripts (can stub for MVP).

5. **Mark tasks [X]** in `specs/002-flock-route-avoidance/tasks.md` for completed T001–T043 items; leave geo-stack/OSM-import and untested items unchecked with a note.

6. **Verify MVP** end-to-end if time: `docker compose ... run --rm backend bin/rails db:seed`, boot server, `curl` POST /api/v1/routes (will need routing service OR a fake — real Valhalla is out of MVP scope, so verification is via specs + a controller-level stub).

7. **Commit** everything on `002-flock-route-avoidance` (user chose "MVP now, commit after"). Consider logical commits: (a) spec-kit artifacts + CLAUDE.md + .tool-versions, (b) infra/docker, (c) backend MVP, (d) frontend MVP. Then offer the optional `after_implement` git hook (it's `enabled: false`, so only on request).

---

## Scope notes / deliberate deferrals

- **Self-hosted geo stack (Valhalla/Pelias/tiles) not running** — needs multi-GB OSM extracts built in Docker (`infra/scripts/`), out of MVP scope. Backend talks to them via `ROUTING_URL`/`GEOCODER_URL` env (default to compose service names). MVP verification relies on RSpec fakes, not live engines.
- **US2 (anonymity hardening), US3 (full i18n/maneuver localization beyond scaffolding), US4 (avoidance control UI), Polish** — not started (later passes per "MVP now").
- **OSM road table for snapping** — not imported; `OsmRoadLookup` no-ops safely.
- Tasks template was already updated so **tests are REQUIRED** (constitution v1.0.1, Principle II).

## Quick reference — verified working commands
```
# DB up
docker compose -f infra/docker-compose.yml up -d postgres
# migrate / boot / eager-load (all previously succeeded)
docker compose -f infra/docker-compose.yml run --rm backend bin/rails db:migrate
docker compose -f infra/docker-compose.yml run --rm backend bin/rails runner 'puts "BOOT_OK"'
docker compose -f infra/docker-compose.yml run --rm backend bin/rails runner 'Rails.application.eager_load!; puts "EAGER_OK"'
# tests (next)
docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bundle exec rspec
# frontend
cd frontend && $HOME/.asdf/shims/pnpm install && $HOME/.asdf/shims/pnpm build
```

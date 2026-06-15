---
description: "Dependency-ordered tasks for the Camera-Avoiding Route Planner"
---

# Tasks: Camera-Avoiding Route Planner

**Input**: Design documents from `/specs/002-flock-route-avoidance/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml

**Tests**: REQUIRED per Constitution Principle II (Testing Standards, NON-NEGOTIABLE). Every behavioral
change ships with automated tests; write tests FIRST and ensure they FAIL before implementation. Geo
services (routing/geocoding/tiles) are stubbed with recorded fixtures so the suite stays deterministic.

**Organization**: Tasks are grouped by user story for independent implementation and testing.

**Stack**: Ruby 3.4.x + Rails 8.1.x (API mode) · TypeScript + React 18 (Vite, MapLibre GL JS) ·
PostgreSQL 16 + PostGIS · self-hosted Valhalla (routing), Pelias (geocoding), Protomaps/PMTiles (tiles)
· Solid Queue (jobs).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1–US4 (user-story phases only)
- File paths are repo-relative.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton, toolchains, and the self-hosted geo stack for local dev.

- [x] T001 Create the repo structure `backend/`, `frontend/`, `infra/` per plan.md Project Structure
- [x] T002 Initialize a Rails 8.1 API-only app in `backend/` targeting Ruby 3.4 with `Gemfile` deps: `rails ~> 8.1`, `pg`, `activerecord-postgis-adapter`, `rgeo`, `rgeo-activerecord`, `faraday`, `oj`, `rack-attack`, `rails-i18n`
- [x] T003 [P] Install & configure RSpec, FactoryBot, Faker, SimpleCov in `backend/` (`rails g rspec:install`, `backend/spec/rails_helper.rb`)
- [x] T004 [P] Configure RuboCop + rubocop-rails at zero warnings in `backend/.rubocop.yml`
- [x] T005 Initialize React 18 + TypeScript (Vite) app in `frontend/` with deps `maplibre-gl`, `@tanstack/react-query`, `react-i18next`, `i18next`, `react-router`
- [x] T006 [P] Configure ESLint + Prettier (zero warnings) and strict `tsconfig.json` in `frontend/`
- [x] T007 [P] Configure Vitest + React Testing Library + Playwright in `frontend/` (`frontend/vitest.config.ts`, `frontend/playwright.config.ts`)
- [x] T008 [P] Create `infra/docker-compose.yml` with services: postgres+postgis, valhalla (routing), pelias (geocoder), tileserver (PMTiles/Martin)
- [x] T009 [P] Create `infra/scripts/fetch-extract.sh` plus routing-graph and vector-tile build scripts for a US metro OSM extract
- [x] T010 Configure CI workflow running the lint + test gates for backend and frontend in `.github/workflows/ci.yml` (Constitution Quality Gates)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database, shared data models, API scaffolding, geo-client base, i18n base, and the
deterministic test harness. **No user story can begin until this phase is complete.**

- [x] T011 Add PostGIS enable migration and configure the postgis adapter in `backend/config/database.yml` + `backend/db/migrate/*_enable_postgis.rb`
- [x] T012 [P] Create DataSource model + migration in `backend/app/models/data_source.rb`
- [x] T013 [P] Create Camera model + migration (PostGIS point, GiST index, verification_status enum, validations) in `backend/app/models/camera.rb`
- [x] T014 [P] Create MonitoredSegment model + migration (LineString geometry, `osm_way_id`, direction enum) in `backend/app/models/monitored_segment.rb`
- [x] T015 [P] Create CoverageArea model + migration (MultiPolygon, GiST index) in `backend/app/models/coverage_area.rb`
- [x] T016 Create API v1 namespace + routes skeleton in `backend/config/routes.rb` and base controller with structured, localized error handling (Error schema from openapi.yaml) in `backend/app/controllers/api/v1/base_controller.rb`
- [x] T017 [P] Create base JSON serializer + application serializer in `backend/app/serializers/application_serializer.rb`
- [x] T018 [P] Implement Faraday-based geo HTTP client base (timeouts, private-network only) in `backend/app/services/geo/http_client.rb`
- [x] T019 [P] Scaffold base i18n config — backend `backend/config/locales/en.yml` and frontend `frontend/src/i18n/index.ts` + `frontend/src/i18n/locales/en.json`
- [x] T020 [P] Create deterministic geo test harness: fake routing/geocoding clients backed by recorded fixtures in `backend/spec/support/geo_fakes.rb` + `backend/spec/fixtures/geo/`
- [x] T021 Add `GET /api/v1/health` endpoint in `backend/app/controllers/api/v1/health_controller.rb`

**Checkpoint**: Foundation ready — user stories can now proceed.

---

## Phase 3: User Story 1 - Plan a driving route that avoids cameras (Priority: P1) 🎯 MVP

**Goal**: A user enters an origin and destination and receives a drivable route that avoids the
monitored road segments of known cameras, shown on a map with localized directions and the fastest-route
trade-off.

**Independent Test**: For an origin/destination whose fastest path crosses a monitored segment, the
returned route avoids it (or is the minimum-exposure route) and renders with directions; a clean-area
pair returns the normal best route.

### Tests for User Story 1 (REQUIRED — Constitution Principle II) ⚠️

> Write these tests FIRST and ensure they FAIL before implementation.

- [x] T022 [P] [US1] Request spec for `POST /api/v1/routes` covering clean route, on-path-camera detour, and no-clean-route minimum-exposure in `backend/spec/requests/api/v1/routes_spec.rb`
- [x] T023 [P] [US1] Service spec for RoutePlanner two-pass logic (exclude → penalize) in `backend/spec/services/routing/route_planner_spec.rb`
- [x] T024 [P] [US1] Service specs for camera Importer and SegmentSnapper in `backend/spec/services/camera_data/importer_spec.rb` and `segment_snapper_spec.rb`
- [x] T025 [P] [US1] Contract test validating `/routes`, `/geocode/*`, `/coverage` responses against `contracts/openapi.yaml` in `backend/spec/contract/openapi_spec.rb`
- [x] T026 [P] [US1] Frontend unit tests for RoutePanel input, geocode autocomplete, and MapView render in `frontend/tests/unit/route-plan.test.tsx`
- [x] T027 [P] [US1] E2E test: enter origin/destination → avoiding route + directions render in `frontend/tests/e2e/plan-route.spec.ts`

### Implementation for User Story 1

- [x] T028 [P] [US1] Camera data Importer (DeFlock / OSM ALPR tags) in `backend/app/services/camera_data/importer.rb`
  - [x] T028a [US1] Real multi-source ingestion: `Sources::Base` adapter contract, `Sources::Overpass` (OSM ALPR via Overpass, ODbL, bbox-scoped, honest UA + rate-limit backoff), `Sources::GeojsonFile` (open-data / FOIA / community exports w/ per-file license), and `AggregateImport` orchestrator into the source-of-truth `cameras` table with per-source provenance/license. WebMock-stubbed specs. Rake: `SOURCE=overpass|geojson|aggregate`.
- [x] T029 [P] [US1] SegmentSnapper (PostGIS snap camera → nearest road, persist `osm_way_id` + geometry) in `backend/app/services/camera_data/segment_snapper.rb`
- [x] T030 [US1] CameraImportJob + SegmentSnapJob (Solid Queue) and `camera_data:import` rake task in `backend/app/jobs/` + `backend/lib/tasks/camera_data.rake`
- [x] T031 [P] [US1] RoutingEngineClient (Valhalla, `exclude_polygons`/costing) in `backend/app/services/routing/routing_engine_client.rb`
- [x] T032 [US1] SegmentExclusionBuilder (active cameras → exclusion set) in `backend/app/services/routing/segment_exclusion_builder.rb`
- [x] T033 [US1] RoutePlanner two-pass strategy building Route (counts, `is_fully_clean`, `fastest_comparison`) in `backend/app/services/routing/route_planner.rb`
- [x] T034 [P] [US1] GeocoderClient (Pelias) forward + reverse in `backend/app/services/geocoding/geocoder_client.rb`
- [x] T035 [US1] Routes controller `POST /api/v1/routes` + Route serializer in `backend/app/controllers/api/v1/routes_controller.rb` and `backend/app/serializers/route_serializer.rb`
- [x] T036 [US1] Geocoding controller `GET /geocode/search` + `POST /geocode/reverse` in `backend/app/controllers/api/v1/geocoding_controller.rb`
- [x] T037 [US1] Coverage controller `GET /coverage` in `backend/app/controllers/api/v1/coverage_controller.rb`
- [x] T038 [P] [US1] Frontend apiClient + route/geocode query hooks (TanStack Query) in `frontend/src/services/apiClient.ts`, `routeApi.ts`, `geocodeApi.ts`
- [x] T039 [P] [US1] MapView component (MapLibre GL, self-hosted PMTiles style — no third-party tiles) in `frontend/src/components/MapView.tsx`
- [x] T040 [US1] RoutePanel: origin/destination inputs with geocode autocomplete + `useGeolocation` (manual entry fallback) in `frontend/src/components/RoutePanel.tsx` + `frontend/src/hooks/useGeolocation.ts`
- [x] T041 [US1] RouteResult: render geometry, localized maneuvers, and fastest-route comparison in `frontend/src/components/RouteResult.tsx`
- [x] T042 [US1] PlanRoutePage mobile-first layout wiring inputs → map → result in `frontend/src/pages/PlanRoutePage.tsx`
- [x] T043 [US1] Dev seed: camera fixtures + coverage area for the extract region in `backend/db/seeds.rb`

**Checkpoint**: US1 independently functional — the MVP. A user can plan and view a camera-avoiding route.

---

## Phase 4: User Story 2 - Use the app anonymously without an account (Priority: P2)

**Goal**: The full flow works with no account/PII, no persistent identifiers, no third-party exposure
of locations; logs retain no coordinates or client IPs. Only exception: explicit, warned open-in-maps.

**Independent Test**: Complete a route with no login/PII; inspect logs (no coords/IP) and network (own
origin only); confirm the maps handoff warns before leaving.

### Tests for User Story 2 (REQUIRED — Constitution Principle II) ⚠️

- [x] T044 [P] [US2] Request spec: after `POST /routes`, logs contain no coordinates/addresses/IP in `backend/spec/requests/anonymity_logging_spec.rb`
- [x] T045 [P] [US2] Request spec: no account/cookie/session required; responses set no identifying cookies in `backend/spec/requests/anonymity_stateless_spec.rb`
- [x] T046 [P] [US2] E2E: zero third-party network requests during full flow; open-in-maps shows a warning first in `frontend/tests/e2e/anonymity.spec.ts`

### Implementation for User Story 2

- [x] T047 [US2] Log redaction: `filter_parameters` + custom log subscriber dropping geo params; drop/truncate client IP in `backend/config/initializers/anonymity_logging.rb`
- [x] T048 [P] [US2] Strict Content-Security-Policy (self-origin only) + security headers in `backend/config/initializers/content_security_policy.rb`
- [x] T049 [P] [US2] rack-attack rate limiting on coarse, non-retained buckets in `backend/config/initializers/rack_attack.rb`
- [x] T050 [P] [US2] Remove session/cookie middleware from the API stack; same-origin CORS in `backend/config/application.rb` + `backend/config/initializers/cors.rb`
- [x] T051 [US2] Open-in-maps handoff (Apple/Google deep links) with a localized pre-handoff warning in `frontend/src/components/ExternalMapsHandoff.tsx`
- [x] T052 [P] [US2] Frontend audit: language pref stored client-side only & non-identifying; no third-party assets/fonts/scripts in `frontend/` (CSP-aligned)

**Checkpoint**: US2 verifiable independently — anonymity guarantees hold for the existing flow.

---

## Phase 5: User Story 3 - Use the app in my own language (Priority: P3)

**Goal**: UI auto-detects the user's language and is fully switchable at runtime; all text including
directions and errors is localized; in-progress input is preserved on switch.

**Independent Test**: Set device language and load; switch languages in-app — all UI, maneuvers, and
errors translate and the current route input persists.

### Tests for User Story 3 (REQUIRED — Constitution Principle II) ⚠️

- [x] T053 [P] [US3] Backend i18n spec: localized errors and maneuver phrasing per locale in `backend/spec/i18n_spec.rb`
- [x] T054 [P] [US3] Frontend test: auto-detect + language switch preserves in-progress input in `frontend/tests/unit/i18n.test.tsx`
- [x] T055 [P] [US3] E2E: switching language updates all UI including directions in `frontend/tests/e2e/i18n.spec.ts`

### Implementation for User Story 3

- [x] T056 [P] [US3] Add backend locale bundles (en, es, +launch set) in `backend/config/locales/*.yml`
- [x] T057 [P] [US3] Add frontend locale bundles in `frontend/src/i18n/locales/*.json`
- [x] T058 [US3] Maneuver localization: map Valhalla maneuver types → localized templates in `backend/app/services/routing/maneuver_localizer.rb`
- [x] T059 [US3] LanguageSwitcher + `navigator.language` auto-detect preserving input in `frontend/src/components/LanguageSwitcher.tsx` + i18n config
- [x] T060 [P] [US3] `GET /api/v1/meta/locales` endpoint in `backend/app/controllers/api/v1/locales_controller.rb`
- [x] T061 [P] [US3] Localize all existing UI strings and add a CI check for missing translation keys in `frontend/`

**Checkpoint**: US3 verifiable independently — the app is fully usable in each launch language.

---

## Phase 6: User Story 4 - Understand and control how cameras are avoided (Priority: P3)

**Goal**: Users choose an avoidance preference (avoid/balanced/fastest), see avoided/remaining camera
counts and cameras on the map, and get clear messaging when no fully clean route exists.

**Independent Test**: Toggle the preference on one route and confirm the route and the avoided/remaining
counts change; the no-clean-route case shows the minimum-exposure explanation.

### Tests for User Story 4 (REQUIRED — Constitution Principle II) ⚠️

- [x] T062 [P] [US4] Request spec: `avoidance_preference` avoid/balanced/fastest changes route + counts in `backend/spec/requests/api/v1/routes_preference_spec.rb`
- [x] T063 [P] [US4] Request spec: `GET /api/v1/cameras` bbox filtering in `backend/spec/requests/api/v1/cameras_spec.rb`
- [x] T064 [P] [US4] Frontend test: preference toggle + CameraSummary display in `frontend/tests/unit/avoidance-control.test.tsx`
- [x] T065 [P] [US4] E2E: toggle preference → avoided/remaining + minimum-exposure message in `frontend/tests/e2e/avoidance-control.spec.ts`

### Implementation for User Story 4

- [x] T066 [US4] RoutePlanner: honor `avoidance_preference` (avoid=exclude, balanced=penalize, fastest=none) in `backend/app/services/routing/route_planner.rb`
- [x] T067 [P] [US4] Cameras controller `GET /api/v1/cameras` (bbox) + serializer in `backend/app/controllers/api/v1/cameras_controller.rb`
- [x] T068 [P] [US4] AvoidancePreference toggle control in `frontend/src/components/AvoidanceControl.tsx`
- [x] T069 [US4] CameraSummary: avoided count + remaining list + minimum-exposure warning in `frontend/src/components/CameraSummary.tsx`
- [x] T070 [P] [US4] Camera layer rendering cameras within the viewport in `frontend/src/components/CameraLayer.tsx`
- [x] T071 [US4] Recalculate route on preference/endpoint change without restarting the flow in `frontend/src/pages/PlanRoutePage.tsx`

**Checkpoint**: All user stories independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Performance budgets, accessibility, scheduled data refresh, observability, deployment.

- [x] T072 [P] Performance tests: route p95 < 2 s and geocode autocomplete p95 < 300 ms with representative data + CI perf gate in `backend/spec/performance/`
- [x] T073 [P] Frontend performance: mobile first-contentful-paint < 2.5 s and bundle budget in `frontend/tests/e2e/perf.spec.ts`
- [x] T074 [P] Accessibility audit (WCAG 2.1 AA via axe) on the core flow in `frontend/tests/e2e/a11y.spec.ts`
- [x] T075 [P] Solid Queue recurring jobs: scheduled camera DataRefreshJob + CoverageArea freshness in `backend/app/jobs/data_refresh_job.rb` + `backend/config/recurring.yml`
- [x] T076 [P] Structured event reporting (Rails 8.1) for route/geocode latency observability in `backend/config/initializers/event_reporter.rb`
- [x] T077 [P] Kamal 2 + Thruster deployment config for backend + geo services in `backend/config/deploy.yml` + `backend/Dockerfile`
- [x] T078 [P] Generate TS types from `contracts/openapi.yaml` into `frontend/src/types/` (contract sync)
- [x] T079 [P] Update `backend/README.md`, `frontend/README.md`, and validate `specs/002-flock-route-avoidance/quickstart.md`
- [x] T080 Run the quickstart end-to-end and verify Success Criteria SC-001…SC-009 are met (see `verification.md`; SC-001/SC-004 statistical sign-off pending a live geo-stack run)
- [x] T081 [P] Security review of anonymity guarantees end-to-end (logs, CSP, no third-party, no PII) (see `verification.md` § T081)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies — start immediately.
- **Foundational (Phase 2)**: depends on Setup — **blocks all user stories**.
- **User Stories (Phases 3–6)**: each depends only on Foundational; otherwise independent. US2/US3/US4
  build on the US1 flow existing but are independently testable slices and can be staffed in parallel
  once Foundational is done.
- **Polish (Phase 7)**: depends on the user stories it touches being complete.

### Story dependencies

- **US1 (P1)**: depends on Foundational only. The MVP.
- **US2 (P2)**: Foundational only; hardens the US1 flow (run in parallel with US1 where files differ).
- **US3 (P3)**: Foundational only; T058 (maneuver localization) integrates with US1's RoutePlanner.
- **US4 (P3)**: Foundational only; T066 modifies US1's RoutePlanner (sequence after T033 if same branch).

### Critical path

Setup → Foundational → US1 (T028→T033 routing chain, then endpoints, then frontend) → ship MVP.

## Parallel Execution Examples

- **Setup**: T003, T004, T006, T007, T008, T009 in parallel after T002/T005.
- **Foundational**: T012, T013, T014, T015 (separate model files) in parallel; T017, T018, T019, T020 in parallel.
- **US1 tests**: T022–T027 all `[P]` — author together first (must fail before impl).
- **US1 impl**: T028, T029, T031, T034 in parallel (distinct services); then T032/T033 (shared planner) sequentially; T038/T039 frontend in parallel with backend.
- **Cross-story**: once Foundational is done, a dev can take US2 (T047–T052), another US3 (T056–T061), another US4 — minimal file overlap except the noted RoutePlanner touches.

## Implementation Strategy

### MVP first

1. Complete Phase 1 (Setup) and Phase 2 (Foundational).
2. Complete Phase 3 (US1) — **stop and validate** the independent test.
3. Deploy/demo the MVP: anonymous, single-language, camera-avoiding routing.

### Incremental delivery

US1 (MVP) → add US2 (anonymity hardening) → US3 (multi-lingual) → US4 (avoidance control) → Polish.
Each story is independently testable and adds value without breaking the previous ones.

---

## Task Summary

- **Total tasks**: 81
- **Setup**: 10 (T001–T010) · **Foundational**: 11 (T011–T021)
- **US1 (P1, MVP)**: 22 (T022–T043) — 6 tests + 16 impl
- **US2 (P2)**: 9 (T044–T052) — 3 tests + 6 impl
- **US3 (P3)**: 9 (T053–T061) — 3 tests + 6 impl
- **US4 (P3)**: 10 (T062–T071) — 4 tests + 6 impl
- **Polish**: 10 (T072–T081)
- **Suggested MVP scope**: Phases 1 + 2 + 3 (US1).

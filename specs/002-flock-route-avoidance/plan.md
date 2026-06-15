# Implementation Plan: Camera-Avoiding Route Planner

**Branch**: `002-flock-route-avoidance` | **Date**: 2026-05-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-flock-route-avoidance/spec.md`

## Summary

An anonymous, mobile-first, multi-lingual web app that plans driving routes which avoid the specific
road segments monitored by known Flock/ALPR cameras. The core promise — strict anonymity — drives the
architecture: **all** geocoding, routing, and map-tile serving run on the product's own
infrastructure, so no external third party ever receives a user's origin, destination, or route. The
only outbound exception is an explicit, user-initiated "open in Apple/Google Maps" handoff.

Technical approach: a **Ruby on Rails (API mode)** backend over **PostgreSQL + PostGIS** orchestrates a
self-hosted geo stack — a routing engine that supports excluding individual road segments, a
self-hosted geocoder, and self-hosted vector map tiles. A **TypeScript + React** single-page app
renders the map with **MapLibre GL JS** (no API keys, no third-party tiles) and is localized from day
one. Camera data is built by a hybrid pipeline: import open/community ALPR datasets (DeFlock /
OpenStreetMap), snap each camera to the road segment(s) it monitors, and layer internal verification on
top — all run as Rails background jobs.

## Technical Context

**Language/Version**: Ruby 3.4.x (latest stable that Rails 8.1 supports — pinned to 3.4.9; Ruby 4.0 is
newer but several native extensions, e.g. msgpack, are not yet binary-compatible with it) with Rails
8.1.x (latest stable — 8.1.3 as of 2026-05-31, API mode) backend; TypeScript 5.x + React 18 frontend.
Pin to the newest stable patch of each at project setup; revisit Ruby 4.0 once the gem ecosystem
catches up.
**Rails 8.1 included features leveraged**: **Solid Queue** (DB-backed background jobs — no Redis) for
the camera-data pipeline, using **job continuations** (Rails 8.1) so long imports survive restarts;
**Solid Cache** (DB-backed cache) for geocode/coverage results; **structured event reporting** (Rails
8.1) for observability of route/geocode latency (Constitution Principle IV); **Propshaft** asset
pipeline; **Kamal 2** + **Thruster** for self-hosted containerized deployment (fits the
own-infrastructure anonymity model). Rails' built-in authentication generator is **intentionally not
used** — the product is account-less and anonymous (FR-010/FR-012).
**Primary Dependencies**:
- Backend (Rails-specific): `rails` 8.1.x (API mode, with Solid Queue/Solid Cache), `pg` +
  `activerecord-postgis-adapter`, `rgeo`/`rgeo-activerecord`, `rails-i18n`, `rack-attack` (rate
  limiting), `faraday` (internal HTTP to geo services), `oj` (JSON). Dev/test: `rspec-rails`,
  `factory_bot_rails`, `faker`, `rubocop`/`rubocop-rails`, `simplecov`. (Background jobs use the
  built-in Solid Queue rather than a third-party gem.)
- Frontend: React 18, Vite, `maplibre-gl`, `@tanstack/react-query`, `react-i18next` + `i18next`,
  `react-router`. Dev/test: Vitest, `@testing-library/react`, Playwright (E2E), ESLint, Prettier.
- Self-hosted geo infrastructure (own servers — not third parties): a segment-exclusion routing engine
  (Valhalla or GraphHopper — decided in research.md), a self-hosted geocoder (Pelias or Nominatim),
  self-hosted vector tiles (Protomaps PMTiles or OpenMapTiles served by Martin/tileserver-gl).
**Storage**: PostgreSQL 16 + PostGIS — camera locations, monitored road-segment references, data
provenance/verification, supported-area coverage. No user/route persistence (see Constraints).
**Testing**: RSpec (backend unit/request/contract), Vitest + React Testing Library (frontend unit),
Playwright (cross-browser E2E incl. mobile viewport), OpenAPI-driven contract tests. Deterministic:
geo services stubbed with recorded fixtures in test; no third-party network calls.
**Target Platform**: Linux containers (backend + geo services); modern mobile & desktop browsers
(iOS Safari, Android Chrome as primary targets).
**Project Type**: web (separate `backend/` Rails API + `frontend/` React SPA)
**Performance Goals**: route response p95 < 2 s server-side (total < 5 s including client render, per
SC-004); geocode autocomplete p95 < 300 ms; mobile first-contentful-paint < 2.5 s on mid-tier device.
**Constraints**: Strict anonymity — no third-party exposure of origin/destination/route (FR-012a); no
accounts/PII (FR-010); no persistent cross-session identifiers (FR-012); request logs MUST NOT retain
route coordinates or client IPs tied to a route (FR-011); mobile-first (no horizontal scroll/zoom to
complete core flow, FR-009); graceful offline/poor-network messaging.
**Scale/Scope**: US-first launch; camera dataset on the order of 10⁴–10⁵ records; US road network in
the routing engine; target low-thousands concurrent users at launch with horizontal scalability.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against the project constitution **v1.0.1**.

| Principle | Gate | Plan compliance |
|-----------|------|-----------------|
| I. Code Quality | Linter/formatter pass with zero warnings; single-responsibility units; intent docs; independent review | RuboCop (+rubocop-rails) for Ruby and ESLint + Prettier for TS, enforced in CI at zero warnings. Routing/geocoding/camera-data each isolated as a single-responsibility service object. All PRs require one independent reviewer. ✅ PASS |
| II. Testing Standards (NON-NEGOTIABLE) | Tests with every behavioral change; deterministic; no coverage decrease; behavior/contract-focused; green CI to merge | RSpec + Vitest/RTL + Playwright. Geo services stubbed via recorded fixtures → deterministic, no third-party calls. Coverage tracked by SimpleCov (backend) and Vitest (frontend); CI blocks merge on red or coverage regression. Tests target API contracts and user-observable behavior. ✅ PASS |
| III. User Experience Consistency | Single naming/error/format convention; actionable errors; human+machine parity; versioned contracts; a11y + i18n | i18n is a first-class feature (US3) via rails-i18n + react-i18next; 100% of strings localized incl. errors. Errors follow one structured, actionable, localized shape. JSON API is the machine contract; OpenAPI is versioned (`/api/v1`). WCAG 2.1 AA targeted; shared terminology glossary in research.md. ✅ PASS |
| IV. Performance Requirements | Budgets defined pre-build; measured with representative data; regression gates; evidence-driven; bounded resources | Budgets above derive from Success Criteria. Perf measured against representative US metro routes and the full camera dataset; CI perf checks gate regressions. Routing engine and DB connection pools are bounded. ✅ PASS |

**Result**: PASS — no violations. Complexity Tracking section omitted (nothing to justify).

## Project Structure

### Documentation (this feature)

```
specs/002-flock-route-avoidance/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── openapi.yaml     # Versioned HTTP API contract (/api/v1)
└── checklists/
    └── requirements.md  # Spec quality checklist (from /speckit.specify)
```

### Source Code (repository root)

```
backend/                         # Ruby 3.4.x + Rails 8.1.x API
├── app/
│   ├── controllers/api/v1/      # routes_controller, geocoding_controller, cameras_controller, tiles
│   ├── models/                  # Camera, MonitoredSegment, CoverageArea, DataSource (ActiveRecord + PostGIS)
│   ├── services/
│   │   ├── routing/             # RoutePlanner, SegmentExclusionBuilder, RoutingEngineClient
│   │   ├── geocoding/           # GeocoderClient, AddressDisambiguator
│   │   └── camera_data/         # Importer (DeFlock/OSM), SegmentSnapper, Verifier
│   ├── serializers/             # JSON shaping for API responses
│   └── jobs/                    # CameraImportJob, SegmentSnapJob, DataRefreshJob (Solid Queue)
├── config/
│   ├── locales/                 # en.yml, es.yml, ... (server-side strings, route-instruction phrasing)
│   └── initializers/            # rack_attack.rb, anonymity/logging redaction, cors.rb
├── db/                          # migrations + PostGIS-enabled schema; seeds for dev camera fixtures
├── lib/tasks/                   # rake tasks: camera data import/refresh
└── spec/                        # RSpec: models/, requests/, services/, contract/

frontend/                        # TypeScript + React SPA
├── src/
│   ├── components/              # MapView (MapLibre), RoutePanel, LanguageSwitcher, CameraSummary
│   ├── pages/                   # PlanRoutePage
│   ├── services/                # apiClient, routeApi, geocodeApi (TanStack Query hooks)
│   ├── i18n/                    # i18next config + locales/{en,es,...}.json
│   ├── hooks/                   # useGeolocation, useRoutePlan
│   └── types/                   # shared API types (generated from openapi.yaml)
└── tests/
    ├── unit/                    # Vitest + React Testing Library
    └── e2e/                     # Playwright (mobile + desktop viewports)

infra/                           # Self-hosted geo stack (own infrastructure)
├── routing/                     # routing-engine config + US graph build scripts
├── geocoder/                    # self-hosted geocoder config + US extract import
├── tiles/                       # vector tile build/serve config (US extract)
└── docker-compose.yml           # local dev: postgres+postgis, routing, geocoder, tileserver
```

**Structure decision**: Web application (Option 2) — a Rails API backend and a React SPA frontend, plus
an `infra/` tree for the self-hosted geo services the anonymity guarantee depends on. The geo engines
run as separate services the Rails app calls over a private network; they are part of our
infrastructure, not third parties, so they do not violate FR-012a.

## Complexity Tracking

> No constitution violations — section intentionally empty.

# flckd — Main Implementation Plan

> Consolidated architecture/plan reflecting the *implemented* state across all archived features
> (002–013). Bootstrapped 2026-06-18 from the full `specs/` directory. Per-feature provenance is
> noted with `[NNN]` tags.

## Architecture Overview

- **Backend**: Ruby 3.4.x + Rails 8.1.x (API mode). Rails 8.1 built-ins: Solid Queue (jobs, recurring
  jobs, job continuations, `limits_concurrency`), Solid Cache, Propshaft, Kamal 2 + Thruster (deploy).
  No Rails auth generator (account-less by design).
- **Frontend**: TypeScript + React 19, Vite, MapLibre GL JS v5, `@tanstack/react-query`,
  react-i18next / i18next, react-router.
- **Data**: PostgreSQL 17 + PostGIS (RGeo + `activerecord-postgis-adapter`).
- **Self-hosted geo stack** (own infrastructure — never third parties): **Valhalla** (segment-exclusion
  routing; dynamic costing + `exclude_polygons`/`exclude_locations` per request), **Nominatim**
  (forward/reverse geocoding; mediagis image + US TIGER), self-hosted **vector tiles** (Protomaps
  PMTiles via go-pmtiles; built with Planetiler/osmium). Same engines in dev (docker-compose) and prod
  (Kamal accessories) — no dev/prod drift.

> Stack evolution: 002 originally specified React 18 / PostgreSQL 16 and named Pelias/GraphHopper as
> primary geocoder/routing; the shipped stack is React 19 / PostgreSQL 17 with Valhalla + Nominatim.

## Primary Dependencies

- **Backend**: Rails 8.1.x, `pg`, `activerecord-postgis-adapter`, `rgeo`/`rgeo-activerecord`,
  `rails-i18n`, `rack-attack`, `faraday`, `oj`; dev/test `rspec-rails`, `factory_bot_rails`, `faker`,
  `webmock`, `rubocop`(+rails), `simplecov`.
- **Frontend**: React 19, `maplibre-gl` (v5), `@tanstack/react-query`, `react-i18next` + `i18next`,
  `react-router`; dev/test Vitest, `@testing-library/react`, Playwright (+ `@axe-core/playwright`),
  ESLint, Prettier.
- **Infra/test**: `bats-core` (Bash script tests, test-only) [005/006/011]; curl, unzip, docker.
- **No new runtime dependency** was introduced by features 003, 004, 007, 008, 009, 010, 012, 013 —
  they reuse the stack above.

## Project Structure (implemented)

```text
backend/                                  # Ruby 3.4 + Rails 8.1 API
├── app/
│   ├── models/
│   │   ├── camera.rb                      # [002] +freshness/lifecycle [003]; auto_retired flag (post-009)
│   │   ├── monitored_segment.rb           # [002] avoidance unit (one per camera+OSM way, unique idx)
│   │   ├── coverage_area.rb               # [002] per-data-region presence + data_freshness_at [011]
│   │   ├── data_source.rb                 # [002] provenance + license/attribution
│   │   └── refresh_run.rb                 # [003] per-source refresh audit
│   ├── services/
│   │   ├── routing/                       # RoutePlanner, SegmentExclusionBuilder, RoutingEngineClient,
│   │   │                                  #   ManeuverLocalizer [002]; ProximityScorer, RouteCameraDetector (post-009)
│   │   ├── geocoding/                     # GeocoderClient, AddressDisambiguator [002];
│   │   │                                  #   CountryRegistry [011]
│   │   └── camera_data/                   # Importer + Sources::{Base,Overpass,GeojsonFile,AggregateImport,
│   │                                      #   Deflock}[003], SegmentSnapper, Verifier [002],
│   │                                      #   StaleReconciler, UsTiles [003]
│   ├── controllers/api/v1/                # routes, geocode, coverage, cameras, meta, base [002];
│   │                                      #   LocaleNegotiator-aware base [012]
│   └── jobs/                              # CameraImportJob, SegmentSnapJob, DataRefreshJob (Solid Queue)
└── spec/                                  # RSpec; geo clients faked via recorded fixtures

frontend/
├── src/
│   ├── components/
│   │   ├── MapView.tsx                     # [002] origin recenter+marker [007]; CameraLayer mount [008];
│   │   │                                   #   comparison layer [009]; map-label language [012]
│   │   ├── RoutePanel.tsx                  # [002] onOriginChange [007]; label lift via onPlan [013]
│   │   ├── RouteResult.tsx                 # [002] comparison/added-distance/toggle [009]; print mount [013]
│   │   ├── CameraLayer.tsx                 # [008] viewport clustering + popup
│   │   ├── CameraSummary.tsx               # [002] avoided/remaining counts
│   │   ├── RouteNotice.tsx                 # (post-009) not-fully-clean banner
│   │   ├── RouteExport.tsx                 # (post-009) client-side GPX export (replaces external-maps handoff)
│   │   ├── PrintableDirections.tsx         # [013] icon trigger + print-only view (window.print)
│   │   ├── LanguageSwitcher.tsx            # [002] runtime switch; clear remembered choice [012]
│   │   └── (removed) PreferenceRadios.tsx / AvoidanceControl.tsx   # deleted by [004]
│   ├── pages/PlanRoutePage.tsx             # lifts origin [007], showComparison [009], O/D labels [013]
│   ├── i18n/
│   │   ├── index.ts                        # synchronous pre-paint locale init [012]
│   │   ├── resolveLocale.ts                # [012] pure q-weighted matcher
│   │   ├── localePreference.ts             # [012] guarded localStorage get/set/clear
│   │   └── locales/{en,es}.json            # catalog (print.* keys [013])
│   ├── services/{apiClient,routeApi,geocodeApi,cameraApi}.ts   # Accept-Language = effective locale [012]
│   └── utils/{reducedMotion.ts [007], routeTotals.ts, gpx.ts, polyline.ts}
└── tests/                                  # Vitest + Testing Library (geo/maplibre stubbed); Playwright e2e

infra/
├── scripts/build-geo.sh                    # [011] canonical one-command country provisioning
│         build-geocoder.sh, fetch-extract.sh, setup.sh, country-registry.sh   # generalized to country [011]
├── docker-compose.yml                      # Valhalla / Nominatim / tiles accessories
└── data/tiger/                             # geocoder TIGER inputs
test/infra/*.bats                           # bats script tests (build-geocoder, fetch_extract, setup)
```

## Configuration

- **API**: versioned namespace `/api/v1`. No session/cookie middleware (account-less, anonymity).
- **Initializers** [002]: `anonymity_logging` (filter_parameters + log redaction, drop client IP),
  `content_security_policy` (self-origin), `rack_attack`, `cors` (same-origin), `event_reporter`.
- **Env vars**:
  - `GEOCODER_COUNTRY` (default `us`) [011] — replaces the older `GEOCODER_REGION_STATE` /
    hand-set `GEOCODER_VIEWBOX` [006]; `infra/.region` carries `COUNTRY`.
  - `NOMINATIM_USE_US_TIGER_DATA=yes` [006] — activates TIGER house-number lookups.
  - `CAMERA_REFRESH_MISSING_LIMIT` (default 3) [003] — auto-retire grace window.
  - `OVERPASS_URL` / `OVERPASS_USER_AGENT` [003]; US tiling grid params.
- **Scheduling**: `config/recurring.yml` cron `0 8 * * *` UTC (`args: [aggregate]`) [003].
- **On-device only**: `localStorage["flckd.locale"]` [012] (never egresses; cookie persistence
  rejected to preserve anonymity).
- **Frontend → backend locale**: `Accept-Language` carries the **effective** locale; `?locale=` is the
  highest-precedence override [012].

## Routing & Navigation (HTTP endpoints)

- `POST /api/v1/routes` — plan a route (avoiding + fastest comparison [009]); body dropped
  `avoidance_preference` [004]. Response includes `is_fully_clean`, `coverage_warning`,
  `fastest_comparison` { geometry, cameras_passed_count } [009].
- `GET /api/v1/geocode/search` · `POST /api/v1/geocode/reverse` [002].
- `GET /api/v1/cameras?bbox=` — viewport cameras, capped at 500 [008]; returns `facing_direction`,
  `snapped_location`, `segment` (post-009).
- `GET /api/v1/coverage` → `{ covered, data_freshness_at }`; `GET /api/v1/coverage/bounds` →
  registry-derived country extent [011] (`area_name` field dropped).
- `GET /api/v1/meta/locales` [002] — catalog/locale parity.
- `GET /health` [002].

> Removed: external-maps deep-link handoff (was a client-side action, removed post-009). Frontend-only
> additions (007, 008, 010, 013) introduced no new endpoints.

## Testing Strategy

- **Backend**: RSpec (unit/request/contract — OpenAPI-driven). Geo engines (Valhalla, Nominatim) and
  external sources (Overpass, DeFlock) are **faked with recorded fixtures** (`spec/support/geo_fakes.rb`,
  `spec/fixtures/`) and WebMock; `travel_to` for time-dependent behavior. Anonymity specs assert no
  coordinate/IP leakage. Tests-first per Constitution Principle II.
- **Frontend**: Vitest + @testing-library/react (MapLibre and `window.print` stubbed; jsdom
  localStorage stub patched in `tests/setup.ts`). Playwright + axe for e2e/a11y/perf (jsdom can't
  measure geometry or paginate) — anonymity e2e asserts zero third-party requests.
- **Infra scripts**: bats-core (Bash 3.2-safe) with PATH-prepend stubs; the live Census/Overpass
  endpoints are never hit in CI.
- **CI gates** (Constitution Quality Gates): lint+format zero-warning, full suite green, UX
  conventions, performance budgets.

## Non-Negotiables (enforced)

- **Strict anonymity** — no third party ever receives a user's origin/destination/route; no
  accounts/PII; no persistent identifiers; logs retain no route coordinates or client IPs. The only
  way a route leaves the app is the user-initiated, fully client-side **GPX export** (file built in
  the browser, saved to the user's device, with a warning that it holds the route). 013 print is
  likewise local-only (`window.print()`, zero network).
- **Camera avoidance** = exclude the specific monitored road segment(s) (snap-to-road), not a radius.
  Hardened post-009 with a soft proximity objective and auto-fallback to fewest-cameras (never a 422).
- **Tests required** for every behavioral change; geo services stubbed with recorded fixtures.

## Known Issues & Gotchas (historical, harvested from feature research)

### ⚠️ Routing engine must support per-request edge exclusion
**Issue:** Avoidance needs to exclude arbitrary monitored segments per request. **Root Cause:** OSRM
contracts its graph at build time — arbitrary per-request exclusion is unsupported. **Prevention:**
use **Valhalla** (dynamic costing + `exclude_polygons`/`exclude_locations` per request). [002]

### ⚠️ "No clean route" must never hard-fail
**Issue:** Hard-excluding all monitored segments can return no route, or trap an endpoint that sits on
a monitored segment. **Root Cause:** strict exclusion has no solution in some graphs. **Prevention:**
two-pass — pass 1 hard-exclude, pass 2 heavily penalize → always returns a minimum-exposure route,
flags `is_fully_clean: false`. (Post-009: also `ProximityScorer` soft objective + iterative-exclusion
and quiet-street candidates under a detour cap.) [002, 004]

### ⚠️ Coordinate/IP leakage in logs
**Issue:** Default Rails logging captures params + client IP. **Root Cause:** standard log subscriber.
**Prevention:** redact geo params via `filter_parameters` + a custom log subscriber; drop/truncate IP.
Refresh logs record only error **class** strings (no bodies). [002, 003]

### ⚠️ Radius-only avoidance over-blocks
**Issue:** A radius blocks parallel/cross streets the camera can't read. **Root Cause:** cameras read
one road, not a disc. **Prevention:** snap the camera to its nearest road and store the monitored OSM
way IDs matching the routing graph. [002]

### ⚠️ Third-party geo services leak user location
**Issue:** Hosted geocoder/tiles/routing would receive user origin/destination. **Root Cause:** SaaS
geo APIs see every query. **Prevention:** self-host Nominatim, PMTiles/MapLibre, Valhalla; the only
route egress is the local GPX export (the external-maps handoff was removed). [002, 007, 008, 009]

### ⚠️ Live Overpass at request time is unreliable; nationwide query times out
**Issue:** Querying Overpass per request (or a single CONUS-wide bbox) fails on latency/timeout/memory.
**Root Cause:** public Overpass server caps. **Prevention:** import on a daily Solid Queue schedule;
**tile** the CONUS bbox (`UsTiles`) and iterate per cell with backoff and bounded (single) concurrency
for fair-use; endpoint configurable for a self-hosted server. [003]

### ⚠️ DeFlock has no licensable read API
**Issue:** DeFlock exposes only geocode/sponsors/healthcheck and its SPA grants no license.
**Root Cause:** the data actually lives in OSM under ODbL ("powered by OpenStreetMap").
**Prevention:** ingest DeFlock as OSM/ODbL ALPR nodes via the Overpass adapter; never scrape; record
DeFlock provenance + ODbL. [003]

### ⚠️ Time-zone-ambiguous schedules drift with DST
**Issue:** "every day at 4am" is interpreted in process TZ and shifts with DST. **Root Cause:**
natural-language cron. **Prevention:** explicit numeric UTC cron `0 8 * * *`; regression test asserts
fire time. [003]

### ⚠️ Overlapping / failed-source refreshes corrupt data
**Issue:** Manual + scheduled runs could double-run; reconciling stale-counts after a *failed* source
fetch would drop last-good data. **Prevention:** Solid Queue `limits_concurrency(key:"camera_refresh",
to:1)` + a `RefreshRun` running-state guard; run `StaleReconciler` per-source **only** after that
source's fetch succeeds. [003]

### ⚠️ Geocoder house-number suggestions silently fail (three independent causes)
**Issue:** A valid house number returns no suggestion. **Root Causes & Prevention:**
(1) TIGER lookups off by default → set `NOMINATIM_USE_US_TIGER_DATA=yes` + `nominatim refresh
--website`. (2) Single-state extract lacks the admin_level-4 state boundary, so a `, IA`/`, Iowa`
token becomes an unsatisfied required term and house-number matches are discarded → strip the state
token from queries (viewbox already bounds the region) — **but gate this off at country scale (011)**,
where the token is needed for sub-region disambiguation. (3) Purely numeric OSM `name`/`ref` features
get indexed as `W`/`w` word tokens, so a bare number is treated as a name and never reaches TIGER
interpolation → delete numeric `W`/`w` tokens after import (`H`/`P` untouched). Confidence: derive from
`place_rank/30` clamped `[0,1]` (fallback `0.5`), not Nominatim's negative `importance`. [006, 011]

### ⚠️ Single-region vs. honest coverage conflation
**Issue:** `CoverageArea` conflated "served region" with "where data exists," and a global freshness
stamp lied per region. **Prevention:** frame from the registry country bbox (`/coverage/bounds`) but
report presence/freshness **per ingested data-region**; set `data_freshness_at` per region as each
refreshes. Bash `country-registry.sh` mirrors the Ruby `CountryRegistry` and must be kept in sync. [011]

### ⚠️ Map source/layer added before style load throws
**Issue:** Adding a GeoJSON source/layer (origin marker, cameras, comparison) before the style loads
throws; child can't mount against a map held only in a ref. **Prevention:** gate behind style-load
readiness; promote the map instance to state, then render `{map && <CameraLayer map={map}/>}`. Use
`moveend` + ~300 ms debounce (not `move`) for viewport fetches; insert camera layers below
route/origin via `beforeId` so they never obscure the route. [007, 008]

### ⚠️ Map framing & motion accessibility
**Issue:** Auto-framing by result bbox over-tightens onto a single dwelling (inconsistent + privacy-
leaking); always-animating ignores reduced-motion. **Prevention:** fixed zoom 16; branch on
`prefersReducedMotion()` → `jumpTo` vs `flyTo`. [007]

### ⚠️ Responsive layout pitfalls
**Issue:** `vh` overflows under mobile browser chrome; flexbox row collapses the map; capping page
width reintroduces the empty-margin defect; orientation queries break on large phones. **Prevention:**
use `svh` + min-height floor; CSS Grid `1fr min(420px,38%)` with `min-width:0` on children; cap only
the sidebar (never the page); drive layout by width thresholds alone. [010]

### ⚠️ Language negotiation must honor q-weights and the effective locale
**Issue:** Naive `header.scan(/[a-z]{2}/i).first` ignored q-weights/order; the frontend sent raw
`navigator.language` so an explicit override never reached the server; lazy locale chunks flashed the
default. **Prevention:** `LocaleNegotiator` parses `(tag,q)`, sorts q-desc then order, base-reduces;
the frontend sends effective `i18n.language` as `Accept-Language`; keep synchronous i18n init with both
bundles statically imported (compute `lng` before `i18n.init`); persist on-device only (no cookie). [012]

### ⚠️ Fake-fixture geometry yields zero exposure counts
**Issue:** Under `GeoFakes`, the fixture polyline is non-decodable so `cameras_passed_count` is 0.
**Prevention:** assert exposure counts via the PostGIS-backed request/integration path with real
geometry, not the fake path. [009]

### ⚠️ Bash 3.2 / curl portability (infra scripts)
**Issue:** `wait -n` is Bash 4.3+ (macOS ships 3.2); `curl -f` suppresses the HTTP code; inline
function overrides don't intercept subshells. **Prevention:** indexed PID array + FIFO `wait`; drop
`-f`, use `--write-out "%{http_code}"`; PATH-prepend stubs intercept at the OS level; one marker file
per failure (no concurrent writes). [005, 006, 011]

### ⚠️ `bundler-audit` on the required gate deadlocks merges
**Issue:** `bundler-audit check --update` fetches the Ruby advisory DB at runtime, so a newly-published
advisory for a gem *already on `main`* turns CI red with **no code change** — and while it ran as a step
inside `backend-tests` (feeding the branch-protection–required `backend` gate) that spontaneously blocked
every open PR (hit real-world with the `json`/`websocket-driver` advisories, PRs #63/#64/#66). **Root
Cause:** a live-updating audit gating merges. **Prevention:** `bundler-audit` runs as its own standalone
**`dependency-audit`** job that is intentionally **not** in the `backend` gate's `needs` — a failure is a
visible ❌ for triage (bump the gem to clear it) but no longer blocks merges. RuboCop/Brakeman/RSpec stay
blocking in `backend-tests`; the audit stays gated on `backend/**` for minutes hygiene. **Tradeoff:** a
serious advisory now flags rather than blocks. See `.github/workflows/ci-backend.yml` header. [PR #67]

## Revision Log

- **2026-06-18** — Bootstrapped from `013-printable-directions`.
- **2026-06-18** — Archived the full `specs/` directory (002–012): consolidated architecture,
  dependencies, project structure, endpoints, config, testing strategy, and a Known Issues & Gotchas
  section harvested from all feature research docs. Reflects the implemented state (preference UI and
  external-maps handoff removed; country-scale geo provisioning; React 19 / PostgreSQL 17).
- **2026-07-08** — Added Known Issue: `bundler-audit` split into a non-blocking `dependency-audit` CI
  job so live advisory-DB updates no longer deadlock merges (PR #67).

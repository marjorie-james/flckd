# Merged Features Log

> Chronological by feature number. Tasks counted from each feature's `tasks.md`
> (`- [X]`/`- [x]` = done). Bootstrapped 2026-06-18 by archiving the full `specs/` directory.

### Camera-Avoiding Route Planner — 2026-06-18 (archived)
**Branch:** `002-flock-route-avoidance` · **Spec:** specs/002-flock-route-avoidance
**What was added:** the founding product — plan a drivable route that avoids known ALPR/Flock cameras
by excluding the specific monitored road segment(s) (snap-to-road), shown on an interactive MapLibre
map with localized turn-by-turn directions; fully anonymous, account-less, self-hosted geo stack.
**New Components:** backend `routing/`, `geocoding/`, `camera_data/` services; models Camera,
MonitoredSegment, CoverageArea, DataSource; Solid Queue import/snap/refresh jobs; `/api/v1`
(`POST /routes`, geocode, coverage, cameras, meta, health); frontend MapView, RoutePanel, RouteResult,
CameraSummary, CameraLayer, LanguageSwitcher, PlanRoutePage; `infra/` Valhalla/Nominatim/tiles.
**Tasks Completed:** 81/81 (T080 SC-001/SC-004 statistical sign-off pending a live geo-stack run).

### Aggregated Camera Data Source-of-Truth — 2026-06-18 (archived)
**Branch:** `003-camera-data-aggregation` · **Spec:** specs/003-camera-data-aggregation
**What was added:** aggregate ALPR/Flock locations from all permissive sources (DeFlock via OSM/ODbL,
OSM, generic importer) into one authoritative provenance-tagged DB; daily 08:00 UTC background refresh
+ manual trigger; preserve human verifications; conservative stale→auto-retire (3 missing refreshes);
partial-failure isolation; nationwide (CONUS) coverage.
**New Components:** `RefreshRun` model; `Sources::Deflock`, `StaleReconciler`, `UsTiles` services;
freshness fields + lifecycle on Camera; `config/recurring.yml` cron; `camera_data:refresh[:status]` rake.
**Tasks Completed:** 44/44.

### Automatic Camera-Priority Routing — 2026-06-18 (archived)
**Branch:** `004-auto-route-priority` · **Spec:** specs/004-auto-route-priority
**What was added:** removed the avoidance-preference choice entirely — always try a zero-camera route
first, else fall back to the fewest-camera route, communicating which kind was returned.
**New Components:** net removal — deleted `PreferenceRadios`, `AvoidanceControl`, and the
`avoidance_preference` param; `RoutePlanner#plan` drops the `preference:` kwarg.
**Tasks Completed:** 20/20.

### Parallel TIGER/Line Data Download — 2026-06-18 (archived, SUPERSEDED)
**Branch:** `005-parallel-tiger-download` · **Spec:** specs/005-parallel-tiger-download
**What was added:** nothing shipped — spec **superseded** (premise invalid: Nominatim 4.4 needs a
preprocessed CSV, not per-county ADDR files; no multi-file download to parallelize). Geo provisioning
was instead reworked at country scale by 011.
**Tasks Completed:** 19/19 (design/tests authored; feature abandoned before adoption).

### House-Number Address Suggestions (geocoder fix) — 2026-06-18 (archived)
**Branch:** `006-geocoder-housenumber-fix` · **Spec:** specs/006-geocoder-housenumber-fix
**What was added:** fixed three independent defects that each suppressed house-number geocoding —
(1) enable `NOMINATIM_USE_US_TIGER_DATA=yes` + `nominatim refresh --website`; (2) strip the state
token from queries; (3) delete purely numeric `W`/`w` word tokens after import; plus confidence from
`place_rank/30` (was surfacing negative `importance`). Reported address now resolves at confidence 1.0.
**New Components:** changes to `build-geocoder.sh` and `geocoder_client.rb`; no plan.md/tasks.md.
**Status:** Implemented (left as-is). **Tasks Completed:** n/a.

### Zoom to Starting Address — 2026-06-18 (archived)
**Branch:** `007-zoom-to-origin` · **Spec:** specs/007-zoom-to-origin
**What was added:** on a confirmed starting address, recenter/zoom the map to a consistent street-level
framing (fixed zoom 16) and drop a single marker — smooth by default, instant under reduced-motion,
only on confirmed selection, no third-party coordinate leak.
**New Components:** `utils/reducedMotion.ts`; MapView origin recenter effect + GeoJSON marker; RoutePanel
`onOriginChange`; PlanRoutePage lifted `origin` state. Frontend-only.
**Tasks Completed:** 18/18.

### Render Camera Locations in the Current Viewport — 2026-06-18 (archived)
**Branch:** `008-viewport-cameras` · **Spec:** specs/008-viewport-cameras
**What was added:** show known cameras in the visible area as individual markers (sparse) or count
clusters (dense), debounced on pan/zoom, with detail popups (Esc-dismissible), disputed-camera
distinction, route-independent, 500-cap with cap-reached telemetry.
**New Components:** rewritten `CameraLayer.tsx` (clustered GeoJSON + popup); MapView promotes the map
instance to state. Reuses existing `GET /cameras?bbox=`. Frontend-only.
**Tasks Completed:** 14/14.

### Comparison Route (Fastest-Route Baseline) — 2026-06-18 (archived)
**Branch:** `009-comparison-route` · **Spec:** specs/009-comparison-route
**What was added:** alongside the recommended avoiding route, compute + show the fastest non-avoiding
route as a distinct dismissible secondary line, surfacing the avoidance cost (added time headline,
added distance, cameras the fastest route would expose) — only when avoidance costs time.
**New Components:** `RoutePlanner#comparison` adds geometry + `cameras_passed_count`; MapView comparison
layer; RouteResult toggle/added-distance/exposure; PlanRoutePage `showComparison`. Two added fields on
the existing response object; new `result.*` i18n keys.
**Tasks Completed:** 24/24.

### Responsive, Full-Width Layout — 2026-06-18 (archived)
**Branch:** `010-responsive-layout` · **Spec:** specs/010-responsive-layout
**What was added:** presentation-only — full-width map-dominant two-pane desktop layout and full-width
stacked mobile flow, graceful reflow 320–2560px, no horizontal scroll, sidebar-capped ultra-wide,
preserving features/styling/accessibility/anonymity/performance.
**New Components:** `App.css` layout rework (CSS Grid `1fr min(420px,38%)`, `svh`); PlanRoutePage split
into map + content panes; `responsive-layout.spec.ts` (axe + viewport-parameterized). Frontend-only.
**Tasks Completed:** 17/17.

### Country-Wide Camera Mapping — 2026-06-18 (archived)
**Branch:** `011-country-camera-mapping` · **Spec:** specs/011-country-camera-mapping
**What was added:** lifted a deployment's scope from a single US state to an entire country (default US)
— search, routing, tiles, geocoder + whole-US TIGER, camera gathering, map framing, and per-data-region
coverage all span the country; one-command provisioning; fail-fast on unsupported country.
**New Components:** `Geocoding::CountryRegistry` + `country-registry.sh`; canonical `build-geo.sh`;
generalized fetch/build/setup scripts; `GEOCODER_COUNTRY` env (replaces `GEOCODER_REGION_STATE`);
`/coverage` + `/coverage/bounds` reshaped; per-region `CoverageArea` freshness.
**Tasks Completed:** 36/36 (T032 country-scale p95 + full default-US `setup.sh` deferred to a
provisioned runner; verified on the dev stack).

### Preferred Language Detection — 2026-06-18 (archived)
**Branch:** `012-preferred-language-detection` · **Spec:** specs/012-preferred-language-detection
**What was added:** derive the UI language from the visitor's full ordered, q-weighted environment
signals matched against offered locales (en, es) with base-language regional fallback, resolved
synchronously before first paint (no flash); explicit choice wins and persists on-device; the effective
locale is sent to the backend; map labels follow the selected language.
**New Components:** `resolveLocale.ts`, `localePreference.ts` (frontend); `Api::V1::LocaleNegotiator`
(backend); `Accept-Language` carries the effective locale; map-style `text-field` selects `name:<lng>`.
**Tasks Completed:** 25/25.

### Printable Driving Directions — 2026-06-18
**Branch:** `013-printable-directions` · **Spec:** specs/013-printable-directions
**What was added:** an icon-only print control atop the on-screen directions opens the browser's native
print dialog showing a dedicated, print-only view (heading, origin/destination, totals, full ordered
steps, privacy notice) — large, high-contrast, paginated; map/chrome/controls and camera notices
excluded; fully client-side (`window.print()` + `@media print`), zero transmission; localized en + es.
**New Components:** `PrintableDirections.tsx`; print stylesheet block in `App.css`; `print.*` i18n keys;
origin/destination label lift `RoutePanel → PlanRoutePage → RouteResult → PrintableDirections`.
**Tasks Completed:** 19/19.

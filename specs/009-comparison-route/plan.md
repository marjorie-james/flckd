# Implementation Plan: Baseline Route Comparison

**Branch**: `009-comparison-route` | **Date**: 2026-06-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-comparison-route/spec.md`

## Summary

When the app plans a camera-avoiding route, also draw the **fastest ordinary (non-avoiding) route** on the
map as a visually distinct secondary "comparison" line, and surface the **extra travel time** (headline)
and **extra distance** (secondary) that avoidance costs — plus how many cameras the fastest route would
have passed. The comparison is shown automatically whenever avoidance adds time (`added time > 0`), is
dismissible, and is informational only (never selectable as the route to follow).

Technical approach: **mostly frontend, with a tiny backend addition.** The backend *already* computes the
fastest route on every request (`RoutePlanner#plan` calls Valhalla without exclusions first) and already
returns `fastest_comparison` with `distance_m`, `duration_s`, `added_distance_m`, `added_duration_s`. Two
gaps remain: (1) the fastest route's **geometry** is dropped, and (2) the **count of cameras the fastest
route passes** isn't computed. The backend change adds both to `fastest_comparison` (the fastest route
object already carries its polyline; the camera count reuses the existing PostGIS segment-intersection
logic). The frontend then draws the second line in `MapView`, adds a dismiss control, and extends
`RouteResult` to show added distance + the fastest route's camera exposure. **No new dependencies, no new
external calls** — both routes are already computed by our own self-hosted Valhalla.

## Technical Context

**Language/Version**: Ruby 3.4 / Rails 8.1 (API mode) backend; TypeScript 5.x + React 19 frontend.

**Primary Dependencies**: Valhalla (self-hosted, already called twice per request — fastest + avoiding),
PostGIS (`ST_Intersects` on monitored segments, existing pattern), MapLibre GL JS (line layers),
@tanstack/react-query (existing `usePlanRoute`), react-i18next.

**Storage**: N/A — routes are computed per request; nothing new persisted. No schema changes.

**Testing**: RSpec + WebMock/`GeoFakes::FakeRoutingEngine` (Valhalla stubbed via recorded fixtures);
Vitest + @testing-library (maplibre stubbed) and Playwright e2e (real map, stubbed network).

**Target Platform**: Rails API + evergreen-browser, mobile-first responsive web frontend.

**Project Type**: Web application (`backend/` + `frontend/`). This feature touches both, but the backend
delta is additive (two fields on an existing response object).

**Performance Goals**: No new latency. The two Valhalla calls already happen today; this adds one extra
PostGIS intersection query (the fastest route's camera count — same cheap query already run for the
avoiding route) and one polyline to the payload. Inherits feature `002`'s route-planning p95 budget;
**no new round-trips, so no regression** (resolves the deferred budget item from `/speckit-clarify`).

**Constraints**: Strict anonymity — both routes are computed by our own Valhalla; the only change is adding
the fastest route's geometry to *our own* response. No new third-party call, no new logging of
coordinates. The comparison line must stay visually subordinate to the primary route and remain
distinguishable where the two overlap.

**Scale/Scope**: Small. Backend: `RoutePlanner#comparison`, the `FastestComparison` contract, and specs.
Frontend: `MapView` (second line + dismiss), `RouteResult` (added distance + exposure + toggle),
`types/api.ts`, lifted `showComparison` state in `PlanRoutePage`, i18n keys, and tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Assessment |
|-----------|------|------------|
| **I. Code Quality** | Lint/format zero warnings; single responsibility; intent comments; no dead code | PASS (planned). Backend change is two added fields on an existing method (`comparison`), reusing `remaining_cameras_on` for the fastest-route count — no new responsibility. Frontend adds one self-contained "comparison line" effect mirroring the existing route-line effect, and one summary row. ESLint + `tsc -b` + RuboCop clean. |
| **II. Testing (NON-NEGOTIABLE)** | Every behavioral change has tests that fail without it; deterministic; behavior-focused | PASS (planned). Backend: `route_planner_spec` asserts `fastest_comparison` now carries the fastest geometry + `cameras_passed_count`, and that on fallback the geometry equals the fastest route and `added_duration_s == 0`; request/serializer spec asserts the new fields on the JSON. Frontend: unit tests for drawing the comparison line only when `added_duration_s > 0` and `showComparison`, removing it on dismiss, distinct styling beneath the primary line; `RouteResult` shows added distance + fastest exposure + toggles; e2e for two lines, dismiss, and anonymity (no third-party request). Geo stays stubbed (fixtures). |
| **III. UX Consistency** | Documented conventions; actionable feedback; accessibility part of "done" | PASS (planned). Reuses the existing GeoJSON-source/line-layer pattern (route/origin/cameras) for the comparison line; the comparison is clearly labeled "fastest route" and visually secondary (dashed, muted, drawn beneath the recommended `#818cf8` line). The added-time string already exists (`result.addedTime`); new strings follow the same `result.*` i18n convention in both `en` and `es`. Dismiss control is a labeled, keyboard-reachable toggle (consistent with the a11y pass in `009`'s predecessor route UI work, features `051`/`052`). |
| **IV. Performance** | Declared, measured budgets for user-perceived latency | PASS (planned). Budget = feature `002`'s route p95, unchanged: no new external calls (fastest route already computed), one extra cheap PostGIS query, one extra polyline in the payload. Verified in quickstart against representative O/D pairs. |

**Initial gate result: PASS** — no violations. Complexity Tracking not required: the design deliberately
reuses the already-computed fastest route and the existing segment-intersection query rather than adding a
new routing pass or service.

**Post-design re-check (after Phase 1): PASS** — no new dependencies, no schema changes, no new
third-party calls, nothing newly persisted or logged. Anonymity holds: both routes are produced by our own
Valhalla and the fastest geometry is added only to our own response.

## Project Structure

### Documentation (this feature)

```text
specs/009-comparison-route/
├── plan.md              # This file (/speckit-plan)
├── research.md          # Phase 0 — trigger, line styling/order, framing, dismiss state, exposure count
├── data-model.md        # Phase 1 — FastestComparison (extended), client comparison view-state
├── quickstart.md        # Phase 1 — run & verify (penalty/no-penalty/dismiss, perf, anonymity)
├── contracts/
│   └── route-comparison.md  # Phase 1 — FastestComparison delta + MapView/RouteResult/Page props
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify, /speckit-clarify)
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

Existing **web application** layout; relevant files:

```text
backend/
├── app/
│   ├── services/routing/
│   │   └── route_planner.rb     # EDIT: comparison() adds `geometry` (fastest[:geometry]) +
│   │   │                        #   `cameras_passed_count` (reuse remaining_cameras_on(fastest, exclusion).size)
│   │   └── result.rb            # (unchanged) fastest_comparison is a hash; no struct field change
│   └── serializers/
│       └── route_serializer.rb  # (unchanged) passes fastest_comparison through verbatim
└── spec/
    └── services/routing/route_planner_spec.rb  # EXTEND: geometry + cameras_passed_count + fallback delta=0
    └── requests/…/routes_spec.rb               # EXTEND: new fields present in JSON contract

frontend/
├── src/
│   ├── components/
│   │   ├── MapView.tsx          # EDIT: add comparison source/layer (dashed, muted, beneath route-line);
│   │   │                        #   draw iff added_duration_s>0 && showComparison; frame both lines; remove on off
│   │   └── RouteResult.tsx      # EDIT: added distance (secondary), "fastest passes N cameras", show/hide toggle
│   ├── pages/PlanRoutePage.tsx  # EDIT: lift `showComparison` state; pass to MapView + RouteResult
│   ├── types/api.ts             # EDIT: FastestComparison += geometry: string; cameras_passed_count: number
│   ├── types/openapi.d.ts       # REGEN/EDIT: mirror contract additions
│   └── i18n/locales/{en,es}.json# EDIT: addedDistance, fastestExposes, showComparison/hideComparison, comparisonLabel
└── tests/
    ├── unit/ (route-result.test.tsx, mapview)  # EXTEND: line drawing/dismiss/styling, summary rows, toggle
    └── e2e/                                     # EXTEND: two lines render, dismiss hides comparison, anonymity
```

**Structure Decision**: Existing web-app layout. The backend change is intentionally minimal — surface the
already-computed fastest route's geometry and its camera count on the existing `fastest_comparison` object
rather than introduce a new endpoint or a new routing pass. All drawing/UX lives in the frontend, reusing
the established GeoJSON-source/line-layer and `result.*` i18n conventions.

## Complexity Tracking

> No constitution violations — section intentionally empty. (Reusing the already-computed fastest route and
> the existing PostGIS segment-intersection query is the simplest approach; no new routing pass, endpoint,
> dependency, or persistence is introduced.)

---
description: "Task list for feature 009-comparison-route"
---

# Tasks: Baseline Route Comparison

**Input**: Design documents from `/specs/009-comparison-route/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/route-comparison.md

**Tests**: Per Constitution Principle II (Testing Standards, NON-NEGOTIABLE), every behavioral change is
accompanied by automated tests that fail without it. Test tasks below are REQUIRED. Write tests FIRST and
confirm they FAIL before implementation. All geo services are stubbed (`GeoFakes` / recorded Valhalla
fixtures) — deterministic, no network.

**Organization**: Tasks are grouped by user story (P1 → P3) for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, Polish carry no story label)

## Path Conventions

Web app: backend at `backend/`, frontend at `frontend/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the working state; this feature adds no new dependencies.

- [X] T001 Confirm branch `009-comparison-route` is checked out and that no new dependencies are introduced (no changes to `backend/Gemfile` or `frontend/package.json`); both routes are already computed by the existing self-hosted Valhalla.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extend the shared response contract + client type that BOTH US1 (geometry) and US3 (camera count) consume.

**⚠️ CRITICAL**: No user-story frontend work can begin until the type exists.

- [X] T002 [P] Add `geometry` (encoded polyline, precision 6) and `cameras_passed_count` (integer, `minimum: 0`) to the `FastestComparison` schema in `specs/002-flock-route-avoidance/contracts/openapi.yaml` per `contracts/route-comparison.md`.
- [X] T003 [P] Extend the `FastestComparison` interface in `frontend/src/types/api.ts` (add `geometry: string;` and `cameras_passed_count: number;`) and mirror the additions in `frontend/src/types/openapi.d.ts`.

**Checkpoint**: Contract + client type carry the new fields; story work can begin.

---

## Phase 3: User Story 1 - See the cost of avoidance on the map (Priority: P1) 🎯 MVP

**Goal**: Draw the fastest non-avoiding route as a distinct secondary line alongside the recommended avoiding route, show each route's travel time and the added time/distance, make the recommended route unmistakably primary, and allow dismissing the comparison.

**Independent Test**: Plan an O/D pair whose fastest path passes a camera and whose avoiding route is longer → two visually distinct lines render (recommended primary, fastest dashed/beneath), each with a travel time, the added time (headline) + added distance (secondary) shown; the comparison can be hidden and the recommended route remains.

### Tests for User Story 1 (REQUIRED — Constitution Principle II) ⚠️

> Write FIRST; confirm they FAIL before implementing.

- [X] T004 [P] [US1] Backend: in `backend/spec/services/routing/route_planner_spec.rb`, assert `result.fastest_comparison[:geometry]` equals the fastest route's geometry when avoidance adds time (distinct `sample_route` geometries for fastest vs avoiding), and assert `added_duration_s == avoiding.duration_s - fastest.duration_s` and `>= 0`, and likewise for `added_distance_m` (SC-003, never negative).
- [X] T005 [P] [US1] Backend: in the routes request spec (`backend/spec/requests/api/v1/routes_spec.rb`), assert the JSON `fastest_comparison.geometry` is present and non-empty for a route with a penalty.
- [X] T006 [P] [US1] Frontend: in `frontend/tests/mapview.test.tsx`, assert the `comparison-line` layer is added (dashed, drawn beneath `route-line`) when `fastest_comparison.added_duration_s > 0` and `showComparison` is true, that `fitBounds` covers both polylines, and that no click/interaction handler is bound to `comparison-line` (FR-005: informational, not selectable).
- [X] T007 [P] [US1] Frontend: in `frontend/tests/route-result.test.tsx`, assert the recommended route's travel time renders (`result.travelTime` from `duration_s`), the added-distance row renders (`result.addedDistance`), and the show/hide toggle calls `onToggleComparison`.
- [X] T008 [P] [US1] Frontend e2e: in `frontend/tests/e2e/route-comparison.spec.ts`, plan a route with a penalty → both route lines present; clicking "Hide fastest route" removes the comparison line while the recommended route remains; then re-plan a no-penalty route and assert the comparison line is gone and `showComparison` has reset to shown (FR-009).

### Implementation for User Story 1

- [X] T009 [US1] Backend: in `backend/app/services/routing/route_planner.rb`, have `#comparison` include `geometry: fastest[:geometry]` in the returned hash.
- [X] T010 [US1] Frontend: in `frontend/src/components/MapView.tsx`, add a `comparison` GeoJSON source + `comparison-line` layer (dashed, muted color, lower weight/opacity), inserted **beneath** `route-line` (beforeId); draw only when `route.fastest_comparison.added_duration_s > 0`, `showComparison` is true, and the comparison geometry decodes to ≥1 point; frame both polylines when shown; remove/skip otherwise. Add a `showComparison?: boolean` prop (default `true`).
- [X] T011 [US1] Frontend: in `frontend/src/pages/PlanRoutePage.tsx`, lift `const [showComparison, setShowComparison] = useState(true)`, reset it to `true` on each new successful plan (FR-009), pass `showComparison` to `MapView` and `{ showComparison, onToggleComparison }` to `RouteResult`.
- [X] T012 [US1] Frontend: in `frontend/src/components/RouteResult.tsx`, add `showComparison`/`onToggleComparison` props, render the added-distance secondary row (from `added_distance_m`), and a labeled, keyboard-reachable show/hide toggle. (Existing `result.addedTime` headline stays.)
- [X] T012a [US1] Frontend: in `frontend/src/components/RouteResult.tsx`, display the recommended route's estimated travel time from `route.duration_s` (new `result.travelTime` key), and add `result.travelTime` (value `"{{minutes}} min"`) to BOTH `frontend/src/i18n/locales/en.json` and `frontend/src/i18n/locales/es.json` (FR-003).
- [X] T013 [P] [US1] i18n: add `result.addedDistance`, `result.showComparison`, `result.hideComparison`, and `result.comparisonLabel` to BOTH `frontend/src/i18n/locales/en.json` and `frontend/src/i18n/locales/es.json`.

**Checkpoint**: US1 is fully functional — two routes, trade-off figures, and dismiss all work. This is a shippable MVP.

---

## Phase 4: User Story 2 - No needless comparison when avoidance is free (Priority: P2)

**Goal**: When avoidance costs no extra time (`added_duration_s == 0`), show a single route and no positive added figures.

**Independent Test**: Plan an O/D pair whose fastest route already passes no cameras → only one route is shown, no dashed comparison line, and no positive added-time/-distance figure.

### Tests for User Story 2 (REQUIRED — Constitution Principle II) ⚠️

- [X] T014 [P] [US2] Backend: in `backend/spec/services/routing/route_planner_spec.rb`, assert that in the fallback / no-exclusion case the chosen route equals the fastest route and `fastest_comparison` has `added_duration_s == 0`, `added_distance_m == 0`, and `geometry == result.geometry`.
- [X] T015 [P] [US2] Frontend: in `frontend/tests/mapview.test.tsx`, assert NO `comparison-line` layer is added when `fastest_comparison.added_duration_s == 0`.
- [X] T016 [P] [US2] Frontend: in `frontend/tests/route-result.test.tsx`, assert no added-time and no added-distance rows render when `added_duration_s == 0`.

### Implementation for User Story 2

- [X] T017 [US2] Frontend: in `frontend/src/components/RouteResult.tsx`, gate the added-time and added-distance rows (and the comparison toggle/label) behind `added_duration_s > 0` so the free case shows a single route with no positive figures. (Map gating already lands in T010; this completes the summary side.)

**Checkpoint**: US1 and US2 both hold — comparison appears only when avoidance has a cost.

---

## Phase 5: User Story 3 - Understand what the fastest route would have exposed (Priority: P3)

**Goal**: Show how many cameras the fastest route would pass, reinforcing why the recommended route detours.

**Independent Test**: Plan a route whose fastest path passes a known number of cameras → the comparison indicates the fastest route is not camera-free (shows the count).

### Tests for User Story 3 (REQUIRED — Constitution Principle II) ⚠️

- [X] T018 [P] [US3] Backend: in the routes request spec (`backend/spec/requests/api/v1/routes_spec.rb`, PostGIS-backed with real geometry), assert `fastest_comparison.cameras_passed_count` equals the number of monitored segments the fastest route intersects in the O/D bbox.
- [X] T019 [P] [US3] Frontend: in `frontend/tests/route-result.test.tsx`, assert the fastest-exposure row renders the pluralized `result.fastestExposes` from `cameras_passed_count` when it is > 0.

### Implementation for User Story 3

- [X] T020 [US3] Backend: in `backend/app/services/routing/route_planner.rb`, compute the fastest route's camera count by reusing `remaining_cameras_on(fastest, exclusion).size` and include it in `fastest_comparison` as `cameras_passed_count` (thread `exclusion` into `#comparison` or compute it in `#build_result` and merge).
- [X] T021 [US3] Frontend: in `frontend/src/components/RouteResult.tsx`, render the fastest-exposure row from `cameras_passed_count`, and add `result.fastestExposes_one` / `result.fastestExposes_other` to BOTH `frontend/src/i18n/locales/en.json` and `frontend/src/i18n/locales/es.json`.

**Checkpoint**: All three stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T022 [P] Verify i18n parity (all new `result.*` keys present in both `en.json` and `es.json`); run `cd frontend && npx eslint . && npx tsc -b` and `cd backend && bundle exec rubocop` with zero warnings (Constitution Principle I).
- [X] T023 Run `quickstart.md` validation: penalty (two lines + figures), no-penalty (single route), dismiss; confirm no latency regression vs feature `002`'s route p95 budget (no new external round-trip), and confirm anonymity (e2e: no off-origin request carries route data; logs still redact coordinates/IPs).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: After Setup. T003 (client type) BLOCKS all frontend story tasks; T002 (contract) BLOCKS backend contract assertions.
- **User Stories (Phase 3–5)**: All depend on Foundational completion. After that, US1/US2/US3 are independently testable.
- **Polish (Phase 6)**: After the desired stories are complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational. No dependency on other stories — the MVP.
- **US2 (P2)**: After Foundational. Independent; verifies the `added_duration_s == 0` path. (Map gating lands in US1's T010, but US2 is independently testable via its own zero-case tests + RouteResult guard.)
- **US3 (P3)**: After Foundational. Independent; adds the backend `cameras_passed_count` and its display.

### Within Each User Story

- Tests written and FAILING before implementation (Principle II).
- Backend field before its frontend display; map/page state before summary wiring.

### Parallel Opportunities

- **Foundational**: T002 and T003 in parallel (different files).
- **US1 tests**: T004–T008 in parallel (distinct files). **US1 i18n** T013 [P] is independent of the component edits.
- **US2 tests**: T014–T016 in parallel.
- **US3 tests**: T018–T019 in parallel.
- Note: T010, T012, T012a, T017, T021 all touch frontend component files (`MapView.tsx` / `RouteResult.tsx`); within a story they are sequential where they share a file. T012/T012a (US1), T017 (US2), and T021 (US3) all edit `RouteResult.tsx` — sequence them across stories.

---

## Parallel Example: User Story 1

```bash
# Write all US1 tests together first (they must fail):
Task: "Backend route_planner_spec: fastest_comparison geometry == fastest geometry"   # T004
Task: "Backend routes request spec: fastest_comparison.geometry present"               # T005
Task: "Frontend mapview.test.tsx: comparison-line drawn dashed beneath route-line"     # T006
Task: "Frontend route-result.test.tsx: added-distance row + toggle"                    # T007
Task: "Frontend e2e route-comparison.spec.ts: two lines + dismiss"                     # T008
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → Phase 2 Foundational (contract + type).
2. Phase 3 US1: backend geometry, MapView comparison line, page state, RouteResult added-distance + toggle, i18n.
3. **STOP and VALIDATE**: two distinct routes, travel times, added time/distance, dismiss — ship.

### Incremental Delivery

1. Foundation → US1 (MVP) → US2 (free-case suppression) → US3 (fastest-route exposure).
2. Each story is independently testable and adds value without breaking the previous.

---

## Notes

- [P] = different files, no incomplete-task dependency.
- No DB/schema changes; no new dependencies; no new external calls (both routes already computed server-side).
- Anonymity preserved: the only response change is adding the fastest route's geometry + camera count to our own response.
- Commit after each task or logical group; verify each story's tests fail before implementing.

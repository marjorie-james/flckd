---
description: "Task list for Zoom to Starting Address"
---

# Tasks: Zoom to Starting Address

**Input**: Design documents from `/specs/007-zoom-to-origin/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ui-contract.md

**Tests**: Per Constitution Principle II (Testing Standards, NON-NEGOTIABLE), every behavioral change
is accompanied by automated tests that fail without the change. Test tasks below are REQUIRED; write
them first and confirm they FAIL before implementing.

**Organization**: Tasks are grouped by user story. Each story is an independently testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 (setup, foundational, polish carry no story label)
- All paths are repository-relative.

## Path Conventions

Web application; this feature is **frontend-only** under `frontend/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Shared constants the map work depends on.

- [x] T001 [P] Add origin map constants near the existing layer constants in
  `frontend/src/components/MapView.tsx`: `ORIGIN_SOURCE = "origin"`, `ORIGIN_LAYER = "origin-point"`,
  `ORIGIN_ZOOM = 16` (research D1), and a marker paint style distinct from the camera dots/route line.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The data channel every user story rides on — the confirmed origin must reach `MapView`,
and `RoutePanel` must announce origin changes. No story can work until this is done.

**⚠️ CRITICAL**: Complete this phase before any user-story phase.

- [x] T002 [P] Add an optional `origin?: Coordinate | null` prop to `MapView` (type + signature only,
  threaded, no behavior yet) in `frontend/src/components/MapView.tsx`.
- [x] T003 [P] Write the RoutePanel callback test in `frontend/tests/unit/route-panel.test.tsx`:
  `onOriginChange` fires with a `Coordinate` when a suggestion is picked, fires with `null` when the
  starting-address field is cleared, fires on geolocation resolving, and does NOT fire on intermediate
  typing (no selection). Confirm it FAILS first.
- [x] T004 Add the optional `onOriginChange?: (origin: Coordinate | null) => void` prop to `RoutePanel`
  and invoke it from `pickOrigin`, from the origin input's clear path (where it already calls
  `setOrigin(null)`), and from the geolocation `useEffect`, in
  `frontend/src/components/RoutePanel.tsx` (makes T003 pass).
- [x] T005 Wire the parent in `frontend/src/pages/PlanRoutePage.tsx`: add
  `const [origin, setOrigin] = useState<Coordinate | null>(null)`, pass `origin={origin}` to
  `<MapView>`, and pass `onOriginChange={setOrigin}` to `<RoutePanel>`.

**Checkpoint**: The confirmed origin flows parent→`MapView`; `RoutePanel` announces set/clear/geo and
stays silent while typing.

---

## Phase 3: User Story 1 - See my starting point on the map (Priority: P1) 🎯 MVP

**Goal**: Selecting a starting address recenters the map on it at street level and drops a single
marker; the marker moves on re-selection and disappears when the origin is cleared.

**Independent Test**: Select a known address → map is centered on it at zoom 16 with one marker;
select another → marker moves; clear the field → marker gone; an address with no coordinate → no
move/marker.

- [x] T006 [P] [US1] Write the MapView recenter+marker test in
  `frontend/tests/unit/map-view.test.tsx` (maplibre stubbed): on `origin` set → **`flyTo`** is called
  with center `[lng, lat]` and zoom `ORIGIN_ZOOM` (US1 default; the reduced-motion `jumpTo` branch is
  added in T011), and the origin source `setData` receives a single Point feature; on `origin` `null`
  → origin source set to an empty `FeatureCollection` and no camera move; on rapid re-selection → ends
  on the latest center with exactly one feature; the recenter MUST NOT disable map interaction handlers
  (no `dragPan`/`scrollZoom`/`touchZoomRotate` `.disable()` calls — FR-008). Confirm it FAILS.
- [x] T007 [US1] Add the origin marker as a GeoJSON source + circle layer in
  `frontend/src/components/MapView.tsx`, created behind the existing style-load gating and following
  the `CameraLayer.tsx` source/layer pattern.
- [x] T008 [US1] Add the recenter-on-origin effect in `frontend/src/components/MapView.tsx`: when
  `origin` is a usable coordinate and the map is ready, recenter to `[lng, lat]` at `ORIGIN_ZOOM` and
  `setData` the marker to that point; when `origin` is `null`/unusable, clear the marker source and do
  not move the map; a newer `origin` supersedes an in-flight move (FR-006/007/012/013). Makes T006 pass.

**Checkpoint**: MVP delivered — picking an address centers the map at street level with a marker.

---

## Phase 4: User Story 2 - A comfortable, non-disorienting move (Priority: P2)

**Goal**: The recenter animates smoothly within a bounded time by default, and jumps instantly with no
animation when the user prefers reduced motion.

**Independent Test**: With default motion, the recenter animates (~600 ms); with the OS reduce-motion
setting on, the recenter is instant.

- [x] T009 [P] [US2] Write the reduced-motion util test in `frontend/tests/unit/reduced-motion.test.ts`:
  `prefersReducedMotion()` returns `true`/`false` per a `matchMedia` mock and `false` when `matchMedia`
  is unavailable. Confirm it FAILS first.
- [x] T010 [P] [US2] Implement `prefersReducedMotion()` in `frontend/src/utils/reducedMotion.ts`
  reading `window.matchMedia("(prefers-reduced-motion: reduce)")` (research D2). Makes T009 pass.
- [x] T011 [US2] Extend `frontend/tests/unit/map-view.test.tsx`: the recenter uses `jumpTo` when
  `prefersReducedMotion()` is `true` and `flyTo` with a bounded duration otherwise. Confirm the new
  assertions FAIL first.
- [x] T012 [US2] Gate the recenter in `frontend/src/components/MapView.tsx` on the motion preference:
  `prefersReducedMotion() ? map.jumpTo({center, zoom}) : map.flyTo({center, zoom, duration: 600})`.
  Makes T011 pass.

**Checkpoint**: Smooth by default, instant under reduced motion — US1 still passes.

---

## Phase 5: User Story 3 - Responsible, predictable framing (Priority: P3)

**Goal**: Confirm the "responsibly" properties end-to-end — a consistent street-level zoom regardless
of density, no map movement while the user is still typing, and no third-party leak of the coordinate.

**Independent Test**: Two different-density addresses land at the same zoom; the map does not move on
intermediate typing; no outbound third-party request carries the coordinate during recenter.

- [x] T013 [US3] Extend the plan-route e2e flow in `frontend/tests/e2e/plan-route.spec.ts`: selecting a
  starting address recenters the map and shows exactly one marker; selecting a different-density
  address yields the same zoom level; clearing the field removes the marker; after the recenter a
  user-initiated pan/zoom still changes the map view (FR-008, manual control retained); and assert the
  map is centered on the address within **1.5 s** of selection (SC-001, automated measurement).
- [x] T014 [US3] Add an e2e "no move while typing" assertion in
  `frontend/tests/e2e/plan-route.spec.ts`: typing characters without selecting a suggestion leaves the
  map center/zoom unchanged (FR-005/SC-004).
- [x] T015 [P] [US3] Add an e2e anonymity assertion in `frontend/tests/e2e/anonymity.spec.ts`: during
  origin selection + recenter, no third-party request carries the origin coordinate — only same-origin
  tile/style requests occur (FR-009).

**Checkpoint**: All three stories verified; the "responsible" framing holds end-to-end.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T016 [P] Add intent-documenting comments and remove any dead code in
  `frontend/src/components/MapView.tsx` and `frontend/src/utils/reducedMotion.ts` (why fixed zoom 16,
  why a GeoJSON marker over `maplibregl.Marker`, why `jumpTo` under reduced motion) — Principle I.
- [x] T017 [P] Run the quality gates from `frontend/`: `pnpm lint` (zero warnings),
  `pnpm exec tsc -b --noEmit`, `pnpm exec vitest run`, `pnpm exec playwright test` — Principles I & II.
- [x] T018 [P] Manual verification per `specs/007-zoom-to-origin/quickstart.md`: reduced-motion and
  anonymity spot checks, plus a manual cross-check of the performance budget (centered ≤ 1.5 s, SC-001
  — now also asserted automatically in T013).

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T005)** → **US1 (T006–T008)** → **US2 (T009–T012)** →
  **US3 (T013–T015)** → **Polish (T016–T018)**.
- **US2 depends on US1** (it gates US1's recenter on the motion preference).
- **US3 depends on US1 + US2** (it verifies the full behavior end-to-end).
- Within Foundational: T002 (MapView prop) and T003 (RoutePanel test) are parallel; T004 depends on
  T003; T005 depends on T002 and T004.

## Parallel Opportunities

- T002 ∥ T003 (different files).
- T006 (US1 test) can be written in parallel with finishing Foundational, but run/verify after T005.
- T009 ∥ T010 (util + its test) can pair-develop; T010 must land to make T009 pass.
- T015 (anonymity e2e, separate file) ∥ T013/T014 (plan-route e2e, shared file — keep sequential).
- T016 ∥ T017 ∥ T018 (independent polish/verification).

## Implementation Strategy

- **MVP = User Story 1** (T001–T008): a confirmed address recenters the map at street level with a
  marker. This alone delivers the core value (visual confirmation of the start point).
- **Increment 2 = User Story 2** (T009–T012): accessibility/comfort — reduced-motion-aware transition.
- **Increment 3 = User Story 3** (T013–T015): verify the responsible-framing and anonymity properties
  end-to-end.
- Land each story behind passing tests and the quality gates before starting the next.

## Task Count

- Total: **18** tasks — Setup 1, Foundational 4, US1 3, US2 4, US3 3, Polish 3.
- Test tasks: T003, T006, T009, T011, T013, T014, T015 (unit + e2e).

## Analyze Remediation (applied)

- **C1 (FR-008 coverage)**: T006 now asserts the recenter never disables map interaction; T013 verifies
  a user pan/zoom still works after recenter.
- **U1 (US1 camera method)**: T006 pins the US1 default to `flyTo` (`jumpTo` branch arrives in T011).
- **C2 (SC-001 measurement)**: T013 now asserts the ≤ 1.5 s budget automatically; T018 keeps a manual
  cross-check.

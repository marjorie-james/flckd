---
description: "Task list for Render Camera Locations in the Current Viewport"
---

# Tasks: Render Camera Locations in the Current Viewport

**Input**: Design documents from `/specs/008-viewport-cameras/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ui-contract.md

**Tests**: Per Constitution Principle II (Testing Standards, NON-NEGOTIABLE), every behavioral change
is accompanied by automated tests that fail without it. Test tasks below are REQUIRED; write them
first and confirm they FAIL before implementing.

**Organization**: Tasks are grouped by user story. Each story is an independently testable increment.
This feature is **frontend-only** — no backend changes (the `cameras` endpoint already serves the
routable set, incl. disputed).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 (setup, foundational, polish carry no story label)
- All paths are repository-relative.

## Path Conventions

Web application; all changes under `frontend/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Shared constants the camera layer depends on.

- [x] T001 [P] Add camera map constants in `frontend/src/components/CameraLayer.tsx`: source id
  `cameras`, layer ids (`camera-clusters`, `camera-cluster-count`, `camera-points`), clustering config
  (`CLUSTER_RADIUS`, `CLUSTER_MAX_ZOOM`), the debounce interval, and paint styles (cluster bubble,
  count label, confirmed vs. disputed/low-confidence point styling).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Mount the camera layer on the live map and establish the viewport→cameras data channel
every story rides on. No story can work until cameras for the current viewport are fetched.

**⚠️ CRITICAL**: Complete this phase before any user-story phase.

- [x] T002 [P] Write the viewport-fetch test in `frontend/tests/unit/camera-layer.test.tsx`:
  `CameraLayer` computes a bbox from the map on `moveend`, debounces it, and requests cameras for that
  bbox (via the `useCameras` hook); rapid moves coalesce to one request for the settled view. Confirm
  it FAILS first.
- [x] T003 Rewrite `frontend/src/components/CameraLayer.tsx` to take `map: maplibregl.Map | null`,
  compute the viewport bbox from `map.getBounds()` on `moveend` (debounced), and call `useCameras(bbox)`
  — the data channel, no rendering yet. Makes T002 pass.
- [x] T004 Mount the layer in `frontend/src/components/MapView.tsx`: promote the created map instance to
  state (set once after construction) and render `{map && <CameraLayer map={map} />}`.

**Checkpoint**: Cameras for the current viewport are fetched (and refetched on pan/zoom, debounced);
nothing rendered yet.

---

## Phase 3: User Story 1 - See cameras where I'm looking (Priority: P1) 🎯 MVP

**Goal**: Render the viewport's cameras on the map — individual markers where sparse, count bubbles
(clusters) where dense.

**Independent Test**: View an area with cameras → individual markers where spread out, a count bubble
where several cluster; an empty area → nothing; markers update as the map pans.

- [x] T005 [P] [US1] Extend `frontend/tests/unit/camera-layer.test.tsx`: on fetched cameras, a GeoJSON
  source is added with `cluster: true` and the cluster / cluster-count / unclustered-point layers are
  added; `setData` updates on a new viewport; an empty result yields no rendered features. Confirm the
  new assertions FAIL.
- [x] T006 [US1] Implement the clustered render in `frontend/src/components/CameraLayer.tsx`: a
  GeoJSON source (`cluster: true`, `CLUSTER_RADIUS`, `CLUSTER_MAX_ZOOM`) fed by `setData` from
  `useCameras`, plus the cluster-circle, cluster-count (symbol), and unclustered-point layers, inserted
  **below** the route line and origin marker (FR-009). When `useCameras` returns the capped 500,
  surface it (log/telemetry — no silent truncation, FR-011). Makes T005 pass.

**Checkpoint**: MVP — cameras render clustered for the current view and update as the map moves.

---

## Phase 4: User Story 2 - Clusters expand on tap (Priority: P2)

**Goal**: Tapping a cluster zooms the map in toward it so it breaks apart into smaller clusters /
individual markers.

**Independent Test**: Tap a cluster bubble → the map zooms in and that cluster separates; under
reduced motion the zoom is instant.

- [x] T007 [P] [US2] Extend `frontend/tests/unit/camera-layer.test.tsx`: clicking a cluster resolves
  its expansion zoom and recenters to it — `easeTo` normally, `jumpTo` when `prefersReducedMotion()` is
  true. Confirm the new assertions FAIL.
- [x] T008 [US2] Implement the cluster click handler in `frontend/src/components/CameraLayer.tsx`: on a
  click hitting the cluster layer, get the cluster's expansion zoom and recenter the map to it, gated on
  `prefersReducedMotion()` (reuse `frontend/src/utils/reducedMotion.ts`). Makes T007 pass.

**Checkpoint**: Tapping a cluster zooms in and expands it; US1 still passes.

---

## Phase 5: User Story 3 - Inspect a camera, spot disputed ones (Priority: P3)

**Goal**: Tapping an individual camera shows its details; disputed/low-confidence cameras look
distinct from confirmed ones.

**Independent Test**: Tap an individual camera → a popup shows type/confidence/status; a disputed
camera renders visibly differently from a confirmed one; tapping empty map shows nothing.

- [x] T009 [P] [US3] Extend `frontend/tests/unit/camera-layer.test.tsx`: clicking an unclustered camera
  opens a popup containing its type/confidence/status; the popup contains **only reference fields** (no
  user data, FR-014) and is **dismissible via keyboard/Esc** (FR-015/SC-010); the unclustered-point
  layer uses a data-driven paint that distinguishes disputed/low-confidence from confirmed. Confirm the
  new assertions FAIL.
- [x] T010 [US3] Implement in `frontend/src/components/CameraLayer.tsx`: a click on the unclustered-point
  layer opens a `maplibregl.Popup` with the camera's type/confidence/verification status (reference
  fields only, FR-014), keyboard-dismissible via Esc (FR-015), and the point layer paint is keyed on
  `verification_status`/`confidence` so disputed/low-confidence differ from confirmed (FR-006/008).
  Makes T009 pass.

**Checkpoint**: Tap a camera → details; disputed cameras are visually distinct.

---

## Phase 6: End-to-End Verification & Polish

- [x] T011 [P] Add the viewport-cameras e2e in `frontend/tests/e2e/viewport-cameras.spec.ts` (mock
  `/cameras` to return a dense group + a disputed camera; read map state via the opt-in `__flckdMap`
  hook): cameras render for the viewport within **1 s** of the view settling (SC-001) and update on
  pan; tapping a cluster zooms in and it expands; tapping a camera opens a details popup that
  **dismisses via Esc** (SC-010); the disputed camera is styled distinctly.
- [x] T012 [P] Add an anonymity e2e in `frontend/tests/e2e/anonymity.spec.ts`: while panning/viewing,
  camera requests go only to our own origin (`/api/v1/cameras?bbox=`) — no third party receives the
  bbox (FR-013).
- [x] T013 [P] Add intent-documenting comments and remove dead code in
  `frontend/src/components/CameraLayer.tsx` (why native clustering, the cap tradeoff, layer ordering) —
  Principle I.
- [x] T014 [P] Run the quality gates from `frontend/`: `pnpm lint` (zero warnings),
  `pnpm exec tsc -b --noEmit`, `pnpm exec vitest run`, `pnpm exec playwright test`; then manual
  verification per `specs/008-viewport-cameras/quickstart.md` (seed fixtures; perf ≤1 s; anonymity).

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T004)** → **US1 (T005–T006)** → **US2 (T007–T008)** /
  **US3 (T009–T010)** → **Polish (T011–T014)**.
- **US2 and US3 both depend on US1** (clusters/points must render before they can be expanded,
  inspected, or styled). US2 and US3 are independent of each other in concept but edit the same file
  (`CameraLayer.tsx`), so run them sequentially.
- Within each phase, the test task precedes its implementation task (tests-first).

## Parallel Opportunities

- T001 (setup) is standalone [P].
- Test tasks (T002, T005, T007, T009) are written before their impl; they touch the same test file as
  each other, so author them in sequence even though each is marked [P] relative to non-test work.
- T012 (anonymity e2e, separate file) ∥ T011 (viewport-cameras e2e, separate file).
- T013 ∥ T014 (comments vs. gate runs) — independent.

## Implementation Strategy

- **MVP = User Story 1** (T001–T006): cameras render clustered for the current viewport and follow the
  map. Delivers the core "see where the cameras are."
- **Increment 2 = User Story 2** (T007–T008): drill into clusters by tapping.
- **Increment 3 = User Story 3** (T009–T010): inspect a camera + distinguish disputed ones.
- Land each story behind passing tests and the quality gates before the next.

## Task Count

- Total: **14** tasks — Setup 1, Foundational 3, US1 2, US2 2, US3 2, Polish 4.
- Test tasks: T002, T005, T007, T009 (unit) + T011, T012 (e2e).

## Analyze Remediation (applied)

- **D1 (accessibility)**: popup is keyboard-dismissible (Esc) + reference-only — new FR-015/SC-010,
  covered by T009 (test), T010 (impl), T011 (e2e Esc dismiss).
- **C1 (perf automated)**: T011 now asserts cameras appear within 1 s (SC-001), not just manual.
- **C2 (cap surfacing)**: T006 surfaces hitting the 500 cap (log/telemetry — FR-011, no silent
  truncation).
- **C3 (reference-data only)**: T009/T010 assert the popup exposes only reference fields (FR-014).
- **A1 (cap subset)**: FR-011 + Assumptions clarified the subset is the server's capped result.

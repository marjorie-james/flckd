---

description: "Task list for Responsive, Full-Width Layout"
---

# Tasks: Responsive, Full-Width Layout

**Input**: Design documents from `/specs/010-responsive-layout/`

**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/responsive-layout.md ✅

**Tests**: Per Constitution Principle II (NON-NEGOTIABLE), this layout change ships with automated tests. Because layout/overflow/measurement can only be verified with a real layout engine, the tests are **Playwright e2e** (jsdom cannot measure geometry). Each story's tests are authored to **FAIL against the current `main` 520px layout** and pass after the change.

**Organization**: Tasks are grouped by user story. Note the shared-file constraint below.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (maps to spec.md user stories)

## Path Conventions

Web app — only `frontend/` is touched:
- Page: `frontend/src/pages/PlanRoutePage.tsx`
- Styles: `frontend/src/App.css`
- Tests: `frontend/tests/e2e/` (reusing `helpers.ts`)

> **⚠️ Shared-file reality**: nearly every task edits `frontend/src/App.css` and the single new spec `frontend/tests/e2e/responsive-layout.spec.ts`. This makes `[P]` markers rare. Stories are each independently **testable** (verify at their viewports), but they are not independently **deliverable in parallel** without merge coordination on `App.css`. Recommended execution is sequential by phase.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test scaffolding the stories build on.

- [X] T001 [P] Add responsive test helpers to `frontend/tests/e2e/helpers.ts`: a `VIEWPORTS` list (`{name,width,height}` for 320/375/768/900/1024/1440/2560 plus a short-height landscape entry `{name:"landscape-phone",width:812,height:375}`), `expectNoHorizontalScroll(page)` (asserts `documentElement.scrollWidth <= clientWidth`), `sideMarginFraction(page)` (combined empty L+R margin as a fraction of viewport width), and `mapWidthFraction(page)` (map element width ÷ content-area width).
- [X] T002 Create `frontend/tests/e2e/responsive-layout.spec.ts` skeleton importing `mockApi`, `planRoute`, and the T001 helpers, with empty per-breakpoint `test.describe` blocks. (Depends on T001.)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The full-width base shell + DOM regions every story depends on.

**⚠️ CRITICAL**: No story work can begin until this phase is complete.

- [X] T003 Restructure `frontend/src/pages/PlanRoutePage.tsx`: keep `<header class="app-header">` at top; wrap `<MapView>` in a map-pane element and group `<RoutePanel>` + the `.result-section` into a content-pane (sidebar) wrapper. PRESERVE: the labelled `.map-container` `role="region"` + `aria-label`, the `aria-live="polite"` result section, and reading order header → origin → destination → plan → results. No behavior/props changes.
- [X] T004 Replace the fixed-width shell in `frontend/src/App.css`: remove `max-width: 520px` and `margin: 0 auto` from `.plan-page`; make it a mobile-first, full-width, edge-to-edge base (`min-height: 100svh`, stacked column) so the page is full-width at every size with the existing header → map → controls → results flow. (Depends on T003 class names.)

**Checkpoint**: App is full-width at all widths (no 520px centered strip, no big side margins); layout is a coherent stacked column. The original empty-margin defect is gone even before per-breakpoint polish.

---

## Phase 3: User Story 1 - Desktop full-width, map-prominent layout (Priority: P1) 🎯 MVP

**Goal**: On wide screens the map dominates with controls/results in an adjacent scrollable sidebar; no wasted side margins.

**Independent Test**: At 1440px, content fills the usable width (combined side margin ≤5%), the map occupies ≥55% of the content area, and after planning a route all controls + results are reachable with no horizontal scroll.

### Tests for User Story 1 (REQUIRED — Constitution Principle II) ⚠️

- [X] T005 [US1] In `frontend/tests/e2e/responsive-layout.spec.ts`, add desktop assertions at 900/1024/1440px: two-pane arrangement present (map pane + sidebar pane side by side), `mapWidthFraction >= 0.55` (INV-7/SC-003), `sideMarginFraction <= 0.05` at 1440 (INV-6/SC-001), `expectNoHorizontalScroll` (INV-1), and — after `planRoute` — route notice/camera summary/results visible & reachable (INV-2). Confirm these FAIL on the current layout before implementing.

### Implementation for User Story 1

- [X] T006 [US1] Add the `≥900px` two-pane layout to `frontend/src/App.css`: make `.plan-page` a CSS Grid (`grid-template-columns: 1fr min(420px, 38%)`) with the header spanning the top, the map pane as the `1fr` dominant column, and the sidebar pane bounded; shell height `100svh`.
- [X] T007 [US1] In `frontend/src/App.css`, make the map pane fill its grid cell height (`.map-container { height: 100% }` at `≥900px`) and give the sidebar pane `overflow-y: auto` so long turn-by-turn lists scroll without moving the map; add `min-width: 0` to grid children to prevent overflow. Verify MapView/overlays reposition on the resized pane.

**Checkpoint**: Desktop is map-dominant two-pane; T005 passes. MVP delivered — the user's "huge margins" complaint is resolved on desktop.

---

## Phase 4: User Story 2 - Adapts across smaller desktop & tablet (Priority: P2)

**Goal**: The layout reflows cleanly between desktop and mobile and behaves well on ultra-wide displays — no overflow, clipping, or centered-strip regression.

**Independent Test**: Resizing from 1440px to 600px crosses the 900px boundary with no overlap/off-screen content or horizontal scrollbar; at 2560px the sidebar stays bounded and the map absorbs the extra width (no narrow centered strip).

### Tests for User Story 2 (REQUIRED — Constitution Principle II) ⚠️

- [X] T008 [US2] Add assertions to `frontend/tests/e2e/responsive-layout.spec.ts`: at 768px the layout is stacked & full-width AND origin/destination/plan controls are visible and clickable, and after `planRoute` the results are reachable (INV-2/SC-004); at 900px it is two-pane (the transition, INV-8); at 2560px `sideMarginFraction` stays low (no centered strip, FR-008) and the sidebar width is bounded; stepping the viewport across 900px in both directions leaves no element off-screen or overlapping (FR-007). Confirm the relevant cases FAIL pre-implementation.

### Implementation for User Story 2

- [X] T009 [US2] Add the `≥1600px` rule to `frontend/src/App.css` capping the sidebar column (~420px) so the map consumes remaining width; ensure NO overall page-width cap is introduced (do not reintroduce centering).
- [X] T010 [US2] Harden the 900px transition in `frontend/src/App.css`: eliminate any intermediate-width overflow (guard grid/flex children with `min-width: 0`, `max-width: 100%` on inputs/content), so reflow across the breakpoint is clean.

**Checkpoint**: Smooth, robust reflow across the full width range; US1 + US2 both verified.

---

## Phase 5: User Story 3 - Mobile full-width stacked flow preserved (Priority: P3)

**Goal**: On phones the map → controls → results flow uses the full device width edge-to-edge with comfortable tap targets.

**Independent Test**: At 320px and 375px, content is edge-to-edge (no side margins), order is map → controls → results, there is no horizontal scroll, and all controls are tappable/operable.

### Tests for User Story 3 (REQUIRED — Constitution Principle II) ⚠️

- [X] T011 [US3] Add assertions to `frontend/tests/e2e/responsive-layout.spec.ts` at 320/375px AND the short-height landscape-phone viewport: `sideMarginFraction ≈ 0` (edge-to-edge, SC-001), stacked DOM order map → controls → results (INV-4), `expectNoHorizontalScroll` (INV-1/SC-002), and origin/destination/plan controls visible & clickable (INV-2). At landscape-phone height, additionally assert the map does not consume the entire visible area and the primary planning controls remain reachable (spec Edge Cases: short viewports). Confirm FAIL against the current layout.

### Implementation for User Story 3

- [X] T012 [US3] Refine the mobile/stacked branch in `frontend/src/App.css`: keep `.map-container` on an `svh`-based height with a `min-height` floor (avoids iOS toolbar `vh` jump), ensure the shell and panes are edge-to-edge full width below 900px, and confirm tap targets/text remain usable at 320px.

**Checkpoint**: All three stories independently functional and verified across the breakpoint matrix.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Accessibility, regression safety, and cleanup across all stories.

- [X] T013 Extend accessibility coverage: run the axe audit at a mobile (375px) and desktop (1440px) viewport — either by parameterizing `frontend/tests/e2e/a11y.spec.ts` over those sizes or adding an axe pass in `responsive-layout.spec.ts` (INV-5, Constitution III). Excludes the MapLibre canvas as the existing a11y spec does.
- [X] T014 Remove dead/duplicated CSS in `frontend/src/App.css` left by the rework (old fixed-width rules, redundant declarations) and ensure responsive sections carry intent-explaining comments (Constitution I). No `[P]` — same file as most tasks.
- [X] T015 Run `cd frontend && pnpm lint` (zero warnings) and `pnpm test` (Vitest component/unit suite); fix any fallout from the JSX/CSS changes.
- [X] T016 Run the full e2e suite `cd frontend && pnpm build && pnpm e2e` and confirm NO regressions in `a11y.spec.ts`, `anonymity.spec.ts` (no new third-party requests/identifiers — anonymity non-negotiable), and `perf.spec.ts` (performance budget holds — NFR-003/SC-007, Constitution IV; verify CLS stays <0.1), plus `plan-route`, `route-comparison`, etc.
- [X] T017 [P] Execute the `quickstart.md` manual verification across all breakpoints, and verify the dark theme (colors, typography, component styling) is visually unchanged (NFR-001): check whether `frontend/tests/e2e/screenshot-redesign.spec.ts` has committed baselines — if it does, confirm/update them; if it does not, record theme-preservation as a manual quickstart sign-off step rather than relying on an absent snapshot.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 → T002. No source dependencies.
- **Foundational (Phase 2)**: T003 → T004. Depends on Setup. **BLOCKS all user stories.**
- **User Stories (Phase 3–5)**: all depend on Foundational. Recommended sequential P1 → P2 → P3 because they edit the same `App.css` (media-query blocks) and the same spec file; each is independently *testable* at its viewports.
- **Polish (Phase 6)**: depends on the desired stories being complete.

### Within Each User Story

- Tests authored first and shown to FAIL against current layout (Constitution II), then implementation.
- US1 establishes the desktop grid; US2 hardens transitions/ultra-wide on top of it; US3 refines the mobile branch.

### Parallel Opportunities

- **Limited by design** — `App.css` and `responsive-layout.spec.ts` are shared across phases.
- Genuinely parallelizable: **T001** (edits `helpers.ts`, different file) and **T017** (manual verification + screenshot check, no source edits).
- Within a story the test task and implementation tasks touch the same files, so they run sequentially.

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (full-width base) → 3. Phase 3 US1 (desktop two-pane).
4. **STOP and VALIDATE**: T005 green; desktop shows full-width map-dominant layout, margins gone.
5. This alone resolves the reported problem and is demoable.

### Incremental Delivery

1. Setup + Foundational → full-width base at all sizes (defect already gone).
2. + US1 → desktop two-pane (MVP). Test → demo.
3. + US2 → robust reflow + ultra-wide. Test → demo.
4. + US3 → mobile/small-screen refinement. Test → demo.
5. Polish → a11y at breakpoints, regression suite, cleanup.

---

## Notes

- This is a presentation-only change: no API, data, theme, or behavior changes; anonymity guarantees untouched (verified by `anonymity.spec.ts` in T016).
- Tests have teeth: each story's assertions fail on the pre-change 520px layout.
- Commit after each phase/checkpoint.
- Avoid: reintroducing any overall page-width cap/centering (that is the exact defect being removed).

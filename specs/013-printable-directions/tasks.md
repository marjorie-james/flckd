---
description: "Task list for Printable Driving Directions"
---

# Tasks: Printable Driving Directions

**Input**: Design documents from `/specs/013-printable-directions/`

**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/print-view.md ✅

**Tests**: Per Constitution Principle II (Testing Standards, NON-NEGOTIABLE), every behavioral
change MUST be accompanied by automated tests that would fail without the change. Test tasks below
are REQUIRED. Write them FIRST and ensure they FAIL before implementing.

**Organization**: Tasks are grouped by user story. This is a **frontend-only** feature; all paths
are under `frontend/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, Polish have no story label)
- Exact file paths are included in every task

## Path Conventions

- Web app: frontend lives in `frontend/src/`, tests in `frontend/tests/`. No backend change.

---

## Phase 1: Setup (Shared)

**Purpose**: Establish a green baseline before changes. No new project/init — the React app and
Vitest suite already exist.

- [X] T001 Confirm the frontend test + lint baseline is green before changes (run the project's `frontend/` Vitest suite, `lint`, and `typecheck`) so regressions introduced later are attributable.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Lift the geocoded origin/destination **labels** out of `RoutePanel` local state up to
`PlanRoutePage` and thread them to `RouteResult`. The `Route` object has no address labels, so this
shared wiring is required before the print view can show origin/destination (US3) and before the
print control mounts inside `RouteResult` (US1). Captured at plan time so they can't desync (FR-012).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Extend the `onPlan` signature in `frontend/src/components/RoutePanel.tsx` to also pass the confirmed labels `{ origin: originText, destination: destText }` at submit time (alongside the existing coordinates).
- [X] T003 In `frontend/src/pages/PlanRoutePage.tsx`, store `originLabel` / `destinationLabel` in page state together with `endpoints` (set in `handlePlan`, cleared/replaced on each new plan), and pass them as props to `RouteResult`.
- [X] T004 In `frontend/src/components/RouteResult.tsx`, accept new `originLabel: string` and `destinationLabel: string` props (thread-through only; no new UI yet) so existing render is unchanged.
- [X] T005 [P] Add/extend tests in `frontend/tests/route-result.test.tsx` (and a focused render test for the page wiring) asserting that (a) confirmed origin/destination labels propagate from plan submission down to `RouteResult` props, and (b) after a second plan with different endpoints, the propagated labels/route reflect the new trip, never the prior one (FR-012, no stale route).

**Checkpoint**: Labels flow `RoutePanel → PlanRoutePage → RouteResult`; existing behavior unchanged and suite green.

---

## Phase 3: User Story 1 - Print a clean copy of the directions (Priority: P1) 🎯 MVP

**Goal**: An icon-only print control at the top of the directions opens the browser print dialog
showing a print-only view containing the full ordered turn-by-turn steps, with the map, page chrome,
and all interactive controls (and camera/coverage notices) excluded.

**Independent Test**: Plan a route → a printer icon appears atop the directions (absent with no
route); activating it calls the print dialog; the print region lists every step in order and
contains no map/chrome/controls/camera text.

### Tests for User Story 1 (REQUIRED — Constitution Principle II) ⚠️

> Write these FIRST and ensure they FAIL before implementation.

- [X] T006 [P] [US1] In `frontend/tests/printable-directions.test.tsx` (NEW): control is hidden when no route is rendered and shown when a route is present; clicking it calls `window.print` exactly once (stub via `vi.spyOn(window, "print")`); the print region renders every `route.maneuvers[i].localized_text` in order; the print region contains NO camera/coverage notice text (FR-010) and no map/control markup (FR-005); the control exposes an accessible name (`aria-label`); after re-rendering with a new route, the print region's steps reflect the new route, not the previous one (FR-012); and a route with 0 or 1 maneuvers still renders a valid, non-blank print region (heading + whatever steps exist).
- [X] T007 [P] [US1] In `frontend/tests/route-result.test.tsx`: assert the print control is mounted at the top of the directions section (in the directions header, before the `<ol>` of steps).

### Implementation for User Story 1

- [X] T008 [US1] Create `frontend/src/components/PrintableDirections.tsx`: an icon-only `<button>` (`aria-hidden` inline SVG printer icon; `aria-label` + `title` = `t("print.action")`) that calls `window.print()`, plus a print-only region (`class="printable-directions"`) rendering the heading `t("print.heading")` and an ordered `<ol class="print-steps">` of `route.maneuvers` `localized_text`. Props per `contracts/print-view.md` (`route`, `originLabel`, `destinationLabel`; origin/dest header added in US3).
- [X] T009 [US1] Add `print.action` and `print.heading` keys to `frontend/src/i18n/locales/en.json` and `frontend/src/i18n/locales/es.json` (parity, FR-011).
- [X] T010 [US1] Mount `PrintableDirections` in `frontend/src/components/RouteResult.tsx` inside a `directions-header` wrapping the existing `<h3>{t("result.directions")}</h3>`, passing `route`, `originLabel`, `destinationLabel`.
- [X] T011 [US1] Add the baseline print stylesheet in `frontend/src/App.css`: `@media screen { .printable-directions { display: none } }`; `@media print` hides app chrome (`.app-header`, `.app-footer`, `.map-container`, `.route-panel`, `.comparison-toggle`, `.export-gpx-btn`, the print trigger, `RouteNotice`, `CameraSummary`, and the on-screen `.directions`/`.stats`/status pills) and shows `.printable-directions`.

**Checkpoint**: MVP — user can print a clean, complete, correctly-scoped list of directions.

---

## Phase 4: User Story 2 - Readable while driving (Priority: P2)

**Goal**: The printed sheet is glanceable at arm's length — large, numbered, well-spaced,
black-on-white steps that paginate cleanly without splitting a step across a page break.

**Independent Test**: Produce the printout from US1 and confirm each step is large, numbered, and
clearly separated; a multi-page route paginates with no step split across a break.

### Tests for User Story 2 (REQUIRED — Constitution Principle II) ⚠️

- [X] T012 [P] [US2] In `frontend/tests/printable-directions.test.tsx`: assert the print steps render as a numbered list with the `print-steps` structure/class that the print CSS targets for per-step pagination (jsdom can't paginate, so assert the markup/classes the `@media print` rules rely on).

### Implementation for User Story 2

- [X] T013 [US2] Extend the `@media print` block in `frontend/src/App.css`: large readable base font with larger step numbering, generous line spacing, black text on white with no backgrounds/shadows/color, `.print-steps li { break-inside: avoid; }`, and NO fixed `@page size` (adapt to the user's Letter/A4 setting). (Depends on T011 — same file.)

**Checkpoint**: Printout is legible while driving and paginates correctly (US1 + US2 working).

---

## Phase 5: User Story 3 - Trip context and route-on-paper awareness (Priority: P3)

**Goal**: The printed sheet shows a heading, origin + destination labels, total travel time and
distance, and a brief notice that the printed page contains the user's route.

**Independent Test**: Produce the printout and confirm it shows From/To origin & destination, total
time & distance, and a privacy notice — in the active language.

### Tests for User Story 3 (REQUIRED — Constitution Principle II) ⚠️

- [X] T014 [P] [US3] In `frontend/tests/printable-directions.test.tsx`: assert the print region renders the origin and destination labels (From/To), the total travel time and distance, and the privacy notice; verify rendering under both `en` and `es`.

### Implementation for User Story 3

- [X] T015 [US3] Extend `frontend/src/components/PrintableDirections.tsx` to render the trip header: `t("print.from")` + `originLabel`, `t("print.to")` + `destinationLabel`, a totals line reusing `result.travelTime` / `result.distance` formatting, and the privacy notice `t("print.privacyNotice")`. (Depends on T008 — same file.)
- [X] T016 [US3] Add `print.from`, `print.to`, and `print.privacyNotice` keys to `frontend/src/i18n/locales/en.json` and `frontend/src/i18n/locales/es.json` (`privacyNotice` mirrors the intent/tone of `gpx.warning`, shortened for paper; parity required). (Depends on T009 — same files.)

**Checkpoint**: All three user stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final gates and acceptance.

- [X] T017 Run the lint + typecheck gates (Principle I) over `frontend/` and resolve any warnings introduced by this feature.
- [X] T018 [P] Confirm en/es parity for all `print.*` keys in `frontend/src/i18n/locales/en.json` and `es.json` (no missing/extra keys).
- [X] T019 Execute `specs/013-printable-directions/quickstart.md` manual verification, including the privacy check (browser network panel shows zero requests carrying route/location data during print, SC-006), confirming the print dialog opens with no perceptible delay (SC-007), and a print-to-PDF pass.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup. BLOCKS all user stories (provides the label lift + `RouteResult` props the print control mounts into).
- **User Stories (Phase 3–5)**: All depend on Foundational. US1 is the MVP; US2 refines US1's output; US3 adds header content.
- **Polish (Phase 6)**: Depends on all desired stories being complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational. Independent MVP.
- **US2 (P2)**: Builds on US1's print region (extends the same print CSS). Testable on its own once US1 exists.
- **US3 (P3)**: After Foundational (needs the lifted labels). Adds header content to US1's print region; does not change US1/US2 behavior.

### Within / across stories (file-contention serializations)

- `App.css` print rules: **T011 → T013** (same file).
- `PrintableDirections.tsx`: **T008 → T015** (same file).
- i18n locales (`en.json`/`es.json`): **T009 → T016** (same files).
- Tests in `printable-directions.test.tsx` (T006, T012, T014) target one file — written in separate, additive blocks; if edited concurrently, serialize by ID.

### Parallel Opportunities

- T005 (foundational tests) runs [P] alongside reviewing T002–T004 outputs.
- US1 tests T006 and T007 are in different files → run in parallel.
- Across stories, the per-story test authoring (T006/T012/T014) targets the same test file; the cross-story implementation files differ but each story's CSS/component/i18n edits are serialized as noted above.

---

## Parallel Example: User Story 1

```bash
# US1 tests live in different files — author them together (both must FAIL first):
Task: "Print control + print-view behavior test in frontend/tests/printable-directions.test.tsx"
Task: "Print control mounts atop directions test in frontend/tests/route-result.test.tsx"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup (baseline green).
2. Phase 2: Foundational (label lift) — CRITICAL, blocks stories.
3. Phase 3: US1 — print control + clean print-only step list.
4. **STOP and VALIDATE**: a complete, correctly-scoped printout from any route.
5. Ship/demo.

### Incremental Delivery

1. Setup + Foundational → wiring ready.
2. US1 → test → ship (MVP: printable directions).
3. US2 → test → ship (legible, paginated).
4. US3 → test → ship (trip header + privacy notice).

---

## Notes

- [P] = different files, no dependency on incomplete tasks.
- Tests are REQUIRED (Constitution Principle II) and must FAIL before implementation.
- Fully client-side: no network during print (assert SC-006 in T019); no backend/API changes.
- Commit after each task or logical group.

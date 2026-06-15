---
description: "Task list for 004-auto-route-priority"
---

# Tasks: Automatic Camera-Priority Routing

**Input**: Design documents from `specs/004-auto-route-priority/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/api-delta.md ✓

**Tests**: Per Constitution Principle II (Testing Standards, NON-NEGOTIABLE), every behavioral change MUST be accompanied by automated tests that would fail without the change. Write tests FIRST and ensure they FAIL before implementation.

**Organization**: Tasks grouped by user story — US1/US2 (backend routing) and US3 (frontend UI removal).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story this task belongs to ([US1]/[US2] = routing behavior; [US3] = no preference UI)

---

## Phase 1: Setup

No new project scaffolding required. All changes are modifications or deletions within the existing `backend/` and `frontend/` trees. Confirm working on branch `004-auto-route-priority` before starting.

---

## Phase 2: Foundational

No blocking shared infrastructure changes. US1/US2 (backend) and US3 (frontend) can proceed in parallel once branch is confirmed; they touch different parts of the stack.

---

## Phase 3: US1 + US2 — Automatic Routing Behavior (Priority: P1) 🎯 MVP

**Goal**: The backend always routes with "zero-camera first, fallback to fastest" — no caller-supplied preference. Existing `is_fully_clean` flag correctly communicates which outcome occurred.

**Independent Test**: POST `{"route":{"origin":{…},"destination":{…}}}` (no `avoidance_preference`) → response contains `is_fully_clean`, `cameras_avoided_count`, `remaining_cameras`. Sending `avoidance_preference` in the body has no effect.

### Tests for US1 + US2 (REQUIRED — Constitution Principle II) ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T001 [US1] In `backend/spec/services/routing/route_planner_spec.rb`: remove `balanced` and `fastest` preference contexts; add/verify an explicit test that `plan()` called without a `preference:` keyword returns a valid result (zero-camera path when available, fallback when not)
- [X] T002 [P] [US1] In `backend/spec/requests/api/v1/routes_spec.rb`: remove any `avoidance_preference` field from POST body fixtures; verify the request spec still exercises `is_fully_clean: true` and `is_fully_clean: false` response shapes
- [X] T003 [P] [US2] Delete `backend/spec/requests/api/v1/routes_preference_spec.rb` entirely (tests preference pass-through behavior that no longer exists)

### Implementation for US1 + US2

- [X] T004 [US1] In `backend/app/services/routing/route_planner.rb`: remove `preference:` keyword from `plan()` signature; remove `PREFERENCES`, `BALANCED_MIN_CONFIDENCE` constants; delete `balanced_route` private method; simplify `avoiding_route` to the two-case cascade (empty polygons → return fastest; otherwise try strict exclusion → return clean or fastest fallback)
- [X] T005 [P] [US2] In `backend/app/controllers/api/v1/routes_controller.rb`: remove `preference: route_params[:avoidance_preference] || "avoid"` from the `planner.plan(…)` call; remove `:avoidance_preference` from the `permit(…)` list

**Checkpoint**: `bundle exec rspec spec/services/routing/route_planner_spec.rb spec/requests/api/v1/routes_spec.rb` passes. `routes_preference_spec.rb` is gone. Backend ships US1 and US2.

---

## Phase 4: US3 — No Preference UI (Priority: P2)

**Goal**: The app renders no avoidance-preference controls at any point — not in the route form and not after a route result is shown.

**Independent Test**: Load the app, submit a route — no `<fieldset class="preference">`, no `.preference-radios`, no `.avoidance-strip` element exists in the DOM at any point in the flow.

### Tests for US3 (REQUIRED — Constitution Principle II) ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T006 [P] [US3] In `frontend/tests/unit/route-plan.test.tsx`: remove the `preference` prop from `<RoutePanel>` renders; remove the `onPreferenceChange` callback assertions; update the `onPlan` call assertion to not include a preference argument (or update to the new two-arg signature: `(origin, destination)`)
- [X] T007 [P] [US3] In `frontend/tests/e2e/plan-route.spec.ts`: remove any assertion that selects or interacts with a preference radio/segmented control
- [X] T008 [P] [US3] Delete `frontend/tests/avoidance-control.test.tsx` entirely
- [X] T009 [P] [US3] Delete `frontend/tests/e2e/avoidance-control.spec.ts` entirely

### Implementation for US3

- [X] T010 [P] [US3] In `frontend/src/types/api.ts`: delete the `AvoidancePreference` type and remove `avoidance_preference` from the `RouteRequest` interface; in `frontend/src/services/routeApi.ts`: remove `avoidance_preference` from the `planRoute()` call body
- [X] T011 [P] [US3] Delete `frontend/src/components/PreferenceRadios.tsx`
- [X] T012 [P] [US3] Delete `frontend/src/components/AvoidanceControl.tsx`
- [X] T013 [US3] In `frontend/src/components/RoutePanel.tsx`: remove `preference` and `onPreferenceChange` props from the `Props` interface and function signature; remove the `<fieldset className="preference">` block and its `<PreferenceRadios>` child; update `onPlan(origin, destination, preference)` call to `onPlan(origin, destination)` (depends on T011)
- [X] T014 [US3] In `frontend/src/pages/PlanRoutePage.tsx`: remove `preference` state and `setPreference`; remove `handlePreferenceChange`; remove `AvoidanceControl` import and `<div className="avoidance-strip">` block; update `handlePlan` and `runPlan` to not pass `pref`; update `RoutePanel` props (remove `preference`, `onPreferenceChange`) (depends on T012, T013)
- [X] T015 [P] [US3] In `frontend/src/App.css`: remove the `.preference-radios` rule block (including `:has(input:checked)` selector) and the `.avoidance-strip` rule
- [X] T016 [US3] In `frontend/src/i18n/locales/en.json` and `frontend/src/i18n/locales/es.json`: remove the entire `"preference"` key block (`avoid`, `balanced`, `fastest` entries) and the `"form.preference"` label key
- [X] T017 [US3] In `frontend/tests/e2e/helpers.ts`: simplify `routeFor()` to remove the `preference` parameter and always return the "avoid" (clean) route shape; update the route-intercept handler to not read `body.route?.avoidance_preference`
- [X] T018 [P] [US3] In `frontend/tests/unit/i18n.test.tsx`: remove any assertion that checks `preference.*` translation keys exist

**Checkpoint**: `pnpm test` (Vitest) and `pnpm exec playwright test` (Playwright) pass. No preference radio, segmented control, or avoidance-strip element exists in any rendered tree.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Contract cleanup and final validation across the full stack.

- [X] T019 [P] In `specs/002-flock-route-avoidance/contracts/openapi.yaml`: remove the `AvoidancePreference` schema component and remove the `avoidance_preference` property from the `RouteRequest` schema
- [X] T020 Run the full test suite end-to-end: `bundle exec rspec` (backend) + `pnpm test` (frontend unit) + `pnpm exec playwright test` (e2e); confirm zero failures and no preference-related dead code remains

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: No blocking setup — US1/US2 and US3 phases can begin together
- **US1 + US2 (Phase 3)**: Independent of US3 (Phase 4) — backend and frontend touch different layers
- **US3 (Phase 4)**: Independent of Phase 3 — can proceed in parallel
- **Polish (Phase 5)**: Depends on Phase 3 + Phase 4 complete

### Within Phase 3

- T001 (update spec) before T004 (implement — makes spec pass)
- T002 + T003 are [P] with T001 (different files)
- T005 is [P] with T004 (different files)

### Within Phase 4

- T006–T009 (tests/deletes) are all [P] — write/delete these first
- T010–T012 are [P] with each other (different files)
- T013 depends on T011 (PreferenceRadios.tsx gone); T014 depends on T012 + T013
- T015, T016, T017, T018 are [P] with T013/T014

### Parallel Opportunities

```
Phase 3 (US1+US2) and Phase 4 (US3) can run concurrently — one developer takes backend, another takes frontend.

Within Phase 3:
  Parallel: T002, T003 (while T001 is being written)
  Sequential: T001 → T004 → T005

Within Phase 4 (test deletes and type changes run together):
  Parallel: T006, T007, T008, T009, T010, T011, T012
  Then: T013 (after T011) → T014 (after T012 + T013)
  Parallel with T013/T014: T015, T016, T017, T018
```

---

## Implementation Strategy

### MVP First (US1 + US2 Only — Phase 3)

1. Complete Phase 3: backend simplification + backend tests
2. **STOP and VALIDATE**: `bundle exec rspec` passes; POST `/api/v1/routes` without `avoidance_preference` works correctly end-to-end
3. The frontend still renders preference controls at this point — that's fine; the backend is already correct

### Incremental Delivery

1. Phase 3 complete → API contract simplified, routing behavior locked in (US1 + US2 ✓)
2. Phase 4 complete → No preference UI anywhere in the app (US3 ✓)
3. Phase 5 complete → OpenAPI contract reflects reality; full test suite green

---

## Notes

- `[P]` tasks target different files with no outstanding dependencies — safe to start simultaneously
- Constitution Principle II: tests marked ⚠️ must be written and confirmed failing BEFORE the production code changes
- Deletions (T003, T008, T009, T011, T012) count as "write tests first" when they remove test files for behavior being deleted — do these before the production code removal
- After T004, `RoutePlanner#plan` no longer accepts `preference:` — any caller passing it will get an `ArgumentError`; verify no other callers exist (`grep -r "avoidance_preference\|preference:" backend/`)

# Implementation Plan: Responsive, Full-Width Layout

**Branch**: `010-responsive-layout` | **Date**: 2026-06-12 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-responsive-layout/spec.md`

## Summary

Replace the fixed 520px-wide, centered single column (`.plan-page` in `frontend/src/App.css`) with a responsive layout that fills the viewport across mobile → ultra-wide. On wide screens the map becomes the dominant surface with the planning controls and results in an adjacent scrollable sidebar; on narrow screens the existing full-width vertical flow (map → controls → results) is preserved. This is a **presentation-only** change: a minimal JSX restructure of `PlanRoutePage` into two regions (map pane + content pane) plus a CSS layout rework. No component is rebuilt, no feature/behavior/API/theme changes. Verified with Playwright e2e across representative viewports (no horizontal scroll, control reachability, map prominence) and axe a11y at each breakpoint.

## Technical Context

**Language/Version**: TypeScript 5.x, React 19

**Primary Dependencies**: Vite, MapLibre GL JS, @tanstack/react-query, react-i18next (all existing — no new dependencies)

**Storage**: N/A (presentational frontend change)

**Testing**: Vitest + Testing Library + jsdom (component/unit); Playwright + @axe-core/playwright (e2e + a11y). Responsive assertions live in Playwright because jsdom does not lay out or measure elements.

**Target Platform**: Modern evergreen browsers (desktop + mobile), served as a static SPA

**Project Type**: Web application (frontend in `frontend/`, backend in `backend/` — only `frontend/` is touched)

**Performance Goals**: No regression on existing load/interaction budgets (`tests/e2e/perf.spec.ts`); negligible cumulative layout shift on first render; resize/orientation reflow stays smooth (no visible jank or flash of broken layout).

**Constraints**: No horizontal scrolling from 320px to 2560px; preserve existing accessibility affordances (labelled map region, polite live region, keyboard reachability) at every breakpoint; no new third-party requests or identifiers (strict-anonymity non-negotiable).

**Scale/Scope**: One page (`PlanRoutePage`) and one stylesheet (`App.css`); ~8 existing presentational components rearranged, not modified in behavior.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Code Quality** — PASS. ESLint must pass with zero warnings (`pnpm lint`). CSS reorganized into clearly-commented responsive sections; no dead/duplicated rules left behind. JSX change is a single-responsibility region split. No new dependencies.
- **II. Testing Standards (NON-NEGOTIABLE)** — PASS (planned). Layout is observable behavior, so the change ships with Playwright e2e tests that fail on the current layout and pass after: no horizontal scroll at 320/375/768/1024/1440/2560px, controls reachable/operable at each, map-prominence on desktop, sidebar-vs-stacked arrangement per breakpoint, and clean reflow on resize. axe a11y re-run at mobile + desktop breakpoints. Existing suite must stay green (no regression).
- **III. User Experience Consistency** — PASS. Terminology, error structure, and the dark theme are unchanged. Accessibility affordances (the labelled `map-container` region, `aria-live` result section, keyboard order) are explicitly preserved and re-tested at each breakpoint. This is the "accessibility/feedback is part of done" clause applied to a layout change.
- **IV. Performance Requirements** — PASS. Budgets declared above; CSS-driven layout (no JS resize listeners, no measurement-driven layout in JS) keeps reflow cheap. Existing `perf.spec.ts` budget must hold; layout shift on first paint must not regress.

No violations → Complexity Tracking section omitted.

## Project Structure

### Documentation (this feature)

```text
specs/010-responsive-layout/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — breakpoints, layout mechanism, test strategy
├── data-model.md        # Phase 1 output — layout regions & breakpoint model (no data entities)
├── quickstart.md        # Phase 1 output — how to run & verify
├── contracts/
│   └── responsive-layout.md   # Phase 1 output — per-breakpoint UI contract & invariants
└── checklists/
    └── requirements.md  # Spec quality checklist (from /speckit-specify)
```

### Source Code (repository root)

```text
frontend/
├── src/
│   ├── App.css                      # PRIMARY CHANGE — replace fixed-width shell with responsive layout
│   ├── pages/
│   │   └── PlanRoutePage.tsx        # MINOR CHANGE — split into map pane + content (sidebar) pane
│   └── components/                  # UNCHANGED behavior — MapView, RoutePanel, RouteResult,
│       │                           #   RouteNotice, CameraSummary, LanguageSwitcher, etc.
│       └── ...                      #   (may receive layout-only class/wrapper tweaks)
└── tests/
    └── e2e/
        └── responsive-layout.spec.ts  # NEW — viewport-parameterized layout assertions + axe
```

**Structure Decision**: Web application; only `frontend/` is affected. The change is concentrated in `App.css` (layout rework) with a small structural edit to `PlanRoutePage.tsx`. Existing components are reused as-is. New tests go in the established `frontend/tests/e2e/` directory alongside `a11y.spec.ts` and `perf.spec.ts`, reusing `tests/e2e/helpers.ts` (`mockApi`, `planRoute`).

## Phase 0 — Research

See [research.md](./research.md). Resolves: exact breakpoint thresholds, the desktop two-pane mechanism (CSS grid vs flex), map sizing strategy per breakpoint, ultra-wide handling, tablet portrait/landscape behavior, and the responsive test approach (Playwright viewport parameterization). No `NEEDS CLARIFICATION` markers remain after research.

## Phase 1 — Design & Contracts

- [data-model.md](./data-model.md) — no persisted data entities; documents the layout regions and the breakpoint model (the structural "shape" the CSS implements).
- [contracts/responsive-layout.md](./contracts/responsive-layout.md) — the UI contract: required arrangement, map prominence, and hard invariants (no horizontal scroll, control reachability, preserved a11y) per breakpoint. These map 1:1 to the e2e assertions.
- [quickstart.md](./quickstart.md) — run the dev server, manually verify across sizes, and run the responsive + a11y e2e suite.
- Agent context: `CLAUDE.md` SPECKIT block updated to reference this plan.

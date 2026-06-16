# Implementation Plan: Printable Driving Directions

**Branch**: `013-printable-directions` | **Date**: 2026-06-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-printable-directions/spec.md`

## Summary

Add an icon-only print control at the top of the on-screen driving-directions section. Activating
it opens the browser's native print dialog rendering a dedicated, print-only view of the route:
a heading, origin + destination labels, total travel time and distance, the full ordered
turn-by-turn steps, and a brief "this page contains your route" privacy notice — in a large,
high-contrast, well-paginated layout that is glanceable while driving. The map, page chrome, and
all interactive controls are excluded; camera/coverage notices are deliberately omitted. The
entire flow is client-side (`window.print()` + a `@media print` stylesheet) with no network
transmission, consistent with the project's anonymity model. The one non-trivial change is
**lifting the geocoded origin/destination address labels** out of `RoutePanel` local state up to
`PlanRoutePage` so the print view can display them.

## Technical Context

**Language/Version**: TypeScript 5.x, React 19 (frontend only — no backend change)

**Primary Dependencies**: React 19, react-i18next (localization), Vite, existing `App.css`. Print
uses the browser-native `window.print()` API and a `@media print` stylesheet — no new library.

**Storage**: N/A — no persistence; renders from data already on screen.

**Testing**: Vitest + @testing-library/react (existing `frontend/tests/` suite; mirrors
`route-result.test.tsx` / `route-export.test.tsx`). `window.print` is stubbed via `vi.spyOn`.

**Target Platform**: Modern desktop + mobile browsers with native print/print-to-PDF.

**Project Type**: Web (frontend + backend); this feature is **frontend-only**.

**Performance Goals**: Print-view assembly is synchronous and trivial (≤ a few hundred list
items); the print dialog MUST open with no perceptible delay (< 100 ms from activation) and MUST
issue zero network requests.

**Constraints**: Fully client-side, no transmission of route/origin/destination (FR-013, SC-006);
icon-only control with an accessible label (FR-001); localized in en + es with parity (FR-011);
print layout legible at arm's length — large type, black-on-white, clean pagination (FR-006/007).

**Scale/Scope**: A single displayed route; maneuver lists up to a few hundred steps. ~1 new
component, 1 print stylesheet block, a small prop-lift in `RoutePanel`/`PlanRoutePage`, i18n keys.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Code Quality**: PASS. One small, single-responsibility component (`PrintableDirections`)
  plus a focused print stylesheet; intent-documenting comments; lint/format clean; no dead code.
  The origin/destination lift is a clean prop addition, not a workaround.
- **II. Testing Standards (NON-NEGOTIABLE)**: PASS. Every behavioral change is covered: control
  visibility (shown with a route, hidden without), `window.print()` invoked on activation,
  print-view content (heading, origin/destination, totals, all ordered steps, privacy notice),
  camera/coverage notices excluded, accessible label present, en/es localization. Tests assert
  observable behavior (DOM + spy), not internals. Deterministic — no real printing.
- **III. User Experience Consistency**: PASS. Icon-only control with `aria-label` + `title`
  follows the existing `geo-btn` pattern; reuses `result.*` terminology and the GPX-style privacy
  notice; accessible and localized as part of "done".
- **IV. Performance Requirements**: PASS. Budget declared above (< 100 ms to dialog, zero network
  requests); no measurable hot path, no unbounded growth.

**Result**: All gates pass. No violations → Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/013-printable-directions/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── print-view.md    # UI contract: component props, rendered structure, i18n keys
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
frontend/
├── src/
│   ├── components/
│   │   ├── PrintableDirections.tsx   # NEW: icon trigger + print-only view
│   │   ├── RouteResult.tsx           # CHANGE: mount the print control atop directions
│   │   ├── RoutePanel.tsx            # CHANGE: surface confirmed origin/dest labels upward
│   │   └── ...
│   ├── pages/
│   │   └── PlanRoutePage.tsx         # CHANGE: hold origin/dest labels, pass to RouteResult
│   ├── i18n/locales/
│   │   ├── en.json                   # CHANGE: add `print.*` keys
│   │   └── es.json                   # CHANGE: Spanish parity
│   └── App.css                       # CHANGE: add `@media print` block + control styles
└── tests/
    ├── printable-directions.test.tsx # NEW: control + print-view behavior
    └── route-result.test.tsx         # CHANGE: assert print control mounts atop directions
```

**Structure Decision**: Existing web layout (`frontend/` React app, `backend/` Rails API). This
feature touches only `frontend/`. A dedicated `PrintableDirections` component owns both the trigger
button and the print-only content region, keeping `RouteResult` focused and the print markup
self-contained. No backend, contract, or data-model changes on the server side.

## Complexity Tracking

> No constitution violations. Section intentionally empty.

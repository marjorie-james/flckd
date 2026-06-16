# Research: Printable Driving Directions

All Technical Context items were resolvable from the existing codebase and platform; there were
no open `NEEDS CLARIFICATION` markers after `/speckit-clarify`. The decisions below record the
approach chosen for each non-trivial aspect.

## Decision 1: Print mechanism — native `window.print()` + `@media print`

- **Decision**: Trigger printing with the browser-native `window.print()` and control output with
  a dedicated print-only DOM region styled under `@media print`. The print region is hidden on
  screen (`display: none`) and revealed only for print; the on-screen app (map, header, panel,
  controls) is hidden for print.
- **Rationale**: Zero new dependencies, fully client-side (satisfies FR-013/SC-006 — no network),
  and gives print-to-PDF for free via the OS dialog. A dedicated print region gives precise
  control over content/order (heading, origin/dest, totals, steps, notice) rather than fighting
  the screen layout's DOM. This mirrors how `RouteExport` stays fully local.
- **Alternatives considered**:
  - *Open a new window/tab and write markup* — leaks into popup-blocker territory, harder to
    localize/test, and a heavier UX than the in-place print dialog.
  - *Generate a PDF in-app (e.g. a PDF library)* — adds a dependency and bundle weight for no
    benefit; the OS print dialog already offers "Save as PDF". Rejected under Principle I.
  - *CSS-only: hide everything except the existing `.directions` list* — can't add origin/dest,
    totals, or the privacy notice, and inherits screen styling we'd have to override. A purpose
    built print region is simpler to reason about and test.

## Decision 2: Origin/destination labels must be lifted from `RoutePanel`

- **Decision**: The confirmed origin/destination **address labels** (`originText` / `destText`)
  currently live as local state in `RoutePanel`. Add an upward notification (extend `onPlan`, or a
  sibling callback, to include the chosen labels) so `PlanRoutePage` can store them alongside
  `endpoints` and pass them to `RouteResult` → `PrintableDirections`.
- **Rationale**: FR-008 (clarified) requires origin + destination on the printout, but the `Route`
  object contains no such labels — only geometry, maneuvers, and summary numbers. The labels exist
  only in the panel's geocode inputs. Lifting them is the minimal faithful source; deriving from
  coordinates would print raw lat/lng, not the human address the user picked.
- **Edge handling**: When origin came from "use my location", the label is a `lat, lng` string —
  acceptable as-is (it's what the user confirmed). Labels are captured at plan time and stored with
  the trip so a later edit of the input fields can't desync the printed sheet (FR-012).
- **Alternatives considered**:
  - *Add origin/destination labels to the backend `Route` response* — unnecessary backend coupling
    and a contract change for data the client already holds. Rejected.
  - *Reverse-geocode coordinates for the printout* — adds a network call (violates FR-013), is
    slower, and may not reproduce the label the user selected. Rejected.

## Decision 3: Camera/coverage notices excluded from print

- **Decision**: The print view renders only heading, origin/destination, totals, ordered steps,
  and the privacy notice. `RouteNotice` / `coverage_warning` / remaining-camera content is NOT
  reproduced.
- **Rationale**: Direct outcome of clarification Q2 ("Omit camera info entirely"). Keeps the sheet
  a clean driving aid; camera-aware planning remains an on-screen concern.

## Decision 4: Control affordance — icon-only with accessible label

- **Decision**: A `<button>` containing an inline SVG printer icon, `aria-hidden` on the SVG, with
  `aria-label` + `title` set to the localized "Print directions" string. Placed at the top of the
  directions section (next to the "Directions" heading).
- **Rationale**: Clarification Q3 chose icon-only. This matches the existing `geo-btn` pattern in
  `RoutePanel` (icon button + `aria-label`/`title`), satisfying Principle III consistency and
  accessibility (the label is localized, FR-011).

## Decision 5: Print legibility & pagination via print CSS

- **Decision**: Under `@media print`: black-on-white, large base font (≈ 14–16pt steps, larger
  numbered markers), generous line spacing, remove decorative backgrounds/shadows/color, and use
  `break-inside: avoid` on each step `<li>` so steps don't split across page breaks; numbered list
  continues across pages. Respect user page size (no fixed `@page size`).
- **Rationale**: Satisfies FR-006/FR-007 and SC-004/SC-005 with standard, well-supported print CSS.
- **Alternatives considered**: Fixed Letter `@page` size — rejected; the layout must adapt to
  Letter or A4 per the user's settings (Assumptions).

## Testing approach (Principle II)

- **Decision**: Vitest + @testing-library/react. Stub `window.print` with `vi.spyOn(window,
  "print")`. Assert: control hidden with no route / shown with a route; activation calls
  `window.print` once; print region contains heading, origin/destination, totals, every maneuver
  in order; contains no camera/coverage text; control has an accessible name; renders correctly
  under both `en` and `es`. Print-CSS visual rules are covered by structural assertions (presence
  of the print region + classes) since jsdom doesn't paginate.
- **Rationale**: Deterministic, behavior-focused, no real printing — consistent with the existing
  `route-export.test.tsx` approach of testing the local export path without performing it.

# flckd — Main Specification

> Consolidated, cross-feature specification. Each archived feature appends its user stories,
> functional requirements, entities, and success criteria here with a `[Source: specs/###-feature]`
> traceability tag. Functional requirement and success-criteria IDs form a single continuing
> sequence across features (the highest existing ID is never reused or renumbered).
>
> **Bootstrapped** from the first archival (`013-printable-directions`) on 2026-06-18.

---

## User Stories / Integration Scenarios

### Printable Driving Directions [Source: specs/013-printable-directions]

**US-013-1 — Print a clean copy of the directions (P1, MVP)**: A driver who has planned a
camera-avoided route activates a print control at the top of the on-screen directions; their
device's print dialog opens showing only the directions in a large, uncluttered, easy-to-read
layout (no map, no app navigation, no controls). Hidden when no route is planned.

**US-013-2 — Readable while driving (P2)**: The printed sheet is glanceable at arm's length —
large type, clear step numbering, generous spacing, black-on-white contrast — and paginates so an
individual step is not split across a page break where avoidable.

**US-013-3 — Trip context and route-on-paper awareness (P3)**: The sheet includes a heading, the
origin and destination labels, total travel time and distance, and a brief notice that the printed
page contains the user's route (mirroring the existing GPX-export warning).

---

## Functional Requirements

### Printable Driving Directions [Source: specs/013-printable-directions]

- **FR-001**: System MUST display a print control at the top of the driving-directions section
  whenever directions for a planned route are shown. The control MUST be presented as an icon only
  (no visible text label) with an accessible label exposed to assistive technology.
- **FR-002**: System MUST NOT display the print control when no route/directions are present.
- **FR-003**: Activating the print control MUST open the device's standard print dialog.
- **FR-004**: The printed output MUST include the complete, ordered set of turn-by-turn steps
  exactly as shown on screen for the currently displayed route.
- **FR-005**: The printed output MUST exclude the interactive map, page navigation/header, form
  inputs, and any on-screen-only controls (including the print control itself).
- **FR-006**: The printed output MUST present steps in a simplified, high-legibility layout: large
  type (step text at a minimum effective print size of ~14pt), clear per-step numbering, generous
  spacing, and black-on-white contrast.
- **FR-007**: The printed output MUST paginate long routes so steps continue across pages and
  individual steps are not split across a page break where avoidable.
- **FR-008**: The printed output MUST include a heading, the origin and destination labels, and the
  route's total travel time and distance.
- **FR-009**: The printed output MUST include a brief notice that the printed page contains the
  user's route (consistent with the existing export warning).
- **FR-010**: The printed output MUST NOT include camera or coverage notices (e.g. remaining-camera
  or coverage warnings); it contains only the driving steps and trip context.
- **FR-011**: The print control's accessible label and all printed text MUST honor the user's active
  language (en + es parity).
- **FR-012**: The print control MUST always reflect the currently displayed directions; after a
  re-plan it MUST print the new route, never a stale one. Origin/destination labels are captured at
  plan time so editing the input fields afterward cannot desync the printed sheet.
- **FR-013**: Producing the printout MUST be fully client-side and MUST NOT transmit the route, its
  directions, origin, or destination to the app's servers or any third party (the only network actor
  is the user's own print/PDF target chosen in the OS dialog). *Upholds the project anonymity
  non-negotiable.*

---

## Key Entities

### Printable Driving Directions [Source: specs/013-printable-directions]

- **Planned Route Directions / PrintableDirectionsView** *(derived, in-memory only — no persisted
  data, no backend schema change)*: The currently displayed route's ordered turn-by-turn steps plus
  its summary — the exact content the print view renders. Fields and their source:
  - `originLabel` (string) — lifted from `RoutePanel` (`originText`) up to `PlanRoutePage`; the
    human address the user picked, or a `lat, lng` string for "use my location". Captured at plan time.
  - `destinationLabel` (string) — as above, for the destination.
  - `totalDurationMin` (number) — from `Route.duration_s` (÷60, rounded), matching `result.travelTime`.
  - `totalDistanceKm` (string) — from `Route.distance_m` (÷1000, 1 dp), matching `result.distance`.
  - `steps` (`Maneuver[]`) — from `Route.maneuvers`, rendered in order via `localized_text`.
  - `privacyNotice` (i18n) — `print.privacyNotice` key.
  - Camera/coverage notices are deliberately excluded from this view.

---

## Edge Cases & Error Handling

### Printable Driving Directions [Source: specs/013-printable-directions]

- **Empty / single-step route**: A route with `maneuvers.length <= 1` still renders a valid sheet
  (heading + whatever steps exist), never a blank page.
- **Very long route**: Many steps paginate cleanly across pages with continued numbering — no
  overflow/clip, no step split across a page break where avoidable.
- **Remaining-camera / coverage notices**: Intentionally NOT carried onto the printout; the sheet is
  a clean driving aid while camera-aware planning stays an on-screen concern.
- **Re-plan after printing**: The print control always reflects the currently displayed directions,
  never a stale earlier route.
- **Localization**: Control label and printed content use the active language (en + es).
- **Print-to-PDF**: Saving as PDF via the OS dialog produces the same readable layout as paper.

---

## Success Criteria

### Printable Driving Directions [Source: specs/013-printable-directions]

- **SC-001**: From displayed directions, a user can open the print dialog in a single action.
- **SC-002**: 100% of the on-screen turn-by-turn steps appear, in order, in the printed output.
- **SC-003**: The printed output contains zero instances of the elements excluded by FR-005 (map,
  page chrome, interactive controls).
- **SC-004**: Printed step text renders at ≥14pt effective size and is readable at arm's length
  across the supported languages.
- **SC-005**: A multi-page route paginates with no step clipped or split across a page break in 100%
  of test cases.
- **SC-006**: Producing the printout results in zero application network requests carrying route or
  location data.
- **SC-007**: Activating the print control opens the print dialog with no perceptible delay (under
  100 ms), reflecting synchronous, client-side, no-network assembly.

---

## Revision Log

- **2026-06-18** — Bootstrapped main spec from first archival; merged `013-printable-directions`
  (US-013-1..3, FR-001..FR-013, PrintableDirectionsView entity, SC-001..SC-007).

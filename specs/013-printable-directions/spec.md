# Feature Specification: Printable Driving Directions

**Feature Branch**: `013-printable-directions`

**Created**: 2026-06-15

**Status**: Completed

**Input**: User description: "user can click print icon by top of driving directions, and the print styles allow it to be displayed in a simple, easily readable format while driving"

## Clarifications

### Session 2026-06-15

- Q: What trip context should appear at the top of the printed sheet? → A: Origin + destination labels plus total travel time and distance.
- Q: How should the route's remaining/avoided cameras be represented on the printout? → A: Omit camera info entirely — print only the driving steps (no camera or coverage notice).
- Q: How should the print control be presented? → A: Icon only, with an accessible label (aria-label) for assistive technology.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Print a clean copy of the directions (Priority: P1)

A driver has planned a camera-avoided route and wants a paper copy of the turn-by-turn
directions to follow while driving, so they don't have to look at a screen. They see a print
control at the top of the directions list, activate it, and their device's print dialog opens
showing only the directions in a large, uncluttered, easy-to-read layout. They print (or save
as PDF) and take the sheet with them.

**Why this priority**: This is the entire feature — a one-tap path from on-screen directions to
a readable printed sheet. Without it there is nothing to deliver. It is independently the MVP.

**Independent Test**: Plan any route, confirm a print control is visible at the top of the
directions, activate it, and verify the print preview shows the full ordered list of directions
in a simplified, legible layout (no map, no app navigation, no controls).

**Acceptance Scenarios**:

1. **Given** a route has been planned and directions are displayed, **When** the user activates
   the print control at the top of the directions, **Then** the device's print dialog opens.
2. **Given** the print dialog/preview is shown, **When** the user reviews the preview, **Then**
   it contains every turn-by-turn step in the same order shown on screen.
3. **Given** the print dialog/preview is shown, **When** the user reviews the preview, **Then**
   the interactive map, page chrome, form inputs, and on-screen-only controls are excluded.
4. **Given** no route has been planned yet, **When** the user looks at the page, **Then** no
   print control is shown (there is nothing to print).

---

### User Story 2 - Readable while driving (Priority: P2)

The printed sheet is formatted to be glanceable at arm's length while driving: large type,
clear step numbering, generous spacing, and high contrast (black on white), so a driver or
passenger can read the next step without squinting.

**Why this priority**: A printout that exists but is hard to read in a moving car fails the
stated goal ("easily readable format while driving"). This refines US1's output rather than
adding a separate capability.

**Independent Test**: Produce the printout from US1 and verify each step is numbered, set in
large high-contrast type with clear separation between steps, and that the directions are not
broken mid-step across a page where avoidable.

**Acceptance Scenarios**:

1. **Given** the printout, **When** read at typical arm's length, **Then** each step is clearly
   numbered and visually separated from adjacent steps.
2. **Given** the printout, **When** rendered, **Then** text is black on a white background with
   no decorative backgrounds, shadows, or color that reduce legibility or waste ink.
3. **Given** a route long enough to span multiple pages, **When** printed, **Then** steps flow
   across pages without an individual step being split across a page break where avoidable.

---

### User Story 3 - Trip context and route-on-paper awareness (Priority: P3)

The printed sheet includes light context so the driver can orient themselves — a heading
identifying it as the route's directions, the origin and destination labels, and the total
travel time and distance — and a brief notice that the printed page contains the route,
mirroring the existing export warning, so the user understands the paper itself holds their trip.

**Why this priority**: Useful orientation and a privacy-consistent reminder, but the core
print-and-read value is delivered by US1 and US2 without it.

**Independent Test**: Produce the printout and verify it shows a directions heading, the origin
and destination, total travel time and distance, and a short notice that the sheet contains the
user's route.

**Acceptance Scenarios**:

1. **Given** the printout, **When** rendered, **Then** it shows a heading, the origin and
   destination labels, and the route's total travel time and distance.
2. **Given** the printout, **When** rendered, **Then** it includes a brief notice that the
   printed page contains the user's route.

---

### Edge Cases

- **Empty / single-step route**: If the route has no maneuvers or only one, the print control
  still produces a valid sheet (heading plus whatever steps exist) rather than a blank page.
- **Very long route**: Many steps must paginate cleanly across multiple pages with continued
  numbering, not overflow or clip.
- **Remaining-camera / coverage notices**: These on-screen notices are intentionally NOT
  carried onto the printout — the printed sheet shows only the driving steps and trip context.
  The camera-aware planning still happens on screen; the printout is a clean driving aid.
- **Re-plan after printing**: If the user changes the route and re-plans, the print control
  always reflects the currently displayed directions, never a stale earlier route.
- **Localization**: The print control label and printed content use the user's active language,
  consistent with the rest of the app.
- **Print-to-PDF**: Saving as PDF (an option in the OS print dialog) produces the same readable
  layout as paper.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a print control at the top of the driving-directions section
  whenever directions for a planned route are shown. The control MUST be presented as an icon
  only (no visible text label) with an accessible label exposed to assistive technology.
- **FR-002**: System MUST NOT display the print control when no route/directions are present.
- **FR-003**: Activating the print control MUST open the device's standard print dialog.
- **FR-004**: The printed output MUST include the complete, ordered set of turn-by-turn steps
  exactly as shown on screen for the currently displayed route.
- **FR-005**: The printed output MUST exclude the interactive map, page navigation/header,
  form inputs, and any on-screen-only controls (including the print control itself).
- **FR-006**: The printed output MUST present steps in a simplified, high-legibility layout:
  large type (step text at a minimum effective print size of ~14pt), clear per-step numbering,
  generous spacing, and black-on-white contrast.
- **FR-007**: The printed output MUST paginate long routes so steps continue across pages and
  individual steps are not split across a page break where avoidable.
- **FR-008**: The printed output MUST include a heading, the origin and destination labels, and
  the route's total travel time and distance.
- **FR-009**: The printed output MUST include a brief notice that the printed page contains the
  user's route (consistent with the existing export warning).
- **FR-010**: The printed output MUST NOT include camera or coverage notices (e.g.
  remaining-camera or coverage warnings); it contains only the driving steps and trip context.
- **FR-011**: The print control's accessible label and all printed text MUST honor the user's
  active language.
- **FR-012**: The print control MUST always reflect the currently displayed directions; after a
  re-plan it MUST print the new route, never a stale one.
- **FR-013**: Producing the printout MUST be fully client-side and MUST NOT transmit the route,
  its directions, origin, or destination to the app's servers or any third party (the only
  network actor is the user's own print/PDF target chosen in the OS dialog).

### Key Entities *(include if data involved)*

- **Planned Route Directions**: The currently displayed route's ordered turn-by-turn steps plus
  its summary (origin, destination, total travel time, total distance) — the exact content the
  print view renders. Camera/coverage notices are excluded from the print view. No new persisted
  data is introduced.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From displayed directions, a user can open the print dialog in a single action.
- **SC-002**: 100% of the on-screen turn-by-turn steps appear, in order, in the printed output.
- **SC-003**: The printed output contains zero instances of the elements excluded by FR-005
  (map, page chrome, interactive controls).
- **SC-004**: Printed step text renders at ≥14pt effective size, and in readability checks
  testers can read the next step at arm's length without leaning in, across the supported
  languages.
- **SC-005**: A route producing more than one printed page paginates with no step clipped or
  split across a page break in 100% of test cases.
- **SC-006**: Producing the printout results in zero application network requests carrying route
  or location data.
- **SC-007**: Activating the print control opens the print dialog with no perceptible delay
  (under 100 ms from activation), reflecting that print-view assembly is a synchronous,
  client-side operation with no network round-trip.

## Assumptions

- The print experience is delivered through the user's existing device/browser print capability
  (print dialog and print-to-PDF); no separate document-generation service is introduced.
- "Print icon by the top of driving directions" means a control placed at the top of the
  existing directions section, not a global page-level print button.
- The printout is text-first: the interactive map is intentionally omitted because it is not
  glanceable while driving and prints poorly; a small static overview map is out of scope.
- The route-on-paper privacy notice mirrors the tone and intent of the existing GPX-export
  warning; printing is treated as a user-initiated, fully local action just like that export.
- Default page size follows the user's print settings (e.g. Letter/A4); the layout adapts to
  either rather than assuming a single size.
- Existing route, maneuver, and summary data already available on screen is sufficient; no new
  backend fields or endpoints are required.

## Dependencies

- Relies on the existing route-planning flow and the directions/summary data it already
  produces on screen.
- Builds on the established localization for control labels and directional text.

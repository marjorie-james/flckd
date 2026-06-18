# Feature Specification: Automatic Camera-Priority Routing

**Feature Branch**: `004-auto-route-priority`

**Created**: 2026-06-09

**Status**: Completed

**Input**: User description: "the app has no options for routing, and instead shows no cam path > fewest cam path in priority, meaning if the routing can't find a zero cam path, it will choose the path that has the fewest"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Zero-Camera Route Found (Priority: P1)

A user enters an origin and destination, submits the form, and the app automatically finds and returns a route that passes zero ALPR cameras. No preference selection is required — the app makes the optimal choice without prompting.

**Why this priority**: This is the primary value proposition of the app — protecting users from camera surveillance with no friction. Removing the choice UI reduces cognitive load and guarantees the best available outcome.

**Independent Test**: Can be fully tested by submitting an origin/destination pair where a camera-free path exists, and confirming the result shows zero cameras avoided with no preference UI visible.

**Acceptance Scenarios**:

1. **Given** a user has entered a valid origin and destination, **When** they submit the route form, **Then** the app returns the route that avoids all known cameras and displays it without any preference selection step.
2. **Given** a route result is displayed, **When** the result shows zero remaining cameras, **Then** the result clearly indicates the route is fully camera-free.
3. **Given** the route form, **When** it is displayed before or after planning, **Then** no avoidance-preference radio group or segmented control is visible.

---

### User Story 2 - Fewest-Camera Fallback (Priority: P1)

A user enters an origin and destination where every possible path passes through at least one ALPR camera. The app automatically falls back to the route with the fewest camera exposures and communicates this clearly.

**Why this priority**: Equal priority to US1 — the fallback behavior defines the app's guarantee. Users must always receive the best available route even when a fully clean one is impossible.

**Independent Test**: Can be fully tested by submitting a route where all paths have at least one camera, and confirming the result shows the minimum-camera route with a clear message that a zero-camera route was not possible.

**Acceptance Scenarios**:

1. **Given** no camera-free path exists between the origin and destination, **When** the route is planned, **Then** the app returns the route with the fewest camera exposures.
2. **Given** the fallback route is displayed, **When** the result is shown, **Then** the remaining camera count is visible and the result does not falsely claim the route is camera-free.
3. **Given** the fallback route is displayed, **When** the user views the result, **Then** the UI indicates this is the minimum-camera option, not a zero-camera option.

---

### User Story 3 - No Preference UI Present (Priority: P2)

The application no longer presents any avoidance-preference selection to the user at any point in the flow — neither before planning nor after receiving results.

**Why this priority**: The UX simplification is a consequence of the routing strategy change; the core routing behavior (US1/US2) can ship and deliver value even before the UI cleanup is fully verified.

**Independent Test**: Can be tested by loading the app and confirming no preference controls appear at any point in the route planning flow, including the initial form and post-result display.

**Acceptance Scenarios**:

1. **Given** the app is loaded, **When** the route input form is displayed, **Then** no avoidance-preference field, radio group, or segmented control is present.
2. **Given** a route has been planned and results are shown, **When** the result section is displayed, **Then** no re-plan preference control is visible.

---

### Edge Cases

- What happens when origin and destination are identical or extremely close? The routing result may be trivial; the app should handle this gracefully without crashing.
- What if the routing service is unreachable? The app should surface a clear error, consistent with existing error handling.
- What if multiple routes tie for fewest cameras? The app picks the one the routing engine considers optimal by other criteria (e.g., shortest travel time); the tie-breaking is transparent to the user.
- What if zero cameras are on record in the database? Every route would be "camera-free" — the result should still display correctly as zero cameras avoided.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The routing system MUST attempt to find a route with zero camera exposures first, before considering any alternative.
- **FR-002**: If no zero-camera route exists, the routing system MUST return the route with the fewest camera exposures.
- **FR-003**: The result MUST clearly distinguish between a zero-camera route and a minimum-camera fallback route.
- **FR-004**: The application MUST NOT present an avoidance-preference selection to the user at any point in the flow.
- **FR-005**: The route result MUST display the count of cameras the route passes through (zero or more) so the user understands their exposure.
- **FR-006**: The application MUST handle the case where the routing service cannot find any route and surface a meaningful error.

### Key Entities

- **Route**: A planned path between two coordinates; has a camera-avoided count, a remaining-camera count, and a flag indicating whether it is fully camera-free.
- **Routing Strategy**: The internal decision logic — "zero-camera first, fewest-camera fallback" — applied automatically with no user-facing parameter.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of route results are produced using the zero-camera-first / fewest-camera-fallback strategy with no user input required beyond origin and destination.
- **SC-002**: Users complete route planning in fewer steps than before — the preference selection step is eliminated entirely.
- **SC-003**: When a zero-camera route exists, 100% of results return a fully camera-free route.
- **SC-004**: When no zero-camera route exists, 100% of results return the route with the minimum camera count available.
- **SC-005**: The result screen accurately communicates in every case whether the displayed route is zero-camera or minimum-camera.

## Assumptions

- The routing backend currently supports a strong "avoid all cameras" mode and can determine when that mode yields no viable route, triggering the fallback.
- The definition of "fewest cameras" is the route that crosses the smallest number of distinct camera-monitored road segments, as tracked in the existing `cameras` table.
- Users do not need the ability to override the automatic strategy (e.g., no "I want the fastest route even with more cameras" option in this feature).
- The `is_fully_clean` and `cameras_avoided_count` fields already present on route results are sufficient to communicate zero-camera vs. fallback outcomes; no new result fields are required.
- Removal of the preference UI does not affect any other feature or external interface (the preference parameter, if it existed in the API, is deprecated or removed as part of this work).

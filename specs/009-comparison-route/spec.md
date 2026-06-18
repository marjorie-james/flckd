# Feature Specification: Comparison Route (Fastest-Route Baseline)

**Feature Branch**: `009-comparison-route`

**Created**: 2026-06-11

**Status**: Completed

**Input**: User description: "the map shows the chosen, flock-avoiding route with time to travel, but it also shows the fastest path not avoiding flock cameras as a comparison to surface additional travel time required for the flock-less route"

## Summary

When the app plans a camera-avoiding route, it also computes the **fastest ordinary driving route** (the
one that does *not* avoid cameras) for the same origin and destination, and shows both on the map at the
same time. The avoiding route is the primary, recommended route; the fastest route is shown as a
secondary **comparison ("baseline") route**. Alongside each route the app shows its travel time, and it
clearly states the **extra time** the user is trading away to stay camera-free — so the user can see, at a
glance, exactly what avoidance is costing them and decide whether the trade is worth it.

> **Context**: The app already plans and displays a single camera-avoiding route with its travel time
> (feature `002`/`004`). Today the cost of avoidance can be *stated* as a number; this feature makes it
> *visible* by drawing the fastest non-avoiding route as a second line and presenting the time delta as a
> first-class comparison. The fastest route is informational only — the app still automatically recommends
> the avoiding route; it does not ask the user to choose between routing strategies.

## Clarifications

### Session 2026-06-11

- Q: When should the comparison (fastest non-avoiding) route be shown? → A: Whenever the avoiding route
  costs any extra travel time (added time > 0); when avoidance is free (delta = 0), only the single
  recommended route is shown.
- Q: Is the comparison route shown automatically or behind a user toggle? → A: Shown automatically with
  the result by default, with a control to hide/dismiss the comparison line.
- Q: Which metric(s) does the comparison surface alongside time? → A: Added travel time is the headline
  metric; added distance is also shown as a secondary detail.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the cost of avoidance on the map (Priority: P1)

A user plans a route from an origin to a destination whose fastest path passes one or more cameras. The
app shows the recommended camera-avoiding route prominently, and also draws the fastest non-avoiding route
as a distinct, secondary line. Each route shows its travel time, and the app surfaces how much *additional*
time the avoiding route takes compared to the fastest route.

**Why this priority**: This is the entire value of the feature — letting the user understand the trade-off
between privacy and travel time visually and quantitatively, in one view, without having to imagine the
alternative. It is independently testable and delivers the full value on its own.

**Independent Test**: Choose an origin/destination pair whose fastest route passes at least one known
camera and whose avoiding route is longer. Plan the route and confirm both routes are drawn distinctly,
each shows a travel time, and the additional time of the avoiding route over the fastest route is displayed.

**Acceptance Scenarios**:

1. **Given** an origin/destination whose fastest path passes one or more cameras and whose avoiding route
   takes longer, **When** the user plans a route, **Then** the map shows two visually distinct routes — the
   recommended avoiding route emphasized as primary and the fastest non-avoiding route shown as a secondary
   comparison line.
2. **Given** both routes are shown, **When** the user views the result, **Then** each route's travel time is
   displayed, and the app shows the additional time the avoiding route requires versus the fastest route
   (e.g. "+7 min to stay camera-free").
3. **Given** both routes are shown, **When** the user inspects which route is recommended, **Then** it is
   unambiguous that the avoiding route is the recommended one and the fastest route is shown only for
   comparison (it is not selectable as the route to follow).
4. **Given** the comparison route is shown automatically, **When** the user dismisses/hides it, **Then**
   the comparison line is removed while the recommended route and its travel time remain visible.

---

### User Story 2 - No needless comparison when avoidance is free (Priority: P2)

A user plans a route where the fastest path already passes no cameras (or the avoiding route is effectively
the same path). The app does not clutter the map with a redundant second line and does not claim any time
penalty, because there is no trade-off to surface.

**Why this priority**: Keeps the comparison meaningful and the map uncluttered. It refines US1's behavior
for the "no cost" case but the core feature (US1) delivers value without it; hence lower priority.

**Independent Test**: Choose an origin/destination pair whose fastest route passes no cameras. Plan the
route and confirm only one route is emphasized, no separate comparison line is drawn, and the result does
not show a positive added-time figure.

**Acceptance Scenarios**:

1. **Given** the fastest route already avoids all cameras, **When** the user plans a route, **Then** the app
   shows a single route and does not draw a separate comparison line.
2. **Given** the fastest route and the avoiding route are the same path, **When** the result is shown,
   **Then** the app does not display a positive "additional time" figure (the cost of avoidance is zero).

---

### User Story 3 - Understand what the fastest route would have exposed (Priority: P3)

A user looking at the comparison wants to understand *why* the recommended route is worth the extra time.
The app indicates that the fastest route passes cameras (e.g. how many), reinforcing the reason the
recommended route detours.

**Why this priority**: Adds explanatory value to the comparison but is not required to convey the core
time-cost trade-off; the feature is useful without it.

**Independent Test**: Plan a route where the fastest path passes a known number of cameras and confirm the
comparison communicates that the fastest route is not camera-free (e.g. shows the count of cameras it would
pass).

**Acceptance Scenarios**:

1. **Given** the fastest route passes one or more cameras, **When** the comparison is shown, **Then** the
   app indicates the fastest route is not camera-free (e.g. the number of cameras it would pass).

---

### Edge Cases

- **No route at all**: If no drivable route exists between origin and destination, the comparison is not
  shown and the existing no-route messaging applies — this feature adds nothing to that case.
- **Avoiding route fails but fastest exists**: If a camera-avoiding route cannot be produced but an ordinary
  fastest route can, the comparison delta cannot be computed; the app falls back to existing
  fewest-camera/no-route behavior (feature `004`) and does not invent a comparison.
- **Fastest route is slower or equal** (e.g. ties): The added-time figure is never shown as a negative; if
  the avoiding route is not slower, it is treated as a zero-cost case (US2).
- **Overlapping routes**: Where the two routes share road segments, the map must still make the primary
  (recommended) route distinguishable from the comparison line along the shared stretch.
- **Map readability on small screens**: Two routes plus camera markers must remain legible on a mobile
  viewport; the comparison line must not obscure the recommended route.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When planning a route, the system MUST also determine the fastest ordinary driving route
  (one that does not avoid cameras) for the same origin and destination.
- **FR-002**: The system MUST display the recommended camera-avoiding route as the visually primary route
  and the fastest non-avoiding route as a visually distinct secondary ("comparison") route whenever the
  avoiding route costs additional travel time (added time > 0).
- **FR-002a**: The comparison route MUST be shown automatically with the route result by default, and the
  user MUST be able to hide/dismiss the comparison line; the recommended route and its travel time remain
  visible when the comparison is dismissed.
- **FR-003**: The system MUST display the recommended route's estimated travel time. The fastest route's
  travel time is conveyed via the added-time delta (FR-004); its absolute travel time MAY also be shown.
- **FR-004**: The system MUST display the additional travel time the recommended avoiding route requires
  compared to the fastest non-avoiding route, expressed as a positive time difference. This added time is
  the headline comparison metric.
- **FR-004a**: The system MUST also display the additional distance of the recommended avoiding route
  versus the fastest route as a secondary detail alongside the headline added-time figure.
- **FR-005**: The system MUST make clear which route is the recommended one to follow and that the
  comparison route is informational only and not selectable as the route to navigate.
- **FR-006**: When the avoiding route costs no additional travel time (added time = 0 — e.g. the fastest
  route already avoids all cameras or is the same path), the system MUST NOT draw a separate comparison
  line and MUST NOT present a positive additional-time figure.
- **FR-007**: The system MUST indicate that the fastest non-avoiding route is not camera-free when it
  passes one or more cameras (e.g. a count of cameras it would pass).
- **FR-008**: The system MUST keep the recommended route distinguishable from the comparison route even
  where the two routes overlap along shared segments.
- **FR-009**: The comparison MUST update consistently whenever a new route is planned (a stale comparison
  from a previous origin/destination MUST NOT remain on the map).
- **FR-010**: Determining the fastest comparison route MUST honor the project's anonymity guarantees: the
  origin, destination, and routes MUST NOT be sent to any third party; only the project's own routing
  service may receive them, and no route coordinates or client identifiers may be retained in logs.

### Key Entities

- **Recommended route (avoiding route)**: The camera-avoiding route the app recommends and the user follows.
  Attributes relevant here: travel time, geometry (for drawing), remaining camera exposure (from existing
  features).
- **Comparison route (baseline / fastest route)**: The fastest ordinary driving route for the same
  origin/destination that does not avoid cameras. Attributes: travel time, geometry, number of cameras it
  would pass. Informational only; never the followed route.
- **Avoidance cost**: The derived comparison between the two routes — the additional travel time (headline)
  and additional distance (secondary) of the recommended route over the fastest route, and, where surfaced,
  the cameras the fastest route would pass.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a route where avoidance adds travel time, a user can identify both the recommended route
  and the fastest alternative on the map, and the extra time of avoidance, within 5 seconds of the result
  appearing, without any further interaction.
- **SC-002**: In 100% of results where the fastest route already avoids all cameras, no separate comparison
  line is drawn and no positive added-time figure is shown.
- **SC-003**: In 100% of results where avoidance adds time, the displayed additional time equals the
  recommended route's travel time minus the fastest route's travel time (never negative).
- **SC-004**: Users can correctly identify which of the two displayed routes is the recommended one to
  follow on first viewing (≥90% correct identification — validated via manual usability testing, not an
  automated test).
- **SC-005**: 0% of planned routes result in the origin, destination, or route geometry being sent to or
  retained by any third party as a result of computing the comparison route.
- **SC-006**: Adding the comparison route does not increase the time from route request to result beyond
  the feature's stated latency budget (see Assumptions), as measured with representative origin/destination
  pairs.

## Assumptions

- The comparison ("fastest non-avoiding") route is **informational only**: the app continues to
  automatically recommend the avoiding route and does not reintroduce a routing-preference choice for the
  user (consistent with feature `004`, which removed preference UI).
- The fastest route is the standard fastest-by-time driving route for the same origin/destination, computed
  by the project's own self-hosted routing service — the same service used for avoidance — so no new third
  party is introduced.
- A separate comparison line is shown **only when avoidance costs additional travel time** (added time >
  0); zero-cost cases (delta = 0) show a single route (US2). See Clarifications.
- "Time to travel" means estimated driving duration under the routing service's default assumptions; the
  comparison uses the same assumptions for both routes so the delta is apples-to-apples.
- The added-time comparison is based on travel **time** as the headline metric; additional **distance** is
  also shown as a secondary detail. See Clarifications.
- Performance budget for the added comparison computation is inherited from the existing route-planning
  budget defined in feature `002`'s plan; computing the second route MUST stay within that budget (the two
  route computations MAY be performed concurrently). The exact p95 target is confirmed during planning.
- This feature is frontend + routing-service-query only; it introduces no accounts, no persistent
  identifiers, and no new external dependencies.

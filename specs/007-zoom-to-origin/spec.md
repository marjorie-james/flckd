# Feature Specification: Zoom to Starting Address

**Feature Branch**: `007-zoom-to-origin`

**Created**: 2026-06-10

**Status**: Completed

**Input**: User description: "when the user enters a starting address, zoom responsibly to that location"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See my starting point on the map (Priority: P1)

A user types a starting address into the route panel and selects it from the suggestions. The map
moves and zooms so the selected starting point is centered and shown at street level, with a marker
placed on the exact point, letting the user immediately see *where* their route will begin and confirm
it is the right place — without having to pan or zoom the map by hand.

**Why this priority**: This is the core of the feature and the minimum viable slice. Today a user can
select a starting address but the map does not respond, so they get no visual confirmation that the
geocoder picked the right place. Centering on the chosen location turns a blind text selection into a
confirmable, trustworthy action. Delivered alone, it is already useful.

**Independent Test**: Enter and select a known starting address; verify the map ends up centered on
that address at a street-level zoom with a marker on the exact point, with no manual map interaction
required.

**Acceptance Scenarios**:

1. **Given** the map is showing a default/region-wide view, **When** the user selects a starting
   address from the suggestions, **Then** the map recenters on that address at street level and a
   marker appears at the address's exact location.
2. **Given** the user has selected a starting address and the map has centered on it with a marker,
   **When** the user selects a *different* starting address, **Then** the map recenters on the new
   location and the single starting marker moves to the new point (no leftover marker remains).
3. **Given** the user manually panned/zoomed the map away, **When** the user selects a starting
   address, **Then** the map returns to and centers on the selected address with its marker.
4. **Given** a starting address is selected and marked, **When** the user clears the starting-address
   field (unsetting the starting point), **Then** the starting marker is removed from the map.

---

### User Story 2 - A comfortable, non-disorienting move (Priority: P2)

When the map repositions to the starting address, the movement is smooth and brief rather than an
abrupt jump, so the user can keep their bearings and understand where the new view is relative to the
old one. Users who have asked their device to reduce motion get an instant, animation-free
repositioning instead.

**Why this priority**: The map *moving* to the address (P1) delivers the value; *how* it moves
determines whether the experience feels polished and accessible. Important, but the feature is still
usable without the animation polish.

**Independent Test**: Select a starting address and observe a smooth, short transition; then enable
the system "reduce motion" preference, repeat, and observe an instant reposition with no animation.

**Acceptance Scenarios**:

1. **Given** default motion settings, **When** the map recenters on a starting address, **Then** the
   movement is animated and completes within a short, bounded time.
2. **Given** the user's system requests reduced motion, **When** the map recenters on a starting
   address, **Then** the map jumps to the location instantly with no animation.

---

### User Story 3 - Responsible, predictable framing (Priority: P3)

The map zooms to a consistent street/address-level framing — close enough to confirm the block and
surrounding streets, but not zoomed all the way in onto a single rooftop — and it only moves once the
user has *confirmed* an address, never while they are still typing. All map data for the new view
comes from the app's own map service, so moving to the address never reveals it to a third party.

**Why this priority**: This is the "responsibly" qualifier — it protects the user from a jarring,
over-tight, or privacy-leaking experience. It refines P1/P2 rather than standing alone.

**Independent Test**: Type a partial address and confirm the map does not move on intermediate
keystrokes; select the address and confirm the map lands at a consistent street-level zoom (not
maximum zoom); inspect outbound network traffic and confirm no third party receives the coordinate.

**Acceptance Scenarios**:

1. **Given** the user is typing characters into the starting-address field, **When** suggestions
   appear but none is selected, **Then** the map does not move.
2. **Given** two starting addresses in areas of different density (e.g., a dense city block and a
   rural road), **When** each is selected, **Then** both result in the same consistent street-level
   zoom rather than wildly different zoom levels.
3. **Given** a starting address is selected, **When** the map recenters, **Then** no request carrying
   the address coordinate is sent to any third-party service.

---

### Edge Cases

- **Unresolvable coordinate**: If the confirmed starting address has no usable coordinate, the map
  view is left unchanged (no jump to a blank or "null island" location) and no marker is placed.
- **Rapid re-selection**: If the user confirms a new starting address before the previous movement
  finishes, the map ends on the most recently confirmed location (no queued/overlapping animations)
  and a single marker ends up on the most recently confirmed point.
- **Clearing the starting point**: If the user clears or empties the starting-address field, the
  starting marker is removed and the map is not moved.
- **Re-selecting the same address**: Selecting the address the map is already centered on produces no
  jarring re-animation.
- **Map not ready**: If a starting address is confirmed before the map is ready to move, the move is
  applied once the map becomes ready.
- **Address near/outside the served region**: The map still centers on the coordinate even if map
  detail is sparse at the region edge; it does not error.
- **Starting location set without typing** (e.g., "use my location"): Setting the starting point this
  way frames the map consistently with selecting a typed address.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When the user confirms a starting address (selecting it from the suggestions), the
  system MUST recenter the map on that address's location.
- **FR-002**: The system MUST zoom to a consistent street/address-level framing that shows the
  immediate block and surrounding streets, applied uniformly regardless of how dense or rural the
  address is, and MUST NOT zoom in to the maximum/rooftop level.
- **FR-003**: The repositioning MUST be a smooth, animated movement bounded to a short duration so it
  does not disorient the user.
- **FR-004**: When the user's environment indicates a reduced-motion preference, the system MUST
  reposition the map instantly, without animation.
- **FR-005**: The system MUST recenter the map ONLY when a starting address is confirmed/selected, and
  MUST NOT move the map on intermediate keystrokes or unselected suggestions while the user is typing.
- **FR-006**: If a newer starting address is confirmed before a prior movement completes, the system
  MUST ensure the map ends on the most recently confirmed location.
- **FR-007**: If the confirmed starting address has no usable coordinate, the system MUST leave the
  map view unchanged.
- **FR-008**: After the repositioning completes, the user MUST retain full manual control of the map
  (pan and zoom).
- **FR-009**: Recentering MUST NOT transmit the starting-address coordinate to any third party; all
  map content for the new view MUST come only from the app's own (self-hosted) map service.
- **FR-010**: The framing behavior MUST be consistent however the starting location is established as
  a confirmed point (selecting a typed address, or "use my location").
- **FR-011**: When the map recenters on a confirmed starting address, the system MUST display a
  visible marker at that address's exact location.
- **FR-012**: The system MUST show at most one starting marker at a time: confirming a new starting
  address MUST move the marker to the new location rather than leaving the previous one behind.
- **FR-013**: When the starting location is unset (e.g., the user clears the starting-address field),
  the system MUST remove the starting marker; when there is no usable coordinate, no marker is shown.

### Key Entities

- **Starting location (origin)**: The user's confirmed start point — a geographic coordinate
  (latitude/longitude) derived from the entered address, optionally with its human-readable label.
- **Map viewport**: The visible area of the map, defined by a center coordinate and a zoom level; this
  is what the feature moves and frames.
- **Starting marker**: A single visible indicator placed on the map at the starting location's
  coordinate; present only while a valid starting location is set, and always reflecting the current
  one.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a user selects a starting address, the map is centered on that location within 1.5
  seconds (including any animation).
- **SC-002**: For at least 95% of resolvable addresses, the resulting view shows the address's street
  and immediate surroundings (neither zoomed out to a city-wide view nor in to a single rooftop).
- **SC-003**: In at least 90% of cases, users can visually confirm the selected starting point is
  correct without any further manual pan or zoom.
- **SC-004**: The map performs zero unintended recenters while the user is typing (it moves only after
  a confirmed selection).
- **SC-005**: For users who have requested reduced motion, the map repositions with no animation 100%
  of the time.
- **SC-006**: Zero requests carrying the starting-address coordinate are sent to any third-party
  service during recentering (verifiable by inspecting outbound network traffic).
- **SC-007**: After selecting a starting address, exactly one marker is visible at the selected point;
  selecting a different address or clearing the field never leaves a stale or duplicate marker behind.

## Assumptions

- **Interpretation of "responsibly"**: taken to mean (a) a consistent street/address-level zoom rather
  than maximum rooftop zoom (predictable framing that confirms the location without over-exposing the
  exact dwelling on screen); (b) a smooth, short, reduced-motion-aware transition; (c) movement only on
  a *confirmed* address, never while typing; and (d) all map data staying on the app's own
  infrastructure (no third-party leak — consistent with the project's strict-anonymity rule).
- **Scope is the starting address (origin) only.** Framing both origin and destination together
  (fitting the map to the whole route) once both are set is a separate behavior and is out of scope
  here.
- The starting address is established primarily by selecting a suggestion from the existing
  origin-address autocomplete; "use my location" produces the same confirmed starting point and is
  expected to frame the map consistently.
- A single fixed target zoom appropriate to address granularity is acceptable; the exact zoom value is
  an implementation detail to be tuned during planning.
- The feature operates on the app's existing self-hosted map; no new map provider or third-party
  service is introduced.
- "Reduced motion" is determined from the standard operating-system/browser accessibility preference.
- A visible marker is placed at the starting location as part of this feature (alongside the
  zoom/recenter behavior). Its exact visual style (icon, color) is an implementation/design detail to
  be settled during planning; the spec only requires a single, current, clearly visible marker.
- The marker represents the **starting** location only; a separate destination marker and any
  route-line rendering are out of scope for this feature.

## Dependencies

- The existing origin-address geocode autocomplete (the source of confirmed starting addresses).
- The existing self-hosted map and tile service (the surface this feature moves and the only source of
  map content for the new view).

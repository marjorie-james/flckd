---
description: "Specification for an anonymous, mobile-first, multi-lingual route planner that avoids Flock (ALPR) cameras"
---

# Feature Specification: Camera-Avoiding Route Planner

**Feature Branch**: `002-flock-route-avoidance`

**Created**: 2026-05-31

**Status**: Draft

**Input**: User description: "build a multi-lingual web application highly tailored to mobile with a focus on anonymity that allows a user to plan a driving route that explicitly avoids Flock cameras"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plan a driving route that avoids cameras (Priority: P1)

A driver wants to travel from one place to another without passing automated license-plate-reader
(ALPR) cameras (commonly "Flock" cameras). They enter a starting point and a destination, request a
route, and receive a drivable route that avoids known camera locations, shown on a map with
directions they can follow.

**Why this priority**: This is the core value of the product. Without camera-aware routing the app is
just another map. A user who can do only this still has a complete, valuable tool — it is the MVP.

**Independent Test**: Choose an origin/destination pair whose fastest route passes at least one known
camera. Request a route and confirm the returned route is drivable and passes zero known cameras (or,
where impossible, the fewest possible), and that directions are displayed.

**Acceptance Scenarios**:

1. **Given** an origin and destination whose fastest path passes one or more known cameras, **When**
   the user requests a route, **Then** the app returns a drivable route that passes no known camera
   locations.
2. **Given** an origin and destination with no known cameras near any reasonable path, **When** the
   user requests a route, **Then** the app returns the normal best driving route.
3. **Given** a camera-avoiding route is longer than the fastest route, **When** the route is shown,
   **Then** the app displays the additional distance and estimated time compared to the fastest route.

### User Story 2 - Use the app anonymously without an account (Priority: P2)

A privacy-conscious user wants to plan a route without revealing who they are. They use the full app
without signing up, logging in, or providing any personal information, and the service does not retain
an identifiable record of where they are going.

**Why this priority**: Anonymity is a defining promise of the product and the reason many users will
choose it over mainstream maps. It is independently valuable and testable, but the app can technically
function (P1) before every anonymity guarantee is hardened, so it ranks just below the core route.

**Independent Test**: Complete the entire route-planning flow without creating an account or entering
personal data. Confirm no login is required and that the server keeps no record of the origin or
destination that can be linked back to the user after the request completes.

**Acceptance Scenarios**:

1. **Given** a first-time visitor, **When** they open the app and plan a route, **Then** they can
   complete the whole flow without registering, logging in, or providing personal information.
2. **Given** a completed route request, **When** the session ends, **Then** no personally
   identifiable record of the origin or destination remains linkable to the user.
3. **Given** the user is using the app, **When** they review what is stored on their device or sent to
   the service, **Then** only non-identifying data strictly necessary to produce the route is used.

### User Story 3 - Use the app in my own language (Priority: P3)

A user who does not read the default language wants to use the app comfortably. The interface appears
in their language automatically, and they can switch languages at any time, with all text — including
directions and errors — translated.

**Why this priority**: Broad, multi-lingual reach widens the audience and is a stated goal, but the
core routing and anonymity value can be delivered in a single language first.

**Independent Test**: Set the device/browser to each supported language and confirm the app loads in
that language; switch languages within the app and confirm all visible text, route instructions, and
error messages are translated and the current route input is preserved.

**Acceptance Scenarios**:

1. **Given** a user whose device language is a supported language, **When** they open the app, **Then**
   the interface is presented in that language by default.
2. **Given** a user with an in-progress route input, **When** they switch to another supported
   language, **Then** the entire interface updates and their input is preserved.

### User Story 4 - Understand and control how cameras are avoided (Priority: P3)

A user wants to see how the route relates to known cameras and decide how aggressively to avoid them —
for example, strictly avoid all cameras, balance avoidance against travel time, or take the fastest
route regardless.

**Why this priority**: This adds transparency and trust and handles the "no fully clean route" case
gracefully, but the default behavior in P1 already produces an avoiding route, so explicit controls
are an enhancement.

**Independent Test**: For one route, switch the avoidance preference between options and confirm the
route and the displayed count of avoided/remaining cameras change accordingly.

**Acceptance Scenarios**:

1. **Given** a planned route, **When** the user views its details, **Then** the app shows how many
   known cameras were avoided and lists any unavoidable cameras remaining on the route.
2. **Given** a planned route, **When** the user changes the avoidance preference (e.g., "avoid
   cameras" vs. "fastest"), **Then** the route updates to reflect the chosen preference.
3. **Given** no fully camera-free route exists, **When** the user requests strict avoidance, **Then**
   the app clearly explains that complete avoidance is not possible and offers the minimum-exposure
   alternative.

### Edge Cases

- No route can fully avoid known cameras → return the minimum-exposure route and clearly warn the user.
- The origin or destination is itself immediately adjacent to a camera (unavoidable) → flag it and
  proceed with the best possible route.
- Camera-location data is stale or temporarily unavailable → still return a standard route and warn
  that avoidance coverage may be incomplete.
- Origin or destination falls outside the area covered by camera data → route normally and indicate
  that avoidance is unavailable for that area.
- Poor or no network connectivity on mobile → fail gracefully with a clear, recoverable message.
- Ambiguous or unrecognized address input → prompt the user to disambiguate or select a match.
- The user declines to share device location → allow manual entry of the origin.
- Very long or cross-region routes → handle without breaking the avoidance logic or the map display.

## Clarifications

### Session 2026-05-31

- Q: How strict must anonymity be regarding third-party exposure of the user's origin/destination? → A: Strict — no third party ever receives the user's origin, destination, or route; all geocoding, routing, and map tiles are served by the product's own infrastructure. The one exception is a user-initiated handoff to open the finished route in Apple Maps or Google Maps, which must be an explicit choice with a clear warning that it shares the route with that external provider.
- Q: When does a route count as "passing" a camera that must be avoided? → A: Monitored-segment — avoid the specific road segment(s) the camera covers (camera snapped to its nearest road/intersection, with a small tolerance for imprecise data), rather than a fixed radius around the camera point. This prevents over-blocking parallel and cross streets the camera cannot read.
- Q: Where does the Flock/ALPR camera-location data come from? → A: Hybrid — seed from open/community datasets (e.g., DeFlock / OpenStreetMap ALPR tags), then layer internal verification and corrections on top. Each camera record carries a source/provenance and verification status so accuracy can improve over time.
- Q: What geographic area does the product target at launch? → A: United States first (where camera deployments and community data are densest). The multi-lingual interface still applies, serving US language communities (e.g., Spanish) and easing later expansion. Success criteria for camera avoidance are evaluated against US coverage at launch.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST let a user specify an origin and a destination (via place/address search,
  map selection, and/or the device's current location when permitted).
- **FR-002**: System MUST generate a drivable route between the chosen origin and destination.
- **FR-003**: System MUST avoid known Flock/ALPR cameras when generating a route by excluding the
  specific road segment(s) each camera monitors (the camera snapped to its nearest road/intersection,
  with a small tolerance for imprecise data), producing a route that traverses zero monitored segments
  whenever such a route exists. A route MUST NOT be penalized merely for passing near a camera on a
  road the camera does not monitor.
- **FR-004**: When no fully camera-free route exists, System MUST return the route that passes the
  fewest known cameras and clearly indicate that complete avoidance was not possible.
- **FR-005**: System MUST display the resulting route on an interactive map together with
  human-readable, step-by-step directions.
- **FR-006**: System MUST show the trade-off between the camera-avoiding route and the fastest route,
  including the added distance and estimated added travel time.
- **FR-007**: System MUST let the user choose an avoidance preference (at minimum: avoid cameras vs.
  fastest route) and recalculate the route accordingly.
- **FR-008**: System MUST indicate the number of known cameras avoided and any unavoidable cameras
  remaining on the chosen route.
- **FR-009**: System MUST be fully usable on mobile devices, treating small touch screens as the
  primary target (no horizontal scrolling or pinch-zoom required to complete the core flow).
- **FR-010**: System MUST allow complete use of all features without account creation, login, or
  submission of personally identifiable information.
- **FR-011**: System MUST NOT persist origins, destinations, or routes in a form linkable to an
  individual user beyond the lifetime required to fulfill the request.
- **FR-012**: System MUST NOT track users across sessions with persistent identifiers for advertising
  or profiling.
- **FR-012a**: System MUST perform all geocoding, route generation, and map-tile serving using its own
  infrastructure, such that no external third party ever receives the user's origin, destination, or
  computed route as part of normal use.
- **FR-012b**: System MUST allow the user to open the finished route in an external maps application
  (Apple Maps or Google Maps) only as an explicit, user-initiated action, and MUST warn the user
  beforehand that doing so shares the route's locations with that external provider.
- **FR-013**: System MUST present its interface in multiple languages and let the user select their
  preferred language at any time.
- **FR-014**: System MUST auto-detect a preferred language from the device/browser when available and
  fall back to a default language otherwise.
- **FR-015**: System MUST localize all user-facing text, including route directions and error
  messages, for every supported language.
- **FR-016**: System MUST handle ambiguous or unrecognized location input by prompting the user to
  clarify or choose among matches.
- **FR-017**: System MUST support manual origin entry when the user declines to share device location.
- **FR-018**: System MUST communicate when camera-location data is incomplete or unavailable for the
  requested area while still providing a standard route.
- **FR-019**: System MUST let the user adjust an existing route (change endpoints or preference) and
  recalculate without restarting the flow.
- **FR-020**: System MUST keep camera-location data reasonably current through periodic updates and
  convey the data's recency or coverage limitations to the user.
- **FR-021**: System MUST build its camera-location data by importing from open/community datasets and
  applying an internal verification/correction layer on top, recording each camera's source/provenance
  and verification status.

### Key Entities

- **Route Request**: An ephemeral request consisting of an origin, a destination, and an avoidance
  preference. Not retained in identifiable form after fulfillment.
- **Route**: A generated path with geometry, total distance, estimated travel time, step-by-step
  directions, count of cameras avoided, and any unavoidable cameras remaining.
- **Camera Location**: A known ALPR/Flock camera reference point with position, the road segment(s) it
  monitors (derived by snapping to the nearest road/intersection), and supporting metadata (e.g.,
  type/brand, facing direction if known, last-verified date, confidence, source/provenance, and
  verification status). Sourced from a hybrid pipeline (open/community data + internal verification),
  not from end users.
- **Avoidance Preference**: The user's chosen balance between avoiding cameras and minimizing travel
  time (e.g., avoid / balanced / fastest).
- **Locale**: The user's selected or detected language used to render all interface text and directions.

## Success Criteria *(mandatory)*

### Success Criteria

- **SC-001**: When a camera-free route exists, the app returns a route that passes zero known cameras
  in at least 95% of cases.
- **SC-002**: A new user can go from opening the app to a displayed route in under 60 seconds and no
  more than four interactions.
- **SC-003**: A user can complete the entire route-planning flow on a phone-sized screen without
  horizontal scrolling or zooming.
- **SC-004**: Users see a planned route within 5 seconds for at least 95% of typical metro-area
  requests.
- **SC-005**: Users can access 100% of features with zero required personal-information fields and no
  account.
- **SC-006**: The interface is available in at least 5 languages at launch, with 100% of user-facing
  strings localized in each.
- **SC-007**: For every route where a camera-free alternative exists, the app presents the
  avoiding-route travel time alongside the fastest-route travel time so the user can see the trade-off.
- **SC-008**: After a request completes, the service retains zero records that link a specific origin
  or destination to an identifiable user.
- **SC-009**: During normal route planning, zero requests containing the user's origin, destination, or
  route are sent to any external third party; external maps handoff occurs only after an explicit
  user action accompanied by a warning.

## Assumptions

- Camera locations come from a hybrid pipeline: open/community-maintained ALPR datasets (e.g., DeFlock /
  OpenStreetMap ALPR tags) seed the data, with an internal verification/correction layer on top. Each
  record carries source/provenance and verification status. Avoidance accuracy depends on the combined
  dataset's completeness and recency. (Flock does not publicly publish its camera locations.)
- "Avoid a camera" means the route does not traverse the road segment(s) the camera monitors (the
  camera is snapped to its nearest road/intersection, with a small tolerance for imprecise data),
  rather than avoiding a fixed radius around the camera point. The snapping tolerance is a tunable
  detail to be set during planning.
- Initial scope is private-vehicle (car) driving routes only; walking, cycling, and transit are out of
  scope for this feature.
- Launch geographic scope is the United States, where camera deployments and community data are
  densest; camera-avoidance success criteria are evaluated against US coverage at launch. The
  multi-lingual interface is offered regardless and primarily serves US language communities (e.g.,
  Spanish) at launch, with room to expand to other regions later.
- Mapping, geocoding, routing, and map-tile capabilities are provided by the product's own
  infrastructure (self-hosted), so that no external third party receives user origins, destinations, or
  routes during normal use (see Clarifications). The external maps handoff (Apple Maps / Google Maps) is
  the only exception and is strictly user-initiated.
- The product is a mobile-first responsive web application that also remains usable on desktop browsers.
- The specific set of launch languages will be finalized during planning (target: at least 5, chosen
  to cover the largest US language communities, e.g., English and Spanish, plus others).

## Dependencies

- One or more open/community ALPR camera datasets (e.g., DeFlock / OpenStreetMap) as the seed source,
  plus an internal verification/correction process, with periodic updates.
- Self-hosted mapping, geocoding (address ↔ coordinates), drivable-route generation, and map-tile
  capability (so route planning requires no third-party calls that expose user locations).
- Deep-link / URL schemes for Apple Maps and Google Maps to support the optional user-initiated handoff.

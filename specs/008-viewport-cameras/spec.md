# Feature Specification: Render Camera Locations in the Current Viewport

**Feature Branch**: `008-viewport-cameras`

**Created**: 2026-06-11

**Status**: Completed

**Input**: User description: "The app renders camera locations in the current viewport"

## Summary

As the user looks at the map, the app shows the known surveillance cameras in the area currently on
screen, and keeps them in sync as the user pans and zooms. Where many cameras sit close together they
are grouped into a **count bubble (cluster)** that breaks apart as the user zooms or taps it, down to
individual camera markers. Tapping an individual camera shows its details. This lets a user *see where
the cameras are* — the same reference data the route planner avoids — directly on the map, independent
of whether they are planning a route.

> **Context:** the supporting pieces already exist — a camera-display component, a viewport-cameras
> data hook, and a `/cameras?bbox=` endpoint that returns reference points within a bounding box
> (capped at 500). What's missing is wiring them to the live map, driving them from the current
> viewport, and adding clustering + tap-to-inspect. This spec describes the user-facing behavior.

## Clarifications

### Session 2026-06-11

- Q: At what zoom should camera markers appear (a hide-below threshold)? → A: No hide threshold —
  **cluster** instead. Nearby cameras group into a count bubble; tapping a cluster zooms in and it
  expands into smaller clusters, down to individual markers.
- Q: Should tapping a camera show its details, or is it display-only? → A: Tapping an individual
  camera marker **shows its details** (type, confidence, verification status).
- Q: Which cameras should the viewport display? → A: **All routable** cameras (active + disputed above
  the confidence floor), with **disputed/low-confidence styled differently** from confirmed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See cameras where I'm looking (Priority: P1)

A user views the map over an area they care about. The known cameras in that visible area are shown —
as individual markers where they're spread out, and as **count bubbles (clusters)** where many sit
close together — so they can see at a glance how many cameras are around and where, without planning a
route.

**Why this priority**: This is the core of the feature and the minimum viable slice. The camera data
and endpoint already exist but nothing renders them, so today the user sees no cameras at all.
Clustering is part of the core display because at typical zooms cameras would otherwise overlap into
an unreadable mass.

**Independent Test**: Open the map over an area known to contain cameras; verify individual markers
appear where cameras are sparse and a count bubble appears where several cluster together, with no
route planned.

**Acceptance Scenarios**:

1. **Given** the map shows an area with a few scattered cameras, **When** the view settles, **Then** a
   distinct marker is shown at each camera location.
2. **Given** the map shows an area where many cameras sit close together, **When** the view settles,
   **Then** they are grouped into a cluster bubble showing the count rather than overlapping pins.
3. **Given** the map shows an area with no known cameras, **When** the view settles, **Then** no camera
   markers or clusters are shown and no error appears.
4. **Given** no route has been planned, **When** the user simply looks at the map, **Then** cameras for
   the visible area are still shown.

---

### User Story 2 - Cameras follow the map and clusters expand (Priority: P2)

When the user pans or zooms, the cameras update to the new visible area; as they zoom in, clusters
break into smaller clusters and individual markers. Tapping a cluster zooms the map toward it so it
expands.

**Why this priority**: Tracking the map and drilling into clusters is what makes the display
explorable. US1 already delivers value for the initial view, so this is the next increment.

**Independent Test**: Pan to a new area and confirm the cameras update; zoom into a cluster (or tap it)
and confirm it splits into smaller clusters / individual markers.

**Acceptance Scenarios**:

1. **Given** cameras are shown for the current area, **When** the user pans to a new area, **Then** the
   markers/clusters update to that area once the map settles.
2. **Given** a cluster bubble is shown, **When** the user taps it, **Then** the map zooms in toward
   that cluster and it expands into smaller clusters or individual markers.
3. **Given** the user zooms in on a dense area, **When** the view settles, **Then** clusters that can
   now be separated are shown as smaller clusters or individual markers.

---

### User Story 3 - Inspect a camera, and spot disputed ones (Priority: P3)

A user taps an individual camera marker and sees its details (type, confidence, verification status).
Disputed or low-confidence cameras are visually distinct from confirmed ones, so the user can tell how
trustworthy each marker is.

**Why this priority**: Inspection and trust cues add depth once the cameras are visible and
explorable. This refines US1/US2 rather than standing alone.

**Independent Test**: Tap an individual camera marker and confirm its details appear; confirm a
disputed/low-confidence camera renders visibly differently from a confirmed one.

**Acceptance Scenarios**:

1. **Given** an individual camera marker is shown, **When** the user taps it, **Then** its details
   (type, confidence, verification status) are displayed.
2. **Given** the area contains both confirmed and disputed cameras, **When** they are shown, **Then**
   the disputed/low-confidence ones are visually distinguishable from the confirmed ones.
3. **Given** the user taps empty map (no camera there), **When** nothing is under the tap, **Then** no
   details are shown.

---

### Edge Cases

- **Empty area**: a viewport with no cameras shows no markers/clusters (not an error).
- **Rapid panning**: only the final settled viewport is reflected; intermediate viewports do not each
  cause a visible refresh (debounced; latest wins).
- **Lone camera**: a single camera with no near neighbors shows as an individual marker, not a cluster.
- **Cluster that can't separate**: if tapping/zooming a cluster cannot separate its members (cameras at
  effectively the same point), the members are still made inspectable (e.g. listed) rather than left
  permanently hidden — exact treatment settled in design.
- **Over the cap**: the viewport endpoint returns at most a capped set; at very low zoom an area may
  hold more cameras than the cap, so cluster counts can under-represent the true total — see
  Assumptions.
- **Layer coexistence**: camera markers and clusters must not obscure or be confused with the route
  line or the starting-point marker.
- **Data refresh**: when the camera dataset updates, the viewport reflects the latest available data
  within a short caching window.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The map MUST display the known cameras whose location falls within the current visible
  area, as individual markers where they are spread out.
- **FR-002**: When the visible area changes (pan or zoom), the displayed cameras/clusters MUST update
  to reflect the new visible area.
- **FR-003**: Updates MUST be debounced so continuous panning/zooming does not trigger a separate
  fetch/refresh per intermediate view — only the settled (latest) viewport is reflected.
- **FR-004**: When multiple cameras are close enough to overlap at the current zoom, they MUST be
  aggregated into a **cluster marker that shows the count** instead of overlapping individual pins.
- **FR-005**: Tapping/selecting a **cluster** MUST zoom the map in toward that cluster so it breaks
  apart into smaller clusters and, at sufficient zoom, individual camera markers.
- **FR-006**: Tapping/selecting an **individual camera** marker MUST show that camera's details (type,
  confidence, verification status).
- **FR-007**: The displayed set MUST include all routable cameras in the area — both confirmed
  (active) and disputed cameras above the confidence floor — not only confirmed ones.
- **FR-008**: Disputed or low-confidence cameras MUST be visually distinguished from confirmed cameras.
- **FR-009**: Camera markers and clusters MUST be visually distinct from other map elements (the route
  line and the starting-point marker) and MUST NOT obscure the route.
- **FR-010**: When the visible area contains no known cameras, the system MUST show nothing and MUST
  NOT present an error.
- **FR-011**: The number of cameras requested for a viewport MUST be bounded by a display cap (the
  server's 500). When an area holds more cameras than the cap, the server's capped set is used (and
  clustered), and reaching the cap MUST be surfaced (e.g. logged/telemetry) rather than silently
  truncating.
- **FR-012**: Camera display MUST function independently of route planning — cameras are shown for the
  visible area whether or not a route exists.
- **FR-013**: Fetching cameras MUST send only the viewport bounds to the app's own backend (never a
  third party), and those bounds MUST NOT be retained in logs with any client identifier (anonymity).
- **FR-014**: Cameras (and their details) MUST represent reference data only — never any user-specific
  data.
- **FR-015**: The camera details popup MUST be dismissible — including via keyboard (Esc), not pointer
  only — and its open/closed state conveyed accessibly. (Camera markers/clusters are rendered on the
  map canvas, whose interaction-accessibility limits are accepted for this feature; the popup is the
  accessible surface.)

### Key Entities

- **Camera (reference point)**: a known camera with a geographic location and descriptive attributes
  (type, confidence, verification status — confirmed vs. disputed). Public reference data, not user
  data.
- **Cluster**: an on-map aggregation of nearby cameras at the current zoom, shown as a count bubble;
  expands into smaller clusters / individual markers as the user zooms in or taps it.
- **Visible area (viewport)**: the geographic bounds currently shown on the map; drives which cameras
  are requested and displayed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When the user views an area containing cameras, their markers/clusters appear within 1
  second of the view settling.
- **SC-002**: After the user pans/zooms to a new area, the displayed cameras/clusters update to that
  area within 1 second of the map settling.
- **SC-003**: During continuous panning, the system issues at most a small bounded number of camera
  refreshes (debounced) rather than one per frame.
- **SC-004**: At any zoom, overlapping cameras are aggregated so the map stays readable — no
  unreadable pile-up of overlapping pins.
- **SC-005**: Tapping a cluster results in the map zooming in and that cluster visibly separating into
  smaller clusters or individual markers.
- **SC-006**: Tapping an individual camera shows its details (type, confidence, verification status).
- **SC-007**: Disputed/low-confidence cameras are visually distinguishable from confirmed cameras in
  100% of cases, and camera markers are distinguishable from the route line and starting marker.
- **SC-008**: Showing cameras and clusters introduces no perceptible map jank — pan and zoom stay
  smooth.
- **SC-009**: Zero requests carrying the viewport bounds are sent to any third party; only the app's
  own backend receives them (verifiable by inspecting outbound traffic).
- **SC-010**: The camera details popup can be opened and then dismissed via keyboard (Esc) — not by
  pointer alone.

## Assumptions

- Reuses the existing camera dataset and `cameras` endpoint, which returns reference points within a
  bounding box and is already capped (500 per request). The display cap (FR-011) is that server cap.
- "Current viewport" means the visible map bounds; cameras are requested for those bounds and
  re-requested when the bounds change, debounced (FR-003).
- Clustering (not a hard hide-below-zoom threshold) is the density-management mechanism: cameras are
  represented at every zoom, grouped into count bubbles when dense and separating as the user zooms in.
- **Cap vs. cluster counts (open for planning):** cluster counts reflect the cameras returned for the
  viewport, subject to the 500 server cap. At very low zoom an area may hold more than the cap, so a
  region-wide count could under-represent the true total. Resolving accurate low-zoom counts (raising
  the cap, or server-side clustering/counts) is a planning decision; this spec assumes
  clustering over the capped set is acceptable for v1. When the cap is reached, the subset used is the
  server's capped result and the truncation is surfaced (FR-011), not hidden.
- Tapping an individual camera shows its existing attributes (type, confidence, verification status);
  no new camera data is introduced.
- Disputed/low-confidence cameras are distinguished by marker style; the exact visual treatment is a
  design detail settled during planning.
- Camera markers and clusters coexist with the route line and starting marker via layer ordering;
  this feature does not change those.
- Camera data freshness follows the existing aggregation cadence; the viewport shows the latest
  available data within a short client caching window.
- Sending the viewport bounds to the app's own backend is consistent with the anonymity rules: it is
  the same self-hosted backend that already serves map tiles for the viewport, it is coarse
  (area-level, not a user's address), and it carries no persistent identifier.

## Dependencies

- The existing `cameras` viewport endpoint and the camera-data aggregation that populates it
  ([`003-camera-data-aggregation`](../003-camera-data-aggregation/spec.md)).
- The existing self-hosted map and the (currently unwired) camera-display component and viewport-data
  hook.

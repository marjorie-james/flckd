# Phase 0 Research: Zoom to Starting Address

All decisions below resolve the design unknowns surfaced from the spec. No `NEEDS CLARIFICATION`
remain.

## D1 — Target zoom level for "responsible" address framing

- **Decision**: Recenter to a single fixed zoom of **16** for every confirmed starting address.
- **Rationale**: Zoom 16 shows the address's block and the surrounding street grid — enough to confirm
  the geocoder picked the right place — without zooming to the rooftop/parcel level (MapLibre max is
  ~18–22). A *fixed* level satisfies FR-002's "consistent regardless of density" and SC-002, and
  avoids the privacy concern of auto-framing a single dwelling. The map's default view is zoom 7
  (region-wide), so 16 is a clear, deliberate street-level step in.
- **Alternatives considered**:
  - *Variable zoom by result type/bbox* (e.g., tighter for a house, looser for a town) — rejected:
    inconsistent framing, contradicts FR-002, and over-tightens on precise addresses.
  - *Reuse the route `fitBounds`* — rejected: that frames two endpoints; here there is one point, so
    `fitBounds` has no meaningful bounds.

## D2 — Camera method and reduced-motion handling

- **Decision**: Use `map.flyTo({ center, zoom: 16, duration: 600 })` by default; when the user prefers
  reduced motion, use `map.jumpTo({ center, zoom: 16 })` (no animation). Gate via a small
  `prefersReducedMotion()` helper reading `window.matchMedia("(prefers-reduced-motion: reduce)")`.
- **Rationale**: `flyTo` gives the smooth, bounded transition FR-003/SC-001 require (600 ms matches the
  existing `fitBounds(..., {duration: 600})` convention — UX consistency, Principle III). `jumpTo`
  satisfies FR-004/SC-005. A standalone helper keeps the matchMedia read testable and reusable.
- **Rapid re-selection (FR-006)**: `flyTo` interrupts any in-flight animation; the recenter effect
  re-runs whenever the origin prop changes, so the camera always ends on the latest coordinate.
- **Alternatives considered**:
  - *`easeTo`* — fine, but `flyTo`'s zoom-out-then-in arc reads better for a large zoom jump (7→16).
  - *Always animate* — rejected: violates FR-004 (reduced motion).
  - *CSS media query only* — insufficient; the choice is between two different imperative map calls.

## D3 — Origin marker rendering

- **Decision**: Render the starting marker as a **GeoJSON source + a `circle` (or `symbol`) layer**,
  following `CameraLayer.tsx` and the route line. One source holds a single Point feature (or an empty
  `FeatureCollection` when no origin). Update via `source.setData(...)` rather than add/remove.
- **Rationale**: This is the established, idiomatic pattern in the codebase — no `new
  maplibregl.Marker()` exists anywhere. GeoJSON layers compose with the existing style, are trivial to
  test against the maplibre stub (assert `setData`/`addLayer`), and `setData` cleanly satisfies "at
  most one marker, moves on re-selection, removed on clear" (FR-011/012/013, SC-007) without DOM
  marker lifecycle management.
- **Visual style**: distinct from the camera dots (`#c0392b`) and route line (`#818cf8`) so the origin
  reads as its own thing; exact color/size is a design detail finalized in implementation.
- **Alternatives considered**:
  - *`maplibregl.Marker` (DOM pin)* — rejected: introduces a second, inconsistent overlay pattern and
    extra lifecycle code; harder to assert in the existing stub-based tests.

## D4 — Threading the confirmed origin to the map

- **Decision**: Lift the confirmed `origin: Coordinate | null` into `PlanRoutePage` and pass it to
  `MapView` as an `origin` prop. `RoutePanel` gains an `onOriginChange(coord | null)` callback it
  fires when the origin is set (suggestion pick **or** geolocation) and when it is cleared (the user
  edits/empties the field).
- **Rationale**: Mirrors the existing parent-mediated flow (`route`/`endpoints` already live in
  `PlanRoutePage` and flow down to `MapView`). It triggers on *selection*, not submit, which FR-001/005
  require, and is strictly simpler than adding a context/store (Principle I — simplest working
  approach). Firing on geolocation too satisfies FR-010.
- **Alternatives considered**:
  - *React context / zustand store* — rejected: unjustified complexity for one coordinate passed one
    level up (would require a Complexity Tracking entry).
  - *Imperative map ref shared into RoutePanel* — rejected: couples RoutePanel to the map and breaks
    the current clean separation.

## D5 — Map readiness & lifecycle

- **Decision**: Apply the recenter + marker inside `MapView` only once the map style is loaded, reusing
  the existing readiness gating used by the route/camera layers (effect guarded on the map instance and
  style-load). The origin effect depends on the `origin` prop and the map being ready.
- **Rationale**: Adding a source/layer before style load throws; the codebase already serializes layer
  work behind load. Satisfies the "map not ready" edge case (defer until ready).
- **Alternatives considered**: *Add layer eagerly in the init effect* — rejected: ordering/throw risk.

## D6 — Anonymity verification (FR-009)

- **Decision**: No new fetch/XHR is introduced by recentering; the only network effect is MapLibre
  requesting tiles for the new viewport from the **self-hosted** tile service already configured in
  `buildStyle(window.location.origin)`. Verified in e2e by asserting no third-party request carries the
  coordinate.
- **Rationale**: The origin coordinate stays in client state and is handed only to the local `map`
  instance. This is a property to *preserve and test*, not new behavior — consistent with the project's
  non-negotiable anonymity rule.

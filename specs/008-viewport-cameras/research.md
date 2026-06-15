# Phase 0 Research: Render Camera Locations in the Current Viewport

All design unknowns are resolved below. No `NEEDS CLARIFICATION` remain. This also settles the
spec's deferred cap-vs-cluster-count item (D7).

## D1 — Clustering approach

- **Decision**: Use **MapLibre GL native GeoJSON clustering** (`cluster: true`, `clusterRadius`,
  `clusterMaxZoom`) on the camera source, over the cameras fetched for the current viewport. Render
  three layers: a cluster circle, a cluster count label (symbol), and an unclustered point.
- **Rationale**: Built into MapLibre — no new dependency, no server work. It fits the existing GeoJSON
  source+layer pattern already used for cameras/route/origin. `setData` on viewport change re-clusters
  automatically. Realistic camera densities are low (5 in dev) and the 500 server cap is ample, so
  clustering over the fetched set is sufficient.
- **Alternatives considered**:
  - *Server-side clustering / a clustering library (supercluster standalone)* — rejected for v1: extra
    complexity/deps for no benefit at current densities. Kept as the upgrade path (see D7).

## D2 — Viewport bbox + debounce

- **Decision**: Compute the bbox from `map.getBounds()` on the map's `moveend` event, **debounced**
  (~300 ms), and feed it to the existing `useCameras(bbox)` hook (`"minLng,minLat,maxLng,maxLat"`).
- **Rationale**: `moveend` fires once the view settles; debouncing coalesces rapid consecutive moves so
  only the latest viewport is fetched (FR-003, SC-003). Reuses `useCameras` (React Query caches by
  bbox, 5-min staleTime).
- **Alternatives considered**: *`move` (per-frame)* — rejected: fires continuously, would thrash.

## D3 — Cluster expand on tap

- **Decision**: On clicking a cluster, call `getClusterExpansionZoom(clusterId)` and recenter to the
  cluster at that zoom — animated `easeTo` normally, instant `jumpTo` under `prefersReducedMotion()`
  (reuse the util from 007).
- **Rationale**: Standard MapLibre cluster-drilldown recipe (FR-005). Reusing the reduced-motion util
  keeps motion behavior consistent with zoom-to-origin (Principle III).
- **Alternatives considered**: *Spiderfy/spread members in place* — rejected for v1: more complex;
  zoom-to-expand is the expected, simpler interaction.

## D4 — Camera details on tap

- **Decision**: On clicking an unclustered camera point, open a `maplibregl.Popup` at its location
  showing type, confidence, and verification status.
- **Rationale**: Built-in, self-contained, dismissible; the content is reference data only (FR-006,
  FR-014). No new overlay machinery.
- **Alternatives considered**: *Custom React overlay panel* — rejected for v1: heavier; the popup
  covers the requirement.

## D5 — Disputed / low-confidence styling

- **Decision**: Style the unclustered-point layer with a **data-driven paint expression** on
  `verification_status` (and/or `confidence`) so disputed/low-confidence cameras render distinctly
  (e.g. different color/outline) from confirmed ones. Cluster bubbles remain uniform count badges in v1.
- **Rationale**: Data-driven expressions are idiomatic MapLibre and need no per-feature JS (FR-008).
  The `cameras` payload already carries `verification_status`/`confidence`.
- **Alternatives considered**: *Encode "contains disputed" into clusters via `clusterProperties`* —
  deferred (nice-to-have); v1 distinguishes at the individual-marker level.

## D6 — Mounting the layer on the map

- **Decision**: `MapView` tracks the created map instance in state (set once, after construction) and
  renders `<CameraLayer map={map} />`. `CameraLayer` is self-contained: given the map, it computes its
  own bbox, fetches, and manages its source/layers/handlers/popup.
- **Rationale**: `MapView` owns the map via a ref (not state), so a child can't currently mount against
  it; promoting the instance to state lets `CameraLayer` mount when it exists. Self-contained
  `CameraLayer` keeps the camera concern in one unit (Principle I).
- **Alternatives considered**: *Parent (PlanRoutePage) computes bbox and threads it* — rejected: it
  doesn't have the map instance, and it splits the camera concern across components.

## D7 — Cap vs. cluster counts (resolves the spec's deferred item)

- **Decision**: For v1, **accept the 500 server cap** and cluster client-side over the fetched set.
- **Rationale**: Camera densities are low (5 in dev; realistic regional counts are well within range),
  so a viewport rarely approaches 500 and counts are accurate in practice. If a future region exceeds
  the cap at low zoom, the upgrade path is server-side counting/clustering (or a higher cap) — out of
  scope for v1. This is logged, not silently assumed (Principle IV "no silent caps").
- **Alternatives considered**: *Raise the cap now* / *server-side counts now* — rejected: premature for
  the current data volume.

## D8 — Layer ordering

- **Decision**: Add the camera source/layers so they sit **below** the route line and origin marker —
  cameras must not obscure the planned route (FR-009). Use `beforeId` (insert before the route layer)
  or add camera layers before the route/origin layers are created.
- **Rationale**: The route is the primary planning artifact; cameras are context. Explicit ordering
  avoids cameras covering the route.
- **Alternatives considered**: *Default top-most insertion* — rejected: risks obscuring the route.

## D9 — Anonymity

- **Decision**: The only network effect is the existing `GET /cameras?bbox=` to our own backend; no new
  third-party call. The viewport bbox is coarse (area-level) and the existing anonymity-logging init
  already redacts coordinates/IPs, so the bbox is not retained with an identifier.
- **Rationale**: Preserve-and-test, not new behavior (FR-013). Verified by an e2e assertion that no
  third-party request carries the bbox.

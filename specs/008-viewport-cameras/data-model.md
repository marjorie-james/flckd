# Phase 1 Data Model: Render Camera Locations in the Current Viewport

No persistent data and no new backend entities — everything is ephemeral client-side state over
reference data fetched per viewport (anonymity: nothing stored, nothing user-specific).

## Entity: Camera (reference point)

Fetched from `GET /cameras?bbox=`; shape mirrors the existing `CameraPin`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | number | Camera identifier (reference data) |
| `location` | { lat, lng } | Position; becomes a GeoJSON Point |
| `camera_type` | string \| null | Shown in the details popup |
| `confidence` | number (0–1) | Drives styling; shown in popup |
| `verification_status` | string | One of `unverified` / `verified` / `disputed` / `removed`; `removed` is excluded server-side (`routable`). Drives disputed styling + popup |

- **Source of truth**: the backend `cameras` endpoint (capped at 500 per viewport). No client mutation.
- **Validation / inclusion**: the displayed set is exactly the endpoint's `routable` result (active —
  i.e. not removed — and above the confidence floor), which **includes disputed** cameras (FR-007).

## Entity: Cluster (client-side, transient)

A MapLibre-generated aggregation of nearby camera points at the current zoom — not stored, recomputed
on every `setData`/zoom.

| Field | Type | Notes |
|-------|------|-------|
| `point_count` | number | Cameras represented; shown on the bubble |
| `cluster_id` | number | MapLibre id; used to compute the expansion zoom |
| geometry | GeoJSON Point | The cluster's centroid |

- **Lifecycle**: created/destroyed by MapLibre clustering as the data or zoom changes. Tapping a
  cluster resolves its expansion zoom and recenters there (D3), splitting it into smaller clusters /
  individual points.
- **Invariant**: a lone camera (no near neighbors at the current zoom) renders as an individual point,
  not a cluster.

## Entity: Viewport (visible area)

| Field | Type | Notes |
|-------|------|-------|
| bbox | "minLng,minLat,maxLng,maxLat" | Derived from `map.getBounds()` on settle |

- **Transitions**: recomputed (debounced) on `moveend`; a changed bbox drives a new `useCameras` fetch
  and re-render. Sent only to our own backend (FR-013).

# Phase 1 UI Contract: Render Camera Locations in the Current Viewport

Frontend-only — **no new or changed backend API**. The existing endpoint is consumed as-is; the
"contract" additions are component props. Existing shapes are preserved.

## Consumed (existing, unchanged): `GET /api/v1/cameras`

```
GET /api/v1/cameras?bbox=<minLng,minLat,maxLng,maxLat>[&min_confidence=<0..1>]
→ 200 { "cameras": [ { id, location:{lat,lng}, camera_type, confidence, verification_status } ... ] }
→ 400 when bbox is missing or non-numeric
```

- Returns `routable` cameras intersecting the bbox (active — not removed — above the confidence
  floor; **includes disputed**), capped at **500**.
- Already wrapped by `useCameras(bbox)` (React Query; enabled when bbox set; 5-min staleTime).
- **No change** required for this feature.

## `CameraLayer` — self-contained component (rewrite)

```ts
interface CameraLayerProps {
  map: maplibregl.Map | null;   // the live map instance (from MapView)
}
```

**Behavior contract**:
- Given a ready map, computes the viewport bbox from `map.getBounds()` on `moveend`, **debounced**,
  and fetches via `useCameras` (FR-001/002/003).
- Renders a **clustered** GeoJSON source: cluster bubbles with counts, and individual points styled by
  `verification_status`/`confidence` so disputed/low-confidence differ from confirmed (FR-004/008).
- Clicking a cluster zooms to its expansion zoom (reduced-motion-aware) so it expands (FR-005).
- Clicking an individual camera opens a popup with type/confidence/status (FR-006).
- Camera layers sit below the route line and origin marker (FR-009).
- Shows nothing for an empty viewport (FR-010); issues no third-party request (FR-013).

## `MapView` — mount the layer

```ts
// MapView tracks the created map instance in state and renders:
//   {map && <CameraLayer map={map} />}
```

- Additive: promotes the existing map ref to a state value set once after construction, so `CameraLayer`
  mounts when the map exists. No change to `MapView`'s existing props (`route`, `center`, `origin`).

## Reused utility (no change)

```ts
// frontend/src/utils/reducedMotion.ts
prefersReducedMotion(): boolean   // gates cluster-expand easeTo vs jumpTo
```

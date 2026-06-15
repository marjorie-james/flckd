# Contract: Coverage endpoints (deltas)

Both endpoints exist today; this feature changes their **meaning** at country scale.
The OpenAPI contract (`backend/spec/contract/openapi_spec.rb`) is updated to match.

## GET /api/v1/coverage?lat&lng

Point coverage — now **per ingested data-region**, including freshness (FR-008, SC-005).

**Response 200** (point inside a data-region with camera data):
```json
{
  "covered": true,
  "data_freshness_at": "2026-06-15T08:00:00Z"
}
```

**Response 200** (point inside the country but with no gathered camera data — honest
"absent, not camera-free"):
```json
{
  "covered": false,
  "data_freshness_at": null
}
```

- `covered` reflects **camera-data presence** at the point (a `CoverageArea`/data-region
  containing it), not merely being inside the country.
- `data_freshness_at` is the containing data-region's own last-refresh time (per-region,
  not a global timestamp), or `null` when absent.
- 400 on missing/non-numeric/out-of-range `lat`/`lng` (existing validation, unchanged).

## GET /api/v1/coverage/bounds

Map-framing extent — now the **configured country's** extent (FR-007), not the union of
camera-data footprints.

**Response 200**:
```json
{ "bounds": [[-125.0, 24.5], [-66.9, 49.5]] }
```
- `[[west, south], [east, north]]`, lng/lat corners — same shape as today.
- Reflects the deployment's configured **scope** (`Geocoding::MapFraming`):
  - **Whole-country** deployment (default) → the country registry bbox (the entire
    country, e.g. continental US shown above), however sparse the camera footprint.
  - **Single-state dev** deployment (`GEOCODER_REGION_STATE` set) → that state's
    extent, from the configured `GEOCODER_VIEWBOX` (which is the state's bbox).
- `null` only if no country is configured.

## Backward-compatibility notes

- `coverage/bounds` response **shape** is unchanged (still `{ bounds: [[w,s],[e,n]] }`);
  only the value's source changes (country extent vs footprint union). Frontend `MapView`
  framing needs no change.
- `coverage` gains an explicit `data_freshness_at` and a presence-accurate `covered`.
  Document as an additive/clarified field; bump the contract example accordingly.

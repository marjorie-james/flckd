# API Contract Delta: Automatic Camera-Priority Routing

This document describes the changes to the `POST /api/v1/routes` contract introduced by this feature. The full baseline contract lives in `specs/002-flock-route-avoidance/contracts/openapi.yaml`.

---

## Request: `RouteRequest` — field removed

**Removed field**: `avoidance_preference`

The `AvoidancePreference` schema and the `avoidance_preference` property on `RouteRequest` are removed. Any client sending this field will have it silently ignored (Rails strong parameters).

**Before**:
```yaml
RouteRequest:
  type: object
  required: [origin, destination]
  properties:
    origin: { $ref: '#/components/schemas/Coordinate' }
    destination: { $ref: '#/components/schemas/Coordinate' }
    avoidance_preference: { $ref: '#/components/schemas/AvoidancePreference' }
    locale: { type: string }
```

**After**:
```yaml
RouteRequest:
  type: object
  required: [origin, destination]
  properties:
    origin: { $ref: '#/components/schemas/Coordinate' }
    destination: { $ref: '#/components/schemas/Coordinate' }
    locale: { type: string }
```

The `AvoidancePreference` schema component is removed entirely.

---

## Response: `RouteResponse` — unchanged

All response fields (`geometry`, `distance_m`, `duration_s`, `maneuvers`, `cameras_avoided_count`, `remaining_cameras`, `is_fully_clean`, `fastest_comparison`, `coverage_warning`) are unchanged.

`is_fully_clean` continues to communicate the routing outcome:
- `true` → zero-camera path found and returned
- `false` → fallback path returned (passes one or more camera-monitored segments)

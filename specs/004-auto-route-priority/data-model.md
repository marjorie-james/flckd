# Data Model: Automatic Camera-Priority Routing

No database schema changes. This feature removes user-facing routing preference logic; all persistence layers are unchanged.

---

## Changed: `Routing::Result` (no schema change)

The struct fields are unchanged. All existing fields (`geometry`, `distance_m`, `duration_s`, `maneuvers`, `cameras_avoided_count`, `remaining_cameras`, `is_fully_clean`, `fastest_comparison`, `coverage_warning`) remain on the response.

`is_fully_clean` semantics are unchanged:
- `true` → route passes zero camera-monitored segments (zero-camera path found)
- `false` → route passes one or more camera-monitored segments (fallback path used)

---

## Removed: `AvoidancePreference` (frontend type)

The union type `"avoid" | "balanced" | "fastest"` and all references to it are removed from:
- `frontend/src/types/api.ts`
- `frontend/src/services/routeApi.ts`

---

## Removed: `avoidance_preference` (API request field)

The `avoidance_preference` field is removed from the `RouteRequest` body schema and from `routes_controller.rb` permitted params.

The backend `RoutePlanner#plan` signature changes:
- **Before**: `plan(origin:, destination:, preference: "avoid", locale: "en")`
- **After**: `plan(origin:, destination:, locale: "en")`

The internal routing strategy is always equivalent to the former `preference: "avoid"` path.

---

## Removed: Internal routing modes

The following backend code is removed:
- `RoutePlanner::PREFERENCES` constant
- `RoutePlanner::BALANCED_MIN_CONFIDENCE` constant
- `RoutePlanner#balanced_route` private method
- The `preference` branch inside `RoutePlanner#avoiding_route`

The `avoiding_route` private method simplifies to:
```
return [fastest, false] if exclusion[:polygons].empty?
strict = safe_route(origin, destination, exclude_polygons: exclusion[:polygons])
strict ? [strict, true] : [fastest, false]
```

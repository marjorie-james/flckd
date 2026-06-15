# Phase 1 Data Model: Baseline Route Comparison

No database entities, migrations, or persisted state. The model below is the **request/response contract
delta** and the **client view-state** — all ephemeral.

## Backend: `FastestComparison` (extended)

Returned as `route.fastest_comparison`. Existing fields unchanged; two added.

| Field | Type | New? | Description |
|-------|------|------|-------------|
| `distance_m` | integer | existing | Distance of the fastest non-avoiding route, meters. |
| `duration_s` | integer | existing | Duration of the fastest non-avoiding route, seconds. |
| `added_distance_m` | integer | existing | `avoiding.distance_m − fastest.distance_m` (the recommended route's extra distance). |
| `added_duration_s` | integer | existing | `avoiding.duration_s − fastest.duration_s` (the recommended route's extra time; the **headline** cost). |
| `geometry` | string (encoded polyline, precision 6) | **NEW** | The fastest route's polyline, for drawing the comparison line. Copied from the already-computed `fastest[:geometry]`. |
| `cameras_passed_count` | integer | **NEW** | Number of monitored segments (in the O/D bbox) the fastest route intersects — i.e. cameras it would pass. `≥ 0`. |

### Validation / invariants

- When avoidance is free (no exclusions, or strict exclusion failed and the planner fell back to the
  fastest route), the chosen route **is** the fastest route: `added_distance_m == 0`,
  `added_duration_s == 0`, and `geometry == route.geometry`. The frontend treats `added_duration_s == 0`
  as "no comparison to show" (FR-006).
- `added_duration_s` and `added_distance_m` are never negative in practice (the avoiding route is the
  fastest route under added constraints). The UI never renders a negative figure (Edge Case).
- `cameras_passed_count ≥ cameras_avoided_count` is the expected relationship but is **not** enforced as a
  hard invariant (shared segments can vary); the count is computed directly, not derived.

### Source of truth

- Backend struct `Routing::Result#fastest_comparison` is a plain hash assembled by
  `RoutePlanner#comparison`; `RouteSerializer` passes it through verbatim. No `Result` struct change is
  needed (it already holds `fastest_comparison`).
- Contract: `FastestComparison` schema in `contracts/openapi.yaml` (see `contracts/route-comparison.md`).

## Frontend: types (`frontend/src/types/api.ts`)

```ts
export interface FastestComparison {
  distance_m: number;
  duration_s: number;
  added_distance_m: number;
  added_duration_s: number;
  geometry: string;            // NEW — encoded polyline (precision 6)
  cameras_passed_count: number; // NEW — cameras the fastest route would pass
}
```

`Route.fastest_comparison` already references this interface; `types/openapi.d.ts` is regenerated/edited to
match.

## Frontend: comparison view-state (ephemeral, not transmitted)

| State | Owner | Type | Description |
|-------|-------|------|-------------|
| `showComparison` | `PlanRoutePage` | boolean (default `true`) | Whether the comparison line is drawn and which framing `MapView` uses; toggled by the `RouteResult` show/hide control. Reset to `true` on each new plan (FR-009). |

Derived (not stored):

- **shouldDrawComparison** = `route != null && route.fastest_comparison.added_duration_s > 0 &&
  showComparison && decodePolyline(route.fastest_comparison.geometry, 6).length > 0`.

No client identifier, route, or coordinate is persisted or sent anywhere as a result of this state
(anonymity).

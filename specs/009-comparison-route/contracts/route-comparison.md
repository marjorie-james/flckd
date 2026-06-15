# Contract: Baseline Route Comparison

This feature does **not** add or change any endpoint. It extends one existing response object and defines
the frontend component props that consume it.

## API delta — `FastestComparison` (in `POST /api/v1/routes` → `Route.fastest_comparison`)

Update the `FastestComparison` schema in the OpenAPI contract
(`specs/002-flock-route-avoidance/contracts/openapi.yaml`) to add two properties:

```yaml
    FastestComparison:
      type: object
      properties:
        distance_m: { type: integer }
        duration_s: { type: integer }
        added_distance_m: { type: integer }
        added_duration_s: { type: integer }
        geometry:
          type: string
          description: Encoded polyline (precision 6) of the fastest non-avoiding route, for drawing the comparison line.
        cameras_passed_count:
          type: integer
          minimum: 0
          description: Number of monitored camera segments the fastest route would pass.
```

The rest of the `Route` schema is unchanged. `RouteSerializer` already emits `fastest_comparison` verbatim,
so no serializer change is required beyond the planner populating the two new keys.

### Example response fragment (avoidance has a cost)

```json
{
  "geometry": "<avoiding route polyline>",
  "distance_m": 6000,
  "duration_s": 800,
  "is_fully_clean": true,
  "cameras_avoided_count": 2,
  "remaining_cameras": [],
  "fastest_comparison": {
    "distance_m": 5000,
    "duration_s": 600,
    "added_distance_m": 1000,
    "added_duration_s": 200,
    "geometry": "<fastest route polyline>",
    "cameras_passed_count": 2
  },
  "coverage_warning": null
}
```

### Example response fragment (avoidance is free — single route)

```json
{
  "fastest_comparison": {
    "distance_m": 5000,
    "duration_s": 600,
    "added_distance_m": 0,
    "added_duration_s": 0,
    "geometry": "<same as route.geometry>",
    "cameras_passed_count": 0
  }
}
```

When `added_duration_s == 0`, the frontend shows a single route and no added-time/-distance figures
(FR-006).

## Frontend component contracts

### `MapView`

```ts
interface Props {
  route: Route | null;
  center?: [number, number];
  origin?: Coordinate | null;
  showComparison?: boolean; // NEW — default true; draw the comparison line + frame both when true
}
```

Behavior:

- Draws a `comparison` GeoJSON source + `comparison-line` layer **only** when
  `route.fastest_comparison.added_duration_s > 0`, `showComparison` is true, and the comparison geometry
  decodes to ≥ 1 coordinate.
- The `comparison-line` layer is inserted **beneath** `route-line` and styled distinctly (dashed, muted
  color, lower weight/opacity) so the recommended route stays primary, including over shared segments.
- When the comparison is shown, `fitBounds` covers both polylines; otherwise it frames the recommended
  route only (existing behavior).
- Removes/keeps-hidden the comparison line when `showComparison` is false, when `added_duration_s == 0`, or
  when `route` is null. No stale comparison persists across a new plan.

### `RouteResult`

```ts
interface Props {
  route: Route;
  origin: Coordinate;
  destination: Coordinate;
  showComparison: boolean;        // NEW
  onToggleComparison: () => void; // NEW
}
```

Behavior (only when `added_duration_s > 0`):

- Headline added time (existing `result.addedTime`).
- Secondary added distance from `added_distance_m` (new `result.addedDistance`).
- Fastest-route exposure from `cameras_passed_count` (new `result.fastestExposes`) — conveys the fastest
  route is not camera-free (FR-007).
- A labeled, keyboard-reachable show/hide toggle calling `onToggleComparison`
  (`result.showComparison` / `result.hideComparison`).

### `PlanRoutePage`

Owns `const [showComparison, setShowComparison] = useState(true)`, resets it to `true` on a new successful
plan (FR-009), passes `showComparison` to `MapView` and `{ showComparison, onToggleComparison }` to
`RouteResult`.

## i18n keys (add to `en.json` and `es.json`, under `result`)

| Key | en (example) |
|-----|--------------|
| `result.addedDistance` | `+{{km}} km vs fastest` |
| `result.fastestExposes_one` | `Fastest route passes {{count}} camera` |
| `result.fastestExposes_other` | `Fastest route passes {{count}} cameras` |
| `result.showComparison` | `Show fastest route` |
| `result.hideComparison` | `Hide fastest route` |
| `result.comparisonLabel` | `Fastest route (passes cameras)` |

(Existing `result.addedTime` = `+{{minutes}} min vs fastest` is reused unchanged.)

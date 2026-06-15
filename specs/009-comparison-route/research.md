# Phase 0 Research: Baseline Route Comparison

All "NEEDS CLARIFICATION" items from the spec were resolved in `/speckit-clarify` (trigger, visibility,
metrics) and the deferred latency budget is resolved below. The research here records the design decisions
grounded in the existing codebase.

## Decision 1: Reuse the already-computed fastest route (no new routing pass)

- **Decision**: Surface the fastest route's **geometry** and **camera count** on the existing
  `fastest_comparison` object. Do not add a new endpoint or a second routing strategy.
- **Rationale**: `Routing::RoutePlanner#plan` already calls Valhalla *without* exclusions
  (`route_planner.rb:19`) to compute the fastest route, and `#comparison` (`:100`) already returns its
  `distance_m`/`duration_s` plus `added_distance_m`/`added_duration_s`. The only missing data is the
  fastest route's `geometry` (already present on the `fastest` hash, just not copied into the comparison)
  and the count of cameras it passes. This is the smallest possible change and adds **zero** new external
  calls.
- **Alternatives considered**: (a) A separate `GET /routes/fastest` endpoint — rejected: a second
  round-trip and duplicate computation for data we already have. (b) Computing the fastest route on the
  frontend — rejected: would require a direct client→routing call, violating anonymity, and the frontend
  has no routing engine.

## Decision 2: Camera count for the fastest route reuses the existing intersection query

- **Decision**: Compute `cameras_passed_count` as `remaining_cameras_on(fastest, exclusion).size` — the
  number of monitored segments (in the O/D bbox) that the fastest route's polyline intersects.
- **Rationale**: `remaining_cameras_on` (`route_planner.rb:71`) already does exactly this PostGIS
  `ST_Intersects(ST_Buffer(...))` test for the avoiding route; running it once more against the fastest
  route is one cheap query against the same already-fetched `exclusion[:segments]`. It is the most honest
  definition of "cameras the fastest route would pass" and is consistent with how avoidance is measured.
- **Alternatives considered**: Deriving it arithmetically from `cameras_avoided_count` — rejected: avoided
  count and remaining-on-avoiding don't uniquely determine the fastest route's exposure when routes share
  some segments; a direct intersection is exact.
- **Note (tests)**: Fake fixtures use a non-decodable polyline, so `decoded_line_ewkt` returns nil and the
  count is 0 under `GeoFakes` — matching existing behavior for `remaining_cameras`. Exposure-count
  assertions use the PostGIS-backed request/integration path with real geometry, as the avoiding-route
  remaining count already does.

## Decision 3: Trigger — draw the comparison only when `added_duration_s > 0`

- **Decision**: The frontend draws the comparison line and shows the added-time/-distance figures only
  when `route.fastest_comparison.added_duration_s > 0`. When avoidance is free (no exclusions, or the
  avoiding route *is* the fastest via fallback), the comparison equals the recommended route, `added_*`
  is 0, and only the single route is shown.
- **Rationale**: Directly implements the clarified trigger (Clarifications, Session 2026-06-11) and FR-006.
  In the fallback case the planner returns `fastest` as the chosen route, so the two geometries are
  identical and a second line would be redundant; gating on `added_duration_s > 0` cleanly suppresses it.
- **Alternatives considered**: Gating on geometry difference — rejected: more complex and can show a line
  for an equal-time alternate path that conveys no time trade-off (the feature is about *time* cost).

## Decision 4: Comparison line styling and layer order (visual subordination)

- **Decision**: Add a dedicated `comparison` GeoJSON source + `comparison-line` layer, **inserted beneath**
  the existing `route-line` layer (via `addLayer(layer, ROUTE_LAYER)` beforeId), styled distinctly: dashed,
  muted/neutral color (e.g. a gray `#9ca3af`), thinner/lower opacity than the recommended `#818cf8` line.
- **Rationale**: FR-002/FR-005/FR-008 require the recommended route to read as primary and stay
  distinguishable where the two overlap. Drawing the comparison underneath and dashing it keeps the solid
  primary line on top along shared segments. Reuses the exact source/layer idiom already used for
  `route`/`origin`/cameras (`MapView.tsx:122`), so no new rendering concept.
- **Alternatives considered**: Same color, different width — rejected: poor contrast on overlap and on small
  screens. A separate map overlay component — rejected: the existing single-`MapView` effect pattern is
  simpler and consistent.

## Decision 5: Framing — fit both routes when the comparison is shown

- **Decision**: When the comparison line is shown, `fitBounds` to the union of both polylines (existing
  48px padding, 600ms); otherwise frame the recommended route only (today's behavior).
- **Rationale**: The comparison is only useful if visible; framing only the avoiding route could push the
  divergent fastest path partly off-screen. Extending bounds keeps both legible (Edge Case: small-screen
  readability) while the styling (Decision 4) preserves primary emphasis.
- **Alternatives considered**: Always frame the recommended route only — rejected: risks clipping the
  comparison. Framing only the comparison — rejected: the recommended route is the focus.

## Decision 6: Visibility default + dismiss — lift `showComparison` to the page

- **Decision**: A single `showComparison` boolean (default `true`) lives in `PlanRoutePage`; it is passed
  to `MapView` (whether to draw the line + which framing) and to `RouteResult` (which renders the
  labeled show/hide toggle). Dismissing removes the comparison line while the recommended route and its
  travel time remain.
- **Rationale**: Implements FR-002a and the clarified "auto-shown, dismissible" decision. Lifting the state
  to the page keeps a single source of truth shared by the map and the summary panel, avoiding cross-
  component duplication. Resetting to `true` on each new plan satisfies FR-009 (no stale comparison).
- **Alternatives considered**: State owned inside `MapView` — rejected: `RouteResult` (a sibling) owns the
  toggle UI, so the flag must live at/above their common parent. A map control button — rejected: the
  summary panel is where the trade-off is read, so the toggle belongs there for discoverability.

## Decision 7: Metrics shown — added time (headline) + added distance (secondary) + exposure

- **Decision**: `RouteResult` keeps the existing `result.addedTime` headline, adds `result.addedDistance`
  (from `added_distance_m`) as a secondary detail, and adds `result.fastestExposes` (from
  `cameras_passed_count`) to convey the fastest route is not camera-free (FR-007). New `result.*` keys are
  added to both `en` and `es`.
- **Rationale**: Implements the clarified metric decision (time headline, distance secondary) and FR-004/
  FR-004a/FR-007, following the established `result.*` i18n convention and the existing bilingual
  requirement.
- **Alternatives considered**: Time only — rejected by clarification. A full expandable breakdown —
  rejected as more UI than the trade-off needs at this stage.

## Resolved deferred item: performance budget

- **Decision**: Inherit feature `002`'s route-planning p95 budget unchanged; assert no regression.
- **Rationale**: The fastest route is already computed today, so no new external round-trip is added. The
  only added work is one PostGIS intersection (same query already run for the avoiding route) and one extra
  polyline in the response — negligible against the existing budget. Verified in quickstart with
  representative O/D pairs.

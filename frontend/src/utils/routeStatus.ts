import type { Route } from "../types/api";

// Single source of truth for how a planned route's camera-avoidance status reads,
// so CameraSummary and RouteResult can't drift (they previously each re-derived
// this and warned about the same contradiction in comments):
//   - "avoided":        fully clean AND it actively dodged at least one camera.
//   - "alreadyClean":   fully clean with no cameras near the route (nothing to dodge).
//   - "minimumExposure": couldn't avoid every camera; this passes the fewest.
export type RouteStatusKind = "avoided" | "alreadyClean" | "minimumExposure";

export function routeStatus(route: Route): RouteStatusKind {
  if (!route.is_fully_clean) return "minimumExposure";
  return route.cameras_avoided_count > 0 ? "avoided" : "alreadyClean";
}

import { useQuery } from "@tanstack/react-query";
import { apiPost } from "./apiClient";
import type { Route, RouteRequest } from "../types/api";

export function planRoute(req: RouteRequest, signal?: AbortSignal): Promise<Route> {
  return apiPost<Route>("/routes", { route: req }, signal);
}

// Plans the route for `req`, cached + deduped + cancelable by react-query. A null
// request disables the query (nothing to plan yet). The query key IS the request, so
// an identical (origin, destination, locale) trip is served from cache, and a
// superseded in-flight plan is canceled (via the AbortSignal) instead of racing a
// stale response onto the screen. retry: false so a service error surfaces promptly.
export function usePlanRoute(req: RouteRequest | null) {
  return useQuery({
    queryKey: ["plan", req],
    queryFn: ({ signal }) => planRoute(req as RouteRequest, signal),
    enabled: req !== null,
    staleTime: 5 * 60_000,
    gcTime: 5 * 60_000,
    retry: false,
  });
}

import { useQuery } from "@tanstack/react-query";
import { apiPost } from "./apiClient";
import type { Route, RouteRequest } from "../types/api";

export function planRoute(req: RouteRequest, signal?: AbortSignal): Promise<Route> {
  return apiPost<Route>("/routes", { route: req }, signal);
}

// Plans the route for `req`, cancelable by react-query. A null request disables
// the query (nothing to plan yet). The query key includes a caller-supplied nonce
// so an explicit re-submit with unchanged endpoints always hits the network (a
// user pressing "Plan route" again expects a fresh plan, not a cached one). A
// superseded in-flight plan is canceled (via the AbortSignal) instead of racing a
// stale response onto the screen. retry: false so a service error surfaces
// promptly.
export function usePlanRoute(req: RouteRequest | null, nonce = 0) {
  return useQuery({
    queryKey: ["plan", req, nonce],
    queryFn: ({ signal }) => planRoute(req as RouteRequest, signal),
    enabled: req !== null,
    staleTime: 5 * 60_000,
    gcTime: 5 * 60_000,
    retry: false,
  });
}

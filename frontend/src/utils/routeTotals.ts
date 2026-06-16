import type { Route } from "../types/api";

// Shared trip-summary formatting so the on-screen result and the printable
// directions sheet always agree on the route's total time and distance (same
// units, same rounding). The paper a driver carries must match the screen they
// planned on, so both surfaces derive these from one place.
export function routeTotals(route: Route): { travelMin: number; km: string } {
  return {
    travelMin: Math.round(route.duration_s / 60),
    km: (route.distance_m / 1000).toFixed(1),
  };
}

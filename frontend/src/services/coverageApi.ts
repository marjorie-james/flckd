import { useQuery } from "@tanstack/react-query";
import { apiGet } from "./apiClient";
import type { RegionBounds } from "../types/api";

interface CoverageBoundsResponse {
  bounds: RegionBounds | null;
}

// The bounding box of this deployment's covered region, used to frame the map on
// load (no hardcoded launch state). The covered region doesn't change at runtime,
// so it's cached for the session. retry: false so a backend error just leaves the
// map at its neutral default rather than retrying.
export function useCoverageBounds() {
  return useQuery({
    queryKey: ["coverage-bounds"],
    queryFn: ({ signal }) => apiGet<CoverageBoundsResponse>("/coverage/bounds", undefined, signal),
    staleTime: Infinity,
    gcTime: Infinity,
    retry: false,
  });
}

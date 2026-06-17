import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { apiGet } from "./apiClient";
import type { GeocodeResult } from "../types/api";

interface SearchResponse {
  results: GeocodeResult[];
}

export async function geocodeSearch(
  q: string,
  lang = "en",
  signal?: AbortSignal,
): Promise<SearchResponse> {
  const data = await apiGet<SearchResponse>("/geocode/search", { q, lang, limit: 5 }, signal);
  // Surface the best match first. `confidence` reflects how precisely a result
  // matches an address (an exact street address scores highest), so sorting
  // descending puts the most relevant suggestion at the top of the list. The
  // sort is stable, so equal-confidence results keep the backend's ordering.
  const results = [ ...(data.results ?? []) ].sort((a, b) => b.confidence - a.confidence);
  return { ...data, results };
}

// Minimum query length before the geocoder is called. Must match the
// flushBelow threshold used in RoutePanel's useDebounce call.
export const MIN_QUERY_LENGTH = 3;

// Type-ahead query. Disabled until the user types >= MIN_QUERY_LENGTH chars.
// keepPreviousData prevents the list from blanking while a new query loads.
export function useGeocodeSearch(q: string, lang: string) {
  return useQuery({
    queryKey: ["geocode", q, lang],
    queryFn: ({ signal }) => geocodeSearch(q, lang, signal),
    enabled: q.trim().length >= MIN_QUERY_LENGTH,
    staleTime: 60_000,
    placeholderData: keepPreviousData,
  });
}

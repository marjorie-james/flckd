import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import type { RouteRequest } from "../../src/types/api";

const apiPost = vi.fn();
vi.mock("../../src/services/apiClient", () => ({
  apiPost: (...args: unknown[]) => apiPost(...args),
}));

import { usePlanRoute } from "../../src/services/routeApi";

const ROUTE_RESPONSE = {
  geometry: "_poly_",
  distance_m: 6000,
  duration_s: 600,
  maneuvers: [],
  cameras_avoided_count: 0,
  remaining_cameras: [],
  is_fully_clean: true,
  fastest_comparison: {
    distance_m: 5000,
    duration_s: 500,
    added_distance_m: 0,
    added_duration_s: 0,
    geometry: "_fast_",
    cameras_passed_count: 0,
  },
  coverage_warning: null,
};

function wrapper() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );
}

const REQ: RouteRequest = {
  origin: { lat: 41.59, lng: -93.60 },
  destination: { lat: 41.53, lng: -93.66 },
  locale: "en",
};

beforeEach(() => {
  apiPost.mockReset();
  apiPost.mockResolvedValue(ROUTE_RESPONSE);
});

describe("usePlanRoute nonce", () => {
  it("re-fetches when the nonce changes even if the request is identical", async () => {
    const w = wrapper();
    const { rerender } = renderHook(
      ({ req, nonce }: { req: RouteRequest | null; nonce: number }) =>
        usePlanRoute(req, nonce),
      { wrapper: w, initialProps: { req: REQ, nonce: 0 } },
    );

    await waitFor(() => expect(apiPost).toHaveBeenCalledTimes(1));

    // Same request, bumped nonce: must trigger a second fetch.
    await act(async () => {
      rerender({ req: REQ, nonce: 1 });
    });

    await waitFor(() => expect(apiPost).toHaveBeenCalledTimes(2));
  });

  it("does not re-fetch when neither request nor nonce changes", async () => {
    const w = wrapper();
    const { rerender } = renderHook(
      ({ req, nonce }: { req: RouteRequest | null; nonce: number }) =>
        usePlanRoute(req, nonce),
      { wrapper: w, initialProps: { req: REQ, nonce: 0 } },
    );

    await waitFor(() => expect(apiPost).toHaveBeenCalledTimes(1));

    // Re-render with the same props: no new fetch.
    await act(async () => {
      rerender({ req: REQ, nonce: 0 });
    });

    // Give react-query a tick to prove it doesn't fire again.
    await new Promise((r) => setTimeout(r, 50));
    expect(apiPost).toHaveBeenCalledTimes(1);
  });

  it("is disabled when req is null", async () => {
    const w = wrapper();
    renderHook(
      ({ req, nonce }: { req: RouteRequest | null; nonce: number }) =>
        usePlanRoute(req, nonce),
      { wrapper: w, initialProps: { req: null as RouteRequest | null, nonce: 0 } },
    );

    await new Promise((r) => setTimeout(r, 50));
    expect(apiPost).not.toHaveBeenCalled();
  });
});

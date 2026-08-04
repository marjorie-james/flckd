import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor, act } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import "../../src/i18n";
import type { GeocodeResult } from "../../src/types/api";

// Regression for the "focus destroyed on every re-plan" bug (WCAG 2.4.3):
// usePlanRoute must keep the previous route mounted during a re-plan
// (placeholderData: keepPreviousData) and PlanRoutePage must move focus to the
// result region once the re-plan resolves. Geo/map/network are mocked so the
// test is deterministic and hits no WebGL or network (Constitution Principle II).

const desMoines: GeocodeResult = { label: "Des Moines, IA", lat: 41.5868, lng: -93.625, type: "city", confidence: 0.9 };
const iowaCity: GeocodeResult = { label: "Iowa City, IA", lat: 41.6612, lng: -91.5299, type: "city", confidence: 0.9 };

// Pass-through debounce so the suggestion list opens without fake timers.
vi.mock("../../src/hooks/useDebounce", () => ({
  useDebounce: (value: string) => value,
}));

vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
  return {
    ...actual,
    useGeocodeSearch: () => ({ data: { results: [desMoines, iowaCity] }, isFetching: false, isError: false }),
  };
});

// jsdom has no WebGL; the minimal map stub mounts the container without a real map.
vi.mock("maplibre-gl", () => ({
  setWorkerUrl: () => {},
  Map: class {
    isStyleLoaded() { return true; }
    getSource() { return undefined; }
    addSource() {} addLayer() {} flyTo() {} jumpTo() {} fitBounds() {}
    easeTo() {} once() {} off() {} remove() {}
  },
}));

vi.mock("../../src/components/CameraLayer", () => ({ CameraLayer: () => null }));
vi.mock("../../src/services/coverageApi", () => ({
  useCoverageBounds: () => ({ data: null }),
}));

// Mock only the network call; keep ApiError (PlanRoutePage imports it).
const apiPost = vi.fn();
vi.mock("../../src/services/apiClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/apiClient")>();
  return {
    ...actual,
    apiPost: (...args: unknown[]) => apiPost(...args),
  };
});

import { PlanRoutePage } from "../../src/pages/PlanRoutePage";

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

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <PlanRoutePage />
    </QueryClientProvider>,
  );
}

function selectEndpoints() {
  const inputs = document.querySelectorAll('input[inputmode="search"]');
  fireEvent.change(inputs[0], { target: { value: "des m" } });
  fireEvent.click(screen.getAllByRole("option", { name: "Des Moines, IA" })[0]);
  fireEvent.change(inputs[1], { target: { value: "iowa" } });
  fireEvent.click(screen.getByRole("option", { name: "Iowa City, IA" }));
}

beforeEach(() => {
  apiPost.mockReset();
});

describe("PlanRoutePage re-plan focus", () => {
  it("keeps the result mounted through a re-plan and focuses it, not <body>", async () => {
    apiPost.mockResolvedValueOnce(ROUTE_RESPONSE);
    renderPage();

    selectEndpoints();
    fireEvent.click(screen.getByRole("button", { name: /plan route/i }));

    // Initial plan renders the result section.
    await waitFor(() => expect(document.querySelector(".route-result")).toBeInTheDocument());
    expect(apiPost).toHaveBeenCalledTimes(1);

    // Second plan resolves on our signal so we can observe the in-flight state.
    let resolveSecond!: (v: typeof ROUTE_RESPONSE) => void;
    apiPost.mockImplementationOnce(
      () => new Promise((res) => { resolveSecond = res; }),
    );

    fireEvent.click(screen.getByRole("button", { name: /plan route/i }));

    // Mid re-plan: the old route stays mounted (keepPreviousData), never blanks.
    await waitFor(() => expect(apiPost).toHaveBeenCalledTimes(2));
    expect(document.querySelector(".route-result")).toBeInTheDocument();

    await act(async () => {
      resolveSecond(ROUTE_RESPONSE);
    });

    // Re-plan resolved: result still mounted, focus landed on the result region.
    await waitFor(() => {
      expect(document.activeElement).not.toBe(document.body);
    });
    expect(document.querySelector(".route-result")).toBeInTheDocument();
    expect(document.activeElement).toHaveClass("result-section");
  });

  it("does not move focus on the initial plan (no previous data)", async () => {
    apiPost.mockResolvedValueOnce(ROUTE_RESPONSE);
    renderPage();

    selectEndpoints();
    const planButton = screen.getByRole("button", { name: /plan route/i });
    planButton.focus();
    fireEvent.click(planButton);

    await waitFor(() => expect(document.querySelector(".route-result")).toBeInTheDocument());

    // Initial plan must not steal focus onto the result region.
    expect(document.activeElement).not.toHaveClass("result-section");
  });
});

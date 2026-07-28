import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent, act } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import "../../src/i18n";
import type { GeocodeResult, Route } from "../../src/types/api";

// Document structure of the planned-route page: heading hierarchy and the
// bypass-blocks link. The map contributes no headings and no tab stop of its own
// in jsdom (no WebGL), so it is stubbed out entirely — that keeps the test
// deterministic and off the network (Constitution Principle II).
vi.mock("../../src/components/MapView", () => ({ MapView: () => null }));

// Fixed geocode results + a pass-through debounce, so the form can be filled and
// submitted synchronously (same approach as tests/unit/route-plan.test.tsx).
const desMoines: GeocodeResult = { label: "Des Moines, IA", lat: 41.5868, lng: -93.625, type: "city", confidence: 0.9 };
const iowaCity: GeocodeResult = { label: "Iowa City, IA", lat: 41.6612, lng: -91.5299, type: "city", confidence: 0.9 };
vi.mock("../../src/hooks/useDebounce", () => ({ useDebounce: (value: string) => value }));
vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
  return { ...actual, useGeocodeSearch: () => ({ data: { results: [desMoines, iowaCity] } }) };
});

const route: Route = {
  geometry: "__ajnA~n{oqD~hbE_ibE",
  distance_m: 6000,
  duration_s: 600,
  maneuvers: [{ type: "start", localized_text: "Head north on Main St", distance_m: 300 }],
  cameras_avoided_count: 2,
  remaining_cameras: [],
  is_fully_clean: true,
  fastest_comparison: {
    distance_m: 5000,
    duration_s: 500,
    added_distance_m: 1000,
    added_duration_s: 100,
    geometry: "_fast_",
    cameras_passed_count: 2,
  },
  coverage_warning: null,
};

// A resolved plan, so the result section (and its headings) render.
vi.mock("../../src/services/routeApi", () => ({
  usePlanRoute: () => ({ data: route, error: null, isError: false, isFetching: false }),
}));
vi.mock("../../src/services/coverageApi", () => ({
  useCoverageBounds: () => ({ data: null }),
}));

import { PlanRoutePage } from "../../src/pages/PlanRoutePage";
import App from "../../src/App";

async function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const utils = render(
    <QueryClientProvider client={client}>
      <PlanRoutePage />
    </QueryClientProvider>
  );
  // The map is a lazy chunk; let Suspense settle before asserting on the tree.
  await act(async () => {});
  return utils;
}

// Fill both address fields from the suggestion list and submit, so the result
// section (and the headings inside it) render.
function planARoute() {
  const inputs = document.querySelectorAll('input[inputmode="search"]');
  fireEvent.change(inputs[0], { target: { value: "des m" } });
  fireEvent.click(screen.getAllByRole("option", { name: "Des Moines, IA" })[0]);
  fireEvent.change(inputs[1], { target: { value: "iowa" } });
  fireEvent.click(screen.getByRole("option", { name: "Iowa City, IA" }));
  fireEvent.click(screen.getByRole("button", { name: /plan route/i }));
}

// Everything focusable, in DOM order, minus anything taken out of the tab order.
function tabbable(root: HTMLElement) {
  const sel = "a[href], button, input, select, textarea, [tabindex]";
  return Array.from(root.querySelectorAll<HTMLElement>(sel)).filter(
    (el) => el.getAttribute("tabindex") !== "-1"
  );
}

describe("PlanRoutePage document structure", () => {
  it("exposes headings with no skipped level", async () => {
    await renderPage();
    planARoute();
    expect(screen.getByRole("heading", { level: 3 })).toBeInTheDocument();

    const levels = screen
      .getAllByRole("heading")
      .map((h) => Number(h.tagName.slice(1)));

    expect(levels[0]).toBe(1);
    // Every step down the outline is at most one level; h1 → h3 would be a skip.
    for (let i = 1; i < levels.length; i++) {
      expect(levels[i] - levels[i - 1]).toBeLessThanOrEqual(1);
    }
    // And the intermediate level is really there, not just absent from both ends.
    expect(levels).toContain(2);
  });

  // Mounts the real app root, not just the page, so anything added above the page
  // (header chrome, a banner) would push the link out of first place and fail here.
  it("puts a skip link first in the tab order, pointing at a focusable target", async () => {
    const { container } = render(<App />);
    await act(async () => {});

    const skip = screen.getByRole("link", { name: /skip to main content/i });
    expect(tabbable(container)[0]).toBe(skip);

    const href = skip.getAttribute("href")!;
    expect(href.startsWith("#")).toBe(true);

    const target = container.querySelector<HTMLElement>(href);
    expect(target).not.toBeNull();
    // Focusable by script (that is what the fragment jump does) without joining
    // the tab order itself.
    expect(target).toHaveAttribute("tabindex", "-1");
    target!.focus();
    expect(document.activeElement).toBe(target);
  });
});

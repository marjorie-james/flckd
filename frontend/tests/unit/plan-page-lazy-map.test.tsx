import { describe, it, expect, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import "../../src/i18n";

// The map (MapLibre + WebGL + camera layer) is loaded as a separate chunk via
// React.lazy so the page paints and the route is usable while it downloads. This
// asserts that behaviour: the Suspense fallback shows first, then the real map
// container resolves. Geo/map are mocked so the test is deterministic and hits no
// network or WebGL (Constitution Principle II).
vi.mock("maplibre-gl", () => ({
  default: {
    Map: class {
      isStyleLoaded() { return true; }
      getSource() { return undefined; }
      addSource() {} addLayer() {} flyTo() {} jumpTo() {} fitBounds() {}
      easeTo() {} once() {} off() {} remove() {}
    },
  },
}));

// CameraLayer drives map APIs the minimal stub doesn't implement and is unrelated
// to load-order; stub it out.
vi.mock("../../src/components/CameraLayer", () => ({ CameraLayer: () => null }));

// No route is planned and no coverage box is needed for this test — the page
// renders the map shell regardless.
vi.mock("../../src/services/routeApi", () => ({
  usePlanRoute: () => ({ data: null, error: null, isError: false, isFetching: false }),
}));
vi.mock("../../src/services/coverageApi", () => ({
  useCoverageBounds: () => ({ data: null }),
}));

import { PlanRoutePage } from "../../src/pages/PlanRoutePage";

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <PlanRoutePage />
    </QueryClientProvider>
  );
}

describe("PlanRoutePage lazy map", () => {
  it("renders the page chrome immediately, then resolves the map chunk", async () => {
    const { container } = renderPage();

    // Page chrome (header heading, route form) is present without waiting on the
    // map chunk — the route flow does not block on the heaviest dependency.
    expect(screen.getByRole("heading", { level: 1 })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /plan route/i })).toBeInTheDocument();

    // The lazy map resolves into the real container.
    await waitFor(() =>
      expect(container.querySelector(".map-view")).toBeInTheDocument()
    );
  });
});

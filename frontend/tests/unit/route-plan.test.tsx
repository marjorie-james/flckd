import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "../../src/i18n";
import type { GeocodeResult, Route } from "../../src/types/api";

// US1: RoutePanel input + geocode autocomplete, and MapView render.
// Geo + map are mocked so the test is deterministic and hits no network or WebGL
// (Constitution Principle II).
const desMoines: GeocodeResult = { label: "Des Moines, IA", lat: 41.5868, lng: -93.625, type: "city", confidence: 0.9 };
const iowaCity:  GeocodeResult = { label: "Iowa City, IA",  lat: 41.6612, lng: -91.5299, type: "city", confidence: 0.9 };

// useDebounce is mocked as pass-through so unit tests don't need fake timers;
// debounce behaviour is an interaction detail tested by the e2e suite.
vi.mock("../../src/hooks/useDebounce", () => ({
  useDebounce: (value: string) => value,
}));

vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
  return {
    ...actual,
    useGeocodeSearch: () => ({ data: { results: [desMoines, iowaCity] } }),
  };
});

// jsdom has no WebGL/canvas; assert the container mounts without constructing a
// real map. The style URL is self-hosted, so no third-party tile request occurs.
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

// CameraLayer drives its own map APIs (getBounds/on/...) the minimal map stub here
// doesn't implement; it's unrelated to these tests, so stub it out.
vi.mock("../../src/components/CameraLayer", () => ({ CameraLayer: () => null }));

import { RoutePanel } from "../../src/components/RoutePanel";
import { MapView } from "../../src/components/MapView";
import { RouteNotice } from "../../src/components/RouteNotice";

function routeFixture(overrides: Partial<Route> = {}): Route {
  return {
    geometry: "_poly_",
    distance_m: 6000,
    duration_s: 600,
    maneuvers: [],
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
    ...overrides,
  };
}

describe("RoutePanel", () => {
  it("renders origin/destination inputs and disables Plan until both are set", () => {
    render(<RoutePanel onPlan={() => {}} planning={false} />);
    expect(screen.getByText(/start/i)).toBeInTheDocument();
    expect(screen.getByText(/destination/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /plan route/i })).toBeDisabled();
  });

  it("selects origin and destination from autocomplete, then plans the route", () => {
    const onPlan = vi.fn();
    render(<RoutePanel onPlan={onPlan} planning={false} />);

    const inputs = document.querySelectorAll('input[inputmode="search"]');

    // Type enough characters so the display guard (>= MIN_QUERY_LENGTH) passes.
    fireEvent.change(inputs[0], { target: { value: "des m" } });
    fireEvent.click(screen.getAllByRole("option", { name: "Des Moines, IA" })[0]); // origin

    fireEvent.change(inputs[1], { target: { value: "iowa" } });
    fireEvent.click(screen.getByRole("option", { name: "Iowa City, IA" })); // destination

    const plan = screen.getByRole("button", { name: /plan route/i });
    expect(plan).toBeEnabled();
    fireEvent.click(plan);

    // The confirmed address labels ride along with the coordinates (013) so the
    // printable directions sheet can show the trip's origin/destination.
    expect(onPlan).toHaveBeenCalledWith(
      { lat: 41.5868, lng: -93.625 },
      { lat: 41.6612, lng: -91.5299 },
      { origin: "Des Moines, IA", destination: "Iowa City, IA" },
    );
  });

  it("reserves space below the destination field so its dropdown clears the Plan button", () => {
    render(<RoutePanel onPlan={() => {}} planning={false} />);
    const inputs = document.querySelectorAll('input[inputmode="search"]');

    // Destination is the last field; it reserves a fixed gap so its dropdown opens
    // into that space instead of covering the button (and the button doesn't move).
    expect(inputs[1].closest(".input-group")).toHaveClass("reserve-dropdown");
    // The origin field keeps the default overlay (no reserved gap).
    expect(inputs[0].closest(".input-group")).not.toHaveClass("reserve-dropdown");
  });
});

describe("RouteNotice", () => {
  it("warns prominently when the route is not fully camera-free", () => {
    render(
      <RouteNotice route={routeFixture({ is_fully_clean: false, remaining_cameras: [{ osm_way_id: 1 }] })} />
    );

    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent(/still passes within view of some cameras/i);
  });

  it("renders nothing for a fully camera-free route", () => {
    const { container } = render(<RouteNotice route={routeFixture({ is_fully_clean: true })} />);
    expect(container).toBeEmptyDOMElement();
    expect(screen.queryByRole("alert")).toBeNull();
  });
});

describe("MapView", () => {
  it("mounts a map container", () => {
    const { container } = render(<MapView route={null} />);
    expect(container.querySelector(".map-view")).toBeInTheDocument();
  });
});

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "../../src/i18n";
import type { GeocodeResult } from "../../src/types/api";

// RoutePanel announces the confirmed starting location via onOriginChange so the
// map can recenter on it (feature 007). Fires on suggestion pick, on clear, and
// on geolocation — never on intermediate typing (spec FR-001/005/010/013).
const desMoines: GeocodeResult = { label: "Des Moines, IA", lat: 41.5868, lng: -93.625, type: "city", confidence: 0.9 };

vi.mock("../../src/hooks/useDebounce", () => ({ useDebounce: (value: string) => value }));

vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
  return { ...actual, useGeocodeSearch: () => ({ data: { results: [desMoines] } }) };
});

// Controllable geolocation: set h.geoCoord before render to simulate a fix.
const h = vi.hoisted(() => ({ geoCoord: null as { lat: number; lng: number } | null }));
vi.mock("../../src/hooks/useGeolocation", () => ({
  useGeolocation: () => ({ coordinate: h.geoCoord, loading: false, error: null, request: () => {} }),
}));

import { RoutePanel } from "../../src/components/RoutePanel";

describe("RoutePanel onOriginChange", () => {
  beforeEach(() => { h.geoCoord = null; });

  it("fires with the coordinate when a suggestion is picked", () => {
    const onOriginChange = vi.fn();
    render(<RoutePanel onPlan={() => {}} planning={false} onOriginChange={onOriginChange} />);

    const inputs = document.querySelectorAll('input[inputmode="search"]');
    fireEvent.change(inputs[0], { target: { value: "des m" } });
    fireEvent.click(screen.getAllByRole("option", { name: "Des Moines, IA" })[0]);

    expect(onOriginChange).toHaveBeenLastCalledWith({ lat: 41.5868, lng: -93.625 });
  });

  it("fires with null when the starting-address field is cleared", () => {
    const onOriginChange = vi.fn();
    render(<RoutePanel onPlan={() => {}} planning={false} onOriginChange={onOriginChange} />);

    const inputs = document.querySelectorAll('input[inputmode="search"]');
    fireEvent.change(inputs[0], { target: { value: "des m" } });
    fireEvent.click(screen.getAllByRole("option", { name: "Des Moines, IA" })[0]); // set
    fireEvent.change(inputs[0], { target: { value: "des" } });                     // edit → clear

    expect(onOriginChange).toHaveBeenLastCalledWith(null);
  });

  it("does not fire while typing without a selection", () => {
    const onOriginChange = vi.fn();
    render(<RoutePanel onPlan={() => {}} planning={false} onOriginChange={onOriginChange} />);

    const inputs = document.querySelectorAll('input[inputmode="search"]');
    fireEvent.change(inputs[0], { target: { value: "des" } });
    fireEvent.change(inputs[0], { target: { value: "des m" } });

    expect(onOriginChange).not.toHaveBeenCalled();
  });

  it("fires with the device location when geolocation resolves (FR-010)", async () => {
    h.geoCoord = { lat: 41.6, lng: -93.6 };
    const onOriginChange = vi.fn();
    render(<RoutePanel onPlan={() => {}} planning={false} onOriginChange={onOriginChange} />);

    await waitFor(() => expect(onOriginChange).toHaveBeenLastCalledWith({ lat: 41.6, lng: -93.6 }));
  });
});

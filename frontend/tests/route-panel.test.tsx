import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "../src/i18n";

// Drive the panel deterministically: collapse the debounce to identity and feed
// the geocoder a single predictable suggestion per query. Geolocation is inert.
vi.mock("../src/hooks/useDebounce", () => ({
  useDebounce: (value: string, _delay: number, min = 0) =>
    value.trim().length >= min ? value : "",
}));
vi.mock("../src/hooks/useGeolocation", () => ({
  useGeolocation: () => ({ coordinate: null, error: null, loading: false, request: vi.fn() }),
}));
vi.mock("../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/services/geocodeApi")>();
  return {
    ...actual,
    useGeocodeSearch: (q: string) => ({
      data:
        q && q.trim().length >= actual.MIN_QUERY_LENGTH
          ? { results: [{ label: `Result for ${q}`, lat: 1, lng: 2, type: "address", confidence: 1 }] }
          : undefined,
      isFetching: false,
      isError: false,
    }),
  };
});

import { RoutePanel } from "../src/components/RoutePanel";

describe("RoutePanel label lift (013)", () => {
  it("forwards the confirmed origin/destination labels alongside the coordinates on submit", () => {
    const onPlan = vi.fn();
    render(<RoutePanel onPlan={onPlan} planning={false} />);

    const [originInput, destInput] = screen.getAllByRole("combobox");

    fireEvent.change(originInput, { target: { value: "123 Main" } });
    fireEvent.click(screen.getByRole("option", { name: "Result for 123 Main" }));

    fireEvent.change(destInput, { target: { value: "456 Oak" } });
    fireEvent.click(screen.getByRole("option", { name: "Result for 456 Oak" }));

    fireEvent.click(screen.getByRole("button", { name: /plan route/i }));

    expect(onPlan).toHaveBeenCalledTimes(1);
    expect(onPlan).toHaveBeenCalledWith(
      { lat: 1, lng: 2 },
      { lat: 1, lng: 2 },
      { origin: "Result for 123 Main", destination: "Result for 456 Oak" },
    );
  });
});

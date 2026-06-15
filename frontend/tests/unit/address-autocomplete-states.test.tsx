import { describe, it, expect } from "vitest";
import { render, screen, within } from "@testing-library/react";
import "../../src/i18n";
import { AddressAutocomplete } from "../../src/components/AddressAutocomplete";
import type { GeocodeResult } from "../../src/types/api";

// The status text appears twice (the visible listbox row + the polite live
// region); scope visible-row assertions to the listbox.
const inList = (re: RegExp) => within(screen.getByRole("listbox")).getByText(re);

// Before this change an in-flight, failed, or empty geocode query rendered
// nothing — a silent dead input. These pin that each state now surfaces a
// non-option status row (and announces it to screen readers).
const result = (label: string): GeocodeResult => ({ label, lat: 1, lng: 2, type: "address", confidence: 0.9 });

function renderField(props: Partial<React.ComponentProps<typeof AddressAutocomplete>> = {}) {
  render(
    <AddressAutocomplete
      id="origin-input"
      label="Start"
      value="des"
      onValueChange={() => {}}
      suggestions={[]}
      onSelect={() => {}}
      open
      {...props}
    />,
  );
}

describe("AddressAutocomplete status states", () => {
  it("shows a searching row while a query is in flight with no results yet", () => {
    renderField({ loading: true });
    expect(inList(/Searching/)).toBeInTheDocument();
  });

  it("shows a no-matches row when an open query returns nothing", () => {
    renderField({ loading: false });
    expect(inList(/No matches found/)).toBeInTheDocument();
  });

  it("shows an error row when the geocode request failed", () => {
    renderField({ error: true });
    expect(inList(/Search unavailable/)).toBeInTheDocument();
  });

  it("announces the status in the polite live region", () => {
    renderField({ error: true });
    expect(screen.getByRole("status")).toHaveTextContent(/Search unavailable/);
  });

  it("renders selectable options (not a status row) when suggestions exist", () => {
    renderField({ suggestions: [result("123 Main St")] });
    expect(screen.getByRole("option", { name: "123 Main St" })).toBeInTheDocument();
    expect(within(screen.getByRole("listbox")).queryByText(/No matches found/)).not.toBeInTheDocument();
  });

  it("shows nothing when the field is closed", () => {
    renderField({ open: false, loading: true });
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
  });
});

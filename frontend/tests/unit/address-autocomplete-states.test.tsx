import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import "../../src/i18n";
import { AddressAutocomplete } from "../../src/components/AddressAutocomplete";
import type { GeocodeResult } from "../../src/types/api";

// The status text appears twice (the visible panel + the polite live region);
// scope visible-panel assertions to the panel itself. It is deliberately not
// inside the listbox, so it can't be reached with a listbox query.
const statusPanel = () => document.querySelector(".suggestion-status");

// Before this change an in-flight, failed, or empty geocode query rendered
// nothing — a silent dead input. These pin that each state now surfaces a
// status panel (and announces it to screen readers).
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
  it("shows a searching panel while a query is in flight with no results yet", () => {
    renderField({ loading: true });
    expect(statusPanel()).toHaveTextContent(/Searching/);
  });

  it("shows a no-matches panel when an open query returns nothing", () => {
    renderField({ loading: false });
    expect(statusPanel()).toHaveTextContent(/No matches found/);
  });

  it("shows an error panel when the geocode request failed", () => {
    renderField({ error: true });
    expect(statusPanel()).toHaveTextContent(/Search unavailable/);
  });

  it("announces the status in the polite live region", () => {
    renderField({ error: true });
    expect(screen.getByRole("status")).toHaveTextContent(/Search unavailable/);
  });

  it("renders selectable options (not a status panel) when suggestions exist", () => {
    renderField({ suggestions: [result("123 Main St")] });
    expect(screen.getByRole("option", { name: "123 Main St" })).toBeInTheDocument();
    expect(statusPanel()).toBeNull();
  });

  it("shows nothing when the field is closed", () => {
    renderField({ open: false, loading: true });
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(statusPanel()).toBeNull();
  });

  // A listbox with no owned options is announced as "list box, 0 items" (or
  // nothing at all), and the status text was sitting inside it on a
  // role="presentation" row where list navigation could never reach it. So there
  // must be no listbox at all in these states, and no claim that one opened.
  it.each([
    ["searching", { loading: true }, /Searching/],
    ["no matches", { loading: false }, /No matches found/],
    ["error", { error: true }, /Search unavailable/],
  ])("exposes no listbox in the %s state but still announces the status", (_name, props, text) => {
    renderField(props);
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(screen.queryAllByRole("option")).toHaveLength(0);

    const input = screen.getByRole("combobox");
    expect(input).toHaveAttribute("aria-expanded", "false");
    expect(input).not.toHaveAttribute("aria-controls");

    expect(statusPanel()).toHaveTextContent(text);
    expect(screen.getByRole("status")).toHaveTextContent(text);
  });

  it("marks the field invalid when its lookup failed and points at the error text", () => {
    renderField({ error: true });
    const input = screen.getByRole("combobox");
    expect(input).toHaveAttribute("aria-invalid", "true");

    const described = (input.getAttribute("aria-describedby") ?? "")
      .split(" ")
      .map((refId) => document.getElementById(refId)?.textContent ?? "");
    expect(described.join(" ")).toMatch(/Search unavailable/);
  });

  it("leaves the field valid while a search is merely in flight", () => {
    renderField({ loading: true });
    expect(screen.getByRole("combobox")).not.toHaveAttribute("aria-invalid");
  });
});

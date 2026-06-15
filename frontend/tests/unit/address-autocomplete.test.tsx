import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "../../src/i18n";
import { AddressAutocomplete } from "../../src/components/AddressAutocomplete";
import type { GeocodeResult } from "../../src/types/api";

// The address field is an ARIA 1.2 combobox: keyboard users move a virtual
// "active" option with the arrows (focus stays on the input) and select with
// Enter; Escape dismisses the list. These tests pin that contract so a refactor
// can't silently regress screen-reader/keyboard support.
const results: GeocodeResult[] = [
  { label: "Des Moines, IA", lat: 41.5868, lng: -93.625, type: "city", confidence: 0.9 },
  { label: "Davenport, IA", lat: 41.5236, lng: -90.5776, type: "city", confidence: 0.8 },
];

function setup(onSelect = vi.fn()) {
  render(
    <AddressAutocomplete
      id="origin-input"
      label="Start"
      value="des"
      onValueChange={() => {}}
      suggestions={results}
      onSelect={onSelect}
      open
    />,
  );
  return { onSelect, input: screen.getByRole("combobox") };
}

describe("AddressAutocomplete combobox", () => {
  it("exposes the ARIA combobox/listbox structure", () => {
    const { input } = setup();
    expect(input).toHaveAttribute("aria-expanded", "true");
    expect(input).toHaveAttribute("aria-autocomplete", "list");
    expect(screen.getByRole("listbox")).toBeInTheDocument();
    expect(screen.getAllByRole("option")).toHaveLength(2);
  });

  it("moves the active option with ArrowDown and reflects it via aria-activedescendant", () => {
    const { input } = setup();
    fireEvent.keyDown(input, { key: "ArrowDown" });
    expect(input).toHaveAttribute("aria-activedescendant", "origin-input-opt-0");
    expect(screen.getByRole("option", { name: "Des Moines, IA" })).toHaveAttribute("aria-selected", "true");

    fireEvent.keyDown(input, { key: "ArrowDown" });
    expect(input).toHaveAttribute("aria-activedescendant", "origin-input-opt-1");
  });

  it("wraps from the last option back to the first", () => {
    const { input } = setup();
    fireEvent.keyDown(input, { key: "ArrowUp" }); // -1 → last
    expect(input).toHaveAttribute("aria-activedescendant", "origin-input-opt-1");
  });

  it("selects the active option on Enter", () => {
    const { input, onSelect } = setup();
    fireEvent.keyDown(input, { key: "ArrowDown" });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onSelect).toHaveBeenCalledWith(results[0]);
  });

  it("dismisses the list on Escape and collapses the combobox", () => {
    const { input } = setup();
    fireEvent.keyDown(input, { key: "Escape" });
    expect(input).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("listbox")).toBeNull();
  });

  it("re-opens a dismissed list on ArrowDown, highlighting the first option", () => {
    const { input } = setup();
    fireEvent.keyDown(input, { key: "Escape" });
    expect(input).toHaveAttribute("aria-expanded", "false");

    fireEvent.keyDown(input, { key: "ArrowDown" });
    expect(input).toHaveAttribute("aria-expanded", "true");
    expect(input).toHaveAttribute("aria-activedescendant", "origin-input-opt-0");
  });

  it("re-opens a dismissed list on ArrowUp, highlighting the last option", () => {
    const { input } = setup();
    fireEvent.keyDown(input, { key: "Escape" });

    fireEvent.keyDown(input, { key: "ArrowUp" });
    expect(input).toHaveAttribute("aria-expanded", "true");
    expect(input).toHaveAttribute("aria-activedescendant", "origin-input-opt-1");
  });

  it("announces the suggestion count in a polite live region", () => {
    setup();
    expect(screen.getByRole("status")).toHaveTextContent("2 suggestions available");
  });
});

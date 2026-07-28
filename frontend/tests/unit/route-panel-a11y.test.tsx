import { describe, it, expect, vi } from "vitest";
import { useState } from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import "../../src/i18n";

// Drive the panel deterministically: identity debounce, one predictable
// suggestion per query, inert geolocation.
vi.mock("../../src/hooks/useDebounce", () => ({
  useDebounce: (value: string, _delay: number, min = 0) =>
    value.trim().length >= min ? value : "",
}));
vi.mock("../../src/hooks/useGeolocation", () => ({
  useGeolocation: () => ({ coordinate: null, error: null, loading: false, request: vi.fn() }),
}));
vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
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

import { RoutePanel } from "../../src/components/RoutePanel";

// Stands in for PlanRoutePage: `planning` flips true synchronously the moment
// the plan starts, which is exactly the re-render that used to disable the
// button while it held focus.
function Harness({ onPlan = () => {} }: { onPlan?: () => void }) {
  const [planning, setPlanning] = useState(false);
  return (
    <RoutePanel
      planning={planning}
      onPlan={() => {
        setPlanning(true);
        onPlan();
      }}
    />
  );
}

function confirmBothAddresses() {
  const [originInput, destInput] = screen.getAllByRole("combobox");
  fireEvent.change(originInput, { target: { value: "123 Main" } });
  fireEvent.click(screen.getByRole("option", { name: "Result for 123 Main" }));
  fireEvent.change(destInput, { target: { value: "456 Oak" } });
  fireEvent.click(screen.getByRole("option", { name: "Result for 456 Oak" }));
}

const planButton = () => screen.getByRole("button", { name: /plan route|planning/i });

describe("RoutePanel submit button accessibility", () => {
  it("keeps focus on the Plan button across a submit", () => {
    render(<Harness />);
    confirmBothAddresses();

    const plan = planButton();
    plan.focus();
    expect(document.activeElement).toBe(plan);

    fireEvent.click(plan);

    // Same node, still focused, after `planning` flipped true. The native
    // disabled attribute is what used to blur it, so it must never appear.
    expect(planButton()).toBe(plan);
    expect(document.activeElement).toBe(plan);
    expect(plan).not.toBeDisabled();
    expect(plan).toHaveAttribute("aria-busy", "true");
    expect(plan).toHaveAttribute("aria-disabled", "true");
  });

  it("stays focusable and refuses to plan while the form is incomplete", () => {
    const onPlan = vi.fn();
    render(<Harness onPlan={onPlan} />);

    const plan = planButton();
    plan.focus();
    // A natively disabled button can't take focus at all, which is the gap:
    // keyboard users tab straight past the form's only action.
    expect(document.activeElement).toBe(plan);
    expect(plan).not.toBeDisabled();
    expect(plan).toHaveAttribute("aria-disabled", "true");

    fireEvent.click(plan);
    expect(onPlan).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(plan);
  });

  it("does not re-plan while a plan is already running", () => {
    const onPlan = vi.fn();
    render(<Harness onPlan={onPlan} />);
    confirmBothAddresses();

    const plan = planButton();
    fireEvent.click(plan);
    fireEvent.click(plan);

    expect(onPlan).toHaveBeenCalledTimes(1);
  });

  it("tells both address fields that a suggestion must be picked", () => {
    render(<Harness />);

    const combos = screen.getAllByRole("combobox");
    expect(combos).toHaveLength(2);

    for (const input of combos) {
      const described = (input.getAttribute("aria-describedby") ?? "")
        .split(" ")
        .map((refId) => document.getElementById(refId)?.textContent ?? "");
      expect(described.join(" ")).toMatch(/Choose a suggestion to confirm this address/);
    }
  });
});

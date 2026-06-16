import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import i18n from "../src/i18n";
import { PrintableDirections } from "../src/components/PrintableDirections";
import type { Route } from "../src/types/api";

function route(overrides: Partial<Route> = {}): Route {
  return {
    geometry: "_p_",
    distance_m: 19400,
    duration_s: 1680,
    maneuvers: [
      { type: "start", localized_text: "Head north on Main St", distance_m: 100 },
      { type: "turn", localized_text: "Turn left onto 5th Ave", distance_m: 200 },
      { type: "arrive", localized_text: "Arrive at destination", distance_m: 0 },
    ],
    cameras_avoided_count: 0,
    remaining_cameras: [],
    is_fully_clean: true,
    fastest_comparison: {
      distance_m: 18000,
      duration_s: 1600,
      added_distance_m: 1400,
      added_duration_s: 80,
      geometry: "_fp_",
      cameras_passed_count: 0,
    },
    coverage_warning: null,
    ...overrides,
  };
}

// jsdom doesn't implement window.print; stub it so activation is observable
// without the "Not implemented" noise.
let printSpy: ReturnType<typeof vi.spyOn>;
beforeEach(() => {
  printSpy = vi.spyOn(window, "print").mockImplementation(() => {});
});
afterEach(() => {
  printSpy.mockRestore();
});

describe("PrintableDirections control (US1)", () => {
  it("renders an icon-only print control with an accessible name", () => {
    render(<PrintableDirections route={route()} originLabel="A" destinationLabel="B" />);
    const btn = screen.getByRole("button", { name: /print directions/i });
    expect(btn).toBeInTheDocument();
    // Icon-only: the button has no visible text label, just the aria-label.
    expect(btn).toHaveTextContent("");
  });

  it("opens the print dialog exactly once per activation (FR-003, SC-001)", () => {
    render(<PrintableDirections route={route()} originLabel="A" destinationLabel="B" />);
    fireEvent.click(screen.getByRole("button", { name: /print directions/i }));
    expect(printSpy).toHaveBeenCalledTimes(1);
  });

  it("is not rendered when there is no planned route (parent gate, FR-002)", () => {
    const r: Route | null = null;
    render(<>{r && <PrintableDirections route={r} originLabel="" destinationLabel="" />}</>);
    expect(screen.queryByRole("button", { name: /print directions/i })).not.toBeInTheDocument();
  });
});

describe("PrintableDirections print sheet content", () => {
  function sheet(container: HTMLElement) {
    const el = container.querySelector(".printable-directions");
    if (!el) throw new Error("print sheet not found");
    return el as HTMLElement;
  }

  it("renders every maneuver in order (FR-004, SC-002)", () => {
    const { container } = render(
      <PrintableDirections route={route()} originLabel="A" destinationLabel="B" />,
    );
    const steps = Array.from(sheet(container).querySelectorAll(".print-steps li")).map(
      (li) => li.textContent,
    );
    expect(steps).toEqual([
      "Head north on Main St",
      "Turn left onto 5th Ave",
      "Arrive at destination",
    ]);
  });

  it("shows origin/destination, totals, and a privacy notice (US3 / FR-008, FR-009)", () => {
    const { container } = render(
      <PrintableDirections
        route={route()}
        originLabel="123 Main St"
        destinationLabel="456 Oak Ave"
      />,
    );
    const el = sheet(container);
    expect(el).toHaveTextContent(/From:\s*123 Main St/i);
    expect(el).toHaveTextContent(/To:\s*456 Oak Ave/i);
    // 1680s → 28 min; 19400m → 19.4 km
    expect(el).toHaveTextContent(/28 min/);
    expect(el).toHaveTextContent(/19\.4 km/);
    expect(el).toHaveTextContent(/contains your route|holds your locations|full route/i);
  });

  it("omits camera/coverage notices and any map/control markup (FR-010, FR-005, SC-003)", () => {
    const { container } = render(
      <PrintableDirections
        route={route({
          is_fully_clean: false,
          remaining_cameras: [{ osm_way_id: 42 }],
          coverage_warning: "partial_coverage",
        })}
        originLabel="A"
        destinationLabel="B"
      />,
    );
    const el = sheet(container);
    expect(el.textContent ?? "").not.toMatch(/camera|monitored|unavoidable|coverage/i);
    expect(el.querySelector("button")).toBeNull();
    expect(el.querySelector(".maplibregl-map, canvas")).toBeNull();
  });

  it("still renders a valid, non-blank sheet for a 0- or 1-step route (edge case)", () => {
    const { container } = render(
      <PrintableDirections
        route={route({ maneuvers: [] })}
        originLabel="A"
        destinationLabel="B"
      />,
    );
    const el = sheet(container);
    expect(el).toHaveTextContent(/driving directions/i);
    expect(el.querySelectorAll(".print-steps li")).toHaveLength(0);
  });

  it("reflects a re-planned route, never a stale one (FR-012)", () => {
    const { container, rerender } = render(
      <PrintableDirections
        route={route({ maneuvers: [{ type: "start", localized_text: "Old step", distance_m: 1 }] })}
        originLabel="Old origin"
        destinationLabel="Old dest"
      />,
    );
    rerender(
      <PrintableDirections
        route={route({ maneuvers: [{ type: "start", localized_text: "New step", distance_m: 1 }] })}
        originLabel="New origin"
        destinationLabel="New dest"
      />,
    );
    const el = sheet(container);
    expect(el).toHaveTextContent("New step");
    expect(el).toHaveTextContent("New origin");
    expect(el.textContent ?? "").not.toMatch(/Old step|Old origin/);
  });

  it("renders the sheet in the active language (FR-011)", async () => {
    await i18n.changeLanguage("es");
    try {
      const { container } = render(
        <PrintableDirections route={route()} originLabel="A" destinationLabel="B" />,
      );
      const el = sheet(container);
      expect(el).toHaveTextContent(/Indicaciones de conducción/i);
      expect(el).toHaveTextContent(/Desde:/);
      expect(el).toHaveTextContent(/Hasta:/);
      expect(
        screen.getByRole("button", { name: /imprimir indicaciones/i }),
      ).toBeInTheDocument();
    } finally {
      await i18n.changeLanguage("en");
    }
  });
});

describe("PrintableDirections print structure (US2 pagination targets)", () => {
  it("renders the numbered .print-steps list the print CSS targets", () => {
    const { container } = render(
      <PrintableDirections route={route()} originLabel="A" destinationLabel="B" />,
    );
    const ol = container.querySelector(".printable-directions ol.print-steps");
    expect(ol).not.toBeNull();
    expect(ol?.tagName).toBe("OL");
    expect(ol?.querySelectorAll("li").length).toBe(3);
  });
});

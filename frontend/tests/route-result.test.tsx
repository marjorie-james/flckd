import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "../src/i18n";
import { RouteResult } from "../src/components/RouteResult";
import type { Route } from "../src/types/api";

function route(overrides: Partial<Route> = {}): Route {
  return {
    geometry: "_p_",
    distance_m: 6000,
    duration_s: 600,
    maneuvers: [],
    cameras_avoided_count: 3,
    remaining_cameras: [],
    is_fully_clean: true,
    fastest_comparison: { distance_m: 5000, duration_s: 500, added_distance_m: 1000, added_duration_s: 100, geometry: "_fp_", cameras_passed_count: 2 },
    coverage_warning: null,
    ...overrides,
  };
}

describe("RouteResult camera status", () => {
  it("does not show '0 cameras avoided' or 'avoids all' when no cameras were near the route", () => {
    render(<RouteResult route={route({ cameras_avoided_count: 0 })} />);
    // The reported contradiction must be gone:
    expect(screen.queryByText(/0 cameras avoided/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/avoids all known cameras/i)).not.toBeInTheDocument();
    expect(screen.getByText(/no cameras on your route/i)).toBeInTheDocument();
  });

  it("shows 'avoids all known cameras' and the count when cameras were actually avoided", () => {
    render(<RouteResult route={route({ cameras_avoided_count: 3 })} />);
    expect(screen.getByText(/avoids all known cameras/i)).toBeInTheDocument();
    expect(screen.getByText(/3 cameras avoided/i)).toBeInTheDocument();
  });

  it("does not show the avoided count when the route can't avoid every camera", () => {
    render(
      <RouteResult
        route={route({
          is_fully_clean: false,
          cameras_avoided_count: 3,
          remaining_cameras: [{ osm_way_id: 42 }],
        })}
      />,
    );
    expect(screen.queryByText(/cameras avoided/i)).not.toBeInTheDocument();
    // The minimum-exposure message is surfaced by RouteNotice, not repeated here.
    expect(screen.queryByText(/no fully camera-free route/i)).not.toBeInTheDocument();
    // The route still reports the unavoidable camera via the remaining-cameras stat.
    expect(screen.getByText(/1 unavoidable camera on route/i)).toBeInTheDocument();
  });
});

describe("RouteResult print control (013)", () => {
  it("mounts the print control at the top of the directions section", () => {
    const { container } = render(
      <RouteResult
        route={route({ maneuvers: [{ type: "start", localized_text: "Go", distance_m: 1 }] })}
      />,
    );
    const header = container.querySelector(".directions-header");
    expect(header).not.toBeNull();
    const btn = screen.getByRole("button", { name: /print directions/i });
    expect(header).toContainElement(btn);
    // The control sits before the on-screen <ol class="directions">.
    const ol = container.querySelector("ol.directions")!;
    expect(header!.compareDocumentPosition(ol) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("forwards the confirmed origin/destination labels into the print sheet (label lift)", () => {
    const { container } = render(
      <RouteResult route={route()} originLabel="123 Main St" destinationLabel="456 Oak Ave" />,
    );
    const sheet = container.querySelector(".printable-directions")!;
    expect(sheet).toHaveTextContent(/From:\s*123 Main St/i);
    expect(sheet).toHaveTextContent(/To:\s*456 Oak Ave/i);
  });

  it("updates the printed labels after a re-plan, never showing the stale trip (FR-012)", () => {
    const { container, rerender } = render(
      <RouteResult route={route()} originLabel="Old origin" destinationLabel="Old dest" />,
    );
    rerender(<RouteResult route={route()} originLabel="New origin" destinationLabel="New dest" />);
    const sheet = container.querySelector(".printable-directions")!;
    expect(sheet).toHaveTextContent("New origin");
    expect(sheet.textContent ?? "").not.toMatch(/Old origin|Old dest/);
  });
});

describe("RouteResult comparison trade-off (009)", () => {
  const fc = (overrides = {}) => ({
    distance_m: 5000,
    duration_s: 500,
    added_distance_m: 1000,
    added_duration_s: 100,
    geometry: "_fp_",
    cameras_passed_count: 2,
    ...overrides,
  });

  it("shows the route's travel time, the added distance, and toggles the comparison (US1)", () => {
    const onToggle = vi.fn();
    render(
      <RouteResult
        route={route({ duration_s: 600 })}
        showComparison
        onToggleComparison={onToggle}
      />,
    );

    // Recommended route's own travel time (FR-003): 600s → 10 min.
    expect(screen.getByText(/^10 min$/)).toBeInTheDocument();
    // Added distance secondary detail (FR-004a): 1000 m → +1.0 km.
    expect(screen.getByText(/\+1\.0 km vs fastest/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /hide fastest route/i }));
    expect(onToggle).toHaveBeenCalledTimes(1);
  });

  it("indicates how many cameras the fastest route would pass (US3 / FR-007)", () => {
    render(<RouteResult route={route({ fastest_comparison: fc({ cameras_passed_count: 2 }) })} />);
    expect(screen.getByText(/fastest route passes 2 cameras/i)).toBeInTheDocument();
  });

  it("shows no added-time/-distance rows or toggle when avoidance is free (US2 / FR-006)", () => {
    render(
      <RouteResult route={route({ fastest_comparison: fc({ added_duration_s: 0, added_distance_m: 0 }) })} />,
    );
    expect(screen.queryByText(/vs fastest/i)).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /fastest route/i })).not.toBeInTheDocument();
  });
});

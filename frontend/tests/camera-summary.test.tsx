import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import "../src/i18n";
import { CameraSummary } from "../src/components/CameraSummary";
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

describe("CameraSummary", () => {
  it("shows the avoided-camera count", () => {
    render(<CameraSummary route={route()} />);
    expect(screen.getByText(/3 cameras avoided/i)).toBeInTheDocument();
  });

  // The minimum-exposure headline is announced prominently by RouteNotice (tested
  // separately); CameraSummary just lists the unavoidable cameras that remain.
  it("lists remaining cameras in the minimum-exposure case", () => {
    render(
      <CameraSummary
        route={route({ is_fully_clean: false, remaining_cameras: [{ osm_way_id: 42 }] })}
      />
    );
    expect(screen.getByText(/1 unavoidable/i)).toBeInTheDocument();
  });

  it("does not show the avoided count when the route can't avoid every camera", () => {
    render(
      <CameraSummary
        route={route({
          is_fully_clean: false,
          cameras_avoided_count: 3,
          remaining_cameras: [{ osm_way_id: 42 }],
        })}
      />
    );
    expect(screen.queryByText(/cameras avoided/i)).not.toBeInTheDocument();
  });

  it("does not show '0 cameras avoided' when no cameras were near the route", () => {
    render(<CameraSummary route={route({ cameras_avoided_count: 0, is_fully_clean: true })} />);
    expect(screen.queryByText(/0 cameras avoided/i)).not.toBeInTheDocument();
    expect(screen.getByText(/no cameras on your route/i)).toBeInTheDocument();
  });

  it("uses singular grammar for a single avoided camera", () => {
    render(<CameraSummary route={route({ cameras_avoided_count: 1 })} />);
    expect(screen.getByText(/^1 camera avoided$/i)).toBeInTheDocument();
  });
});

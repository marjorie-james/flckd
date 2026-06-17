import { describe, it, expect, vi, beforeEach } from "vitest";
import { render } from "@testing-library/react";
import type { Coordinate, Route } from "../../src/types/api";

// Everything the hoisted vi.mock factories need is built inside vi.hoisted so it
// exists before the mocks are applied. A recording fake of the maplibre Map lets
// us assert the camera + marker calls MapView makes (jsdom has no WebGL).
const H = vi.hoisted(() => {
  const calls = {
    flyTo: [] as unknown[],
    jumpTo: [] as unknown[],
    setData: [] as GeoJSON.FeatureCollection[],
    addSource: [] as string[],
    addLayer: [] as string[],
    addLayerBefore: [] as Array<[string, string | undefined]>,
    disabled: [] as string[],
    construct: [] as unknown[],
    fitBounds: [] as unknown[],
  };
  type Src = { data: unknown; setData: (d: unknown) => void };
  const state = { sources: {} as Record<string, Src>, reduced: false };

  class FakeMap {
    constructor(opts?: unknown) { calls.construct.push(opts); }
    // Interaction handlers record any (incorrect) attempt to disable them (FR-008).
    dragPan = { disable: () => calls.disabled.push("dragPan") };
    scrollZoom = { disable: () => calls.disabled.push("scrollZoom") };
    touchZoomRotate = { disable: () => calls.disabled.push("touchZoomRotate") };
    isStyleLoaded() { return true; }
    getSource(id: string) { return state.sources[id]; }
    addSource(id: string, cfg: { data: unknown }) {
      calls.addSource.push(id);
      const src: Src = { data: cfg.data, setData: (d: unknown) => { src.data = d; calls.setData.push(d as GeoJSON.FeatureCollection); } };
      state.sources[id] = src;
      src.setData(cfg.data);
    }
    addLayer(cfg: { id: string }, beforeId?: string) {
      calls.addLayer.push(cfg.id);
      calls.addLayerBefore.push([cfg.id, beforeId]);
    }
    getLayer(id: string) { return calls.addLayer.includes(id) ? { id } : undefined; }
    flyTo(o: unknown) { calls.flyTo.push(o); }
    jumpTo(o: unknown) { calls.jumpTo.push(o); }
    fitBounds(b: unknown, o: unknown) { calls.fitBounds.push([b, o]); }
    once() {}
    off() {}
    remove() {}
  }

  return { calls, state, FakeMap };
});

vi.mock("../../src/utils/reducedMotion", () => ({ prefersReducedMotion: () => H.state.reduced }));
vi.mock("maplibre-gl", () => ({
  default: { Map: H.FakeMap, LngLatBounds: class { extend() { return this; } } },
}));

// CameraLayer uses map APIs the FakeMap here doesn't implement and is unrelated
// to the origin-recenter behavior under test; stub it out.
vi.mock("../../src/components/CameraLayer", () => ({ CameraLayer: () => null }));

import { MapView } from "../../src/components/MapView";
import type { RegionBounds } from "../../src/types/api";

const CAPITOL: Coordinate = { lat: 41.591200, lng: -93.603000 };
// A sample covered-region bbox [[w,s],[e,n]] the map should frame to on load.
const REGION: RegionBounds = [[-96.64, 40.37], [-90.14, 43.50]];
const lastFeature = () => H.calls.setData[H.calls.setData.length - 1];

describe("MapView origin recenter + marker", () => {
  beforeEach(() => {
    H.calls.flyTo = []; H.calls.jumpTo = []; H.calls.setData = [];
    H.calls.addSource = []; H.calls.addLayer = []; H.calls.disabled = [];
    H.calls.construct = []; H.calls.fitBounds = [];
    H.state.sources = {};
    H.state.reduced = false;
  });

  it("frames the map on the covered region when its bounds load (page load)", () => {
    render(<MapView route={null} origin={null} regionBounds={REGION} />);

    expect(H.calls.fitBounds).toHaveLength(1);
    expect(H.calls.fitBounds[0]).toEqual([REGION, { padding: 24, duration: 0 }]);
  });

  it("starts at a neutral view with no region hardcoded until bounds arrive", () => {
    render(<MapView route={null} origin={null} regionBounds={null} />);

    expect(H.calls.construct[0]).toMatchObject({ center: [0, 0], zoom: 1 });
    expect(H.calls.fitBounds).toHaveLength(0); // nothing to frame yet
  });

  it("flies to the origin at street level and drops a single marker (US1)", () => {
    render(<MapView route={null} origin={CAPITOL} />);

    expect(H.calls.flyTo).toHaveLength(1);
    expect(H.calls.flyTo[0]).toMatchObject({ center: [CAPITOL.lng, CAPITOL.lat], zoom: 16 });
    expect(H.calls.addSource).toContain("origin");
    expect(H.calls.addLayer).toContain("origin-point");
    expect(lastFeature().features).toHaveLength(1);
    expect(lastFeature().features[0].geometry).toEqual({
      type: "Point", coordinates: [CAPITOL.lng, CAPITOL.lat],
    });
  });

  it("does not disable map interaction — the user keeps manual control (FR-008)", () => {
    render(<MapView route={null} origin={CAPITOL} />);
    expect(H.calls.disabled).toEqual([]);
  });

  it("moves the single marker on re-selection, latest wins (FR-006/012)", () => {
    const { rerender } = render(<MapView route={null} origin={CAPITOL} />);
    const next: Coordinate = { lat: 41.5868, lng: -93.625 };
    rerender(<MapView route={null} origin={next} />);

    expect(H.calls.flyTo[H.calls.flyTo.length - 1]).toMatchObject({ center: [next.lng, next.lat], zoom: 16 });
    expect(lastFeature().features).toHaveLength(1);
    expect(lastFeature().features[0].geometry.coordinates).toEqual([next.lng, next.lat]);
  });

  it("clears the marker and does not move the map when origin is unset (FR-007/013)", () => {
    const { rerender } = render(<MapView route={null} origin={CAPITOL} />);
    const flyCountAfterSet = H.calls.flyTo.length;
    rerender(<MapView route={null} origin={null} />);

    expect(H.calls.flyTo).toHaveLength(flyCountAfterSet); // no new camera move
    expect(H.calls.jumpTo).toHaveLength(0);
    expect(lastFeature().features).toHaveLength(0); // marker removed
  });

  it("jumps instantly (no fly) when reduced motion is preferred (US2 / FR-004)", () => {
    H.state.reduced = true;
    render(<MapView route={null} origin={CAPITOL} />);

    expect(H.calls.jumpTo).toHaveLength(1);
    expect(H.calls.jumpTo[0]).toMatchObject({ center: [CAPITOL.lng, CAPITOL.lat], zoom: 16 });
    expect(H.calls.flyTo).toHaveLength(0);
  });
});

describe("MapView comparison route (009)", () => {
  // Real Iowa polylines so decodePolyline yields non-empty coordinates; the route
  // and the comparison use distinct lines.
  const baseRoute = (fc: Partial<Route["fastest_comparison"]> = {}): Route => ({
    geometry: "__ajnA~n{oqD~hbE_ibE",
    distance_m: 8200,
    duration_s: 960,
    maneuvers: [],
    cameras_avoided_count: 3,
    remaining_cameras: [],
    is_fully_clean: true,
    fastest_comparison: {
      distance_m: 7000,
      duration_s: 780,
      added_distance_m: 1200,
      added_duration_s: 180,
      geometry: "_ahknA~pbqqD~{|F_mpG",
      cameras_passed_count: 3,
      ...fc,
    },
    coverage_warning: null,
  });

  const compData = () =>
    H.state.sources["comparison"]?.data as GeoJSON.Feature<GeoJSON.LineString> | undefined;

  beforeEach(() => {
    H.calls.setData = [];
    H.calls.addSource = [];
    H.calls.addLayer = [];
    H.calls.addLayerBefore = [];
    H.state.sources = {};
  });

  it("draws the comparison line beneath the route line when avoidance costs time (US1)", () => {
    render(<MapView route={baseRoute()} origin={null} showComparison />);

    expect(H.calls.addLayer).toContain("route-line");
    expect(H.calls.addLayer).toContain("comparison-line");
    // Inserted beneath the route line so the recommended route stays on top (FR-008).
    expect(H.calls.addLayerBefore).toContainEqual(["comparison-line", "route-line"]);
    expect(compData()?.geometry.coordinates.length).toBeGreaterThan(0);
  });

  it("draws no comparison line when avoidance is free (US2 / SC-002)", () => {
    render(<MapView route={baseRoute({ added_duration_s: 0 })} origin={null} showComparison />);
    expect(H.calls.addLayer).not.toContain("comparison-line");
  });

  it("draws no comparison line when dismissed (showComparison=false / FR-002a)", () => {
    render(<MapView route={baseRoute()} origin={null} showComparison={false} />);
    expect(H.calls.addLayer).not.toContain("comparison-line");
  });

  it("clears a previously drawn comparison line when it is later hidden (FR-009)", () => {
    const { rerender } = render(<MapView route={baseRoute()} origin={null} showComparison />);
    expect(compData()?.geometry.coordinates.length).toBeGreaterThan(0);

    rerender(<MapView route={baseRoute()} origin={null} showComparison={false} />);
    expect(compData()?.geometry.coordinates).toHaveLength(0);
  });

  it("clears the previous route line when a new route decodes to empty geometry", () => {
    const { rerender } = render(<MapView route={baseRoute()} origin={null} showComparison />);
    // A real route was drawn into the route source.
    const routeData = () =>
      H.state.sources["route"]?.data as GeoJSON.Feature<GeoJSON.LineString> | undefined;
    expect(routeData()?.geometry.coordinates.length).toBeGreaterThan(0);

    // A new, non-null route whose geometry decodes to no points must not leave the
    // previous line under the new plan — the route source is emptied.
    rerender(<MapView route={baseRoute({})} origin={null} showComparison />);
    H.calls.setData = [];
    rerender(<MapView route={{ ...baseRoute(), geometry: "" }} origin={null} showComparison />);

    const last = lastFeature() as unknown as GeoJSON.Feature<GeoJSON.LineString>;
    expect(last.geometry).toEqual({ type: "LineString", coordinates: [] });
    expect(routeData()?.geometry.coordinates).toHaveLength(0);
  });
});

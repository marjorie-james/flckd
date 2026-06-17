import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, act } from "@testing-library/react";

// CameraLayer renders viewport cameras as a clustered MapLibre source, expands
// clusters on tap, and shows a details popup. Hooks + maplibre are mocked; the
// map is a recording fake passed as a prop.
const H = vi.hoisted(() => {
  const popups: Array<{ html: string; removed: boolean; closeHandlers: Array<() => void> }> = [];
  class FakePopup {
    html = "";
    removed = false;
    closeHandlers: Array<() => void> = [];
    constructor() {}
    setLngLat() { return this; }
    setHTML(h: string) { this.html = h; return this; }
    addTo() { popups.push(this); return this; }
    on(type: string, fn: () => void) { if (type === "close") this.closeHandlers.push(fn); return this; }
    remove() { this.removed = true; this.closeHandlers.forEach((f) => f()); }
  }
  return {
    data: { cameras: [] as unknown[] },
    reduced: false,
    bboxes: [] as Array<string | null>,
    debounceDelays: [] as number[],
    popups,
    FakePopup,
  };
});

vi.mock("../../src/services/cameraApi", () => ({
  useCameras: (bbox: string | null) => { H.bboxes.push(bbox); return { data: H.data }; },
}));
vi.mock("../../src/hooks/useDebounce", () => ({
  useDebounce: (v: string, delay: number) => { H.debounceDelays.push(delay); return v; },
}));
vi.mock("../../src/utils/reducedMotion", () => ({ prefersReducedMotion: () => H.reduced }));
vi.mock("maplibre-gl", () => ({ default: { Popup: H.FakePopup } }));

import { CameraLayer } from "../../src/components/CameraLayer";

const BOUNDS = { getWest: () => -93.7, getSouth: () => 41.5, getEast: () => -93.5, getNorth: () => 41.7 };
const VERIFIED = { id: 1, location: { lat: 41.61, lng: -93.61 }, snapped_location: { lat: 41.611, lng: -93.611 }, segment: [[-93.612, 41.611], [-93.610, 41.611]], facing_direction: 90, camera_type: "flock", confidence: 0.9, verification_status: "verified" };
const DISPUTED = { id: 2, location: { lat: 41.62, lng: -93.62 }, snapped_location: null, segment: null, facing_direction: null, camera_type: "flock", confidence: 0.3, verification_status: "disputed" };

type SourceCfg = { cluster?: boolean; data: GeoJSON.FeatureCollection };
type LayerCfg = { id: string; paint?: Record<string, unknown>; layout?: Record<string, unknown>; minzoom?: number };

function makeFakeMap(bounds = BOUNDS) {
  const handlers: Record<string, Array<(...a: unknown[]) => void>> = {};
  const calls = {
    addSource: [] as Array<{ id: string; cfg: SourceCfg }>,
    addLayer: [] as LayerCfg[],
    setData: [] as GeoJSON.FeatureCollection[],
    easeTo: [] as unknown[],
    jumpTo: [] as unknown[],
  };
  let added = false;
  const source = {
    setData: (fc: GeoJSON.FeatureCollection) => calls.setData.push(fc),
    getClusterExpansionZoom: () => Promise.resolve(14),
  };
  return {
    calls,
    getBounds: () => bounds,
    isStyleLoaded: () => true,
    getLayer: () => undefined,
    getSource: () => (added ? source : undefined),
    addSource: (id: string, cfg: SourceCfg) => { calls.addSource.push({ id, cfg }); added = true; },
    addLayer: (cfg: LayerCfg) => calls.addLayer.push(cfg),
    hasImage: () => false,
    addImage: () => {},
    queryRenderedFeatures: () => [{ properties: { cluster_id: 7 }, geometry: { type: "Point", coordinates: [-93.6, 41.6] } }],
    easeTo: (o: unknown) => calls.easeTo.push(o),
    jumpTo: (o: unknown) => calls.jumpTo.push(o),
    on(type: string, a: unknown, b?: unknown) {
      const key = typeof a === "function" ? type : `${type}:${a}`;
      (handlers[key] ||= []).push((typeof a === "function" ? a : b) as (...x: unknown[]) => void);
    },
    off() {},
    once() {},
    fire(type: string, ...args: unknown[]) { (handlers[type] || []).forEach((f) => f(...args)); },
    fireLayer(type: string, layer: string, ...args: unknown[]) { (handlers[`${type}:${layer}`] || []).forEach((f) => f(...args)); },
  };
}

beforeEach(() => { H.data = { cameras: [] }; H.reduced = false; H.bboxes = []; H.debounceDelays = []; H.popups.length = 0; });

describe("CameraLayer viewport fetch (T002)", () => {
  it("computes a bbox from the map and fetches cameras for it (debounced)", () => {
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    expect(H.bboxes).toContain("-93.7,41.5,-93.5,41.7");
    expect(H.debounceDelays).toContain(300); // bbox goes through the debounce
  });

  it("recomputes the bbox when the map settles (moveend)", () => {
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    act(() => map.fire("moveend"));
    expect(H.bboxes.filter((b) => b === "-93.7,41.5,-93.5,41.7").length).toBeGreaterThan(0);
  });
});

describe("CameraLayer clustered render (T005)", () => {
  it("adds a clustered source and the cluster/count/point layers", () => {
    H.data = { cameras: [VERIFIED, DISPUTED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    expect(map.calls.addSource[0].cfg.cluster).toBe(true);
    expect(map.calls.addSource[0].cfg.data.features).toHaveLength(2);
    const ids = map.calls.addLayer.map((l) => l.id);
    expect(ids).toEqual(expect.arrayContaining(["camera-clusters", "camera-cluster-count", "camera-points"]));
  });

  it("styles disputed/low-confidence points distinctly (data-driven case)", () => {
    H.data = { cameras: [VERIFIED, DISPUTED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    const point = map.calls.addLayer.find((l) => l.id === "camera-points");
    expect(JSON.stringify(point.paint["circle-color"])).toContain("case");
    expect(JSON.stringify(point.paint["circle-color"])).toContain("suspect");
  });

  it("updates the source on a new viewport result via setData", () => {
    H.data = { cameras: [VERIFIED] };
    const map = makeFakeMap();
    const { rerender } = render(<CameraLayer map={map as never} />);
    H.data = { cameras: [VERIFIED, DISPUTED] };
    rerender(<CameraLayer map={map as never} />);
    expect(map.calls.setData.at(-1)!.features).toHaveLength(2);
  });
});

describe("CameraLayer directionality + watched stretch", () => {
  it("snaps dots to the road, draws the watched stretch, a cone for directional and a ring for 360 cameras", () => {
    H.data = { cameras: [VERIFIED, DISPUTED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);

    const ids = map.calls.addLayer.map((l) => l.id);
    expect(ids).toEqual(expect.arrayContaining(["camera-segment-lines", "camera-360-ring", "camera-cones"]));

    // VERIFIED is directional (faces 90°) and is drawn at its snapped road point.
    const points = map.calls.addSource.find((s) => s.id === "cameras")!.cfg.data.features;
    const v = points.find((f) => f.properties!.id === 1)!;
    expect(v.geometry).toMatchObject({ coordinates: [-93.611, 41.611] }); // snapped, not the raw point
    expect(v.properties).toMatchObject({ directional: true, facing_direction: 90 });
    // DISPUTED has no facing direction → omnidirectional (360, gets the ring).
    const d = points.find((f) => f.properties!.id === 2)!;
    expect(d.properties).toMatchObject({ directional: false });

    // The watched stretch is its own line source; only the snapped camera has one.
    const seg = map.calls.addSource.find((s) => s.id === "camera-segments")!.cfg.data.features;
    expect(seg).toHaveLength(1);
    expect(seg[0].geometry.type).toBe("LineString");

    // The cone is rotated to the bearing the camera faces.
    const cone = map.calls.addLayer.find((l) => l.id === "camera-cones")!;
    expect(JSON.stringify(cone.layout!["icon-rotate"])).toContain("facing_direction");
  });

  it("gates the watched-stretch lines to higher zoom so dense viewports stay light", () => {
    // The segment lines are not clustered, so they must not draw at every zoom;
    // a minzoom keeps a dense viewport down to just the clustered dots.
    H.data = { cameras: [VERIFIED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    const seg = map.calls.addLayer.find((l) => l.id === "camera-segment-lines")!;
    expect(seg.minzoom).toBe(14);
  });
});

describe("CameraLayer cluster expand (T007)", () => {
  it("zooms to the cluster's expansion zoom on click (easeTo)", async () => {
    H.data = { cameras: [VERIFIED, DISPUTED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    await act(async () => { map.fireLayer("click", "camera-clusters", { features: [{ properties: { cluster_id: 7 }, geometry: { type: "Point", coordinates: [-93.6, 41.6] } }] }); });
    expect(map.calls.easeTo[0]).toMatchObject({ center: [-93.6, 41.6], zoom: 14 });
    expect(map.calls.jumpTo).toHaveLength(0);
  });

  it("jumps instantly under reduced motion", async () => {
    H.reduced = true;
    H.data = { cameras: [VERIFIED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    await act(async () => { map.fireLayer("click", "camera-clusters", { features: [{ properties: { cluster_id: 7 }, geometry: { type: "Point", coordinates: [-93.6, 41.6] } }] }); });
    expect(map.calls.jumpTo[0]).toMatchObject({ center: [-93.6, 41.6], zoom: 14 });
    expect(map.calls.easeTo).toHaveLength(0);
  });
});

describe("CameraLayer inspect + dismiss (T009)", () => {
  it("opens a details popup with reference fields on camera click", () => {
    H.data = { cameras: [DISPUTED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    act(() => map.fireLayer("click", "camera-points", {
      features: [{ geometry: { type: "Point", coordinates: [-93.62, 41.62] }, properties: { camera_type: "flock", confidence: 0.3, verification_status: "disputed" } }],
    }));
    expect(H.popups).toHaveLength(1);
    expect(H.popups[0].html).toContain("flock");
    expect(H.popups[0].html).toContain("disputed");
    expect(H.popups[0].html).not.toContain("undefined");
  });

  it("dismisses the popup via Escape (FR-015/SC-010)", () => {
    H.data = { cameras: [VERIFIED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    act(() => map.fireLayer("click", "camera-points", {
      features: [{ geometry: { type: "Point", coordinates: [-93.61, 41.61] }, properties: { camera_type: "flock", confidence: 0.9, verification_status: "verified" } }],
    }));
    act(() => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })));
    expect(H.popups[0].removed).toBe(true);
  });

  it("escapes HTML in camera fields — no markup injection in the popup", () => {
    H.data = { cameras: [VERIFIED] };
    const map = makeFakeMap();
    render(<CameraLayer map={map as never} />);
    const xss = "<img src=x onerror=alert(1)>";
    act(() => map.fireLayer("click", "camera-points", {
      features: [{ geometry: { type: "Point", coordinates: [-93.6, 41.6] }, properties: { camera_type: xss, confidence: 0.9, verification_status: "verified" } }],
    }));
    expect(H.popups[0].html).not.toContain("<img");
    expect(H.popups[0].html).toContain("&lt;img");
  });
});

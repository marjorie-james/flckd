import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, act } from "@testing-library/react";
import type { RegionBounds } from "../../src/types/api";

// The map boots at a neutral world view before the covered region's bounds
// arrive; revealing it then would flash the whole-world basemap. This asserts the
// canvas stays hidden (opacity 0) until the style loads AND the region is framed,
// then fades in. A controllable fake whose style is NOT loaded up front lets us
// drive the deferred "load" path that the main map-view suite's always-loaded
// fake can't reach.
const H = vi.hoisted(() => {
  const loadHandlers: Array<() => void> = [];
  class FakeMap {
    isStyleLoaded() { return false; } // force the deferred once("load") path
    getSource() { return undefined; }
    addSource() {} addLayer() {} getLayer() { return undefined; }
    flyTo() {} jumpTo() {}
    fitBounds() {}
    getZoom() { return 5; }
    getBounds() { return { _bounds: "framed" }; }
    setMinZoom() {} setMaxBounds() {}
    once(event: string, cb: () => void) { if (event === "load") loadHandlers.push(cb); }
    off() {} remove() {}
  }
  const fireLoad = () => { for (const cb of loadHandlers.splice(0)) cb(); };
  return { FakeMap, fireLoad };
});

vi.mock("../../src/utils/reducedMotion", () => ({ prefersReducedMotion: () => false }));
vi.mock("maplibre-gl", () => ({
  default: { Map: H.FakeMap, LngLatBounds: class { extend() { return this; } } },
}));
vi.mock("../../src/components/CameraLayer", () => ({ CameraLayer: () => null }));

import { MapView } from "../../src/components/MapView";

const REGION: RegionBounds = [[-96.64, 40.37], [-90.14, 43.50]];
const opacityOf = (c: HTMLElement) => (c.querySelector(".map-view") as HTMLElement).style.opacity;

describe("MapView reveal (no world-view flash)", () => {
  beforeEach(() => { H.fireLoad(); /* drain any leftover handlers */ });

  it("keeps the canvas hidden until the style loads and the region is framed", () => {
    const { container } = render(<MapView route={null} origin={null} regionBounds={REGION} />);

    // Style hasn't loaded yet → framing is deferred → canvas stays hidden.
    expect(opacityOf(container)).toBe("0");

    // Style loads → the deferred frame runs and reveals the canvas.
    act(() => { H.fireLoad(); });
    expect(opacityOf(container)).toBe("1");
  });

  it("still reveals a bounds-less deployment once the style loads (fallback)", () => {
    const { container } = render(<MapView route={null} origin={null} regionBounds={null} />);

    // Nothing to frame, style not loaded yet → hidden.
    expect(opacityOf(container)).toBe("0");

    // Once the style loads, the fallback reveals the neutral map rather than
    // leaving the pane blank forever.
    act(() => { H.fireLoad(); });
    expect(opacityOf(container)).toBe("1");
  });
});

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render } from "@testing-library/react";

// A fake maplibre Map whose style is NOT loaded, so a languageChanged that fires
// before "load" registers a deferred map.once("load", ...) handler. We record the
// once/off calls to assert the label-language effect removes its pending load
// handler on unmount (parity with the route/origin effects).
const H = vi.hoisted(() => {
  const calls = {
    once: [] as Array<[string, () => void]>,
    off: [] as Array<[string, () => void]>,
  };
  class FakeMap {
    isStyleLoaded() { return false; }
    getLayer() { return undefined; }
    setLayoutProperty() {}
    getSource() { return undefined; }
    addSource() {}
    addLayer() {}
    flyTo() {}
    jumpTo() {}
    fitBounds() {}
    once(ev: string, cb: () => void) { calls.once.push([ev, cb]); }
    off(ev: string, cb: () => void) { calls.off.push([ev, cb]); }
    remove() {}
  }
  return { calls, FakeMap };
});

vi.mock("../../src/utils/reducedMotion", () => ({ prefersReducedMotion: () => false }));
vi.mock("maplibre-gl", () => ({
  default: { Map: H.FakeMap, LngLatBounds: class { extend() { return this; } } },
}));
vi.mock("../../src/components/CameraLayer", () => ({ CameraLayer: () => null }));

import { MapView } from "../../src/components/MapView";
import i18n from "../../src/i18n";

describe("MapView label-language effect cleanup", () => {
  beforeEach(() => {
    H.calls.once = [];
    H.calls.off = [];
  });

  it("removes a pending load handler on unmount when a switch fired before style load", async () => {
    const { unmount } = render(<MapView route={null} origin={null} />);

    // A language switch before the style loads registers a deferred load handler.
    await i18n.changeLanguage("es");
    const pending = H.calls.once.find(([ev]) => ev === "load");
    expect(pending).toBeDefined();

    unmount();

    // The same deferred handler must be removed (not just the i18n listener).
    expect(H.calls.off).toContainEqual(pending);

    await i18n.changeLanguage("en");
  });
});

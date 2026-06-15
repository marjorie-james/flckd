import { describe, it, expect, vi, afterEach } from "vitest";
import { geocodeSearch } from "../src/services/geocodeApi";
import type { GeocodeResult } from "../src/types/api";

// geocodeSearch sorts suggestions by confidence so the most precise match
// (an exact street address) surfaces at the top of the autocomplete list.
function stubFetch(body: unknown) {
  const res = { ok: true, status: 200, statusText: "OK", json: async () => body } as Response;
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(res));
}

const result = (label: string, confidence: number): GeocodeResult => ({
  label,
  lat: 0,
  lng: 0,
  type: "x",
  confidence,
});

describe("geocodeSearch result ordering", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("sorts suggestions by confidence, most confident first", async () => {
    // Returned out of order by the backend; the exact house (1.0) must lead.
    stubFetch({ results: [result("city", 0.53), result("house", 1.0), result("street", 0.87)] });

    const { results } = await geocodeSearch("anything");

    expect(results.map((r) => r.label)).toEqual(["house", "street", "city"]);
  });

  it("keeps the backend order for equal-confidence ties (stable sort)", async () => {
    stubFetch({ results: [result("first", 0.5), result("second", 0.5), result("top", 1.0)] });

    const { results } = await geocodeSearch("anything");

    expect(results.map((r) => r.label)).toEqual(["top", "first", "second"]);
  });

  it("tolerates an empty result set", async () => {
    stubFetch({ results: [] });

    await expect(geocodeSearch("anything")).resolves.toEqual({ results: [] });
  });
});

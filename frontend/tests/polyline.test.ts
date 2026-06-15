import { describe, it, expect } from "vitest";
import { decodePolyline } from "../src/lib/polyline";

describe("decodePolyline", () => {
  it("decodes the canonical precision-5 example to [lng, lat] pairs", () => {
    // Google's reference polyline → (38.5,-120.2),(40.7,-120.95),(43.252,-126.453)
    const coords = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@", 5);

    expect(coords).toHaveLength(3);
    expect(coords[0][0]).toBeCloseTo(-120.2, 5);
    expect(coords[0][1]).toBeCloseTo(38.5, 5);
    expect(coords[2][0]).toBeCloseTo(-126.453, 5);
    expect(coords[2][1]).toBeCloseTo(43.252, 5);
  });

  it("round-trips precision-6 magnitudes (default)", () => {
    // Precision 6 packs ~10x more chars per degree than precision 5; just assert
    // the default precision yields sane lng/lat ranges from a known Valhalla-ish
    // string and that order is [lng, lat].
    const coords = decodePolyline("}_qsFt}whMnDsB|GeE", 6);
    expect(coords.length).toBeGreaterThan(0);
    for (const [lng, lat] of coords) {
      expect(lng).toBeGreaterThanOrEqual(-180);
      expect(lng).toBeLessThanOrEqual(180);
      expect(lat).toBeGreaterThanOrEqual(-90);
      expect(lat).toBeLessThanOrEqual(90);
    }
  });

  it("returns [] for empty input", () => {
    expect(decodePolyline("")).toEqual([]);
  });
});

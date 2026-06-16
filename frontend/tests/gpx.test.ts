import { describe, it, expect } from "vitest";
import { buildGpx } from "../src/lib/gpx";

describe("buildGpx", () => {
  // coords are [lng, lat] (GeoJSON order, as decodePolyline returns).
  const coords: [number, number][] = [
    [-93.625, 41.587],
    [-93.62, 41.59],
  ];

  it("emits a GPX 1.1 track with the points as <trkpt> in lat/lon order", () => {
    const gpx = buildGpx(coords);
    expect(gpx).toContain('<?xml version="1.0" encoding="UTF-8"?>');
    expect(gpx).toContain('<gpx version="1.1" creator="flckd"');
    expect(gpx).toContain("<trk>");
    expect(gpx).toContain("<trkseg>");
    // lng,lat in => lat=..., lon=... out
    expect(gpx).toContain('<trkpt lat="41.587000" lon="-93.625000"/>');
    expect(gpx).toContain('<trkpt lat="41.590000" lon="-93.620000"/>');
  });

  it("includes one trkpt per coordinate", () => {
    const gpx = buildGpx(coords);
    expect(gpx.match(/<trkpt /g)).toHaveLength(2);
  });

  it("XML-escapes the track name", () => {
    const gpx = buildGpx(coords, "a & b <c>");
    expect(gpx).toContain("<name>a &amp; b &lt;c&gt;</name>");
  });
});

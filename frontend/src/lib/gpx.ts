// Build a GPX 1.1 document from a route's geometry.
//
// The point of GPX export is FAITHFULNESS: the file holds flckd's exact
// camera-avoided line as a track (<trk>), so a track-following navigator (e.g.
// OsmAnd, a GPS device) follows THIS path instead of computing its own — which
// is what would have driven the user back past the cameras we avoided. A track
// (not a <rte>) is the most widely supported "follow this exact line" form.
//
// Built entirely client-side: the coordinates never leave the device except as
// the file the user explicitly saves (see RouteExport's warning).
import { escapeHtml } from "./escapeHtml";

// coords are [lng, lat] pairs (GeoJSON axis order, as decodePolyline returns).
// name is a static label — no user input — but escaped defensively anyway.
export function buildGpx(coords: [number, number][], name = "flckd route"): string {
  const pts = coords
    .map(([lng, lat]) => `      <trkpt lat="${lat.toFixed(6)}" lon="${lng.toFixed(6)}"/>`)
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="flckd" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>${escapeHtml(name)}</name>
    <trkseg>
${pts}
    </trkseg>
  </trk>
</gpx>
`;
}

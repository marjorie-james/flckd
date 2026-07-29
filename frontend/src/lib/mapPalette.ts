// Single source of truth for the colors MapLibre paints on the map overlay.
//
// MapLibre paints from JS, so the overlay cannot reference CSS custom properties
// the way the rest of the UI does. Before this file it was a second, parallel
// palette that had drifted from the design tokens: the route line still used the
// indigo the token block records as retired, "confirmed" was drawn in two
// different reds (dot vs cone), and "suspect" in two different ambers.
//
// These are plain constants, not a runtime read of the CSS variables.
// getComputedStyle(document.documentElement).getPropertyValue(...) was considered
// and rejected: jsdom returns an empty string for custom properties, so tests
// would only ever exercise the fallback path, and a layer that constructs before
// the stylesheet loads would snapshot the wrong values in production. A one-time
// read buys no theming reactivity either.
//
// The `--map-*` block in src/App.css mirrors this table value for value so CSS
// can paint the same roles. tests/unit/map-palette.test.ts parses that block and
// fails if either side is edited alone.

// One entry per semantic role. Keys are the matching CSS custom property names.
export const MAP_COLOR_TOKENS = {
  // Primary planned route. --accent-hi, the bright step of the steel-teal accent
  // that replaced the retired indigo.
  "--map-route": "#6fc6cb",
  // Fastest non-avoiding route, drawn dashed beneath the primary line. --text-muted.
  "--map-route-comparison": "#9aa3ad",
  // Confirmed starting address. --green, the same token the "clean" verdict uses.
  "--map-origin": "#34d399",
  // Camera cluster bubble. Darkened teal (5.0:1 against white cluster-count
  // text, WCAG AA). One step below the route so a cluster never competes with
  // the planned line.
  "--map-cluster": "#2b7a80",
  // Confirmed camera: dot, 360 halo ring, and watched-stretch line. --red.
  "--map-camera-confirmed": "#f87171",
  // Disputed or low-confidence camera, same three elements. --amber.
  "--map-camera-suspect": "#fbbf24",
  // Vision cones, one step brighter than their dot so the cone stays legible
  // against both the dark basemap and the same-hue watched-stretch line beneath it.
  "--map-camera-confirmed-hi": "#fca5a5",
  "--map-camera-suspect-hi": "#fcd34d",
  // Outline on markers that must stay readable over any basemap fill.
  "--map-marker-stroke": "#ffffff",
} as const;

export const ROUTE_COLOR = MAP_COLOR_TOKENS["--map-route"];
export const ROUTE_COMPARISON_COLOR = MAP_COLOR_TOKENS["--map-route-comparison"];
export const ORIGIN_COLOR = MAP_COLOR_TOKENS["--map-origin"];
export const CLUSTER_COLOR = MAP_COLOR_TOKENS["--map-cluster"];
export const CAMERA_CONFIRMED_COLOR = MAP_COLOR_TOKENS["--map-camera-confirmed"];
export const CAMERA_SUSPECT_COLOR = MAP_COLOR_TOKENS["--map-camera-suspect"];
export const CONE_CONFIRMED_COLOR = MAP_COLOR_TOKENS["--map-camera-confirmed-hi"];
export const CONE_SUSPECT_COLOR = MAP_COLOR_TOKENS["--map-camera-suspect-hi"];
export const MARKER_STROKE_COLOR = MAP_COLOR_TOKENS["--map-marker-stroke"];

// Fully transparent fill for the 360 halo, which is stroke-only. Not a palette
// role, so it carries no CSS token.
export const TRANSPARENT = "rgba(0,0,0,0)";

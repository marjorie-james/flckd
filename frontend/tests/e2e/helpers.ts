import { expect, type Page } from "@playwright/test";

// Two canned Iowa places the mock geocoder returns. Labels are matched against
// the typed query so autocomplete behaves like the real thing.
export const ORIGIN = { label: "Iowa State Capitol, Des Moines, IA", lat: 41.5914, lng: -93.6037 };
export const DEST   = { label: "Blank Park Zoo, Des Moines, IA",     lat: 41.5326, lng: -93.6634 };

// Server-localized maneuvers (directions are localized backend-side, FR-014).
function maneuvers(locale: string) {
  return locale.startsWith("es")
    ? [
        { type: "start", localized_text: "Dirígete al norte por Main St", distance_m: 400, shape_index: 0 },
        { type: "turn", localized_text: "Gira a la derecha en la 5.ª Avenida", distance_m: 1200, shape_index: 3 },
        { type: "destination", localized_text: "Llega a tu destino", distance_m: 0, shape_index: 9 },
      ]
    : [
        { type: "start", localized_text: "Head north on Main St", distance_m: 400, shape_index: 0 },
        { type: "turn", localized_text: "Turn right onto 5th Ave", distance_m: 1200, shape_index: 3 },
        { type: "destination", localized_text: "Arrive at your destination", distance_m: 0, shape_index: 9 },
      ];
}

// A deterministic route for the given locale. Always returns a fully-clean
// result — the automatic routing strategy always tries zero-camera first.
export function routeFor(locale: string) {
  return {
    // Precision-6 encoded polyline: [-93.6, 41.6] → [-93.5, 41.5] (Iowa region).
    // Must decode to valid lat/lng or MapLibre's fitBounds throws and unmounts React.
    geometry: "__ajnA~n{oqD~hbE_ibE",
    distance_m: 8200,
    duration_s: 960,
    maneuvers: maneuvers(locale),
    cameras_avoided_count: 3,
    remaining_cameras: [],
    is_fully_clean: true,
    fastest_comparison: {
      distance_m: 7000,
      duration_s: 780,
      added_distance_m: 1200,
      added_duration_s: 180,
      // A distinct, decodable Iowa polyline so the comparison line renders separately.
      geometry: "_ahknA~pbqqD~{|F_mpG",
      cameras_passed_count: 3,
    },
    coverage_warning: null,
  };
}

// Installs deterministic stubs for the whole API surface plus self-hosted tiles.
// Must be called before page.goto so the first requests are intercepted.
export async function mockApi(page: Page) {
  await page.route("**/api/v1/geocode/search**", async (route) => {
    const q = (new URL(route.request().url()).searchParams.get("q") || "").toLowerCase();
    const pool = [ORIGIN, DEST].map((p) => ({
      label: p.label,
      lat: p.lat,
      lng: p.lng,
      type: "venue",
      confidence: 0.9,
    }));
    const matched = pool.filter((r) => r.label.toLowerCase().includes(q));
    await route.fulfill({ json: { results: matched.length ? matched : pool } });
  });

  await page.route("**/api/v1/routes", async (route) => {
    let body: { route?: { locale?: string } };
    try {
      body = JSON.parse(route.request().postData() || "{}");
    } catch {
      body = {};
    }
    const locale = body.route?.locale ?? "en";
    await route.fulfill({ json: routeFor(locale) });
  });

  await page.route("**/api/v1/cameras**", (route) => route.fulfill({ json: { cameras: [] } }));

  // Coverage bounds frame the map on load. Iowa's bbox (the dev tile region).
  await page.route("**/api/v1/coverage/bounds**", (route) =>
    route.fulfill({ json: { bounds: [[-96.64, 40.37], [-90.14, 43.50]] } })
  );

  // Self-hosted tiles: stub an empty style so MapLibre initializes offline.
  await page.route("**/tiles/**", (route) =>
    route.fulfill({ json: { version: 8, sources: {}, layers: [] } })
  );
}

// Picks origin + destination via the geocode autocomplete, then submits the plan.
// waitFor is needed because suggestions appear after the 300 ms debounce.
export async function planRoute(page: Page) {
  const inputs = page.locator('.route-panel input[inputmode="search"]');
  const firstSuggestion = page.locator(".suggestions li button").first();

  await inputs.nth(0).fill("iowa state");
  await firstSuggestion.waitFor({ state: "visible" });
  await firstSuggestion.click();

  await inputs.nth(1).fill("blank park");
  await firstSuggestion.waitFor({ state: "visible" });
  await firstSuggestion.click();

  await page.locator('.route-panel button[type="submit"]').click();
}

// ─── Responsive-layout helpers (feature 010) ───

// The breakpoint matrix the responsive-layout suite exercises. Heights are chosen
// so each width has a realistic aspect ratio; `landscape-phone` is the short-height
// case (the map must not consume the entire viewport).
export const VIEWPORTS = [
  { name: "mobile-320", width: 320, height: 720 },
  { name: "mobile-375", width: 375, height: 812 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-900", width: 900, height: 900 },
  { name: "desktop-1024", width: 1024, height: 800 },
  { name: "desktop-1440", width: 1440, height: 900 },
  { name: "ultrawide-2560", width: 2560, height: 1440 },
  { name: "landscape-phone", width: 812, height: 375 },
] as const;

export function viewport(name: (typeof VIEWPORTS)[number]["name"]) {
  const v = VIEWPORTS.find((x) => x.name === name);
  if (!v) throw new Error(`unknown viewport: ${name}`);
  return v;
}

// Asserts the document has no horizontal overflow (INV-1). 1px tolerance for
// sub-pixel rounding.
export async function expectNoHorizontalScroll(page: Page) {
  const { scrollWidth, clientWidth } = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  expect(scrollWidth, "no horizontal overflow").toBeLessThanOrEqual(clientWidth + 1);
}

// Combined empty left+right margin as a fraction of viewport width: the app shell
// (.plan-page) vs the viewport. ~0 when the layout fills the width (FR-001/SC-001),
// large when the old 520px column is centered.
export async function sideMarginFraction(page: Page): Promise<number> {
  return page.evaluate(() => {
    const shell = document.querySelector(".plan-page");
    const vw = document.documentElement.clientWidth;
    if (!shell || vw === 0) return 1;
    const empty = Math.max(0, vw - shell.getBoundingClientRect().width);
    return empty / vw;
  });
}

// Map width as a fraction of the content area (the shell). ≥0.55 on desktop means
// the map is the dominant element (FR-003/SC-003).
export async function mapWidthFraction(page: Page): Promise<number> {
  return page.evaluate(() => {
    const shell = document.querySelector(".plan-page");
    const map = document.querySelector(".map-container");
    if (!shell || !map) return 0;
    const shellW = shell.getBoundingClientRect().width;
    return shellW === 0 ? 0 : map.getBoundingClientRect().width / shellW;
  });
}

// Runtime deployment config — fetched once at boot from /config.json.
//
// Why this exists: the production frontend is a static bundle, but WHERE it
// sends API and tile requests must be changeable WITHOUT rebuilding. config.json
// is copied verbatim into the build (it lives in public/), so editing
// dist/config.json on the static host re-points the app at a different API host
// or tiles origin on the next page load — no rebuild, no redeploy of the bundle.
// That one-file edit is the failover lever in the chokepoint-resilient layout
// (swing to a standby API spine / a backup domain / a separate tiles CDN).
//
// Both fields default to the page's own origin, so the common co-located deploy
// (API + tiles + frontend on one host) needs no config.json at all and behaves
// exactly as before this indirection existed.
//
// ANONYMITY: apiBase still only ever points at our OWN backend — never a third
// party. The route never leaves our infrastructure. tilesBase may be a CDN
// because tiles carry no user data (FR-012a).
export interface RuntimeConfig {
  // Origin (scheme + host[:port]) for the backend API, e.g. "https://api.flckd.example".
  // Empty string => same-origin (relative /api/v1 requests). No trailing slash needed.
  apiBase: string;
  // Origin serving the vector tiles (/tiles/{z}/{x}/{y}.mvt). Empty string =>
  // same-origin. May be a CDN (tiles are public, user-data-free).
  tilesBase: string;
}

// Module-level state, seeded with same-origin defaults so the app is fully
// functional before (and even without) loadConfig() — tests and minimal deploys
// never need to fetch anything.
let config: RuntimeConfig = { apiBase: "", tilesBase: "" };

const trimSlash = (s: string): string => s.replace(/\/+$/, "");

// Fetch /config.json once at startup. Always resolves: a missing or malformed
// file falls back to same-origin defaults so the app still boots. `no-store` so
// a CDN-cached config can't pin the app to a dead origin during a failover —
// deploy config.json with a short/zero cache TTL for the same reason.
export async function loadConfig(): Promise<void> {
  try {
    const res = await fetch("/config.json", { cache: "no-store" });
    if (!res.ok) return;
    const json: unknown = await res.json();
    if (json && typeof json === "object") {
      const c = json as Partial<RuntimeConfig>;
      config = {
        apiBase: typeof c.apiBase === "string" ? c.apiBase : "",
        tilesBase: typeof c.tilesBase === "string" ? c.tilesBase : "",
      };
    }
  } catch {
    // Network error / invalid JSON → keep same-origin defaults.
  }
}

// API origin prefix. Empty => relative (same-origin) requests, the default.
export function apiBase(): string {
  return trimSlash(config.apiBase);
}

// Absolute origin for tiles + glyphs. Tiles must be absolute because MapLibre's
// web worker resolves style URLs against its blob: origin, not the page — so a
// relative "/tiles/..." would break. Falls back to the page origin when unset.
export function tilesBase(): string {
  return config.tilesBase ? trimSlash(config.tilesBase) : window.location.origin;
}

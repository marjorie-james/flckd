// Runtime deployment config, fetched once at boot from /config.json.
//
// The production frontend is a static bundle, but its public tile origin may
// need to change without rebuilding. config.json is copied verbatim into the
// build (it lives in public/), so editing dist/config.json on the static host
// updates the tile origin on the next page load. Browser API requests are not
// configurable and always use the same-origin /api/v1 endpoint.
export interface RuntimeConfig {
  // Origin serving the vector tiles (/tiles/{z}/{x}/{y}.mvt). Empty string means
  // same-origin. May be a CDN because tiles are public and carry no user data.
  tilesBase: string;
}

// Seed with the same-origin tile default so the app works before (and even
// without) loadConfig().
let config: RuntimeConfig = { tilesBase: "" };

const trimSlash = (s: string): string => s.replace(/\/+$/, "");

// Fetch /config.json once at startup. Always resolves: a missing or malformed
// file falls back to same-origin tiles so the app still boots. `no-store` lets
// tile origin changes take effect on the next page load.
export async function loadConfig(): Promise<void> {
  try {
    const res = await fetch("/config.json", { cache: "no-store" });
    if (!res.ok) return;
    const json: unknown = await res.json();
    if (json && typeof json === "object") {
      const c = json as Partial<RuntimeConfig>;
      config = {
        tilesBase: typeof c.tilesBase === "string" ? c.tilesBase : "",
      };
    }
  } catch {
    // Network error / invalid JSON: keep same-origin tiles.
  }
}

// Absolute origin for tiles + glyphs. Tiles must be absolute because MapLibre's
// web worker resolves style URLs against its blob: origin, not the page — so a
// relative "/tiles/..." would break. Falls back to the page origin when unset.
export function tilesBase(): string {
  return config.tilesBase ? trimSlash(config.tilesBase) : window.location.origin;
}

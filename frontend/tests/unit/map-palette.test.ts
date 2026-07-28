import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { MAP_COLOR_TOKENS } from "../../src/lib/mapPalette";

// The map overlay is painted by MapLibre from JS, so it cannot read CSS custom
// properties; src/lib/mapPalette.ts and the `--map-*` block in src/App.css are
// two copies of the same table. That is exactly how the overlay palette drifted
// from the tokens in the first place (a retired indigo route line, two reds for
// "confirmed", two ambers for "suspect"). These tests are the guard: edit either
// side alone and they fail.

const read = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), "utf8");

const APP_CSS = read("../../src/App.css");
const MAP_VIEW = read("../../src/components/MapView.tsx");
const CAMERA_LAYER = read("../../src/components/CameraLayer.tsx");

// Custom properties declared directly in the `:root` block, comments stripped.
function rootTokens(css: string): Record<string, string> {
  const open = css.indexOf(":root");
  if (open === -1) throw new Error("no :root block in App.css");
  const start = css.indexOf("{", open);
  let depth = 0;
  let end = -1;
  for (let i = start; i < css.length; i++) {
    if (css[i] === "{") depth++;
    else if (css[i] === "}" && --depth === 0) {
      end = i;
      break;
    }
  }
  if (end === -1) throw new Error(":root block is unterminated");
  const body = css.slice(start + 1, end).replace(/\/\*[\s\S]*?\*\//g, "");
  const tokens: Record<string, string> = {};
  for (const [, name, value] of body.matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/gi)) {
    tokens[name] = value.trim().toLowerCase();
  }
  return tokens;
}

const mapTokensInCss = () =>
  Object.fromEntries(Object.entries(rootTokens(APP_CSS)).filter(([name]) => name.startsWith("--map-")));

describe("map palette / CSS token parity", () => {
  it("declares exactly the --map-* tokens that mapPalette.ts exports, with the same values", () => {
    // toEqual both ways, so this fails on a changed value, an added token, or a
    // removed token on either side.
    expect(mapTokensInCss()).toEqual({ ...MAP_COLOR_TOKENS });
  });

  it("parses a non-empty :root block (the parity check would pass vacuously otherwise)", () => {
    expect(Object.keys(mapTokensInCss()).length).toBeGreaterThan(0);
    expect(rootTokens(APP_CSS)["--accent-hi"]).toBe("#6fc6cb");
  });

  it("writes every color as a full six-digit lowercase hex on both sides", () => {
    // `#fff` and `#ffffff` are the same color but not the same string, and the
    // parity check compares strings.
    for (const [name, value] of Object.entries(MAP_COLOR_TOKENS)) {
      expect(value, name).toMatch(/^#[0-9a-f]{6}$/);
    }
  });

  it("does not resurrect the retired indigo", () => {
    expect(Object.values(MAP_COLOR_TOKENS)).not.toContain("#818cf8");
    expect(APP_CSS).not.toContain("#818cf8");
  });
});

describe("map components carry no color literals", () => {
  // Every overlay color must come from mapPalette.ts, so a token change reaches
  // the map. A hex literal in either component is a second palette re-forming.
  const HEX = /#[0-9a-f]{3,8}\b/gi;

  it("MapView.tsx has no hex literal", () => {
    expect(MAP_VIEW.match(HEX)).toBeNull();
  });

  it("CameraLayer.tsx has no hex literal", () => {
    expect(CAMERA_LAYER.match(HEX)).toBeNull();
  });

  it("both components import their colors from mapPalette", () => {
    expect(MAP_VIEW).toContain('from "../lib/mapPalette"');
    expect(CAMERA_LAYER).toContain('from "../lib/mapPalette"');
  });
});

import { describe, it, expect } from "vitest";
import { resolveLocale } from "../../src/i18n/resolveLocale";

// The pure matcher (contracts §1/§4). Input is the visitor's already-ordered
// preference list, so order encodes strength. Mirrors the backend negotiator's
// semantics against the shared scenario table.
const SUPPORTED = ["en", "es"];

describe("resolveLocale", () => {
  it("row 1: picks the top supported language", () => {
    expect(resolveLocale(["es", "en"], SUPPORTED, { default: "en" })).toBe("es");
  });

  it("row 2: falls back to the default when nothing is supported", () => {
    expect(resolveLocale(["fr", "de"], SUPPORTED, { default: "en" })).toBe("en");
  });

  it("row 3: matches a regional variant to its base language", () => {
    expect(resolveLocale(["es-MX", "en"], SUPPORTED, { default: "en" })).toBe("es");
  });

  it("row 4: skips an unsupported higher-ranked entry for a supported one", () => {
    expect(resolveLocale(["de", "es"], SUPPORTED, { default: "en" })).toBe("es");
  });

  it("row 5: respects order as strength (first supported wins)", () => {
    expect(resolveLocale(["en", "es"], SUPPORTED, { default: "en" })).toBe("en");
  });

  it("row 6: ignores a wildcard entry", () => {
    expect(resolveLocale(["*"], SUPPORTED, { default: "en" })).toBe("en");
  });

  it("row 7: returns the default for an empty list", () => {
    expect(resolveLocale([], SUPPORTED, { default: "en" })).toBe("en");
  });

  it("row 8: reduces multiple regional variants to the base", () => {
    expect(resolveLocale(["es-ES", "es-MX"], SUPPORTED, { default: "en" })).toBe("es");
  });

  it("row 9: breaks ties by advertised order (deterministic)", () => {
    expect(resolveLocale(["en", "es"], SUPPORTED, { default: "en" })).toBe("en");
    expect(resolveLocale(["es", "en"], SUPPORTED, { default: "en" })).toBe("es");
  });

  it("skips empty and malformed entries", () => {
    expect(resolveLocale(["", "123", "e", "es"], SUPPORTED, { default: "en" })).toBe("es");
  });

  it("defaults to 'en' when no default is provided", () => {
    expect(resolveLocale(["fr"], SUPPORTED)).toBe("en");
  });
});

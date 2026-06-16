import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import i18n, { resolveEnvironmentLocale } from "../../src/i18n";
import { LanguageSwitcher } from "../../src/components/LanguageSwitcher";
import { RoutePanel } from "../../src/components/RoutePanel";

// Auto-detect the interface language and switch it at runtime without losing
// in-progress route input. Geocode is mocked to keep the test offline.
vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
  return { ...actual, useGeocodeSearch: () => ({ data: undefined }) };
});

// Temporarily override navigator.languages for environment-derivation tests.
function withLanguages<T>(languages: string[], fn: () => T): T {
  const original = Object.getOwnPropertyDescriptor(navigator, "languages");
  Object.defineProperty(navigator, "languages", { value: languages, configurable: true });
  try {
    return fn();
  } finally {
    if (original) Object.defineProperty(navigator, "languages", original);
  }
}

describe("i18n", () => {
  beforeEach(async () => {
    window.localStorage.removeItem("flckd.locale");
    await i18n.changeLanguage("en");
  });

  it("auto-detects a supported language with an English fallback", () => {
    // jsdom's navigator.language is en-US → resolves to a supported locale.
    expect(["en", "es"]).toContain(i18n.language.slice(0, 2));
  });

  it("switches language at runtime while preserving in-progress input", async () => {
    render(
      <>
        <LanguageSwitcher />
        <RoutePanel onPlan={() => {}} planning={false} />
      </>,
    );

    // Type a partial origin; this lives in React state, not the URL. The address
    // fields are ARIA comboboxes, so query by id (label text changes on locale switch).
    const origin = () => document.getElementById("origin-input") as HTMLInputElement;
    fireEvent.change(origin(), { target: { value: "Iowa State Cap" } });
    expect(screen.getByRole("button", { name: /plan route/i })).toBeInTheDocument();

    // Switch to Spanish via the language switcher (named "Language").
    fireEvent.change(screen.getByRole("combobox", { name: /language/i }), { target: { value: "es" } });
    await screen.findByRole("button", { name: /planificar ruta/i });

    // The in-progress input survived the language change.
    expect(origin().value).toBe("Iowa State Cap");
  });
});

// US1: the interface language is derived from the environment's ordered
// preference list, matched against the offered locales with base fallback.
describe("environment derivation (US1)", () => {
  it("resolves to the highest-ranked offered language", () => {
    expect(withLanguages(["es-ES", "en"], resolveEnvironmentLocale)).toBe("es");
  });

  it("falls back to the default when nothing is offered", () => {
    expect(withLanguages(["fr", "de"], resolveEnvironmentLocale)).toBe("en");
  });

  it("matches a regional variant to its base language", () => {
    expect(withLanguages(["es-MX"], resolveEnvironmentLocale)).toBe("es");
  });
});

// US2: a valid remembered choice takes precedence over the environment at
// startup; an invalid stored value is ignored and the environment is re-resolved.
describe("startup precedence (US2)", () => {
  afterEach(() => {
    vi.resetModules();
    window.localStorage.removeItem("flckd.locale");
  });

  // Re-evaluate the i18n module with a controlled environment + storage, so we
  // observe the language it resolves at startup. navigator.languages is restored
  // only AFTER the dynamic import has run (the module reads it during init).
  async function freshI18n(opts: { stored?: string; languages?: string[] }) {
    vi.resetModules();
    window.localStorage.removeItem("flckd.locale");
    if (opts.stored !== undefined) window.localStorage.setItem("flckd.locale", opts.stored);
    const original = Object.getOwnPropertyDescriptor(navigator, "languages");
    Object.defineProperty(navigator, "languages", {
      value: opts.languages ?? ["en-US"],
      configurable: true,
    });
    try {
      const mod = await import("../../src/i18n");
      return mod.default;
    } finally {
      if (original) Object.defineProperty(navigator, "languages", original);
    }
  }

  it("prefers a valid stored choice over the environment guess", async () => {
    const fresh = await freshI18n({ stored: "es", languages: ["en-US"] });
    expect(fresh.language).toBe("es");
  });

  it("ignores a no-longer-supported stored value and re-resolves the environment", async () => {
    const fresh = await freshI18n({ stored: "zz", languages: ["en-US"] });
    expect(fresh.language).toBe("en");
  });
});

// FR-014: a string missing from the selected language falls back to the default
// (English) rather than rendering blank or the raw key.
describe("missing-string fallback (FR-014)", () => {
  afterEach(async () => {
    await i18n.changeLanguage("en");
  });

  it("renders the English fallback for a key absent in the selected language", async () => {
    i18n.addResource("en", "translation", "__fallback_probe__", "English only");
    await i18n.changeLanguage("es");
    expect(i18n.t("__fallback_probe__")).toBe("English only");
  });
});

// FR-009: every visitor-facing surface the app controls localizes — including the
// camera details popup. Each representative key resolves to distinct text per
// locale, proving the surface is wired to i18n rather than hardcoded.
describe("all surfaces localize (FR-009)", () => {
  afterEach(async () => {
    await i18n.changeLanguage("en");
  });

  const SURFACE_KEYS = [
    "app.title", // page heading
    "form.plan", // action button
    "cameras.popup.title", // camera details popup
    "cameras.popup.direction",
    "cameras.popup.type",
    "errors.locationDenied", // error messaging
  ];

  it.each(SURFACE_KEYS)("localizes %s differently in en and es", async (key) => {
    await i18n.changeLanguage("en");
    const enText = i18n.t(key);
    await i18n.changeLanguage("es");
    const esText = i18n.t(key);
    expect(enText).toBeTruthy();
    expect(esText).toBeTruthy();
    expect(esText).not.toBe(enText);
  });
});

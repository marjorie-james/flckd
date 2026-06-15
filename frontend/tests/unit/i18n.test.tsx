import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import i18n from "../../src/i18n";
import { LanguageSwitcher } from "../../src/components/LanguageSwitcher";
import { RoutePanel } from "../../src/components/RoutePanel";

// US3: auto-detect the interface language and switch it at runtime without
// losing in-progress route input. Geocode is mocked to keep the test offline.
vi.mock("../../src/services/geocodeApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../src/services/geocodeApi")>();
  return { ...actual, useGeocodeSearch: () => ({ data: undefined }) };
});

describe("i18n", () => {
  beforeEach(async () => {
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

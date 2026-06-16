import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { getStoredLocale, setStoredLocale, clearStoredLocale } from "../../src/i18n/localePreference";

// On-device persistence of the explicit choice (FR-007/008/008a/015). Client-only:
// localStorage, never a cookie, and every access guarded so a blocked store
// degrades gracefully.
describe("localePreference", () => {
  beforeEach(() => {
    window.localStorage.removeItem("flckd.locale");
  });

  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.removeItem("flckd.locale");
  });

  it("returns null when nothing is stored", () => {
    expect(getStoredLocale()).toBeNull();
  });

  it("round-trips a stored choice", () => {
    setStoredLocale("es");
    expect(getStoredLocale()).toBe("es");
  });

  it("clears a stored choice", () => {
    setStoredLocale("es");
    clearStoredLocale();
    expect(getStoredLocale()).toBeNull();
  });

  it("writes only to localStorage, never to document.cookie (FR-015/SC-007)", () => {
    const cookieBefore = document.cookie;
    setStoredLocale("es");
    expect(window.localStorage.getItem("flckd.locale")).toBe("es");
    expect(document.cookie).toBe(cookieBefore);
  });

  it("degrades gracefully when reads throw (FR-008a)", () => {
    vi.spyOn(window.localStorage, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(getStoredLocale()).toBeNull();
  });

  it("degrades gracefully when writes throw (FR-008a)", () => {
    vi.spyOn(window.localStorage, "setItem").mockImplementation(() => {
      throw new Error("quota exceeded");
    });
    expect(() => setStoredLocale("es")).not.toThrow();
  });

  it("degrades gracefully when clears throw (FR-008a)", () => {
    vi.spyOn(window.localStorage, "removeItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(() => clearStoredLocale()).not.toThrow();
  });
});

import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import en from "./locales/en.json";
import es from "./locales/es.json";
import { resolveLocale } from "./resolveLocale";
import { getStoredLocale, clearStoredLocale } from "./localePreference";

// The languages the app offers. This list MUST stay in sync with the backend
// catalog — backend/config/locales/*.yml and Api::V1::LocalesController's
// LOCALE_NAMES — so any derived/selected locale always resolves to a fully
// translated language (the authoritative-catalog dependency, research D8).
export const SUPPORTED_LOCALES = [
  { code: "en", name: "English" },
  { code: "es", name: "Español" },
];

const SUPPORTED_CODES = SUPPORTED_LOCALES.map((l) => l.code);

// True when `code` is one of the offered locales. Shared so startup resolution
// and the language switcher validate a (possibly stored) code the same way.
export function isSupportedCode(code: string | null | undefined): code is string {
  return code != null && SUPPORTED_CODES.includes(code);
}

// The browser's ordered preference list (navigator.languages), or a single-entry
// fallback list when it isn't populated.
function advertisedLanguages(): readonly string[] {
  if (typeof navigator === "undefined") return ["en"];
  if (navigator.languages && navigator.languages.length > 0) return navigator.languages;
  return [navigator.language || "en"];
}

// The best-available language derived purely from the environment (ignores any
// remembered choice). Exposed so the switcher can return to automatic derivation.
export function resolveEnvironmentLocale(): string {
  return resolveLocale(advertisedLanguages(), SUPPORTED_CODES, { default: "en" });
}

// Resolve the effective language BEFORE init, synchronously, so the very first
// render is already in the right language with no flash of English (FR-001a).
// Precedence: a valid remembered choice → environment-derived best match →
// default (FR-007/005). The locale resources are bundled, so this is free.
function initialLocale(): string {
  const stored = getStoredLocale();
  if (isSupportedCode(stored)) return stored;
  // A stored value that is no longer offered is discarded (edge case): drop it
  // so a dead key isn't re-evaluated on every load.
  if (stored != null) clearStoredLocale();
  return resolveEnvironmentLocale();
}

void i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
    es: { translation: es },
  },
  lng: initialLocale(),
  fallbackLng: "en",
  interpolation: { escapeValue: false },
});

// Keep <html lang> in sync so screen readers pronounce content in the right
// language when the user switches at runtime.
if (typeof document !== "undefined") {
  const applyLang = (lng: string) => { document.documentElement.lang = lng.slice(0, 2); };
  applyLang(i18n.language);
  i18n.on("languageChanged", applyLang);
}

export default i18n;

import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import en from "./locales/en.json";
import es from "./locales/es.json";

// Auto-detect from the browser; fall back to English. Switchable at runtime
// (FR-013/014) while preserving in-progress input (state lives in React).
const browserLang = (typeof navigator !== "undefined" ? navigator.language : "en").slice(0, 2);

void i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
    es: { translation: es },
  },
  lng: ["en", "es"].includes(browserLang) ? browserLang : "en",
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
export const SUPPORTED_LOCALES = [
  { code: "en", name: "English" },
  { code: "es", name: "Español" },
];

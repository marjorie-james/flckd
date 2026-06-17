import { useTranslation } from "react-i18next";
import { SUPPORTED_LOCALES, resolveEnvironmentLocale, isSupportedCode } from "../i18n";
import { getStoredLocale, setStoredLocale, clearStoredLocale } from "../i18n/localePreference";

// Sentinel option value: "derive automatically from the environment".
const AUTOMATIC = "auto";

// Runtime language switch. Picking a language remembers it on-device and applies
// it immediately (FR-006/007); "Automatic" forgets the choice and re-derives from
// the environment (FR-008). In-progress route input is preserved because it lives
// in component state, not the URL.
export function LanguageSwitcher() {
  const { i18n, t } = useTranslation();

  // Reflect whether an explicit choice is remembered: if so the select shows that
  // language; otherwise it shows "Automatic" (the language is environment-derived).
  const stored = getStoredLocale();
  const value = isSupportedCode(stored) ? stored : AUTOMATIC;

  const onChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
    const choice = event.target.value;
    if (choice === AUTOMATIC) {
      clearStoredLocale();
      void i18n.changeLanguage(resolveEnvironmentLocale());
    } else {
      setStoredLocale(choice);
      void i18n.changeLanguage(choice);
    }
  };

  return (
    <label className="language-switcher">
      <span className="language-switcher__label">{t("language")}</span>
      <select value={value} onChange={onChange}>
        <option value={AUTOMATIC}>{t("languageAuto")}</option>
        {SUPPORTED_LOCALES.map((l) => (
          // lang marks each native language name (e.g. "Español") in its own
          // language so a screen reader pronounces it with the right phonetics
          // regardless of the page language (WCAG 3.1.2 Language of Parts).
          <option key={l.code} value={l.code} lang={l.code}>
            {l.name}
          </option>
        ))}
      </select>
    </label>
  );
}

import { useTranslation } from "react-i18next";
import { SUPPORTED_LOCALES } from "../i18n";

// Runtime language switch. Changing the language re-renders all text; in-progress
// route input is preserved because it lives in component state, not the URL.
export function LanguageSwitcher() {
  const { i18n, t } = useTranslation();
  return (
    <label className="language-switcher">
      <span className="visually-hidden">{t("language")}</span>
      <select
        value={i18n.language.slice(0, 2)}
        onChange={(e) => void i18n.changeLanguage(e.target.value)}
      >
        {SUPPORTED_LOCALES.map((l) => (
          <option key={l.code} value={l.code}>
            {l.name}
          </option>
        ))}
      </select>
    </label>
  );
}

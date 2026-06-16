// On-device persistence of the visitor's explicit language choice (FR-007/008).
//
// Client-only by design: the preference is stored in localStorage — never a
// cookie, never sent to a server, never tied to any identity (FR-015). Every
// access is wrapped so a blocked or throwing store (private browsing, denied
// permissions, quota errors) degrades gracefully: the explicit choice still
// applies for the current session via the in-memory i18n instance, it simply
// isn't remembered across visits, and the UI never blocks or errors (FR-008a).

const KEY = "flckd.locale";

/** The remembered explicit choice, or null if none / storage is unavailable. */
export function getStoredLocale(): string | null {
  try {
    return window.localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

/** Remember an explicit choice. Best-effort: a storage failure is swallowed. */
export function setStoredLocale(code: string): void {
  try {
    window.localStorage.setItem(KEY, code);
  } catch {
    // Storage unavailable — the choice still applies this session (FR-008a).
  }
}

/** Forget the explicit choice, returning to automatic derivation (FR-008). */
export function clearStoredLocale(): void {
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    // Nothing to do — storage unavailable.
  }
}

// Pure language matcher (research D2, contracts §1). Given the visitor's ordered
// advertised language tags (e.g. navigator.languages) and the app's supported
// base codes, returns the best-satisfying supported code, else `default`.
//
// "Best" = the first advertised tag whose base language is offered — the browser
// already orders the list by preference, so order encodes strength (FR-002/003).
// Regional variants fall back to their base (`es-MX` → `es`, FR-004); empty,
// wildcard, and malformed entries are skipped (FR-012). No navigator/DOM/storage
// access — the caller supplies inputs, keeping this deterministic (FR-013) and
// trivially unit-testable.

export interface ResolveLocaleOptions {
  /** Locale to use when no advertised tag matches a supported one. Defaults to "en". */
  default?: string;
}

export function resolveLocale(
  advertised: readonly string[],
  supported: readonly string[],
  options: ResolveLocaleOptions = {},
): string {
  const fallback = options.default ?? "en";
  const supportedSet = new Set(supported);

  for (const tag of advertised) {
    if (typeof tag !== "string") continue;
    // Reduce a BCP-47 tag to its base language subtag and normalize case.
    const base = tag.toLowerCase().split("-")[0];
    // Skip empty, "*", and anything that isn't a 2–3 letter language code.
    if (!/^[a-z]{2,3}$/.test(base)) continue;
    if (supportedSet.has(base)) return base;
  }

  return fallback;
}

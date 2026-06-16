# Contract: Locale Resolution & Negotiation

Two contracts with **identical matching semantics** (D2): the frontend resolver and the backend negotiator.
Both are pure, deterministic, and verified against the shared scenario table at the bottom.

---

## 1. Frontend — `resolveLocale(advertised, supported, opts?) → string`

`frontend/src/i18n/resolveLocale.ts`

**Input**:
- `advertised: readonly string[]` — ordered BCP-47 tags (caller passes `navigator.languages`, or
  `[navigator.language]` if that's empty).
- `supported: readonly string[]` — supported base codes (caller passes `SUPPORTED_LOCALES.map(l => l.code)`).
- `opts?: { default?: string }` — default code (defaults to `"en"`).

**Output**: a code that is always a member of `supported` (or `opts.default`).

**Rules**:
1. For each `tag` in `advertised` order: lowercase, take the substring before `-` as `base`. Skip if `base`
   is empty, `*`, or not `/^[a-z]{2,3}$/`.
2. If `base ∈ supported` → return `base` (first match wins).
3. If no tag matches → return `opts.default`.
4. Pure: no `navigator`/`localStorage`/DOM access inside; caller supplies inputs (keeps it unit-testable).

**Separate**: `localePreference.ts` — `get(): string | null`, `set(code)`, `clear()` over
`localStorage["flckd.locale"]`, each wrapped in `try/catch` returning a safe value on failure (FR-008a).

**Startup composition** (in `i18n/index.ts`, synchronous, pre-`init`, FR-001a):
```
const stored = localePreference.get();
const supported = SUPPORTED_LOCALES.map(l => l.code);
const lng = (stored && supported.includes(stored))
  ? stored
  : resolveLocale(navigator.languages ?? [navigator.language], supported, { default: "en" });
```

---

## 2. Backend — `Api::V1::LocaleNegotiator`

`backend/app/services/api/v1/locale_negotiator.rb` (path matches the `Api::V1::LocaleNegotiator` module)

**Interface**:
```ruby
Api::V1::LocaleNegotiator.call(accept_language_header, available: I18n.available_locales, default: I18n.default_locale)
# => Symbol (a member of `available`, or `default`)
```

**Rules**:
1. Parse the header into `(tag, q)` pairs: split on `,`; each item `tag;q=0.8` → `q` defaults to `1.0`;
   ignore malformed q (treat as 1.0).
2. Sort by `q` desc, then original order (stable) — deterministic tie-break (FR-013).
3. Reduce each `tag` to its base (`es-MX` → `es`); skip empty / `*` / non-alpha.
4. Return the first base whose symbol ∈ `available`; else `default`.

**Controller wiring** (`base_controller.rb#switch_locale`) — precedence unchanged in spirit, sharpened:
```
locale = params[:locale].presence_in(I18n.available_locales.map(&:to_s))      # explicit override (highest)
       || Api::V1::LocaleNegotiator.call(request.headers["Accept-Language"])  # negotiated from header
locale ||= I18n.default_locale
I18n.with_locale(locale, &action)
```
The frontend sends the **effective** selected locale as `Accept-Language` (D4/FR-016), so server-rendered
error/status messages match the visitor's UI even under an explicit override.

---

## 3. Existing endpoint contract (unchanged, referenced)

`GET /api/v1/meta/locales` → `{ default: string, locales: [{ code, name }] }` — the authoritative catalog
(D8). No shape change; it remains the source of truth the frontend mirrors.

---

## 4. Shared scenario table (both implementations MUST satisfy)

`supported = [en, es]`, `default = en`.

| # | Advertised (ordered) / Accept-Language | Expected | Covers |
|---|----------------------------------------|----------|--------|
| 1 | `es`, `en`                             | `es`     | FR-001/003, top match wins (SC-001) |
| 2 | `fr`, `de`                             | `en`     | FR-005 no-match → default (SC-002) |
| 3 | `es-MX`, `en`                          | `es`     | FR-004 regional → base (SC-003) |
| 4 | `de;q=0.9, es;q=0.8`                   | `es`     | FR-002 skip unsupported-but-higher, take supported |
| 5 | `en;q=0.7, es;q=0.9`                   | `es`     | FR-002 strength over order (backend q); frontend: order = `es` first input |
| 6 | `*`                                    | `en`     | FR-012 wildcard ignored → default |
| 7 | `` (empty) / no header                 | `en`     | edge: no signal → default |
| 8 | `es-ES`, `es-MX`                       | `es`     | FR-004 both reduce to base |
| 9 | `en, es` (tie, equal q on backend)     | `en`     | FR-013 stable tie-break = order |

> Note row 5: the frontend receives `navigator.languages` already ordered by the browser, so "strength" is
> encoded as order; the backend receives explicit q-values and sorts by them. Both yield `es` for the
> equivalent intent. Unit tests assert each implementation against its natural input form.

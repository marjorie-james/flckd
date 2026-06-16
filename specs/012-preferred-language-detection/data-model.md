# Phase 1 Data Model: Preferred Language Detection

This feature is presentation/runtime state, not persistent server data. "Entities" here are the in-memory
and on-device value shapes the resolution logic operates on. No database tables, migrations, or server-side
records are introduced (FR-015).

## SupportedLanguage

The authoritative catalog of offered languages (D8).

| Field  | Type   | Notes                                                        |
|--------|--------|-------------------------------------------------------------|
| `code` | string | Base language code, lowercase (`en`, `es`). Unique.         |
| `name` | string | Human-readable display name (`English`, `Español`).         |

- **Frontend source**: `SUPPORTED_LOCALES` in `frontend/src/i18n/index.ts`.
- **Backend source**: `I18n.available_locales` (from `config/locales/*.yml`) + display names in
  `LocalesController::LOCALE_NAMES`, exposed via `GET /api/v1/meta/locales`.
- **Invariant**: the two sources list the same `code` set; a derived/selected language MUST always be a member
  (matching never returns a non-member; default `en` is always a member).

## AdvertisedPreference (transient input)

The visitor's environment-provided ranked preference, consumed during resolution and never stored.

| Field      | Type            | Notes                                                       |
|------------|-----------------|-------------------------------------------------------------|
| `tag`      | string (BCP-47) | e.g. `es-MX`, `en`. From `navigator.languages` (frontend)   |
|            |                 | or an `Accept-Language` entry (backend).                    |
| `region`   | string?         | Optional subtag; ignored for matching (base-only, FR-004).  |
| `quality`  | number          | 1.0 for `navigator.languages` (order encodes rank); parsed  |
|            |                 | q-value (0–1) for `Accept-Language` entries. Default 1.0.   |

- Validation: entries that are empty, `*`, or non-`[a-z]{2}`-reducible are dropped (FR-012).
- Ordering: by `quality` desc, then original advertised order (stable) — the deterministic tie-break (FR-013).

## RememberedChoice (on-device, optional)

The visitor's explicit override, persisted client-side only (D5).

| Field      | Type    | Notes                                                            |
|------------|---------|------------------------------------------------------------------|
| `code`     | string  | A `SupportedLanguage.code`. Stored in `localStorage["flckd.locale"]`. |
| (presence) | boolean | Absent ⇒ automatic derivation; present+valid ⇒ overrides it.     |

- **Lifecycle**:
  - *Set* — visitor picks a language in the switcher → write `code` (best-effort; failure tolerated, FR-008a).
  - *Read* — at startup; if value is not a current `SupportedLanguage.code`, discard + remove (edge case).
  - *Clear* — visitor selects "automatic" → remove key → re-resolve from environment (FR-008).
- **Anonymity**: no identity, timestamp, or any other field; never transmitted as a cookie or to a third
  party (FR-015). It only influences the `Accept-Language` value the app itself sends (D4).

## SelectedLanguage (resolved, in-memory)

The single language in effect for the current visit — the output of resolution and the input to rendering.

| Field    | Type   | Notes                                                                   |
|----------|--------|-------------------------------------------------------------------------|
| `code`   | string | Always a `SupportedLanguage.code`.                                       |
| `source` | enum   | `remembered` \| `environment` \| `default` — provenance, for tests/debug.|

- **Resolution precedence** (FR-007 / FR-005 / FR-013):
  1. `remembered` — valid `RememberedChoice` present.
  2. `environment` — best match of `AdvertisedPreference[]` against `SupportedLanguage[]` (D2).
  3. `default` — `en`.
- **Application targets** (FR-009/FR-010/FR-011): i18next active language → all UI strings; `<html lang>`;
  the `Accept-Language` header sent to the backend (→ server-rendered messages); the map label `text-field`
  language. All MUST reflect the same `code` at any instant (SC-005).

## State transitions

```text
            startup
              │
   read RememberedChoice (guarded)
       │valid           │absent/invalid/unreadable
       ▼                ▼
   SelectedLanguage  resolveLocale(navigator.languages, SUPPORTED)
   (source=remembered)   │match            │no match
       │                 ▼                 ▼
       │            source=environment  source=default(en)
       └───────────────┬─────────────────┘
                       ▼
        apply: i18next.lng, <html lang>, Accept-Language, map labels

   ── runtime ──
   switcher → pick code  → write RememberedChoice (best-effort)
                         → i18n.changeLanguage(code)
                         → re-apply all targets (incl. map labels, no reload)
   switcher → "automatic"→ clear RememberedChoice → re-resolve from environment → re-apply
```

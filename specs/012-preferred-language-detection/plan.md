# Implementation Plan: Preferred Language Detection

**Branch**: `012-preferred-language-detection` | **Date**: 2026-06-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-preferred-language-detection/spec.md`

## Summary

Strengthen the app's existing i18n foundation so the UI language is **derived automatically from the
visitor's full set of environment language signals** (the ordered `navigator.languages` list and the
`Accept-Language` q-weights), matched against the offered locales with base-language regional fallback,
resolved **synchronously before first paint** (no flash). A visitor's explicit choice wins, is persisted
on-device (localStorage, graceful when unavailable), and the **effective** selected language — override
included — is sent to the backend on every request so server-rendered text matches. Map labels follow the
selected language at runtime. Catalog of languages is unchanged (en, es); the mechanism is locale-agnostic.

The current code is naive in three places this feature replaces:

1. `frontend/src/i18n/index.ts` — picks `navigator.language.slice(0,2)` (single signal, no ordering/q,
   no persistence).
2. `frontend/src/services/apiClient.ts` — sends raw `navigator.language` as `Accept-Language`, so an
   explicit override never reaches the server (FR-016 gap).
3. `frontend/public/map-style.json` — two label layers hardcode `name:en` (US3 gap).

…and the backend `Api::V1::BaseController#locale_from_header` grabs the first two-letter token, ignoring
q-values, ordering, and base-language fallback.

## Technical Context

**Language/Version**: TypeScript + React 19 (Vite) frontend; Ruby 3.4.x + Rails 8.1.x (API mode) backend.

**Primary Dependencies**: Frontend — `i18next` 26.x + `react-i18next` 17.x, MapLibre GL JS 5.x. Backend —
Rails I18n (`config/locales/*.yml`). No new runtime dependencies required (matching uses standard
`navigator.languages` + Rails I18n; no new gem/package).

**Storage**: Browser `localStorage` for the remembered explicit choice (client-side only, key `flckd.locale`).
No server-side or database storage of any language preference (strict anonymity, FR-015).

**Testing**: Frontend — Vitest unit (`frontend/tests/unit/`), Playwright e2e (`frontend/tests/e2e/`).
Backend — RSpec request specs (`backend/spec/requests/`). Geo engines stay stubbed/fixtured.

**Target Platform**: Modern evergreen browsers (frontend SPA) talking to the self-hosted Rails API.

**Project Type**: Web application (frontend + backend), existing repo layout.

**Performance Goals**:
- Startup language resolution is **synchronous, in-memory, zero network** (locale strings are bundled) —
  adds no measurable delay to first paint; correct language on the very first rendered frame (SC-001).
- Runtime language switch (UI + map labels) applies in **< 100 ms** perceived, with no page reload.

**Constraints**:
- FR-001a: no flash of default language — resolution MUST complete before `i18n.init` returns / first render.
- FR-015: no PII, no accounts, no persistent identifier or route data to any third party; preference stays
  on the visitor's device.
- FR-008a: localStorage access MUST be wrapped so a blocked/throwing store degrades gracefully (session-only).
- Determinism (FR-013/SC-006): same inputs → same locale; ties broken by advertised order then default.

**Scale/Scope**: Small, surgical change. 2 offered locales today (en, es); mechanism is locale-agnostic so
adding a locale later needs no algorithm change. Touch ~3 frontend modules + 1 new util, 1 backend negotiator
refinement, 2 map-style label layers, plus tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Code Quality** — PASS. Changes are small, single-responsibility units: a pure `resolveLocale` matcher
  (frontend) and a `LocaleNegotiator` (backend), each documented for intent. No dead code; the naive
  one-liners they replace are removed, not left behind. Lint/format gates apply unchanged.
- **II. Testing Standards (NON-NEGOTIABLE)** — PASS. Every behavioral change is covered by tests that would
  fail without it: unit tests for the matcher (ordering, q-weights, base fallback, no-match, malformed/wildcard,
  persistence, storage-unavailable), e2e for no-flash first paint + persisted override + runtime map-label
  switch, and backend request specs for Accept-Language negotiation + base fallback + override precedence.
  Geo services remain stubbed for determinism.
- **III. User Experience Consistency** — PASS. One selected language drives all visitor-facing text (UI,
  server errors, map labels). Existing switcher convention and structured/localized error shape are preserved;
  no new error surfaces. `<html lang>` stays in sync for accessibility.
- **IV. Performance Requirements** — PASS. Explicit budgets declared above (synchronous zero-network startup
  resolution; < 100 ms runtime switch). No new network calls; no unbounded resource use. Measured via the
  e2e first-frame assertion and switch timing.

**Result: PASS — no violations. Complexity Tracking not required.**

## Project Structure

### Documentation (this feature)

```text
specs/012-preferred-language-detection/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── locale-negotiation.md
├── checklists/
│   └── requirements.md  # from /speckit-specify + /speckit-clarify
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
frontend/
├── src/
│   ├── i18n/
│   │   ├── index.ts            # MODIFY: synchronous resolve via resolveLocale; persisted-choice precedence
│   │   ├── resolveLocale.ts    # NEW: pure matcher (navigator.languages + supported set → effective locale)
│   │   ├── localePreference.ts # NEW: localStorage get/set/clear with graceful-degrade guards
│   │   └── locales/{en,es}.json # unchanged (catalog stable)
│   ├── services/
│   │   └── apiClient.ts        # MODIFY: send effective selected locale (i18n.language) as Accept-Language
│   └── components/
│       ├── LanguageSwitcher.tsx# MODIFY: persist choice on change; add "use automatic" reset affordance
│       └── MapView.tsx         # MODIFY: build label text-field from selected locale; update on languageChanged
├── public/
│   └── map-style.json          # UNCHANGED: keeps name:en as the in-coalesce fallback; the
│                               #   per-language label field is injected at runtime by MapView
└── tests/
    ├── unit/
    │   ├── resolveLocale.test.ts   # NEW
    │   ├── localePreference.test.ts# NEW
    │   └── i18n.test.tsx           # EXTEND
    └── e2e/
        └── i18n.spec.ts            # EXTEND: no-flash, persistence, map-label switch

backend/
├── app/
│   ├── controllers/api/v1/
│   │   └── base_controller.rb  # MODIFY: delegate locale to LocaleNegotiator (q-values, ordered, base fallback)
│   └── services/api/v1/        # path matches the Api::V1::LocaleNegotiator module (Rails autoloading)
│       └── locale_negotiator.rb# NEW: parse Accept-Language → best available locale (deterministic)
├── config/locales/{en,es}.yml  # unchanged
└── spec/
    └── requests/
        └── i18n_spec.rb        # EXTEND: q-values, ordered preference, es-MX→es, override precedence
```

**Structure Decision**: Existing web-app layout (`frontend/` + `backend/`). No new top-level dirs. New code is
two small pure units (frontend `resolveLocale`/`localePreference`, backend `LocaleNegotiator`) plus targeted
edits to the four naive sites identified in the Summary.

## Complexity Tracking

> No Constitution violations — section intentionally empty.

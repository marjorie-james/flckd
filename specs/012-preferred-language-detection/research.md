# Phase 0 Research: Preferred Language Detection

All spec ambiguities were resolved in `/speckit-clarify` (see spec § Clarifications); there are no
open `NEEDS CLARIFICATION` markers. This document records the technical decisions for the design.

## D1 — Source of advertised language signals (frontend)

**Decision**: Use `navigator.languages` (the ordered list) as the primary signal, falling back to
`navigator.language` when `languages` is empty/undefined. Each entry is a BCP-47 tag (e.g. `es-MX`,
`en`). The browser already orders them by preference, so order alone encodes strength; no q-value
parsing is needed on the client.

**Rationale**: `navigator.languages` is the standard, fully-supported, ordered preference list (FR-002).
The current code reads only `navigator.language` (single entry) and discards everything after the first
two characters — exactly the limitation this feature removes.

**Alternatives considered**:
- *Keep `navigator.language` only* — rejected: ignores the rest of the visitor's ranked preferences (FR-002).
- *Parse an `Accept-Language`-style q-string on the client* — rejected: the browser doesn't expose a q-string
  to JS; `navigator.languages` already conveys the ordering.

## D2 — Matching algorithm (shared semantics, two implementations)

**Decision**: A deterministic "best-match" over the ordered preference list against the supported set:

1. Normalize each advertised tag: lowercase, split on `-`, keep `[base, region?]`. Drop empty/`*`/malformed.
2. Walk the advertised list in order. For each entry:
   - **Exact base match**: if `base` is a supported locale → select it.
   - (Region-specific translations are out of scope; `es-MX` and `es-ES` both reduce to base `es`.)
3. First match wins (advertised order is the tie-break, FR-013).
4. If no entry matches any supported locale → **default** (`en`) (FR-005).

This is implemented twice with identical semantics: `resolveLocale` (frontend, over `navigator.languages`)
and `LocaleNegotiator` (backend, over the parsed `Accept-Language` header). Both are pure and unit-tested
against the same scenario table so they cannot drift.

**Rationale**: Satisfies FR-003 (best satisfying match), FR-004 (regional → base), FR-012 (skip malformed),
FR-013 (deterministic, stable tie-break). Base-only matching matches the assumption that the app has no
region-variant translations.

**Alternatives considered**:
- *Use `i18next-browser-languagedetector` + caches plugin* — rejected: heavier dependency, its ordering and
  caching behavior is harder to assert deterministically, and we still need a backend twin. A ~30-line pure
  matcher is simpler to test and reason about (Constitution I/II).
- *Weighted scoring across all entries* — rejected: over-engineered; first-ordered-match is unambiguous and
  matches browser semantics.

## D3 — Backend Accept-Language negotiation

**Decision**: Add `Api::V1::LocaleNegotiator` that parses `Accept-Language` into `(tag, q)` pairs, sorts by
q descending then by header order (stable), reduces each tag to its base, and returns the first base that is
in `I18n.available_locales`, else `I18n.default_locale`. `BaseController#switch_locale` keeps `?locale=`
as an explicit highest-precedence override (validated against available locales), then falls back to the
negotiator, then to the default.

**Rationale**: The frontend will send the **effective** selected locale as `Accept-Language` (D4), so the
negotiator usually receives a single clean tag. But proper q-value/ordered negotiation with base fallback
keeps the API correct for direct/non-browser callers and makes `es-MX` resolve to `es` server-side too
(FR-004, FR-011). The current `header.scan(/[a-z]{2}/i).first` is replaced because it ignores q-weights and
ordering and would mis-handle e.g. `de, es;q=0.9` (picks unsupported `de`'s token → falls to default,
missing the supported `es`).

**Alternatives considered**:
- *Rails `http_accept_language` gem* — rejected: avoid a new dependency for ~20 lines; keep parsing in-repo
  and unit-tested.
- *Trust only `?locale=`* — rejected: header is the standard channel already wired through `apiClient`.

## D4 — Conveying the effective language to the server (resolves clarification Q2 / FR-016)

**Decision**: Change `apiClient.navigatorLang()` to return the **effective selected locale** (`i18n.language`)
instead of raw `navigator.language`, and send it as the `Accept-Language` header on every request. The route
request body already carries `locale` for routing/caching; that stays. Result: a visitor who overrode to `es`
gets `es` on geocode, cameras, and route error responses — not just the UI.

**Rationale**: Directly implements FR-016 ("send the effective selected language, server honors it"). The
header is already the wired channel; we only correct its *value*. Backend honors it via D3.

**Alternatives considered**:
- *Forward raw `navigator.language`* — rejected by clarification Q2: breaks server localization under override.
- *Server re-derives independently* — rejected: risks app/server divergence and ignores overrides.

## D5 — Persistence of the explicit choice (FR-007/FR-008/FR-008a)

**Decision**: Store the explicit choice in `localStorage` under key `flckd.locale` (value = a supported
locale code). Precedence at startup: **valid stored choice → environment-derived match → default**. A stored
value that is not a currently-supported locale is ignored and removed (FR + edge case). All `localStorage`
reads/writes are wrapped in `try/catch`; on failure the choice lives only in the in-memory i18n instance for
the session (FR-008a — no UI block/error). Clearing (the switcher's "automatic" option) removes the key and
re-resolves from the environment.

**Rationale**: localStorage is the minimal, anonymous, client-only persistent store consistent with the
account-less design (FR-015). The try/catch guard delivers the graceful-degrade behavior chosen in
clarification Q3.

**Alternatives considered**:
- *Cookie* — rejected: would be sent to the server on every request (unnecessary data egress) and complicates
  the strict-anonymity posture; localStorage stays on-device.
- *URL locale prefix* — rejected: changes routing/shareable URLs and conflicts with "preserve in-progress
  input" and the no-accounts framing; out of scope.

## D6 — No-flash, synchronous first paint (FR-001a / SC-001)

**Decision**: Keep i18n initialization synchronous at module load. Compute the effective locale (stored →
resolveLocale → default) **before** calling `i18n.init`, and pass it as `lng`. Because both locale bundles
are statically imported (no async resource loading), the first React render already has the correct language.
Assert it in e2e by checking the first painted heading/text is in the resolved language with no English
intermediate.

**Rationale**: Resources are bundled, so synchronous resolution is free and eliminates any flash (FR-001a).
This preserves the current synchronous-init structure rather than introducing a Suspense/async loader that
would reintroduce a flash.

**Alternatives considered**:
- *Async language detector / lazy locale chunks* — rejected: would flash the default while loading; violates
  FR-001a for the sake of a bundle-size saving that is negligible for two small JSON files.

## D7 — Map label language (US3 / FR-010)

**Decision**: Parametrize the two `symbol` label layers (`road-labels`, `place-labels`) so their `text-field`
is `["coalesce", ["get", "name:<lng>"], ["get", "name:en"], ["get", "name"]]`. `MapView.buildStyle` already
patches runtime fields; extend it to inject the selected `<lng>`. On `i18n.on("languageChanged")`, update both
layers via `map.setLayoutProperty(layerId, "text-field", expr)` so labels switch without a reload (AS3). The
`coalesce` chain provides the local/default fallback when `name:<lng>` is absent in the tile data (FR-010, no
blank labels).

The static `public/map-style.json` is **not** edited — it keeps `name:en` as the in-`coalesce` fallback; the
per-language field is built and applied at runtime in `MapView` so the file stays a single static default.

**Rationale**: Minimal, data-driven change localized to the style builder + a small map effect. Coalesce gives
the required graceful fallback. For `en`, behavior is identical to today (`name:en` → `name`).

**Alternatives considered**:
- *Full `map.setStyle` on every switch* — rejected: heavier (reloads sources/sprites, visible flash),
  `setLayoutProperty` on two layers is cheaper and meets the < 100 ms budget.
- *Server-side localized tiles* — rejected: tiles are shared/cacheable and carry no user data by design;
  per-language tilesets are unnecessary when the style can select the label field client-side.

## D8 — Authoritative supported-locale set (Dependencies)

**Decision**: Backend `config/locales/*.yml` (exposed via `GET /api/v1/meta/locales`) is the source of truth
for *which* locales exist; the frontend `SUPPORTED_LOCALES` constant mirrors it and is what the bundled
strings cover. Both currently list `en, es` and must stay in sync when a locale is added. Full dynamic
discovery (frontend fetching the set before resolving) is explicitly **out of scope** — it would reintroduce
an async pre-paint step (conflicts with D6) for no launch benefit at two locales.

**Rationale**: Keeps first paint synchronous (D6) while still honoring the Dependencies note that interface
and server agree on one catalog. Adding a locale is a deliberate, reviewed change in both places.

**Alternatives considered**:
- *Fetch `/meta/locales` before first paint* — rejected: async, would flash or delay first paint (FR-001a).
- *Generate the frontend list from the backend at build time* — viable future improvement; deferred as it
  isn't required to satisfy any FR at two locales.

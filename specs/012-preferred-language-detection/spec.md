# Feature Specification: Preferred Language Detection

**Feature Branch**: `012-preferred-language-detection`

**Created**: 2026-06-15

**Status**: Completed

**Input**: User description: "user's preferred language is derived from available environment/other info"

## Summary

When someone opens the app, the interface should already be in the language they are most likely to
understand — without making them hunt for a language menu first. Today the app makes a crude guess
(it looks at a single browser signal and only keeps the first two letters), and that guess is thrown
away the moment the page reloads. This feature makes the language **derived automatically from the
full set of signals the visitor's environment already provides** — their ordered list of preferred
languages and the relative strength of each — matched against the languages the app actually offers,
with sensible regional fallback. A visitor's own explicit choice always wins and is remembered, and
the chosen language is applied consistently everywhere the visitor reads text, including labels drawn
on the map. All of this happens with zero accounts and without sending any identifying information to
a third party.

## Clarifications

### Session 2026-06-15

- Q: Must the derived language be resolved before first paint, or is a brief flash of the default language acceptable? → A: No flash — the language MUST be fully resolved before the initial render.
- Q: How should the server learn which language to use for its responses, so they match what the visitor sees (including an explicit override)? → A: The app sends the resolved/effective selected language (including any override) to the server on each request; the server localizes its responses to that.
- Q: What should happen when on-device storage for the remembered choice is unavailable or blocked? → A: Degrade gracefully — the explicit choice still applies for the current session (in memory) but isn't remembered across visits; the UI never blocks or errors.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Interface opens in the visitor's best-available language automatically (Priority: P1)

A first-time visitor whose device is configured to prefer Spanish (then English) opens the app. Without
touching any setting, the entire interface — form labels, buttons, result messages, error text, and the
camera details popup — appears in Spanish, because Spanish is offered by the app and ranked highest among
the visitor's preferences. A different visitor who prefers only languages the app does not offer sees the
default language (English) instead of a broken or empty interface.

**Why this priority**: This is the core of the feature and the primary value — the right language on first
paint, derived purely from environment signals, with no manual step. Everything else builds on it.

**Independent Test**: Configure the test environment to advertise an ordered language preference list and
verify the rendered interface language matches the highest-ranked offered language (and falls back to the
default when none match). Fully testable on its own and delivers immediate value.

**Acceptance Scenarios**:

1. **Given** a visitor whose environment advertises Spanish ranked above English, **When** they open the app, **Then** the interface renders in Spanish on first paint with no manual selection.
2. **Given** a visitor whose environment advertises only languages the app does not offer, **When** they open the app, **Then** the interface renders in the default language (English) rather than empty or partial text.
3. **Given** a visitor whose environment advertises a regional variant of an offered language (for example a Mexico-region Spanish), **When** they open the app, **Then** the interface renders in the base offered language (Spanish) rather than falling through to the default.
4. **Given** a visitor whose environment advertises several offered languages with different strengths, **When** they open the app, **Then** the interface uses the offered language with the strongest preference, not merely the first one listed.

---

### User Story 2 - A visitor's own choice overrides the guess and is remembered (Priority: P2)

A visitor whose environment defaults them to English deliberately switches the app to Spanish. They use the
app, close the tab, and return later. The app reopens in Spanish — their explicit choice is honored over the
environment guess and survives a reload — until they choose to change it again. No account or login is
involved; the preference lives only on their own device.

**Why this priority**: The automatic guess is only ever a starting point. Respecting and remembering an
explicit override is what makes the experience feel correct over repeat visits, and it closes the existing
gap where any choice is discarded on reload. It depends on P1 being in place but adds clear, independent value.

**Acceptance Scenarios**:

1. **Given** a visitor whose environment would select English, **When** they manually switch to Spanish, **Then** the interface immediately re-renders in Spanish without losing any text they have already entered.
2. **Given** a visitor who previously made an explicit language choice, **When** they reopen the app later on the same device, **Then** the app starts in their chosen language, ignoring the environment guess.
3. **Given** a visitor who has an explicit choice remembered, **When** they reset that preference, **Then** the app returns to deriving the language automatically from environment signals.

---

### User Story 3 - Map labels match the interface language (Priority: P3)

A visitor using the app in Spanish looks at the map. Place and road labels rendered on the map appear in
Spanish where that label is available in the underlying map data, and gracefully fall back to the local or
default name where a Spanish label does not exist — so the map reads consistently with the rest of the
interface rather than always showing English.

**Why this priority**: A high-value consistency improvement that removes a jarring mismatch (Spanish UI, English
map). It is genuinely independent — the map renders fine without it — so it is the lowest of the three, but it
completes the "language applied everywhere" promise.

**Acceptance Scenarios**:

1. **Given** the interface is in Spanish, **When** the map renders labels, **Then** labels show the Spanish name where the map data provides one.
2. **Given** the interface is in Spanish and a particular feature has no Spanish label in the map data, **When** that feature is labeled, **Then** the local or default name is shown rather than a blank label.
3. **Given** the visitor switches the interface language at runtime, **When** the switch completes, **Then** map labels update to reflect the newly selected language without requiring a page reload.

---

### Edge Cases

- **No usable environment signal**: The environment advertises no language preference at all → the app uses the default language (English).
- **Malformed or unexpected preference data**: A preference entry is empty, wildcard (`*`), or malformed → it is ignored and matching continues with the remaining valid entries; if none remain, the default is used.
- **Conflicting strengths/ties**: Two offered languages are advertised with equal strength → a deterministic tie-break (advertised order) selects one, so the result is stable and not random across loads.
- **Stored preference references a no-longer-offered language**: A remembered explicit choice points to a language the app no longer offers → the app discards it and re-derives from environment signals.
- **On-device storage unavailable**: Storage for the remembered choice is blocked or fails (private browsing, denied permissions, quota error) → an explicit choice applies for the current session only; the next visit re-derives from environment signals, with no UI block or error.
- **Partial translation coverage**: A selected language is missing a small number of strings → the missing strings fall back to the default language rather than showing blank or key-like placeholders.
- **Backend and interface disagree**: The text the app renders itself and any text returned by the server (such as error messages) must resolve to the same selected language for a given visit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST derive the initial interface language automatically from the visitor's environment-advertised language preferences, with no manual step required on first visit.
- **FR-001a**: The selected language MUST be fully resolved before the interface's initial render — the visitor MUST NOT see a flash of the default language before the derived language is applied.
- **FR-002**: The system MUST consider the visitor's full ordered list of preferred languages and their relative strengths (not only the single first entry) when deriving the language.
- **FR-003**: The system MUST match advertised preferences against the set of languages the app actually offers and select the offered language that best satisfies the visitor's preferences.
- **FR-004**: When an advertised preference specifies a regional variant of an offered language, the system MUST fall back to the base offered language rather than skipping to the default.
- **FR-005**: When no advertised preference matches an offered language, the system MUST use the default language (English) and render a complete interface.
- **FR-006**: The system MUST allow the visitor to explicitly override the derived language at any time, and the override MUST take effect immediately without discarding text the visitor has already entered.
- **FR-007**: The system MUST remember a visitor's explicit language choice across reloads and return visits on the same device, and MUST prefer that remembered choice over the environment-derived guess.
- **FR-008**: The system MUST provide a way for the visitor to clear their remembered choice and return to automatic derivation.
- **FR-008a**: When on-device storage is unavailable or blocked, the system MUST degrade gracefully — an explicit choice still applies for the current session but is not remembered across reloads/return visits, and the interface MUST NOT block or surface an error for this condition.
- **FR-009**: The system MUST apply the selected language consistently to all visitor-facing text it controls, including form labels, action buttons, result and status messages, error messages, and the camera details popup.
- **FR-010**: The system MUST render labels drawn on the map in the selected language where the underlying map data provides that language, and MUST fall back to a local or default name where it does not — never showing a blank label.
- **FR-011**: Any text produced by the server for a given visit (such as error or status messages) MUST resolve to the same selected language as the rest of the interface for that visit. (Mechanism: FR-016.)
- **FR-012**: The system MUST handle missing, empty, wildcard, or malformed preference entries by ignoring them and continuing to evaluate the remaining valid entries.
- **FR-013**: Language derivation MUST be deterministic for identical inputs — the same environment signals and remembered state MUST always yield the same selected language, with ties broken by a stable rule.
- **FR-014**: When a selected language is missing individual strings, the system MUST fall back to the default language for those strings rather than displaying blank or identifier-like placeholders.
- **FR-015**: The system MUST NOT require an account, login, or any personally identifying information to derive, apply, or remember the language, and MUST NOT transmit any persistent identifier or the visitor's route data to any third party as part of language handling. The remembered preference MUST live only on the visitor's own device.
- **FR-016**: The app MUST communicate the **effective selected language** — the resolved result including any explicit override, not merely the raw environment signal — to the server on each request, so the server localizes its responses to exactly what the visitor sees. The server MUST honor this conveyed language rather than independently re-deriving from the environment signal.

### Key Entities *(include if data involved)*

- **Supported Languages**: The set of languages the app offers, each identified by a language code and a human-readable display name. This set is the authoritative list that all derivation and matching is performed against.
- **Advertised Preference**: The visitor's environment-provided, ordered list of preferred languages with relative strengths. Consumed as input; never stored or sent anywhere beyond what is needed to localize the current visit.
- **Selected Language**: The single language currently in effect for the visit, resulting from precedence: remembered explicit choice → environment-derived best match → default.
- **Remembered Choice**: A visitor's explicit language selection, stored only on their own device, with no associated identity, used to override automatic derivation until cleared.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A visitor whose top environment preference is an offered language sees the interface in that language on the very first rendered frame — with no manual interaction and no visible flash of the default language — in at least 99% of cases.
- **SC-002**: A visitor whose advertised preferences match no offered language always sees a complete default-language interface with zero blank or placeholder strings.
- **SC-003**: A visitor whose top preference is a regional variant of an offered language is matched to the base offered language (not the default) in 100% of such cases.
- **SC-004**: After making an explicit language choice, a visitor returning on the same device starts in that chosen language in 100% of reloads and return visits until they clear it.
- **SC-005**: For a visit in a given selected language, every piece of visitor-facing text — including server-produced messages and map labels where data exists — renders in that language, with no mixed-language interface visible to the visitor.
- **SC-006**: Language derivation produces the same result for identical inputs on every run (deterministic), verified across repeated trials.
- **SC-007**: No accounts, no personally identifying information, and no persistent identifier leave the visitor's device as part of language handling.

## Assumptions

- **Scope is the derivation and application mechanism, not the catalog of languages.** This feature improves how the app chooses and applies a language from existing signals; English and Spanish are the currently offered languages, and the mechanism is built to be language-agnostic so additional languages can be added later without reworking it.
- **English is the default/fallback language** when no preference matches and no explicit choice exists.
- **"Available environment/other info" refers to the visitor's standard, already-available language signals** (the device/browser's ordered preferred-language list and the strengths it advertises) plus a previously remembered on-device choice — not new tracking, fingerprinting, geolocation, or additional data collection.
- **Regional fallback is base-language only** (for example, a Mexico-region Spanish maps to the offered Spanish); the app does not maintain region-specific variant translations.
- **Remembered choice is stored client-side only** (on the visitor's own device), consistent with the project's strict-anonymity, account-less design; it is never persisted server-side or tied to an identity.
- **Map label language depends on the underlying map data.** Where the map data lacks a label in the selected language, falling back to the local or default name is acceptable and expected.
- **The existing i18n foundation is reused.** The app already auto-detects a single browser signal, sends a language hint to the server, offers a manual switcher, and ships English/Spanish strings; this feature strengthens and completes that foundation rather than replacing it.

## Dependencies

- Requires the languages the app offers to be defined in one authoritative place that both interface and server agree on, so derived selections always resolve to a real, fully translated language.
- Requires the underlying map data to expose language-specific label fields for map-label matching (User Story 3); where it does not, fallback behavior applies.

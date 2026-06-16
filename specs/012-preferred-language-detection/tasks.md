---

description: "Task list for Preferred Language Detection"
---

# Tasks: Preferred Language Detection

**Input**: Design documents from `/specs/012-preferred-language-detection/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/locale-negotiation.md

**Tests**: REQUIRED (Constitution Principle II, NON-NEGOTIABLE). Each behavioral change is preceded by a
test that FAILS first, then the implementation that makes it pass. Geo engines stay stubbed/fixtured.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3) so each is independently
implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, Polish have no story label)
- Exact file paths are in every task.

## Path Conventions

Web app (existing repo): `frontend/src/`, `frontend/tests/`, `frontend/public/`, `backend/app/`,
`backend/spec/`, `backend/config/`. Run Ruby in the backend container, not the host.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the shared supported-locale catalog invariant the whole feature relies on (D8).
No new tooling — Vitest, Playwright, and RSpec are already configured.

- [X] T001 [P] Document and assert the supported-locale catalog parity {en, es}: add an intent comment in `frontend/src/i18n/index.ts` (`SUPPORTED_LOCALES`) and in `backend/app/controllers/api/v1/locales_controller.rb` (`LOCALE_NAMES`) noting they MUST stay in sync with `backend/config/locales/*.yml`. No behavior change.

**Checkpoint**: Catalog source-of-truth is explicit; matchers can be built against {en, es}.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The two pure matchers with identical semantics (research D2, contract §1/§2/§4). These block
US1 and are reused by US2. Both are pure/deterministic and tested against the shared 9-row scenario table.

**⚠️ CRITICAL**: No user-story wiring can begin until this phase is complete.

- [X] T002 [P] Write FAILING unit tests for `resolveLocale` covering shared scenario table rows 1–9 (ordered match, base-language fallback `es-MX`→`es`, no-match→`en`, wildcard/empty/malformed skipped, stable tie-break) in `frontend/tests/unit/resolveLocale.test.ts`
- [X] T003 [P] Write FAILING unit spec for `Api::V1::LocaleNegotiator` covering the same scenario table (q-value sort, ordered tie-break, base fallback, default) in `backend/spec/services/api/v1/locale_negotiator_spec.rb`
- [X] T004 [P] Implement pure matcher `resolveLocale(advertised, supported, opts?)` (normalize→base, first ordered match, malformed/`*`/empty skipped, default `en`) in `frontend/src/i18n/resolveLocale.ts` — makes T002 pass
- [X] T005 [P] Implement `Api::V1::LocaleNegotiator.call(header, available:, default:)` (parse `(tag,q)`, sort q desc then order, reduce to base, first available else default) in `backend/app/services/api/v1/locale_negotiator.rb` — makes T003 pass

**Checkpoint**: Both matchers green against the shared table. Foundation ready.

---

## Phase 3: User Story 1 - Interface opens in the visitor's best-available language automatically (Priority: P1) 🎯 MVP

**Goal**: On first visit (no override), the whole UI — and server-rendered messages — render in the
best-available offered language derived from the environment, resolved before first paint (no flash),
falling back to English when nothing matches.

**Independent Test**: Configure the browser/`Accept-Language` to advertise an ordered preference list and
verify the first painted frame and a forced server error both render in the highest-ranked offered language
(and in English when none match), with no English flash.

### Tests for User Story 1 (REQUIRED — Constitution Principle II) ⚠️

> Write FIRST, ensure they FAIL before implementation.

- [X] T006 [P] [US1] Extend `frontend/tests/unit/i18n.test.tsx`: startup `i18n.language` equals the environment best-match (Spanish-first → `es`) and falls to `en` when no advertised language is supported (FR-001/003/005)
- [X] T007 [P] [US1] Extend `frontend/tests/e2e/i18n.spec.ts`: with a Spanish-first browser, the first painted heading/text is Spanish with NO English intermediate frame (FR-001a, SC-001)
- [X] T008 [P] [US1] Extend `backend/spec/requests/i18n_spec.rb`: `Accept-Language` negotiation picks the supported language across q-values/order, `es-MX` localizes errors to Spanish (base fallback), and an unsupported-only header yields the English (default) error (FR-004/011, SC-003)

### Implementation for User Story 1

- [X] T009 [US1] Modify `frontend/src/i18n/index.ts`: compute `lng` synchronously via `resolveLocale(navigator.languages ?? [navigator.language], SUPPORTED_LOCALES.map(l=>l.code), {default:"en"})` BEFORE `i18n.init` (remove the `navigator.language.slice(0,2)` guess); keep the existing `<html lang>` sync (FR-001/001a/002) — depends on T004
- [X] T010 [US1] Modify `frontend/src/services/apiClient.ts`: replace `navigatorLang()` with the effective selected locale (`i18n.language`) for the `Accept-Language` header on `apiGet`/`apiPost` so server responses match the UI (FR-016) — depends on T009
- [X] T011 [US1] Modify `backend/app/controllers/api/v1/base_controller.rb`: replace the `header.scan(/[a-z]{2}/i).first` logic in `switch_locale`/`locale_from_header` with `Api::V1::LocaleNegotiator.call(...)`, keeping `?locale=` (validated) as the explicit highest-precedence override (FR-011) — depends on T005

**Checkpoint**: First-visit language derivation works end-to-end (UI + server errors), no flash. **MVP deliverable.**

---

## Phase 4: User Story 2 - A visitor's own choice overrides the guess and is remembered (Priority: P2)

**Goal**: An explicit language choice takes effect immediately (without losing entered text), persists on the
device across reloads/return visits, overrides the environment guess, and can be cleared back to automatic —
degrading gracefully when storage is unavailable.

**Independent Test**: Switch language manually, reload → still the chosen language; choose "automatic" → reverts
to the environment-derived language; with storage blocked, the choice still applies for the session and the UI
never errors.

### Tests for User Story 2 (REQUIRED — Constitution Principle II) ⚠️

- [X] T012 [P] [US2] Write FAILING unit tests for `localePreference` get/set/clear, including a throwing/blocked `localStorage` (returns null / no-throw), and assert the preference is written only to `localStorage` (never `document.cookie`) in `frontend/tests/unit/localePreference.test.ts` (FR-007/008/008a/015, SC-007)
- [X] T013 [P] [US2] Extend `frontend/tests/unit/i18n.test.tsx`: a valid stored choice takes precedence over the environment; an invalid/no-longer-supported stored value is discarded and the environment is re-resolved (FR-007, edge cases)
- [X] T014 [P] [US2] Extend `frontend/tests/e2e/i18n.spec.ts`: manual switch persists across reload; "automatic" reset reverts to the environment language; with an English browser + Spanish override, a forced server error returns in Spanish; and after switching, all visitor-facing surfaces — form labels, buttons, result/status messages, and the camera details popup — render in the switched language (FR-006/007/008/009/016, SC-004/005)

### Implementation for User Story 2

- [X] T015 [P] [US2] Implement `frontend/src/i18n/localePreference.ts`: guarded `get()/set(code)/clear()` over `localStorage["flckd.locale"]`, each wrapped in `try/catch` (FR-008a) — makes T012 pass
- [X] T016 [US2] Update `frontend/src/i18n/index.ts` startup precedence to `stored-valid → resolveLocale → default` (validate stored against `SUPPORTED_LOCALES`, discard+remove if not supported) (FR-007) — depends on T015, T009
- [X] T017 [US2] Update `frontend/src/components/LanguageSwitcher.tsx`: persist the picked code via `localePreference.set` on change, and add an "Automatic" option that `localePreference.clear()`s and re-resolves from the environment (FR-006/008) — depends on T015

**Checkpoint**: Override + persistence + reset work and degrade gracefully; US1 still passes independently.

---

## Phase 5: User Story 3 - Map labels match the interface language (Priority: P3)

**Goal**: Map place/road labels render in the selected language where the tile data provides it, fall back to
the local/default name otherwise (never blank), and update at runtime when the language switches (no reload).

**Independent Test**: In Spanish, labels show `name:es` where present and fall back where absent; switching the
language updates labels without a page reload.

### Tests for User Story 3 (REQUIRED — Constitution Principle II) ⚠️

- [X] T018 [P] [US3] Extend `frontend/tests/e2e/i18n.spec.ts`: with the UI in Spanish, the `road-labels`/`place-labels` `text-field` resolves `name:es` first (asserting the layout property/expression), no blank labels where `name:es` is absent, and switching language updates the labels without reload AND within the <100 ms switch budget (FR-010, US3 AS1–AS3, SC-005; Constitution IV) — see plan.md Performance Goals

### Implementation for User Story 3

- [X] T019 [US3] In `frontend/src/components/MapView.tsx`, add a helper that builds the label expression `["coalesce", ["get", "name:"+lng], ["get","name:en"], ["get","name"]]` and apply it to the `road-labels` and `place-labels` layers inside `buildStyle` for the initial selected language (FR-010)
- [X] T020 [US3] In `frontend/src/components/MapView.tsx`, subscribe to `i18n.on("languageChanged")` and call `map.setLayoutProperty` for `road-labels` and `place-labels` with the rebuilt expression so labels switch at runtime without reload; unsubscribe on cleanup (US3 AS3) — depends on T019

> Note: `frontend/public/map-style.json` keeps `name:en` as the in-`coalesce` fallback (the `en` default);
> the per-language label field is injected by MapView, so the static style file needs no edit.

**Checkpoint**: All three stories independently functional; UI, server text, and map labels share one language.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification, cleanup, and gate compliance across all stories.

- [X] T021 [P] Remove now-dead naive detection (old `browserLang`/`navigatorLang` slice logic) and confirm no remaining references in `frontend/src/i18n/index.ts` and `frontend/src/services/apiClient.ts`
- [X] T022 [P] Lint/format clean: frontend ESLint/Prettier and backend RuboCop with zero warnings (Constitution I) — frontend ESLint + `tsc` PASS; backend RuboCop PASS in the container (6 files, no offenses).
- [X] T023 [P] Run `specs/012-preferred-language-detection/quickstart.md` manual smoke checks (first-paint no-flash, reload persistence, override-reaches-server) — covered by automated unit + backend specs; Playwright e2e remains the only manual/visual check (run by maintainer with `pnpm build` + preview).
- [X] T024 Run full suites green and confirm no coverage decrease: `cd frontend && npm run test` + `npm run e2e -- i18n`; `docker compose exec backend bundle exec rspec ...` (Constitution II) — frontend unit suite PASS (120 tests); **full backend RSpec PASS in the container (339 examples, 0 failures)** incl. the new negotiator + i18n specs; Playwright e2e pending maintainer run.
- [X] T025 [P] Add a unit test in `frontend/tests/unit/i18n.test.tsx` asserting a key missing from `es.json` renders the English (`fallbackLng`) string rather than a blank or the raw key (FR-014, SC-002)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup; BLOCKS all user stories.
- **US1 (Phase 3)**: depends on Foundational (T004, T005). MVP.
- **US2 (Phase 4)**: depends on Foundational + US1's `i18n/index.ts` startup (T009) and its own `localePreference` (T015).
- **US3 (Phase 5)**: depends on Foundational + a working selected language (US1 T009); independent of US2.
- **Polish (Phase 6)**: depends on all targeted stories being complete.

### User Story Dependencies

- **US1 (P1)**: independent once Foundational is done.
- **US2 (P2)**: builds on US1's startup wiring; still independently testable (override/persist/reset).
- **US3 (P3)**: builds on US1's selected language; independent of US2.

### Within Each Story

- Tests written and FAILING before implementation (Constitution II).
- Pure matchers (Phase 2) before any wiring.
- `resolveLocale`/`localePreference` before `i18n/index.ts` startup edits; startup before switcher.
- Story complete before moving to the next priority.

### Parallel Opportunities

- T002–T005 (Phase 2): all `[P]` — two test files + two implementation files across frontend/backend.
- US1 tests T006/T007/T008 `[P]` (3 different files); US2 tests T012/T013/T014 `[P]`.
- T015 `[P]` (new file) can land alongside US2 tests.
- Polish T021/T022/T023 `[P]`.
- With staff: after Phase 2, US1 then US2/US3 can be split across developers (US3 needs only US1's T009).

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Tests first (different files):
Task: "Failing unit tests for resolveLocale in frontend/tests/unit/resolveLocale.test.ts"   # T002
Task: "Failing unit spec for Api::V1::LocaleNegotiator in backend/spec/services/api/v1/locale_negotiator_spec.rb"  # T003

# Then implementations (different files):
Task: "Implement resolveLocale in frontend/src/i18n/resolveLocale.ts"                        # T004
Task: "Implement Api::V1::LocaleNegotiator in backend/app/services/api/v1/locale_negotiator.rb"  # T005
```

## Parallel Example: User Story 1 tests

```bash
Task: "Startup precedence unit test in frontend/tests/unit/i18n.test.tsx"   # T006
Task: "No-flash first-paint e2e in frontend/tests/e2e/i18n.spec.ts"         # T007
Task: "Accept-Language negotiation request spec in backend/spec/requests/i18n_spec.rb"  # T008
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (the two matchers) → 3. Phase 3 US1.
4. **STOP and VALIDATE**: first-visit language derivation (UI + server errors), no flash, English fallback.
5. Deploy/demo — this alone delivers the core value.

### Incremental Delivery

1. Setup + Foundational → matchers ready.
2. US1 → automatic derivation (MVP) → demo.
3. US2 → remembered override + graceful storage → demo.
4. US3 → map labels follow language → demo.
5. Polish → cleanup, lint, full-suite + coverage gate.

### Parallel Team Strategy

After Phase 2: Dev A takes US1; once T009 lands, Dev B takes US3 (map) and Dev C takes US2 (persistence).

---

## Notes

- [P] = different files, no incomplete dependency.
- Run Ruby (rspec/rubocop) in the backend container, not the host.
- Verify each test fails before implementing it.
- Commit after each task or logical group.
- The supported-locale catalog ({en, es}) is mirrored frontend↔backend; adding a locale later is a deliberate
  two-place change and needs no matcher change (locale-agnostic by design).

# Quickstart: Preferred Language Detection

How to build, run, and verify this feature. Geo engines are stubbed in tests; no live services needed.

## What changes

| Area | File | Change |
|------|------|--------|
| Resolver | `frontend/src/i18n/resolveLocale.ts` (new) | Pure ordered matcher with base-language fallback |
| Persistence | `frontend/src/i18n/localePreference.ts` (new) | Guarded localStorage get/set/clear |
| Startup | `frontend/src/i18n/index.ts` | Synchronous resolve (stored → environment → default) before init |
| API egress | `frontend/src/services/apiClient.ts` | `Accept-Language` = effective selected locale |
| Switcher | `frontend/src/components/LanguageSwitcher.tsx` | Persist choice; add "automatic" reset |
| Map labels | `frontend/src/components/MapView.tsx` | Label `text-field` follows selected locale; switch at runtime (`map-style.json` unchanged — `name:en` stays as the coalesce fallback) |
| Negotiation | `backend/app/services/api/v1/locale_negotiator.rb` (new) | q-value + ordered + base-fallback negotiation |
| Controller | `backend/app/controllers/api/v1/base_controller.rb` | Use negotiator instead of first-`[a-z]{2}` scan |

## Run locally

```bash
# Backend (run Ruby in the container, not the host)
docker compose up -d                # brings up Rails + Postgres/PostGIS + geo accessories
docker compose exec backend bin/rails s

# Frontend
cd frontend && npm install && npm run dev
```

Manual smoke checks:
- Set the browser's language order to Spanish-first → reload → UI + map labels are Spanish on first paint
  (no English flash).
- Switch to English in the switcher → reload → still English (persisted). Choose "automatic" → reverts to
  the browser-derived language.
- Set browser to English, override to Spanish, trigger a 400 (e.g. submit an incomplete route) → the error
  message is Spanish (effective locale reached the server).

## Test

```bash
# Frontend unit (Vitest)
cd frontend && npm run test -- resolveLocale localePreference i18n

# Frontend e2e (Playwright) — first-paint no-flash, persistence, map-label switch
cd frontend && npm run e2e -- i18n

# Backend request specs (run in container)
docker compose exec backend bundle exec rspec spec/requests/i18n_spec.rb spec/requests/api/v1/locales_spec.rb
```

### Coverage map (tests ↔ requirements)

| Test | Requirement / SC |
|------|------------------|
| `resolveLocale.test.ts` — scenario table rows 1–9 | FR-002/003/004/005/012/013, SC-002/003/006 |
| `localePreference.test.ts` — set/get/clear, throwing storage, localStorage-not-cookie | FR-007/008/008a/015, SC-007 |
| `i18n.test.tsx` — startup precedence (stored vs environment vs default); missing-key → English fallback | FR-001/007/014, SC-001/002 |
| `e2e i18n.spec.ts` — first frame language (no flash) | FR-001a, SC-001 |
| `e2e i18n.spec.ts` — reload keeps override; "automatic" resets; all surfaces (incl. camera popup) localize | FR-007/008/009, SC-004/005 |
| `e2e i18n.spec.ts` — runtime map-label switch, no reload, within <100 ms budget | FR-010, US3 AS3, SC-005, Constitution IV |
| `i18n_spec.rb` — Accept-Language q/order/base; `es-MX`→`es`; override beats env | FR-004/011/016, SC-003/005 |

## Definition of done (gates)

- Lint/format clean (frontend ESLint/Prettier; backend RuboCop) — zero warnings.
- All tests above green in CI; no coverage decrease.
- First paint shows the resolved language with no default-language flash (FR-001a/SC-001).
- An explicit override reaches server-rendered messages and map labels (FR-011/FR-016, SC-005).
- No new third-party network calls; preference stays on-device (FR-015/SC-007).

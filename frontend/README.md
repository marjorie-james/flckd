# flckd — Frontend (React SPA)

Mobile-first, multi-lingual single-page app for the Camera-Avoiding Route Planner. Renders the map
with **MapLibre GL JS** against **self-hosted vector tiles only** (no API keys, no third-party tiles)
and talks to the Rails API under `/api/v1`. Localized from day one (i18next) — the UI language is
auto-detected from the visitor's environment before first paint, with an explicit choice remembered
on-device — and account-less by design.

Key UI: **always-maximal camera avoidance** (no slider — the planner always prefers a route past *no*
camera, auto-falling back to the fewest-cameras route, never erroring), a prominent **`RouteNotice`**
banner when the chosen route still passes within view of some cameras (`is_fully_clean: false`), the
recommended route plus a dashed fastest-route comparison line, and a camera layer that snaps each camera
to its road with a directional "vision cone" (or a 360° halo) and a localized details popup.

## Stack

- **React 19** + **TypeScript** + **Vite 8**
- **MapLibre GL JS** (self-hosted PMTiles)
- **TanStack Query** (data fetching), **i18next** / **react-i18next** (i18n)
- **Vitest** + **Testing Library** (unit), **ESLint** (lint)

## Setup (Docker-only)

Local development runs entirely in Docker — no host Node/pnpm install. From the **repo root**:

```bash
# Dev server with HMR (proxies /api to the backend over the compose network)
docker compose -f infra/docker-compose.yml up frontend   # http://localhost:5173
```

The `frontend` service builds [`Dockerfile.dev`](Dockerfile.dev); deps live in a named volume
(`frontend_node_modules`), so the host stays clean and platform binaries are built for the container.
After changing dependencies, rebuild: `docker compose -f infra/docker-compose.yml build frontend`.

## Scripts

Run any script inside the container, e.g.
`docker compose -f infra/docker-compose.yml run --rm frontend <script>`:

| Command | What it does |
|---------|--------------|
| `pnpm dev` | Vite dev server with HMR |
| `pnpm build` | Type-check (`tsc -b`) + production build |
| `pnpm test -- run` | Run the Vitest unit suite once |
| `pnpm lint` | ESLint (zero warnings required) |
| `pnpm gen:types` | Regenerate `src/types/openapi.d.ts` from the OpenAPI contract |

## Types & contract sync

`src/types/api.ts` holds the curated working types used across the app. The full API contract is
generated verbatim into `src/types/openapi.d.ts` from
[`contracts/openapi.yaml`](../specs/002-flock-route-avoidance/contracts/openapi.yaml) via
`pnpm gen:types`, and is type-checked by the build. Regenerate after any contract change.

## Tests

```bash
# Unit (Vitest + Testing Library, jsdom)
docker compose -f infra/docker-compose.yml run --rm frontend pnpm test -- run
docker compose -f infra/docker-compose.yml run --rm frontend pnpm lint

# E2E (Playwright) — runs the production build with the API mocked, in the
# official Playwright image (browsers preinstalled); node_modules is isolated
# so the host is never touched:
docker run --rm --ipc=host -v "$PWD/frontend":/work -v /work/node_modules -w /work \
  -e CI=1 mcr.microsoft.com/playwright:v1.60.0-noble \
  bash -lc "npm i -g pnpm@11.5.2 >/dev/null 2>&1 && pnpm install && pnpm build && pnpm exec playwright test"
```

Unit tests live under `tests/` (and `tests/unit/`); WebGL/MapLibre are mocked so component tests stay
deterministic. Geo/API calls are stubbed at the fetch layer — no network, no third-party requests.
E2E specs live under `tests/e2e/` and stub the API via `page.route` (no live geo stack needed).

## Project layout

```
src/
├── components/   # MapView, RoutePanel, AddressAutocomplete, RouteResult, RouteNotice,
│                 # CameraLayer, CameraSummary, LanguageSwitcher, RouteExport
├── pages/        # PlanRoutePage
├── services/     # apiClient, routeApi, geocodeApi, cameraApi, coverageApi (TanStack Query)
├── hooks/        # useGeolocation, useDebounce
├── i18n/         # i18next config + locales; resolveLocale (env matcher) + localePreference (stored choice)
└── types/        # api.ts (curated) + openapi.d.ts (generated)
```

## Anonymity notes

- Language preference is stored **client-side only** and is non-identifying.
- No third-party assets/fonts/scripts/tiles — everything is same-origin (CSP-aligned).
- A route is never transmitted off-device — the only way to take one with you is a fully client-side
  **GPX export** (`RouteExport` builds the file in the browser; nothing is sent to any third party),
  gated behind a warning that the saved file itself holds your route.

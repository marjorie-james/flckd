# flckd — Main Implementation Plan

> Consolidated architecture/plan reflecting the *implemented* state of the project. Each archived
> feature appends its new dependencies, modules, configuration, routing, and test strategy here.
>
> **Bootstrapped** from the first archival (`013-printable-directions`) on 2026-06-18.

## Architecture Overview

- **Backend**: Ruby 3.4.x + Rails 8.1.x (API mode). Rails 8.1 built-ins in use: Solid Queue (jobs,
  with job continuations), Solid Cache, Propshaft, Kamal 2 + Thruster (deploy). No Rails auth
  generator (account-less by design).
- **Frontend**: TypeScript + React 19, Vite, MapLibre GL JS.
- **Data**: PostgreSQL 17 + PostGIS.
- **Self-hosted geo stack** (own infrastructure — never third parties): Valhalla
  (segment-exclusion routing), Nominatim (forward/reverse geocoding), self-hosted vector tiles
  (Protomaps PMTiles via go-pmtiles). The same engines run in dev (docker-compose) and prod (Kamal
  accessories) — no dev/prod geocoder/tile drift.

## Primary Dependencies

- **Backend**: Rails 8.1.x, Solid Queue / Solid Cache, PostGIS bindings.
- **Frontend**: React 19, react-i18next (localization), Vite, MapLibre GL JS.
- **Printing** [Source: specs/013-printable-directions]: none added — uses the browser-native
  `window.print()` API plus a `@media print` stylesheet. No PDF library, no new dependency.

## Project Structure

```text
backend/                         # Ruby 3.4 + Rails 8.1 API
└── ...                          # routing (Valhalla), geocoding (Nominatim), camera services

frontend/
├── src/
│   ├── components/
│   │   ├── PrintableDirections.tsx   # [013] icon trigger + print-only view (window.print)
│   │   ├── RouteResult.tsx           # [013] mounts print control atop directions; gains
│   │   │                             #       originLabel / destinationLabel props
│   │   ├── RoutePanel.tsx            # [013] surfaces confirmed origin/dest labels upward (onPlan)
│   │   └── ...                       # RouteNotice, CameraSummary, RouteExport, map, etc.
│   ├── pages/
│   │   └── PlanRoutePage.tsx         # [013] holds origin/dest labels alongside endpoints
│   ├── i18n/locales/
│   │   ├── en.json                   # [013] adds print.* keys
│   │   └── es.json                   # [013] Spanish parity
│   └── App.css                       # [013] @media print block + print control styles
└── tests/
    ├── printable-directions.test.tsx # [013] control + print-view behavior
    └── route-result.test.tsx         # [013] print control mounts atop directions; label propagation
```

## Configuration

- No new environment variables or config introduced by `013-printable-directions` (frontend-only,
  client-side print).

## Routing & Navigation

- No new HTTP routes/endpoints from `013-printable-directions`. The backend `Route` response is
  unchanged; the print view renders entirely from data already on the client. Frontend wiring change:
  origin/destination labels flow `RoutePanel → PlanRoutePage → RouteResult → PrintableDirections`
  (`onPlan` extended to carry the confirmed labels at plan time).

## Testing Strategy

- **Frontend**: Vitest + @testing-library/react (`frontend/tests/`). Geo/print side effects stubbed
  for determinism — `window.print` stubbed via `vi.spyOn(window, "print")`; print-CSS visual rules
  covered by structural assertions (jsdom does not paginate). Per Constitution Principle II, every
  behavioral change ships with tests that would fail without it. [Source: specs/013-printable-directions]
- **Backend**: RSpec; geo services stubbed with recorded fixtures.

## Non-Negotiables (enforced)

- **Strict anonymity** — no third party ever receives a user's origin/destination/route; no
  accounts/PII; no persistent identifiers; logs retain no route coordinates or client IPs. The only
  way a route leaves the app is a user-initiated, fully client-side GPX export. The printable
  directions feature preserves this: `window.print()` is fully local and issues zero network requests
  (FR-013, SC-006).
- **Camera avoidance** = exclude the specific monitored road segment(s) (snap-to-road), not a radius.
- **Tests required** for every behavioral change; geo services stubbed with recorded fixtures.

## Revision Log

- **2026-06-18** — Bootstrapped main plan from first archival; merged `013-printable-directions`
  (frontend-only print control + print-only view; `PrintableDirections` component; print stylesheet;
  origin/dest label lift; print.* i18n keys; no new deps, routes, or config).

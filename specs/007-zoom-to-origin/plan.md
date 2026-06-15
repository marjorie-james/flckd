# Implementation Plan: Zoom to Starting Address

**Branch**: `007-zoom-to-origin` | **Date**: 2026-06-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-zoom-to-origin/spec.md`

## Summary

When the user confirms a starting address, recenter the self-hosted MapLibre map on that point at a
consistent street-level zoom and place a single marker there. The move is a smooth, short animation by
default and an instant jump when the user prefers reduced motion. The marker tracks the current
starting location (moves on re-selection, disappears when the starting point is cleared). All map
content for the new view comes only from the app's own tile service — the origin coordinate never
leaves the client, preserving strict anonymity.

Technical approach: lift the confirmed `origin` coordinate from `RoutePanel` up to `PlanRoutePage`
(matching the existing parent-mediated data flow) and pass it to `MapView` as a prop. `MapView` gains
a recenter effect (`flyTo`/`jumpTo` gated on a reduced-motion check) and an origin marker rendered as
a GeoJSON source + layer — the pattern already used for cameras and the route line. No new
dependencies, no backend changes, no new network calls.

## Technical Context

**Language/Version**: TypeScript 5.x, React 19 (frontend only — no backend changes)

**Primary Dependencies**: MapLibre GL JS (map + camera + GeoJSON layers), Vite, @tanstack/react-query,
react-i18next

**Storage**: N/A — starting location is ephemeral client-side state; nothing is persisted (anonymity)

**Testing**: Vitest + @testing-library (unit/component, maplibre-gl stubbed), Playwright (e2e, real map
with stubbed network)

**Target Platform**: Modern evergreen browsers, mobile-first responsive web app

**Project Type**: Web application (existing `frontend/` + `backend/`); this feature is **frontend-only**

**Performance Goals**: map visually centered on the address within 1.5 s including animation (SC-001);
recenter animation bounded (~600 ms, ≤1 s) and runs at the map's native frame rate without main-thread
jank

**Constraints**: strict anonymity — recentering MUST NOT transmit the origin coordinate to any third
party and MUST source tiles only from the self-hosted tile service (FR-009); reduced-motion preference
MUST be honored (FR-004); behavior identical whether origin comes from address selection or "use my
location" (FR-010)

**Scale/Scope**: small, self-contained frontend change — `MapView`, `RoutePanel`, `PlanRoutePage`, one
small reduced-motion utility, plus unit/e2e tests. ~3 components touched.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Assessment |
|-----------|------|------------|
| **I. Code Quality** | Lint/format zero warnings; single-responsibility units; intent comments; no dead code | PASS (planned). New units are small and single-purpose: a `prefersReducedMotion()` util, an origin-recenter effect, an origin-marker source/layer. Each documented with the "why" (e.g., why a fixed zoom, why GeoJSON over `Marker`). ESLint + `tsc -b` run clean. |
| **II. Testing (NON-NEGOTIABLE)** | Every behavioral change has tests that fail without it; deterministic; behavior-focused | PASS (planned). Unit: `prefersReducedMotion` (matchMedia mock), `RoutePanel` fires `onOriginChange` on pick/clear/geolocation, `MapView` recenters + adds/moves/removes the origin marker (maplibre stub asserts `flyTo`/`jumpTo`/source-data calls). E2e: select origin → assert camera centered + marker present; clear → marker gone. |
| **III. UX Consistency** | Documented conventions; actionable errors; accessibility part of "done" | PASS (planned). Reuses the existing GeoJSON-layer pattern and animation conventions (cf. `fitBounds(..., {duration: 600})`); reduced-motion honored; the marker gives clear visual feedback of the confirmed point. No user-facing errors introduced (unresolvable coordinate is a silent no-op per FR-007). |
| **IV. Performance** | Declared, measured budgets for user-perceived latency | PASS (planned). Budget declared (SC-001: centered ≤1.5 s; animation ~600 ms). Work is one camera animation + one single-feature GeoJSON update per selection — negligible cost; verified against the budget in quickstart. |

**Initial gate result: PASS** — no violations; Complexity Tracking not required.

**Post-design re-check (after Phase 1): PASS** — the design adds no new dependencies, no new network
calls, no shared global state (a single prop + callback threaded through the existing parent), and no
persistence. Anonymity and performance constraints are satisfied by construction.

## Project Structure

### Documentation (this feature)

```text
specs/007-zoom-to-origin/
├── plan.md              # This file (/speckit-plan)
├── research.md          # Phase 0 — decisions (zoom level, animation, marker, state threading)
├── data-model.md        # Phase 1 — Starting location, Map viewport, Starting marker
├── quickstart.md        # Phase 1 — how to run & verify (incl. perf + anonymity checks)
├── contracts/
│   └── ui-contract.md   # Phase 1 — component prop/callback contract (no backend API)
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify)
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

This feature is frontend-only; the relevant existing structure:

```text
frontend/
├── src/
│   ├── components/
│   │   ├── MapView.tsx        # owns the maplibre map; ADD origin recenter effect + origin marker layer
│   │   ├── RoutePanel.tsx     # owns origin/destination; ADD onOriginChange callback (pick/clear/geo)
│   │   └── CameraLayer.tsx    # reference pattern: GeoJSON source + layer
│   ├── pages/
│   │   └── PlanRoutePage.tsx  # parent; lift `origin` state, pass to MapView, wire RoutePanel callback
│   ├── hooks/                 # (existing useDebounce/useGeolocation live here)
│   ├── utils/                 # ADD prefers-reduced-motion helper (new file)
│   └── types/api.ts           # Coordinate type (reused; no change expected)
└── tests/
    ├── unit/                  # ADD reduced-motion + RoutePanel callback + MapView recenter/marker tests
    └── e2e/                   # EXTEND plan-route flow: assert recenter + marker on origin selection
```

**Structure Decision**: Existing **web application** layout; all changes land in `frontend/`. No
`backend/` changes (no new endpoints, no persistence). State is threaded through the existing
`PlanRoutePage → {MapView, RoutePanel}` parent rather than introducing a store/context, consistent
with how `route`/`endpoints` already flow.

## Complexity Tracking

> No constitution violations — section intentionally empty.

# Implementation Plan: Render Camera Locations in the Current Viewport

**Branch**: `008-viewport-cameras` | **Date**: 2026-06-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-viewport-cameras/spec.md`

## Summary

Render the known cameras in the current map viewport, clustered into count bubbles where they're dense
and individual markers where they're sparse. Tapping a cluster zooms in to expand it; tapping a camera
shows its details; disputed/low-confidence cameras look distinct from confirmed ones. The display
follows the map (debounced on pan/zoom) and works whether or not a route is planned.

Technical approach: **frontend-only**. The backend `GET /cameras?bbox=` endpoint already returns the
needed set — `routable` includes disputed cameras above the confidence floor, and `camera_json`
already exposes `verification_status`/`confidence`. Make the existing-but-unwired `CameraLayer`
self-contained: it takes the live map, computes the viewport bbox on `moveend` (debounced), fetches
via the existing `useCameras` hook, and renders a **MapLibre GL native clustered** GeoJSON source —
cluster bubbles + count labels + individual points styled by status — with click handlers to expand a
cluster (reduced-motion-aware) and to show a camera's details in a popup. `MapView` mounts it once the
map is ready. No new dependencies, no backend changes.

## Technical Context

**Language/Version**: TypeScript 5.x, React 19 (frontend only)

**Primary Dependencies**: MapLibre GL JS (native GeoJSON clustering + Popup), @tanstack/react-query
(existing `useCameras`)

**Storage**: N/A — camera reference data is fetched per viewport and held in client cache; nothing
persisted.

**Testing**: Vitest + @testing-library (maplibre stubbed), Playwright (real map, stubbed network)

**Target Platform**: evergreen browsers, mobile-first responsive web app

**Project Type**: Web application (`frontend/` + `backend/`); this feature is **frontend-only** — the
cameras endpoint already serves everything needed (incl. disputed via `routable`).

**Performance Goals**: cameras/clusters appear within 1 s of the view settling (SC-001/002); viewport
fetches are debounced (FR-003); clustering bounds the number of rendered features; pan/zoom stays at
the map's native frame rate (SC-008).

**Constraints**: strict anonymity — the viewport bbox is sent only to our own backend, never a third
party, and is not logged with a client identifier (FR-013; the existing anonymity-logging init already
redacts coordinates/IPs). Reduced-motion preference honored for cluster-expand zoom. Server returns at
most 500 cameras per request (FR-011).

**Scale/Scope**: realistic camera densities are low (5 in dev); designed for up to the 500-per-viewport
cap. Touches `CameraLayer`, `MapView`, a reused reduced-motion util, and tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Assessment |
|-----------|------|------------|
| **I. Code Quality** | Lint/format zero warnings; single responsibility; intent comments; no dead code | PASS (planned). `CameraLayer` becomes the single, self-contained "render cameras on the map" unit (source + layers + handlers + popup). Intent comments explain clustering choice and the cap tradeoff. ESLint + `tsc -b` clean. |
| **II. Testing (NON-NEGOTIABLE)** | Every behavioral change has tests that fail without it; deterministic; behavior-focused | PASS (planned). Unit (maplibre stub): bbox computed on moveend + debounced; clustered source added with `cluster:true`; cluster-click triggers expansion zoom; point-click opens a details popup; disputed paint expression applied. E2e: cameras render in viewport, update on pan, cluster expands on tap, popup on camera tap, and no third-party request carries the bbox. |
| **III. UX Consistency** | Documented conventions; actionable feedback; accessibility part of "done" | PASS (planned). Reuses the existing GeoJSON source+layer pattern (cameras/route/origin) and the reduced-motion util from 007; clusters + popup give clear feedback; camera markers stay visually distinct from the route line and origin marker and don't obscure the route (FR-009). |
| **IV. Performance** | Declared, measured budgets for user-perceived latency | PASS (planned). Budget declared (SC-001/002: ≤1 s; SC-008: no jank). Native clustering caps rendered features; fetches are debounced; the per-viewport set is bounded by the server cap. Verified against budget in quickstart. |

**Initial gate result: PASS** — no violations; Complexity Tracking not required (client-side native
clustering is the *simplest* option — no new deps, no backend work).

**Post-design re-check (after Phase 1): PASS** — design adds no dependencies, no backend changes, no
new third-party calls, no persistence. Anonymity holds (bbox → own backend only, already redacted in
logs).

## Project Structure

### Documentation (this feature)

```text
specs/008-viewport-cameras/
├── plan.md              # This file (/speckit-plan)
├── research.md          # Phase 0 — clustering, debounce, expand, popup, styling, mounting, cap
├── data-model.md        # Phase 1 — Camera, Cluster, Viewport (all ephemeral)
├── quickstart.md        # Phase 1 — run & verify (incl. seeding fixtures, perf, anonymity)
├── contracts/
│   └── ui-contract.md   # Phase 1 — consumed cameras endpoint + CameraLayer/MapView props
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify, /speckit-clarify)
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

Frontend-only; relevant existing structure:

```text
frontend/
├── src/
│   ├── components/
│   │   ├── CameraLayer.tsx    # REWRITE: self-contained; map prop → bbox(moveend, debounced) →
│   │   │                      #   useCameras → clustered source + layers + cluster/point handlers + popup
│   │   ├── MapView.tsx        # mount CameraLayer once the map is ready (track map instance in state)
│   │   └── RouteResult.tsx    # (unchanged) reference for popup/UI conventions
│   ├── services/
│   │   └── cameraApi.ts       # REUSE useCameras(bbox); no change expected
│   ├── utils/
│   │   └── reducedMotion.ts   # REUSE for cluster-expand zoom (jumpTo vs easeTo)
│   └── types/api.ts           # CameraPin shape (reused)
└── tests/
    ├── unit/                  # ADD camera-layer tests (bbox/debounce, clustering, expand, popup, styling)
    └── e2e/                   # EXTEND: viewport cameras render/update, cluster expand, popup, anonymity
```

**Structure Decision**: Existing **web application** layout; all changes land in `frontend/`. No
`backend/` changes — `GET /cameras?bbox=` already returns the routable set (incl. disputed) with the
attributes needed for styling and the details popup. `MapView` owns the map and gains a small
map-ready signal so `CameraLayer` mounts when the instance exists, consistent with how the map is
already managed.

## Complexity Tracking

> No constitution violations — section intentionally empty. (Native MapLibre clustering is chosen
> precisely because it avoids new dependencies and server-side work.)

# Quickstart: Zoom to Starting Address

How to run and verify the feature. Frontend-only; no backend or data rebuild needed.

## Run the app

```bash
# from repo root — full stack (geo services already built)
docker compose -f infra/docker-compose.yml up -d
# frontend dev server is at http://localhost:5173
```

Or run just the frontend against the running backend:

```bash
cd frontend
pnpm install
pnpm dev   # http://localhost:5173
```

## Manual verification (maps to acceptance scenarios)

1. **Recenter + marker (US1 / FR-001, FR-011)**: In the starting-address field type a known address
   (e.g. `1007 East Grand Avenue, Des Moines`) and pick the suggestion. → The map flies to the address at
   street level (zoom 16) and a single marker appears on the point.
2. **Re-selection moves the marker (FR-012, SC-007)**: Pick a different starting address. → The map
   recenters and the one marker moves; no stale marker remains.
3. **Clearing removes the marker (FR-013)**: Clear the starting-address field. → The marker disappears
   and the map does not jump.
4. **No move while typing (FR-005, SC-004)**: Type characters without selecting. → The map does not
   move.
5. **Reduced motion (FR-004, SC-005)**: Enable the OS "reduce motion" setting (or DevTools →
   Rendering → "Emulate prefers-reduced-motion"), then pick an address. → The map jumps instantly with
   no fly animation.
6. **Consistent framing (FR-002, SC-002)**: Pick a dense-city address and a rural address. → Both land
   at the same street-level zoom.

## Performance check (Principle IV / SC-001)

- After picking a suggestion, the map should be centered on the address within **1.5 s** (animation
  ~600 ms). Spot-check with DevTools Performance; no long main-thread tasks should be introduced by the
  recenter or the single-feature marker update.

## Anonymity check (FR-009 / non-negotiable)

- Open DevTools → Network, pick a starting address. → Confirm the only new requests are tile/style
  requests to the app's own origin; no request to any third party carries the coordinate.

## Tests

```bash
cd frontend
pnpm exec vitest run            # unit/component (maplibre stubbed)
pnpm exec tsc -b --noEmit       # typecheck
pnpm lint                       # eslint, zero warnings (Principle I)
pnpm exec playwright test       # e2e (real map, stubbed network) — incl. recenter + marker assertions
```

Expected new/updated tests:
- `tests/unit/reduced-motion.test.ts` — `prefersReducedMotion()` true/false via matchMedia mock.
- `tests/unit/route-panel.test.tsx` — `onOriginChange` fires on pick, on clear, and on geolocation;
  not on intermediate typing.
- `tests/unit/map-view.test.tsx` — on `origin` prop set: `flyTo` (or `jumpTo` under reduced motion) +
  marker source `setData` with the point; on `origin` null: marker source cleared, no camera move.
- `tests/e2e/plan-route.spec.ts` (extend) — selecting an origin recenters and shows the marker; no
  third-party request carries the coordinate.

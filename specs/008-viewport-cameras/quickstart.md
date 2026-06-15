# Quickstart: Render Camera Locations in the Current Viewport

Frontend-only; no backend or data rebuild. Note: the dev DB has only **5 cameras** (all
`unverified`), so seed fixtures to see clustering and disputed styling.

## Run the app

```bash
docker compose -f infra/docker-compose.yml up -d   # full stack
# frontend: http://localhost:5173
```

## Seed visible camera data (to exercise clustering + disputed styling)

```bash
# Add a dense cluster + a disputed camera near the dev map's default view (Iowa).
docker compose -f infra/docker-compose.yml exec backend bin/rails runner '
  src = DataSource.first || DataSource.create!(name: "dev-fixture", kind: "manual")
  20.times { |i|
    Camera.create!(data_source: src, external_ref: "devclust-#{i}",
      location: "POINT(#{-93.62 + (i % 5) * 0.001} #{41.59 + (i / 5) * 0.001})",
      confidence: 0.9, verification_status: "verified")
  }
  Camera.create!(data_source: src, external_ref: "devdisputed-1",
    location: "POINT(-93.60 41.60)", confidence: 0.3, verification_status: "disputed")
'
```

## Manual verification (maps to acceptance scenarios)

1. **Cameras in viewport (US1 / FR-001)**: pan to the seeded area → camera markers appear; where many
   sit close, a **count bubble** appears instead of overlapping pins (FR-004).
2. **Follow + expand (US2 / FR-002, FR-005)**: pan away → cameras update; tap a cluster → the map zooms
   in and it splits into smaller clusters / individual markers.
3. **Inspect (US3 / FR-006)**: tap an individual camera → a popup shows its type/confidence/status.
4. **Disputed styling (FR-008)**: the `disputed` fixture renders visibly differently from the
   `verified` ones.
5. **No route needed (FR-012)**: all of the above work with no route planned.
6. **Empty area (FR-010)**: pan to an area with no cameras → nothing shown, no error.

## Performance check (Principle IV / SC-001/002/008)

- Cameras/clusters appear within **1 s** of the view settling; panning stays smooth (no jank). Confirm
  fetches are debounced (one request after the move settles, not per frame) in DevTools → Network.

## Anonymity check (FR-013)

- DevTools → Network while panning: the only camera request goes to our own origin
  (`/api/v1/cameras?bbox=...`); no third party receives the bbox.

## Tests

```bash
cd frontend
pnpm exec vitest run            # unit (maplibre stubbed)
pnpm exec tsc -b --noEmit
pnpm lint
pnpm exec playwright test       # e2e (real map, stubbed network)
```

Expected new/updated tests:
- `tests/unit/camera-layer.test.tsx` — bbox computed on moveend + debounced; clustered source added
  (`cluster: true`); cluster-click triggers expansion zoom; point-click opens a popup; disputed paint
  expression present.
- `tests/e2e/viewport-cameras.spec.ts` — cameras render for the viewport, update on pan, a cluster
  expands on tap, a camera popup opens on tap; and (anonymity) no third-party request carries the bbox.

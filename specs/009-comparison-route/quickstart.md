# Quickstart: Baseline Route Comparison

How to run and verify feature `009-comparison-route` locally. The geo stack runs via docker-compose in dev
(same engines as prod); tests stub it with recorded fixtures.

## Run

```bash
# from repo root — start the self-hosted geo stack + db (Valhalla, Nominatim, tiles, PostGIS)
docker compose up -d

# backend (Rails API)
cd backend && bin/rails s

# frontend (Vite)
cd frontend && npm run dev
```

Open the app, enter an origin and destination, and plan a route.

## Verify the behavior

### 1. Avoidance has a cost → two routes + trade-off (US1)

Pick an O/D pair whose fastest path passes at least one camera and whose avoiding route is longer (the
dev seed includes such pairs near the Iowa coverage area; see camera data docs from feature `003`/`049`).

- The map shows **two** lines: the recommended avoiding route (solid, `#818cf8`, on top) and the fastest
  route (dashed, muted, beneath it).
- The result panel shows the **added time** headline (e.g. "+4 min vs fastest"), the **added distance**
  secondary (e.g. "+1.2 km vs fastest"), and **how many cameras the fastest route passes**.
- The recommended route is unmistakably primary; where the two overlap, the solid line stays on top.

### 2. Dismiss the comparison (FR-002a)

- Click **Hide fastest route** in the result panel → the dashed comparison line disappears; the
  recommended route and its travel time remain.
- Click **Show fastest route** → it returns.

### 3. Avoidance is free → single route (US2)

Pick an O/D pair whose fastest route already passes no cameras.

- The map shows a **single** route; no dashed comparison line is drawn.
- The result panel shows **no** positive added-time/-distance figures.

### 4. New plan clears stale comparison (FR-009)

- Plan a route with a penalty (two lines), then plan a different route with no penalty → the previous
  comparison line is gone, and `showComparison` is back to its default (shown) for the next penalty case.

## Performance check (Principle IV / SC-006)

The fastest route is already computed on every request today, so no new external round-trip is added.
Verify no regression against feature `002`'s route p95 budget with representative O/D pairs:

```bash
cd backend && bundle exec rspec spec/requests   # request specs assert the contract incl. new fields
# spot-check latency of POST /api/v1/routes against the 002 budget with a few real O/D pairs
```

Expectation: planning latency is within feature `002`'s budget; the added work is one PostGIS intersection
(the fastest route's camera count) plus one extra polyline in the payload.

## Anonymity check (Non-negotiable / SC-005)

- Both routes are computed by our **own** Valhalla; the fastest geometry is added only to our own response.
- Confirm no third-party host receives the origin/destination/route (e2e asserts no off-origin request
  carries route data), and that logs still redact coordinates/IPs (existing anonymity-logging init).

## Tests

```bash
# backend
cd backend && bundle exec rspec \
  spec/services/routing/route_planner_spec.rb \
  spec/requests           # fastest_comparison carries geometry + cameras_passed_count; fallback delta==0

# frontend
cd frontend && npm test   # MapView comparison line draw/dismiss/styling; RouteResult rows + toggle
cd frontend && npm run test:e2e   # two lines render, dismiss hides comparison, anonymity
```

All geo calls in tests are stubbed via `GeoFakes` / recorded Valhalla fixtures — deterministic, no network.

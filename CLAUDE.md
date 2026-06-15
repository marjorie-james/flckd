<!-- SPECKIT START -->
**Active feature**: [`011-country-camera-mapping`](specs/011-country-camera-mapping/plan.md)
([spec](specs/011-country-camera-mapping/spec.md)) — lift a deployment's scope from a single US
state to an entire **country, defaulting to the US**: one operator-chosen country drives the OSM
extract, routing graph, tiles, geocoder + whole-US TIGER, camera gathering, map framing, and
per-data-region coverage. Country-generic config; US is the sole validated/supported target at
launch (un-provisioned country fails fast). Provisioning is in scope via a one-command path.
Key changes: remove the single-state geocoder workarounds, add `Geocoding::CountryRegistry`,
reinterpret `CoverageArea` as per-data-region (freshness set per region), generalize the infra
scripts. Anonymity + segment-exclusion unchanged.

Prior feature: [`010-responsive-layout`](specs/010-responsive-layout/plan.md)
([spec](specs/010-responsive-layout/spec.md)) — full-width responsive layout (map-dominant
two-pane on desktop, full-width stack on mobile); presentation-only.

## Recent work (post-009, no separate spec dir)

Camera avoidance was extended well beyond the original "exclude the monitored segment" mechanism:

- **Camera avoidance (always maximal, auto-fallback)** — there is no aggressiveness setting/slider. The
  planner always prefers a route that passes **no camera at all** (the fastest such, whatever the detour);
  when none exists it **automatically falls back to the fewest-cameras route** (never a 422). It chooses
  among the fastest route, an iterative-exclusion route, and a "quiet" surface-street route; the fallback
  minimizes `duration_s + λ·proximity_cost` — a *soft* camera-proximity objective (how close a route passes
  every nearby camera, not just an on-segment count) — under a detour cap. When the result isn't fully clean
  (`is_fully_clean: false`), the UI shows a prominent **`RouteNotice`** banner making clear the route still
  passes within view of some cameras. See `RoutePlanner`, `ProximityScorer`, `RouteCameraDetector`, and
  `RouteNotice`.
- **Camera map rendering** — dots are snapped onto the monitored road, the watched stretch is highlighted,
  directional cameras get a "vision cone" rotated to `facing_direction`, omnidirectional cameras get a 360°
  halo, and the popup is styled + localized. `/cameras` now returns `facing_direction`, `snapped_location`,
  and `segment`.
- **Camera lifecycle** — auto-retirement uses a recoverable `auto_retired` flag (revived when the source
  reports the camera again), distinct from terminal human `removed`.

Shipped specs: [`009-comparison-route`](specs/009-comparison-route/plan.md)
([spec](specs/009-comparison-route/spec.md)) ·
[`008-viewport-cameras`](specs/008-viewport-cameras/plan.md)
([spec](specs/008-viewport-cameras/spec.md)) ·
[`007-zoom-to-origin`](specs/007-zoom-to-origin/plan.md)
([spec](specs/007-zoom-to-origin/spec.md)) ·
[`006-geocoder-housenumber-fix`](specs/006-geocoder-housenumber-fix/spec.md) ·
[`005-parallel-tiger-download`](specs/005-parallel-tiger-download/plan.md)
([spec](specs/005-parallel-tiger-download/spec.md)) ·
[`004-auto-route-priority`](specs/004-auto-route-priority/plan.md)
([spec](specs/004-auto-route-priority/spec.md)) ·
[`003-camera-data-aggregation`](specs/003-camera-data-aggregation/plan.md)
([spec](specs/003-camera-data-aggregation/spec.md)) ·
[`002-flock-route-avoidance`](specs/002-flock-route-avoidance/plan.md)
([spec](specs/002-flock-route-avoidance/spec.md)).

**Stack**: Ruby 3.4.x + Rails 8.1.x (latest stable, API mode) backend; TypeScript + React 19 (Vite, MapLibre GL JS)
frontend; PostgreSQL 17 + PostGIS. Rails 8.1 built-ins in use: Solid Queue (jobs, with job continuations), Solid Cache,
Propshaft, Kamal 2 + Thruster (deploy). No Rails auth generator (account-less by design).

**Self-hosted geo stack** (own infrastructure — never third parties): Valhalla (segment-exclusion
routing), Nominatim (forward/reverse geocoding), self-hosted vector tiles (Protomaps PMTiles via go-pmtiles).
The same engines run in dev (docker-compose) and prod (Kamal accessories) — no dev/prod geocoder/tile drift.

**Non-negotiables**:
- Strict anonymity — no third party ever receives a user's origin/destination/route; no accounts/PII;
  no persistent identifiers; logs must not retain route coordinates or client IPs. Only exception:
  explicit user-initiated "open in Apple/Google Maps" handoff (with warning).
- Camera avoidance = exclude the specific monitored road segment(s) (snap-to-road), not a radius.
- Tests are required for every behavioral change (Constitution Principle II); geo services are stubbed
  with recorded fixtures so tests stay deterministic.

For full technical context, project structure, and commands, read the plan and quickstart.
<!-- SPECKIT END -->

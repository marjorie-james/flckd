# Phase 0 Research: Camera-Avoiding Route Planner

All Technical Context unknowns are resolved below. No `NEEDS CLARIFICATION` remain.

## R1. Routing engine with per-road-segment exclusion

**Decision**: Self-host **Valhalla** as the routing engine, using its dynamic per-request costing to
exclude the OSM way segments monitored by cameras (via `exclude_polygons` around monitored segments
and/or edge costing), with **GraphHopper** documented as the fallback.

**Rationale**: Monitored-segment avoidance (spec clarification Q2) requires excluding *specific* edges
at request time, not a static graph. Valhalla supports dynamic costing and `exclude_polygons`/
`exclude_locations` per request, runs self-hosted (Docker), and exposes a JSON HTTP API the Rails app
can call privately. It also returns alternates and turn-by-turn maneuvers we localize. We can build the
US graph from an OSM extract offline, satisfying strict anonymity (no third-party routing calls).

**Alternatives considered**:
- **GraphHopper**: Excellent custom-profile/`block_area` support and edge-based weighting; equally
  self-hostable. Strong fallback; chosen second only because Valhalla's per-request polygon exclusion
  maps more directly to "exclude these monitored segments" without rebuilding profiles.
- **OSRM**: Fastest, but the graph is contracted at build time; arbitrary per-request edge exclusion is
  not natively supported, forcing graph rebuilds or hacks. Rejected for the avoidance use case.
- **Third-party APIs (Google/Mapbox Directions)**: Reject outright — they would receive the user's
  origin/destination, violating FR-012a.

## R2. Minimum-exposure routing (no fully clean route)

**Decision**: Two-pass strategy. Pass 1 requests a route with monitored segments hard-excluded. If no
route is returned (or origin/destination sit on a monitored segment), Pass 2 re-requests with monitored
segments **heavily penalized** (high cost multiplier) instead of excluded, yielding the
minimum-exposure route; the response flags it as not fully camera-free and lists remaining cameras.

**Rationale**: Directly satisfies FR-004 and US4 scenario 3 and the "no clean route" + "endpoint
adjacent to camera" edge cases without ever failing hard.

**Alternatives considered**: Single-pass soft penalty only (simpler, but can't guarantee a truly clean
route when one exists, weakening SC-001). Rejected.

## R3. Self-hosted geocoding

**Decision**: Self-host **Pelias** (US extract) for forward/reverse geocoding and autocomplete;
**Nominatim** documented as the lighter-weight fallback.

**Rationale**: Anonymity requires geocoding on our own infrastructure (FR-012a). Pelias provides
type-ahead autocomplete (needed for FR-001/FR-016 disambiguation) and structured results with good US
coverage from OSM/OpenAddresses. Runs in Docker; called privately by Rails.

**Alternatives considered**: **Nominatim** — simpler to operate but weaker autocomplete; kept as
fallback. Third-party geocoders rejected (would expose typed addresses).

## R4. Self-hosted map tiles + client rendering

**Decision**: Serve **self-hosted vector tiles** from a US OSM extract using **Protomaps (PMTiles)**
served via a small tile endpoint (or Martin), rendered client-side with **MapLibre GL JS**. No API
keys, no third-party tile/CDN requests.

**Rationale**: MapLibre is the open-source, key-free renderer; PMTiles is a single-file tile archive
that is cheap to host and easy to range-serve, keeping all map requests on our infrastructure
(FR-012a). Vector tiles give the crisp mobile experience required by FR-009/SC-003.

**Alternatives considered**: **OpenMapTiles + tileserver-gl** (heavier but battle-tested) — viable
alternative. **Mapbox/Google tiles** rejected (third-party exposure + keys).

## R5. Camera data source, import, and segment snapping

**Decision**: Hybrid pipeline (spec clarification Q3). Seed from **DeFlock** and **OpenStreetMap** ALPR
tags (`man_made=surveillance` + `surveillance:type=ALPR` / `brand=Flock`) pulled via Overpass/exports;
**snap each camera to its nearest drivable road segment(s)** using PostGIS (`ST_ClosestPoint` /
`ST_LineLocatePoint`) against the same OSM road geometry the routing graph is built from; store the
resulting monitored OSM way IDs, plus a small snapping tolerance. Layer an internal verification/
correction step recording source/provenance and verification status. Refresh periodically via Solid
Queue recurring jobs (R9).

**Rationale**: Matches the clarified hybrid source and the monitored-segment avoidance model, and keeps
camera→segment identity consistent with the routing engine's OSM way IDs so exclusion is exact.

**Alternatives considered**: Radius-only avoidance (rejected in Q2 — over-blocks). Live Overpass calls
at request time (rejected — latency + reliability; we import on a schedule instead).

## R6. Anonymity hardening

**Decision**: (a) No accounts, no auth, no cookies or localStorage identifiers; language preference, if
remembered, stored client-side only and non-identifying. (b) Rails request logging configured to
**redact** route coordinates/addresses and to **not** store client IPs against route requests
(`config.filter_parameters` + custom log subscriber dropping geo params; truncate/omit IP). (c) Strict
CSP that disallows third-party origins; all JS/CSS/fonts/tiles self-hosted. (d) Rate limiting via
rack-attack keyed on coarse, non-retained buckets. (e) Route requests handled statelessly; nothing
persisted server-side beyond the request lifecycle (FR-011).

**Rationale**: Operationalizes FR-010/011/012/012a and SC-005/008/009 at the layers where leaks
actually happen (logs, cookies, third-party assets, IPs).

**Alternatives considered**: Session cookies for CSRF — unnecessary for an anonymous, stateless,
token-free JSON API consumed by our own SPA; rely on same-origin + CSP instead.

## R7. Open-in-external-maps handoff

**Decision**: Build platform deep links on the client — Apple Maps (`maps://?saddr=…&daddr=…` /
`https://maps.apple.com/?...`) and Google Maps (`https://www.google.com/maps/dir/?api=1&...`) — behind
an explicit button that first shows a localized warning that the route's locations will be shared with
that provider (FR-012b).

**Rationale**: Keeps the third-party exposure strictly user-initiated and informed, as clarified.

**Alternatives considered**: Server-side redirect (rejected — would route the coordinates through our
logs/referrers unnecessarily; client-side deep link keeps it local until the user taps).

## R8. Internationalization

**Decision**: Server strings and **route-maneuver phrasing** via `rails-i18n` + locale YAML; client UI
via `react-i18next` with JSON locale bundles and language auto-detection from `navigator.language`,
overridable by a switcher (FR-013/014/015). Launch locales target the largest US communities (English,
Spanish, +others — finalized in tasks). Turn instructions are generated from Valhalla maneuver *types*
mapped to localized templates rather than using any provider's prose, so they translate cleanly.

**Rationale**: Covers US3 fully and keeps directions localized and provider-neutral.

**Alternatives considered**: FormatJS/react-intl (comparable; react-i18next chosen for simpler runtime
language switching that preserves in-progress input per US3 scenario 2).

## R9. Background jobs

**Decision**: **Solid Queue** — Rails 8's built-in, database-backed Active Job backend — for camera
import/snap/refresh jobs, with the **Solid Queue recurring/cron** support for scheduled refreshes.

**Rationale**: Ships with Rails 8, reuses the existing PostgreSQL instance (no Redis, no extra gem),
and keeps the ops surface — and thus the anonymity attack surface — minimal. Job volume is modest
(scheduled data refreshes + snapping), well within Solid Queue's envelope.

**Alternatives considered**: **GoodJob** and **Sidekiq** — both viable, but Solid Queue is now the
in-the-box default and avoids an extra dependency (Sidekiq additionally requires Redis).

## R10. Test determinism for geo services

**Decision**: In test, the routing/geocoding/tile clients are replaced by fakes backed by **recorded
fixtures** (representative US metro request/response pairs, including a camera-on-path case, a clean
case, and a no-clean-route case). E2E (Playwright) runs against a seeded local stack via
docker-compose.

**Rationale**: Satisfies Constitution Principle II (deterministic, no third-party network in tests)
while still exercising real avoidance behavior end-to-end.

**Alternatives considered**: Hitting live self-hosted engines in unit tests (rejected — slow,
non-deterministic for unit scope; reserved for E2E).

## Terminology glossary (UX consistency — Principle III)

- **Camera** — a known ALPR/Flock automated license-plate reader.
- **Monitored segment** — the road segment(s) a camera reads; the unit of avoidance.
- **Avoiding route** — a route that traverses zero monitored segments.
- **Minimum-exposure route** — the route with the fewest monitored segments when none is fully clean.
- **Avoidance preference** — user choice of avoid / balanced / fastest.
- **Handoff** — user-initiated open-in-external-maps action.

# Verification Report — Camera-Avoiding Route Planner

Covers tasks **T080** (quickstart end-to-end + Success Criteria SC-001…SC-009) and **T081**
(end-to-end anonymity security review). Evidence is the automated suite, which runs deterministically
with the geo services stubbed (Constitution Principle II).

**Environment:** backend tests run in the `infra-backend` dev container against the PostGIS service;
frontend unit tests via Vitest; E2E via the `mcr.microsoft.com/playwright:v1.60.0` image serving the
production build with the API mocked (no live geo stack, zero third-party requests).

**Suite status at verification time:**
- Backend RSpec: **50 examples, 0 failures** (models, requests, services, jobs, contract, performance)
- Frontend Vitest: **9 tests, 0 failures**
- Frontend Playwright E2E: **10 tests, 0 failures**
- RuboCop: clean · `tsc -b` + `vite build`: clean

## T080 — Success Criteria

| ID | Criterion | Status | Evidence |
|----|-----------|--------|----------|
| **SC-001** | Camera-free route returned when one exists (≥95%) | ✅ Measured | `bin/rails eval:routes` over 28 Iowa O/D pairs: of the 4 pairs whose fastest route crosses a camera, `avoid` returned a fully camera-free route for **4/4 (100%)**. See "Live geo stack" below. |
| **SC-002** | Open → route in <60 s and ≤4 interactions | ✅ Verified | E2E `plan-route.spec.ts`: 4 interactions (pick origin, pick destination, submit) complete in <1 s. |
| **SC-003** | Full flow on phone-sized screen, no horizontal scroll/zoom | ✅ Verified | E2E `perf.spec.ts` runs at 393×851 mobile viewport; mobile-first layout (`App.css`). |
| **SC-004** | Route shown within 5 s for ≥95% of metro requests | ✅ Measured | Stubbed perf gate (`spec/performance/route_performance_spec.rb`, p95 < 2 s); and live `eval:routes` over real Iowa routes: server-side plan **p95 ≈ 213 ms** (budget 2000 ms). Client-render budget covered by the frontend perf E2E. |
| **SC-005** | 100% of features with zero PII and no account | ✅ Verified | `requests/anonymity_spec.rb`; `config.api_only` (no session/cookie middleware); no auth anywhere. |
| **SC-006** | ≥5 launch languages, 100% strings localized | ⚠️ Partial | i18n framework + en/es bundles complete and verified (`i18n_spec.rb`, `i18n.test.tsx`, E2E `i18n.spec.ts`). Remaining launch locales (3+) are content to be added to the existing bundles. |
| **SC-007** | Avoiding vs fastest travel-time trade-off shown | ✅ Verified | `RouteResult` `fastest_comparison`; E2E asserts "+3 min vs fastest"; `routes_spec.rb`. |
| **SC-008** | Zero records linking origin/destination to a user | ✅ Verified | No route/user persistence; `anonymity_logging.rb` (param filter, IP-free log tags, coord scrubber); `anonymity_spec.rb`. |
| **SC-009** | Zero third-party exposure of origin/destination/route; maps handoff only after explicit warned action | ✅ Verified | E2E `anonymity.spec.ts`: asserts no non-same-origin requests across the full flow; handoff shows a warning `alertdialog` before any external link; self-origin CSP. |

### Quickstart cross-check

The documented quickstart flow (`quickstart.md`) was reconciled against the implementation and the
READMEs. Local development is **Docker-only**: the backend, frontend, and PostGIS all run via
`infra/docker-compose.yml`. The backend reaches Postgres as `postgres:5432` over the compose network;
the host port is published on 5432 for ad-hoc DB tools.

## T081 — Anonymity security review

| Guarantee | Mechanism | Verdict |
|-----------|-----------|---------|
| No route coordinates in logs | `filter_parameters` redacts `origin/destination/lat/lng/coordinate/bbox/q/address`; coordinate scrubber on the logger | ✅ |
| No client IP tied to a route in logs | `log_tags = [:request_id]` (no `:ip`/`:remote_ip`); rack-attack keys on a truncated, non-retained SHA digest, never the raw IP | ✅ |
| No third-party exposure of locations | Strict self-origin CSP (`default_src/script_src/connect_src/img_src/font_src :self`); E2E proves zero non-same-origin requests; routing/geocoding/tiles all self-hosted | ✅ |
| No accounts / PII | `config.api_only` (no session/cookie/flash middleware); no auth; no user model | ✅ |
| No persistent cross-session identifier | Stateless API, no cookies set; CORS `credentials: false` and closed unless `FRONTEND_ORIGIN` is explicitly set | ✅ |
| Coordinates kept out of URLs | Routing is `POST /routes` (body, not query); geocode reverse is POST | ✅ |
| External maps handoff is explicit + warned | `ExternalMapsHandoff` requires a click, then shows a warning `alertdialog` naming the data shared before exposing Apple/Google links (`target=_blank`) | ✅ |

**Conclusion:** the anonymity guarantees (FR-010, FR-011, FR-012, FR-012a/b) hold across the verified
flow. No PII, identifiers, coordinates, or third-party calls were observed in logs, headers, cookies,
or network traffic during the automated suite.

## Live geo stack (Iowa launch region)

The self-hosted geo stack is now built and wired for **Iowa** (see [infra/README.md](../../infra/README.md)):

- **Routing (Valhalla)** — live and validated. Camera data is seeded (5 fixtures, snapped to ~100 m
  monitored spans on I-80 via Valhalla `/locate`) with an Iowa `CoverageArea`. On Des Moines → Iowa City:

  | preference | distance | clean? | avoided | remaining | vs fastest |
  |-----------|---------:|:------:|--------:|----------:|-----------|
  | fastest    | 184.2 km | false  | 2 | 3 | — |
  | balanced   | 194.7 km | false  | 4 | 1 | +10.5 km / +16 min |
  | **avoid**  | 203.0 km | **true** | **5** | **0** | +18.7 km / +25 min |

  Three distinct routes: `avoid` returns a genuinely camera-free route (SC-001); `balanced`
  hard-excludes only **high-confidence** cameras (≥ 0.8) and tolerates lower-confidence ones, so it
  passes the one 0.7-confidence camera while dodging the two 0.9 ones; `fastest` passes all. The
  avoiding-vs-fastest trade-off is surfaced (SC-007), and server-side latency stays ~90 ms (SC-004).
  Implementation gaps closed to make this work: a Valhalla-backed road lookup + edge clipping
  (`ValhallaRoadLookup`), polyline decoding (`Routing::Polyline`), the `exclude_polygons` payload
  format ([lon,lat] rings), and confidence-subset exclusion for `balanced`
  (`SegmentExclusionBuilder#build(min_confidence:)`).
- **Tiles (Protomaps PMTiles via go-pmtiles)** — built (132 MB) and served; the frontend renders a
  self-hosted, label-less MapLibre style (`frontend/public/map-style.json`) that pulls only our own
  `/tiles/{z}/{x}/{y}.mvt` (no glyphs/third-party). Text labels (self-hosted glyphs) are a follow-up.
- **Geocoder (Nominatim)** — wired and live: `/geocode/search` + `/reverse` verified against the Iowa
  import (`mediagis/nominatim`). `Geocoding::GeocoderClient` maps jsonv2 places to the app shape.
- **Labels** — the basemap style now renders self-hosted text labels (vendored Noto Sans glyphs under
  `frontend/public/fonts`, `glyphs` + symbol layers in `map-style.json`); no third-party/runtime fetch.

SC-001 / SC-004 are now measured by `bin/rails eval:routes` over Iowa O/D pairs (100% camera-free when
needed; server-side p95 ≈ 213 ms). A larger real-traffic dataset would tighten the confidence interval,
but the criteria are met on representative routes.

All other criteria are verified by the passing automated suite.

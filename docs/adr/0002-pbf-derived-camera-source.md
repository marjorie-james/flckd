# ADR 0002 — Derive the OSM camera substrate from the PBF extract, not tiled Overpass

Status: **Accepted — implemented (Option C).** Supersedes the *mechanism* (not the
intent) of the Overpass tiling in [ADR 0001](0001-camera-refresh-scaling.md). The
tiling machinery is **kept** (not deleted) because the Overpass escape hatch still
uses it — it's simply bypassed by the default PBF path.

**What landed:**
- `Sources::OsmTagging` — shared OSM ALPR predicate + provenance + record mapper,
  mixed into both mechanisms so they emit byte-identical records (parity by
  construction).
- `Sources::OsmExtractFile` — the default source: reads the GeoJSON
  `infra/scripts/build-cameras.sh` filters out of the OSM PBF extract, narrowing
  to ALPR with the same predicate as Overpass and re-deriving `osm:node/<id>`.
- Mechanism-neutral provenance: `DataSource` renamed `"OpenStreetMap (Overpass)"`
  → `"OpenStreetMap"` (migration `20260602000001`, idempotent), so both
  mechanisms share one identity and switching is seamless.
- `CAMERA_OSM_SOURCE` (default `pbf`, escape hatch `overpass`) +
  `CAMERA_OSM_GEOJSON_PATH`, wired in `DataRefreshJob` (a single served-region
  "tile" in PBF mode; the full UsTiles sweep in Overpass mode).
- `infra/scripts/build-cameras.sh` (osmium tags-filter + export).
- Escape-hatch ops documented in [geo-stack.md](../runbooks/geo-stack.md#camera-substrate-pbf-default-vs-overpass-escape-hatch).
- Tests: new `osm_extract_file_spec` + `data_refresh_job_spec` coverage for both
  modes; full backend suite + RuboCop + Brakeman green.

Original analysis follows unchanged.

## Context

The daily `DataRefreshJob` (08:00 UTC) populates the `cameras` source-of-truth
table from the OpenStreetMap ALPR substrate. Today that substrate is fetched with
the public **Overpass API**, tiled over the continental US:

- [`Sources::UsTiles`](../../backend/app/services/camera_data/sources/us_tiles.rb)
  splits CONUS (`24.5,-125.0 … 49.5,-66.9`) into 2° cells → **~390 cells**
  (≈13 rows × 30 cols).
- [`Sources::Overpass`](../../backend/app/services/camera_data/sources/overpass.rb)
  queries each cell for `man_made=surveillance` nodes narrowed to ALPR
  (`surveillance:type=ALPR`, `camera:type~alpr|anpr`, `brand|operator~flock`).
- [`TiledRefresh`](../../backend/app/services/camera_data/tiled_refresh.rb) +
  `DataRefreshJob` wrap this in **per-tile isolation, continuation
  checkpoint/resume, and tile-scoped stale reconciliation** — the bulk of
  [ADR 0001](0001-camera-refresh-scaling.md). All of that exists to make ~390
  serial, fair-use-throttled HTTP requests survive partial failure and
  interruption without false-retiring cameras in tiles that didn't fetch.

Separately, the self-hosted geo stack **already downloads an OSM PBF extract**
(Geofabrik) on every build —
[`fetch-extract.sh`](../../infra/scripts/fetch-extract.sh) →
[`build-geo.sh`](../../infra/scripts/build-geo.sh), run by `build-geo.yml`. That
extract feeds the Valhalla graph, the vector tiles, and the Nominatim index. The
camera nodes we query Overpass for are **already inside that PBF**.

**The idea:** filter ALPR nodes out of the OSM PBF we already have, instead of
sweeping Overpass tile by tile.

## The coverage-coupling insight (why this is more than a refactor)

The Overpass sweep covers *all of CONUS* regardless of where we can route. But the
geo stack is built **region by region** (Iowa launch; states added on demand —
see `infra/README.md`). So today the camera table can contain cameras in regions
we have **no routing graph for** — and a camera we can't route around is
inert reference data.

Deriving cameras from the same extract that builds the routing graph **couples
camera coverage to served coverage**: we ingest exactly the cameras in the
regions we can actually plan avoidance routes through. That coupling is the
*correct* product behavior, not a limitation — it falls out for free.

## Coverage parity

| Aspect | Overpass (today) | PBF-derived (proposed) |
|---|---|---|
| Tag set | `man_made=surveillance` + ALPR discriminators | **Identical** — same filter, applied locally |
| Node geometry | Point nodes, returned in full | Point nodes, present in the extract (no clip loss for points) |
| Region | All CONUS, always | The regions we've built extracts for (= served regions) |
| Identity | `external_ref: osm:node/<id>` | **Must preserve `osm:node/<id>`** (see Tooling) |

- **Tag parity is exact** if we apply the same discrimination logic. `osmium
  tags-filter` cleanly extracts `n/man_made=surveillance` (a small set); the
  ALPR/Flock narrowing (currently regex in the Overpass QL) is then applied in the
  normalizer — the same `normalize_camera_type` logic already in
  [`Sources::Base`](../../backend/app/services/camera_data/sources/base.rb).
- **No geometry-clipping gap.** Geofabrik clips ways/relations at region borders,
  but surveillance cameras are *nodes* (points); a node is either in the extract or
  not. No partial-feature loss.
- **The only coverage *difference* is intentional:** PBF-derived returns cameras
  for served regions, Overpass returns CONUS-wide. Per the coupling insight above,
  the served-region set is what we actually want.

## Freshness trade-off

- **Overpass** is near-live (minutes behind OSM edits).
- **Geofabrik extracts** are daily snapshots; our **geo build runs monthly**.

Naively piggy-backing camera extraction on the monthly geo build would drop camera
refresh from daily to monthly — unacceptable against the staleness model
(`StaleReconciler` auto-retires after 3 missed *daily* refreshes; FR-008/009).

**Resolution — decouple cadence, share tooling.** Keep the heavy geo build monthly
(routing/tiles/Nominatim are expensive and don't change fast), but run a **daily
lightweight extract+filter** for cameras: download the served-region PBF(s),
`osmium tags-filter` to surveillance nodes, emit GeoJSON, import. This preserves
the daily 08:00 cadence; camera data lags OSM by ≤~24h instead of minutes.

Is ≤24h acceptable? Yes. Cameras are physical infrastructure that changes on the
order of weeks; a sub-day lag is immaterial to avoidance routing, and it sits
comfortably inside the 3-missed-refresh (72h) staleness window. The honest caveat:
the "one download feeds everything" framing is aspirational — routing needs a
monthly heavy rebuild, cameras a daily light refresh; they **share
`fetch-extract.sh` tooling but not the same physical download**, because of the
cadence mismatch.

## Simplicity win (what gets retired)

A single-file regional import has no per-tile failure surface, so most of ADR 0001
becomes unnecessary:

| ADR 0001 machinery | Fate under this proposal |
|---|---|
| `UsTiles` ~390-cell CONUS grid | **Removed** |
| Overpass per-tile fan-out + keep-alive + backoff | **Removed** from the default path |
| Per-tile isolation / `tiles_ok`/`tiles_failed` status | **Removed** — one import, one status |
| Continuation checkpoint/resume (`ActiveJob::Continuable`) | **Removed** — a single file import is short; rerun on failure |
| Overpass fair-use throttling (concurrency 1) | **Gone** — no public-API calls in the default path |
| Tile-scoped `StaleReconciler` (`bboxes:`) | **Simplified** — reconcile over the served-region bbox(es); skip entirely if the daily download failed (same anti-false-retire rule, simpler) |

Net: ~390 throttled HTTP requests/night → **1 download + 1 local filter**; and the
single most intricate correctness constraint in ADR 0001 (tile-aware reconcile to
avoid false retirement) collapses to "did the whole-region fetch succeed? y/n."

## Licensing / provenance

- **Same substrate, same license.** The PBF is OSM data → **ODbL-1.0**, identical
  to the Overpass path. No new licensing question. (DeFlock contributions are in
  OSM already — ADR 0001's demotion still holds.)
- **Provenance preserved per record.** Reuse the existing provenance machinery:
  the source declares `name/kind/url/license` and every row carries it
  ([`Sources::Base`](../../backend/app/services/camera_data/sources/base.rb)).
- **Identity must stay stable.** `external_ref` must remain `osm:node/<id>` so the
  unique index, idempotent re-imports, and cross-source dedup keep working. The
  generic [`GeojsonFile`](../../backend/app/services/camera_data/sources/geojson_file.rb)
  source would emit the raw feature id, **not** the `osm:node/` prefix — so this
  needs a thin OSM-aware variant (below), not `GeojsonFile` as-is.

## Tooling

1. **Extract** (daily, per served region): `osmium tags-filter region.osm.pbf
   n/man_made=surveillance -o surveillance.osm.pbf` then `osmium export
   surveillance.osm.pbf -f geojson -o cameras.geojson`. `osmium-tool` is the
   standard OSM CLI; minutes even on a full-US PBF. Hook it into the existing
   `infra/scripts/` family (a new `build-cameras.sh`, sibling to `fetch-extract.sh`).
2. **Where it runs:** a **daily** GitHub Actions step (cheap — download + filter,
   no graph build), OR inside the Rails job shelling to `osmium`. Prefer the
   CI/infra step so the Rails host needs no `osmium` and the job just reads a file
   — symmetric with how the geo artifacts are produced.
3. **Into the table:** a new source class
   `Sources::OsmExtractFile < GeojsonFile` that overrides `external_ref_for` to
   emit `osm:node/<id>` and declares OSM/ODbL provenance — ~20 lines, reusing
   `GeojsonFile`'s GeoJSON parsing and the shared normalizers. `DataRefreshJob`
   swaps `default_source`/`TiledRefresh` for a single-file import path
   (`StaleReconciler` scoped to served-region bbox(es); skip-on-fetch-failure).

## Options considered

- **A. Status quo (tiled Overpass).** Near-live; but carries all of ADR 0001's
  machinery and sweeps CONUS regardless of served coverage.
- **B. Adopt PBF-derived as the default substrate** *(recommended)*. Retires the
  tiling machinery; couples camera↔served coverage; ≤24h freshness.
- **C. Hybrid.** B as the nightly bulk substrate, **keep the `Overpass` source
  class behind config** (`OVERPASS_URL`) for optional near-live top-ups or a
  self-hosted Overpass. Preserves an escape hatch at near-zero cost (don't delete
  `Overpass`, just remove it from the default path).

## Recommendation

**Adopt Option C — PBF-derived primary, Overpass retained but dormant.**

Make the daily default a single regional `osmium` filter feeding
`Sources::OsmExtractFile`; this removes `UsTiles`, the per-tile fan-out, the
continuation/checkpoint complexity, and the fair-use throttle, and aligns camera
coverage with served regions. Keep the `Overpass` class in the tree (unwired) so a
self-hosted Overpass or near-live top-up remains a config flip, not a rewrite —
mirroring how ADR 0001 left the parallel-cell path as a documented conditional.

**Rough effort: ~2–4 days.** New `build-cameras.sh` + a daily CI step; a ~20-line
`OsmExtractFile` source; collapse `TiledRefresh`→single-file import and simplify
`StaleReconciler` scoping; drop `UsTiles`/Overpass from the default path; update
the staleness/freshness notes in the geo-stack runbook; tests (the GeoJSON import
path already has fixtures via `GeojsonFile`).

## Consequences

- **Simpler, cheaper nightly job** with a far smaller failure surface; no public
  Overpass dependency or fair-use ceiling in the default path.
- **Camera coverage tracks served coverage** automatically as states are added —
  arguably more correct.
- **Freshness drops** from near-live to ≤~24h — judged immaterial for physical
  camera infrastructure and well inside the staleness window.
- **New build dependency** (`osmium-tool`) in the infra/CI layer; the Rails app
  gains a tiny source class and loses a lot of orchestration code.
- **Reversible:** Option C keeps `Overpass` available, so reverting to the tiled
  sweep is configuration, not redevelopment.
- If accepted, update ADR 0001's status to note its tiling machinery is superseded
  by this ADR (its batched-importer and provenance decisions still stand).

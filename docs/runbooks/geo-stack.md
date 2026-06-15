# Runbook: Building & rebuilding the self-hosted geo stack

Routing, geocoding, and tiles all run on **our own infrastructure** — never a
third party — so a user's origin/destination/route is never sent out (FR-012a).
The geo data is built from a **public OpenStreetMap extract** by three scripts in
`infra/scripts/`. Everything is rebuildable from public OSM; only the PostGIS
`cameras` table needs backing up (see [backups.md](backups.md)).

A deployment covers a whole **country**, defaulting to the **US** (`COUNTRY`, default
`us`). The canonical one-command provisioning path is
[`infra/scripts/build-geo.sh`](../../infra/scripts/build-geo.sh) (country-aware;
referenced throughout). See also [infra/README.md](../../infra/README.md).

## Build the data (in order)

Heavy tooling runs in containers — no host toolchain needed. The one-command path
is `infra/scripts/build-geo.sh` (default US; `GEO_ARTIFACTS_ONLY=1` for an
artifact-only CI build). The individual steps:

```bash
# 1. Download the configured country's OSM extract → infra/data/extract.osm.pbf
#    (COUNTRY=us → the whole-US Geofabrik PBF, ~10+ GB)
infra/scripts/fetch-extract.sh

# 2. Build the Valhalla routing graph → infra/routing/data
#    (Valhalla excludes individual road segments — exactly how camera
#    avoidance works: exclude the monitored segment, not a radius.)
infra/scripts/build-routing-graph.sh

# 3. Build self-hosted vector tiles (PMTiles) → infra/tiles/data/tiles.pmtiles
infra/scripts/build-tiles.sh
```

Then start the services:

```bash
docker compose -f infra/docker-compose.yml up -d postgres routing tileserver geocoder
```

`geocoder` (Nominatim) runs a slow one-time import of the same extract on first
`up`, persisted in the `nominatim_data` volume.

## Camera substrate: PBF (default) vs. Overpass (escape hatch)

The daily camera refresh draws the OpenStreetMap ALPR substrate one of two ways
(ADR [0002](../adr/0002-pbf-derived-camera-source.md)). **Same data, same ODbL
license, same `OpenStreetMap` `DataSource` identity, same `osm:node/<id>`
external_refs** — only the *access mechanism* differs, so you can flip between
them with **zero data migration** and no duplicate cameras.

Selected by `CAMERA_OSM_SOURCE`:

| Value | Mechanism | Use when |
|-------|-----------|----------|
| `pbf` *(default)* | Filter ALPR nodes out of the OSM PBF extract we already download → a local GeoJSON file. No API calls. | Normal operation. |
| `overpass` | Live (or self-hosted) Overpass API, tiled over CONUS. Near-live data. | **Escape hatch** — see below. |

### Default path (`pbf`) — building & delivering the file

```bash
# 4. Filter cameras out of the same extract (cadence: DAILY, independent of the
#    monthly graph/tiles rebuild). Needs osmium-tool on PATH.
infra/scripts/build-cameras.sh            # → infra/data/cameras.geojson
```

The app reads the file at **`CAMERA_OSM_GEOJSON_PATH`** (default
`storage/cameras.geojson`). In production, the daily build delivers the GeoJSON to
that path on the app host — the same way the graph/tiles artifacts are delivered
to the accessory volumes. Camera data then lags OSM by ≤~24h (the extract's
freshness), well inside the 3-missed-refresh staleness window (FR-008/009).

### Escape hatch — switching to live Overpass

Flip the substrate to the live API **without a deploy of new code** — it's pure
configuration. Reach for it when: the daily extract/delivery is broken and you
need fresh camera data *now*; you're debugging a suspected parity gap; or you've
stood up a self-hosted Overpass and want near-live refreshes.

```bash
# 1. Set the mode (and, optionally, a self-hosted endpoint to avoid the public
#    Overpass fair-use limits — strongly preferred for nationwide tiling):
kamal env set CAMERA_OSM_SOURCE=overpass          # app + job roles
kamal env set OVERPASS_URL=http://your-overpass:port/api/interpreter   # optional
kamal app boot                                    # pick up the new env

# 2. (Optional) run a refresh immediately instead of waiting for 08:00 UTC:
kamal app exec 'bin/rails runner "DataRefreshJob.perform_later(\"aggregate\", trigger: \"manual\")"'

# 3. Revert when the PBF path is healthy again:
kamal env set CAMERA_OSM_SOURCE=pbf && kamal app boot
```

Notes & cautions:
- **Public Overpass fair-use:** the tiled CONUS sweep is ~390 serial,
  rate-limited requests against `overpass-api.de`. Fine occasionally; for routine
  use point `OVERPASS_URL` at a self-hosted instance (ADR 0001 §parallel-cell).
- **Seamless both ways:** because both mechanisms write the same `OpenStreetMap`
  `DataSource` and the same `osm:node/<id>` refs, flipping back and forth just
  updates the existing camera rows — no retire/re-add churn, no duplicates.
- **No code path is deleted:** `Sources::Overpass` and `UsTiles` stay in the tree
  precisely so this remains a config flip, not a redeploy.

## Images are pinned by digest

`routing`, `tileserver`, and `geocoder` are pinned by `@sha256:…` in
`infra/docker-compose.yml` so dev/prod and reruns are reproducible. To upgrade an
image, change the digest deliberately — do not float to `:latest`.

## Switching the configured country

Switching country is a config change + one provisioning run (no code changes, SC-004):

```bash
COUNTRY=<iso2> infra/scripts/build-geo.sh   # full provisioning incl. cameras + seed
```

The whole-country geocoder OSM import takes **hours**; `build-geo.sh` waits up to
`GEO_GEOCODER_TIMEOUT` minutes (default 360) before importing TIGER — raise it on
slow hardware. `build-geo.sh` **refuses** a leftover single-state `infra/.region`
(it would mis-scope a state extract) — use `setup.sh --region <state>` for those.

Only **US** is provisioned/validated at launch; an unknown country fails fast
(FR-009). Adding a country = a populated record in
[`Geocoding::CountryRegistry`](../../backend/app/services/geocoding/country_registry.rb)
**and** its bash mirror
[`infra/scripts/country-registry.sh`](../../infra/scripts/country-registry.sh),
plus the provisioning run above. The map frames the country from the registry bbox
(`/coverage/bounds`); `/coverage` reports honest present/absent/freshness per
ingested data-region.

### Dev override: a single US state

For a cheaper local build, pick a state at the `setup.sh` prompt (default `IA`) or
pass it explicitly — the wizard makes a single state turnkey:

```bash
infra/scripts/setup.sh --region CA   # single state; or --region US for the country
```

`setup.sh` writes `infra/.env` with `GEOCODER_REGION_STATE` + `GEOCODER_VIEWBOX`
(the state's bbox), which `docker-compose` interpolates into the backend: the
single-region geocoder behavior is enabled (a single-state extract lacks state
boundaries) **and** the initial map frames that state. The TIGER import is narrowed
to just that state. Selecting `US` writes `GEOCODER_COUNTRY=us` (whole-country
geocoding + CONUS framing); absent `infra/.env`, the backend defaults to US (FR-002).

You can also point the extract straight at any Geofabrik `.osm.pbf`:

```bash
REGION_URL=https://download.geofabrik.de/north-america/us/illinois-latest.osm.pbf \
  infra/scripts/fetch-extract.sh
```

## When / why to rebuild

- **Stale OSM** — extracts are point-in-time. Re-fetch and rebuild periodically
  (new/closed roads, geometry fixes) so routing and tiles stay accurate.
- **Coverage change** — adding/removing a region (above).
- **Image upgrade** — after bumping a pinned digest, rebuild to validate.

## Parallelism & tuning (rate-safe)

Both provisioning paths — `build-geo.sh` **and** the `setup.sh` wizard — overlap the
heavy work so the multi-hour Nominatim import hides the rest, **without** leaning on
any rate-limited service:

- The geocoder **OSM import starts right after the extract download**, concurrent
  with the routing + tiles build (which it dwarfs) — so routing/tiles (and, in the
  wizard, the DB + camera steps) are effectively free wall-clock. The wizard's
  "Geocoder OSM import" step then just waits out the tail, and its ETA already
  credits the overlap.
- The ~1.8 GB **TIGER bundle is prefetched in the background** during that import
  (one sequential GET to nominatim.org — *not* parallel chunks), then the import
  step finds it cached. `build-geocoder.sh DOWNLOAD_ONLY=1` is that primitive.
  (`build-geo.sh` does this; the wizard fetches TIGER at its dedicated step.)
- Routing (Valhalla) and tiles (Planetiler) already run in parallel.

The expensive stages (Nominatim/TIGER import, Valhalla, Planetiler) are
**compute-bound, not rate-limited** — scale them with hardware:

| Knob | Applies to | Default | Notes |
|------|-----------|---------|-------|
| `NOMINATIM_THREADS` | geocoder import (osm2pgsql) | **all cores** | `setup.sh`/`build-geo.sh` set it from `nproc`/`hw.ncpu`; the long pole. (Bare `docker compose up` without the scripts falls back to 4.) |
| `NOMINATIM_SHM` | geocoder Postgres `shm_size` | `1gb` | raise (e.g. `4gb`) for a whole-US import |
| `GEO_BUILD_JOBS` | Valhalla + Planetiler | all cores | cap when sharing a box |
| `PLANETILER_XMX` | tiles JVM heap | JVM default | e.g. `16g` for whole-US |
| `GEO_GEOCODER_TIMEOUT` | import wait cap (min) | 360 | raise on slow hardware |

The Postgres import saturates **disk IOPS** before CPU — fast NVMe matters more
than extra threads past a point. The `setup.sh` wizard shows live **elapsed time +
a rough ETA** per build (state ≈ tens of minutes, whole US ≈ hours).

**Do not** parallelize the rate-limited surfaces: the Geofabrik extract is one
bandwidth-bound download (single `curl --retry`); nominatim.org wants ≤2
sequential GETs with the descriptive UA; and the public **Overpass** camera path
throttles hard — which is why the default camera source is the **local PBF**
(`osmium`, no API). Preview the orchestration with `GEO_PLAN_ONLY=1
infra/scripts/build-geo.sh`.

## Resources (whole-US envelope)

A whole-country (US) build is the supported default and is **far heavier** than a
single-state dev extract. Budget for it and run it on a larger/self-hosted machine
— **not a laptop or a standard CI runner** (`build-geo.sh` calls this out, and the
scheduled workflow's runner-sizing note below matches).

| Artifact / step                         | Approx. envelope (whole US)              |
|-----------------------------------------|------------------------------------------|
| OSM extract (`us-latest.osm.pbf`)       | ~10+ GB download on disk                 |
| Valhalla routing graph                  | several GB; RAM-hungry build             |
| Vector tiles (Planetiler, JVM)          | several GB; needs multi-GB heap          |
| Nominatim OSM import (geocoder)         | the long pole — **hours**; large Postgres volume |
| Whole-US TIGER bundle + import          | ~1.8 GB bundle; all ~3,200 counties; **hours** |
| Working RAM (concurrent services)       | **16 GB+ recommended** (Nominatim/Planetiler OOM below ~6 GB) |

By contrast a single-state **dev override** extract builds in minutes at a few
hundred MB. The dominant cost is **build-time provisioning** (above), not
request-time — routing/tiles are pre-built and geocode/coverage are indexed
lookups (perf budgets: spec SC-008).

**Run country builds on a larger/self-hosted runner**, not a hosted GitHub runner
or a laptop. The scheduled rebuild workflow publishes artifacts only
(`GEO_ARTIFACTS_ONLY=1`); full provisioning (TIGER + seed + cameras) is the
operator's `build-geo.sh` run on adequately-sized hardware.

### SC-008 performance verification

Budgets are frozen in spec **SC-008**; this records the verification (T032). The
heavy cost is **build-time** (above), not request-time — country scale does not
change the request-time shape: `/coverage/bounds` is a registry constant,
`/coverage` is an indexed PostGIS containment, and `/geocode/search` is a
viewbox-**bounded** search (research R7), so candidate sets stay small even on a
whole-US index. Routing/tiles are pre-built.

Dev-stack sanity (request-time, 15 samples each — well inside budget; re-run
against the provisioned country stack to capture country-scale p95):

| Path                | Budget (SC-008)     | Dev p50 |
|---------------------|---------------------|---------|
| `/coverage/bounds`  | p95 ≤ 150 ms        | ~9 ms   |
| `/coverage` (point) | p95 ≤ 150 ms        | ~8 ms   |
| `/geocode/search`   | p95 ≤ 600 ms        | ~15 ms  |

Capture the country-scale numbers on the provisioned runner (whole-US Nominatim
index) and confirm against the SC-008 p95 targets before declaring a country GA.

## Verify each service

```bash
# Valhalla up and serving the graph:
curl -s "http://localhost:8002/status"

# A live route through the backend (Des Moines -> Iowa City), ~184 km:
curl -s http://localhost:3000/api/v1/routes -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":41.6611,"lng":-91.5302},
       "aggressiveness":"completely_avoid","locale":"en"}}'

# Tiles (Protomaps PMTiles via go-pmtiles): metadata + a sample vector tile.
# The path key is the filename WITHOUT .pmtiles, i.e. /tiles/...
curl -s "http://localhost:8080/tiles/metadata"
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' "http://localhost:8080/tiles/10/247/380.mvt"

# Nominatim (host port 8081 → container 8080): status + a sample search.
curl -s "http://localhost:8081/status.php"
curl -s "http://localhost:8081/search?q=Des+Moines&format=jsonv2&limit=1"
```

If routing or geocoding is down, the app fails **soft** (a routing request
returns a localized 503; address search degrades and routing still works with
explicit coordinates) — it is not gated by the `/api/v1/health` endpoint. See
[incident-response.md](incident-response.md).

## Staleness detection

The geo substrate is built from a point-in-time OSM extract and is **not**
rebuilt on the camera-refresh cadence, so it drifts from current OSM (new roads,
closures), quietly degrading route quality and camera-segment snapping.

`GeoStalenessJob` (weekly, `config/recurring.yml`) reads Valhalla's
`tileset_last_modified` via `/status` and alerts through `Telemetry` when the
graph is older than `GEO_SUBSTRATE_STALE_DAYS` (default 30). When you see that
alert, rebuild (below). Check manually any time:

```bash
curl -s http://localhost:8002/status | grep tileset_last_modified
```

## Rebuild automation

The build + publish is automated; deploying onto the geo hosts is the one manual
step (it needs host access).

**Build + publish (automated):** `.github/workflows/build-geo.yml` runs
`infra/scripts/build-geo.sh` (fetch → routing graph → tiles → manifest), verifies
integrity, and publishes a versioned GitHub Release tagged
`geo-<region>-<date>-<run>` with the artifacts plus `manifest.json` /
`manifest.sha256` (region, source extract, build time, per-artifact sha256+size).
It runs **on demand** (`workflow_dispatch`, with `region` / `region_url` inputs) —
there is no cron. Trigger a rebuild when `GeoStalenessJob`'s weekly alert reports
the graph has drifted (see [Staleness detection](#staleness-detection)). Build it
locally the same way:

```bash
REGION=iowa infra/scripts/build-geo.sh      # full build + manifest
infra/scripts/geo-manifest.sh verify        # re-check artifacts vs the manifest
```

> **Runner sizing.** Hosted runners fit the Iowa launch region (~0.5 GB). A
> full-US build needs substantially more RAM/disk — point the workflow at a
> larger or self-hosted runner before expanding coverage.

**Deploy the new build onto the geo hosts (manual):**

1. Download the release's `manifest.sha256` + artifacts onto the builder/host and
   `infra/scripts/geo-manifest.sh verify` (or `sha256sum -c manifest.sha256`).
2. Place them in the Kamal accessory volumes — `valhalla.json` +
   `valhalla_tiles.tar` into `routing-data:/data`, `tiles.pmtiles` into
   `tiles-data:/data`, the extract into `nominatim-import` — then restart the
   accessories (`kamal accessory reboot routing tiles geocoder`).
3. `GeoStalenessJob` confirms freshness after the swap; the staleness alert
   clears (or check `curl -s $ROUTING/status | grep tileset_last_modified`).

Tracked in [ADR 0001](../adr/0001-camera-refresh-scaling.md).

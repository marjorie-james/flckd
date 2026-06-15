# Runbook: Building & rebuilding the self-hosted geo stack

Routing, geocoding, and tiles all run on **our own infrastructure** — never a
third party — so a user's origin/destination/route is never sent out (FR-012a).
The geo data is built from a **public OpenStreetMap extract** by three scripts in
`infra/scripts/`. Everything is rebuildable from public OSM; only the PostGIS
`cameras` table needs backing up (see [backups.md](backups.md)).

Launch region is **Iowa**. See also [infra/README.md](../../infra/README.md).

## Build the data (in order)

Heavy tooling runs in containers — no host toolchain needed.

```bash
# 1. Download the OSM extract → infra/data/extract.osm.pbf (Iowa by default)
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

## Expanding coverage beyond Iowa

Override the extract with `REGION_URL` (any Geofabrik `.osm.pbf`):

```bash
REGION_URL=https://download.geofabrik.de/north-america/us/illinois-latest.osm.pbf \
  infra/scripts/fetch-extract.sh
```

For multiple states, fetch each and merge before building, or build per region:

```bash
osmium merge a.osm.pbf b.osm.pbf -o infra/data/extract.osm.pbf
```

Then **rebuild** the routing graph and tiles (steps 2–3) and **re-import**
Nominatim (rebuild the `geocoder` service) from the new/merged extract. Also
import camera data for the new states (`camera_data:import`) and seed a
`CoverageArea` per state so the app reports where avoidance is supported (FR-018).
The default `REGION_URL` lives in
[infra/scripts/fetch-extract.sh](../../infra/scripts/fetch-extract.sh).

## When / why to rebuild

- **Stale OSM** — extracts are point-in-time. Re-fetch and rebuild periodically
  (new/closed roads, geometry fixes) so routing and tiles stay accurate.
- **Coverage change** — adding/removing a region (above).
- **Image upgrade** — after bumping a pinned digest, rebuild to validate.

## Resources

The whole US is ~10+ GB of OSM and needs **substantially more RAM/disk and build
time** than a single state. Build full-US graphs/tiles on a beefy machine or in
CI — **not a laptop**. A single-state extract builds in minutes at a few hundred
MB.

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

# Self-hosted geo stack

Everything the Camera-Avoiding Route Planner needs to route, geocode, and draw maps runs on **our own
infrastructure** — never a third party. This directory holds the local dev stack
([docker-compose.yml](docker-compose.yml)) and the scripts that build the geo data from a public OSM
extract ([scripts/](scripts/)).

> **Anonymity:** the build scripts download only **public** OpenStreetMap data. Once built, routing,
> geocoding, and tiles all run locally/self-hosted, so a user's origin/destination/route is never sent
> to a third party (FR-012a).

## Launch region: Iowa

The initial launch region is **Iowa**. The build scripts default to the Iowa extract from Geofabrik.
A single-state metro extract keeps local builds fast (minutes, a few hundred MB) versus the whole US.

## Build the geo data

All heavy tooling runs in containers — no host toolchain needed (local dev is Docker-only).

```bash
# 1. Download the Iowa OSM extract → infra/data/extract.osm.pbf
infra/scripts/fetch-extract.sh

# 2. Build the Valhalla routing graph → infra/routing/data
#    (Valhalla supports excluding individual road segments — exactly how
#    camera avoidance works: exclude the monitored segment, not a radius.)
infra/scripts/build-routing-graph.sh

# 3. Build self-hosted vector tiles (PMTiles) → infra/tiles/data/tiles.pmtiles
infra/scripts/build-tiles.sh

# 4. Filter camera nodes from the extract → infra/data/cameras.geojson
#    (cadence: daily — independent of the monthly graph/tiles rebuild)
infra/scripts/build-cameras.sh
```

## Run the services

After the geo data is built, start everything at once:

```bash
docker compose -f infra/docker-compose.yml up -d
```

Service startup order is handled automatically via `depends_on`:
`postgres` (healthy) → geo services start → `backend` starts → `frontend` starts.

**Starting individual services** (if you need a subset):

```bash
# Database only
docker compose -f infra/docker-compose.yml up -d postgres

# Geo services only (after build)
docker compose -f infra/docker-compose.yml up -d routing tileserver geocoder

# App layer only (assumes postgres + geo already up)
docker compose -f infra/docker-compose.yml up -d backend frontend
```

## Reset / teardown

To reset the local environment to a fresh state — tear down the compose stack and
its volumes (wiping the Postgres database and the Nominatim OSM import) and delete
the generated geo data on disk — run the inverse of `setup.sh`:

```bash
# Full reset: containers + volumes + generated geo data (keeps infra/.region)
infra/scripts/teardown.sh

# Preview what would be removed, without removing anything
infra/scripts/teardown.sh --dry-run
```

Useful flags: `--keep-data` (only tear down containers/volumes, keep the downloaded
geo data for a faster re-up), `--purge-region` (also drop `infra/.region`), and
`-y/--yes` (skip the confirmation prompt). After teardown, rebuild with
`infra/scripts/setup.sh`.

**Nominatim first-run note:** on initial `up`, the geocoder runs a one-time OSM
import that takes ~25–30 minutes for Iowa (persisted in the `nominatim_data` volume).
Address search degrades gracefully during this time — routing still works. Watch
progress with `docker compose -f infra/docker-compose.yml logs -f geocoder`.

The backend reaches each service by its compose hostname over the private network:
`routing:8002`, `tileserver:8080`, `geocoder:8080` (env: `ROUTING_URL`, `VITE_TILES_PROXY`,
`GEOCODER_URL`). Verified working with the Iowa data:

```bash
# Valhalla is up and serving the Iowa graph:
curl -s "http://localhost:8002/status"
# A live route through the backend (Des Moines -> Iowa City): ~184 km, ~104 min,
# localized maneuvers, ~90 ms server-side.
curl -s http://localhost:3000/api/v1/routes -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":41.6611,"lng":-91.5302},
       "aggressiveness":"completely_avoid","locale":"en"}}'
# Tiles (Protomaps PMTiles via go-pmtiles): metadata + a vector tile.
# NOTE the path key is the filename WITHOUT .pmtiles, i.e. /tiles/...
curl -s "http://localhost:8080/tiles/metadata"
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' "http://localhost:8080/tiles/10/247/380.mvt"
```

### Basemap style

`tileserver` serves the raw vector tiles at `/tiles/{z}/{x}/{y}.mvt` (proxied to the frontend via
`vite.config.ts`). The frontend renders them with a self-hosted MapLibre style at
`frontend/public/map-style.json` (the `MapView` default; override with `VITE_MAP_STYLE_URL`). It is
intentionally **label-less** — it references only our own `/tiles` and uses no glyphs/sprites/
third-party sources, so the basemap makes zero outbound requests (anonymity, FR-012a).

**Follow-up:** text labels (place/road names) need self-hosted glyph PBFs plus symbol layers. Add a
`fonts/{fontstack}/{range}.pbf` set under `public/` (or serve via Martin) and reference it from
`map-style.json` (`glyphs`), then add `symbol` layers — keeping everything self-hosted.

## Camera data

The map renders the known ALPR/Flock cameras in the current viewport. **`setup.sh` imports only 5 demo
"fixture" cameras** for a fast first run — so the map looks almost empty until you load the real data.
(`setup.sh` offers to do this for you right after the build; this section is the manual path.)

The real cameras live in **OpenStreetMap** — the same substrate community maps (e.g. DeFlock)
contribute to. Two ways to load them:

**Default — PBF extract** (`SOURCE=pbf`, the production path; no API, no rate limit). Filters the ALPR
cameras out of the OSM extract the stack already downloaded and imports the GeoJSON. `osmium-tool` runs
from a small pinned image (`infra/osmium/Dockerfile`) if it isn't on your host — no install needed. This
is what `setup.sh` offers right after the build:

```bash
# Build the GeoJSON into the backend's read path, then import it:
OUT=backend/storage/cameras.geojson infra/scripts/build-cameras.sh
docker compose -f infra/docker-compose.yml run --rm -e SOURCE=pbf backend bin/rails camera_data:import
# Iowa: ~717 ALPR cameras.
```

**Escape hatch — Overpass API** (live data; needs internet). Fetches the region's ALPR nodes scoped to a
bounding box `south,west,north,east` (the example is Iowa — match it to your region). Note the public
Overpass API rate-limits aggressively; the import exits non-zero and tells you to retry if it's throttled:

```bash
docker compose -f infra/docker-compose.yml run --rm -e SOURCE=overpass \
  -e BBOX="40.3,-96.7,43.6,-90.0" backend bin/rails camera_data:import
```

Either path snaps each camera to its monitored road segment(s) via Valhalla (avoidance excludes the
segment, not a radius). Re-run anytime to refresh; in production the daily aggregate refresh
(`backend/config/recurring.yml`) keeps it current.

## Geocoder (Nominatim)

Forward/reverse geocoding (`/api/v1/geocode/*`) is served by self-hosted **Nominatim**
(`mediagis/nominatim`), which imports the same Iowa OSM extract. On first `up` it runs a one-time
import (slow; persisted in the `nominatim_data` volume), then serves `/search` and `/reverse`.
`Geocoding::GeocoderClient` maps Nominatim's jsonv2 places to the app's
`{ label, lat, lng, type, confidence }` shape. `IMPORT_STYLE=address` keeps the import lean for
autocomplete. If the geocoder is down, address search degrades gracefully and routing still works with
explicit coordinates.

### House-number coverage (TIGER/Line)

OSM often lacks individual house numbers. `infra/scripts/build-geocoder.sh` downloads ADDR
shapefiles from the US Census Bureau (up to 5 files in parallel) and imports them into the running
Nominatim instance, enabling queries like `"123 Main St, Des Moines"` to resolve to specific house
numbers rather than falling back to street-level results.

**If you used the setup wizard** (`infra/scripts/setup.sh`), this step ran automatically — no action
needed.

**To run it manually** (must be done after the geocoder finishes its initial OSM import, ~25–30 min
first run):

```bash
infra/scripts/build-geocoder.sh
```

ZIP files are cached in `infra/data/tiger/<fips>/` — re-running is fast (cached `.dbf` files are
detected and skipped; only missing files are fetched). HTTP 429 / 5xx responses trigger automatic
exponential backoff with jitter, up to 4 attempts per file. Lower `MAX_PARALLEL_DOWNLOADS` in the
script if you see persistent rate-limit errors.

## Expanding coverage to more states

Iowa is just the launch region. To add more states (and eventually national coverage):

1. **Pick the extents.** Fetch each additional state extract from Geofabrik, e.g.
   `REGION_URL=https://download.geofabrik.de/north-america/us/illinois-latest.osm.pbf infra/scripts/fetch-extract.sh`.
   For multiple states, either build each separately or merge the `.osm.pbf` files first
   (`osmium merge a.osm.pbf b.osm.pbf -o extract.osm.pbf`) and build once.
2. **Rebuild** the routing graph and tiles from the new/merged extract (steps 2–3 above). Valhalla and
   Planetiler scale to multi-state and full-US inputs given enough RAM/disk and time.
3. **Geocoder:** re-import Nominatim for the new/merged extract (rebuild the `geocoder` service).
4. **Camera data + coverage:** import camera data for the new states (`camera_data:import`) and add a
   `CoverageArea` per state so the app reports where avoidance is supported (FR-018). The app already
   degrades gracefully outside coverage (`coverage_warning: outside_coverage`).
5. **Resources:** the whole US is ~10+ GB of OSM and needs substantially more RAM/disk and build time
   than a single state — plan to build graphs/tiles on a beefier machine or in CI, not a laptop.

When the launch set grows beyond Iowa, update the default `REGION_URL` in
[scripts/fetch-extract.sh](scripts/fetch-extract.sh) (or document the per-region build) and seed the
matching `CoverageArea` rows.

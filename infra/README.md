# Self-hosted geo stack

Everything the Camera-Avoiding Route Planner needs to route, geocode, and draw maps runs on **our own
infrastructure** — never a third party. This directory holds the local dev stack
([docker-compose.yml](docker-compose.yml)) and the scripts that build the geo data from a public OSM
extract ([scripts/](scripts/)).

> **Anonymity:** the build scripts download only **public** OpenStreetMap data. Once built, routing,
> geocoding, and tiles all run locally/self-hosted, so a user's origin/destination/route is never sent
> to a third party (FR-012a).

## Deployment scope: start with a state, scale to a country

**For local dev, build a single US state** — it's cheap and fast (a few hundred MB, ~25–30 min) and runs
on a laptop. The setup wizard defaults to one (Iowa); see "Dev override" below.

The full **production scope is an entire country, defaulting to the United States** (FR-002). The
configured country (`COUNTRY`, default `us`) drives the OSM extract, routing graph, vector tiles,
geocoder index + whole-US TIGER house numbers, camera gathering, map framing, and coverage — all from
[`Geocoding::CountryRegistry`](../backend/app/services/geocoding/country_registry.rb) and its bash mirror
[`scripts/country-registry.sh`](scripts/country-registry.sh). Only **US** is populated and validated at
launch; an unknown / un-provisioned country **fails fast** with an actionable error (FR-009).

> **Resource note:** a whole-US build is **far heavier** than a state — **16 GB+ RAM** and
> **~350–400 GB of free disk** (the Nominatim Postgres volume alone reaches ~250–350 GB during the
> import, on top of the ~10+ GB OSM extract and ~1.8 GB TIGER bundle), and a multi-hour Nominatim
> import. If the host disk fills, the import dies and leaves a corrupt volume you must delete
> (`docker volume rm infra_nominatim_data`) before retrying. Run country
> builds on a larger/self-hosted machine, **not** a laptop or a standard CI runner. See
> [docs/runbooks/geo-stack.md](../docs/runbooks/geo-stack.md).

## Provision a country (one command)

The canonical, country-aware one-command provisioning path is
[`scripts/build-geo.sh`](scripts/build-geo.sh) (FR-013). It fetches the country extract, builds routing
+ tiles, runs TIGER, seeds the data-region, imports cameras, and writes the manifest:

```bash
infra/scripts/build-geo.sh                 # full provisioning, whole US (default)
COUNTRY=us infra/scripts/build-geo.sh      # explicit country
```

`infra/scripts/setup.sh` is the interactive wrapper (prompts + progress panel). At its prompt you can
enter a **2-letter state** *or* **`US`** for the whole country — it **defaults to `IA`** (Iowa: a cheap,
fast dev build). It writes `infra/.region` and `infra/.env` (the latter selects the backend's
country-vs-state geocoder scope + map framing, turnkey — see "Dev override" below). For CI/artifact-only
builds (extract + routing + tiles + manifest, no services), set `GEO_ARTIFACTS_ONLY=1`.

### Individual steps

All heavy tooling runs in containers — no host toolchain needed (local dev is Docker-only).

```bash
# 1. Download the configured country's OSM extract → infra/data/extract.osm.pbf
#    (COUNTRY=us → the whole-US Geofabrik PBF)
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
import (persisted in the `nominatim_data` volume) — **~25–30 minutes for a single state**
(e.g. Iowa); a whole-US build takes **hours**. Address search degrades gracefully during
this time — routing still works. Watch progress with
`docker compose -f infra/docker-compose.yml logs -f geocoder`.

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
       "locale":"en"}}'
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

## Switching the configured country

Switching country is a **configuration change plus one provisioning run** — no code changes (SC-004):

```bash
COUNTRY=<iso2> infra/scripts/build-geo.sh   # full provisioning incl. cameras + seed (FR-012/013)
```

Only **US** is populated and validated at launch. Adding a country means: (1) add a populated record to
[`Geocoding::CountryRegistry`](../backend/app/services/geocoding/country_registry.rb) **and** its bash
mirror [`scripts/country-registry.sh`](scripts/country-registry.sh) (extract URL, bbox, whether TIGER
applies), and (2) provision its data with the command above. Until both exist, that country code fails
setup fast (FR-009) — it is never silently swapped for another country.

`build-geo.sh` seeds the country's data-region and frames the whole country from the registry bbox
(`/coverage/bounds`), so the map frames the country however sparse the camera footprint. `/coverage`
then reports honest present / absent / freshness **per ingested data-region** (FR-007/FR-008).

## Dev override: a single US state

For a cheaper, faster local build, pick a single US **state** at the `setup.sh` prompt (the default is
`IA`), or pass it explicitly:

```bash
infra/scripts/setup.sh --region CA          # single-state dev scope
infra/scripts/setup.sh --region US          # or the whole country, from the same wizard
infra/scripts/setup.sh                       # interactive; defaults to IA
```

Selecting a state is **turnkey**: `setup.sh` writes `infra/.env` with `GEOCODER_REGION_STATE` (the
state) and `GEOCODER_VIEWBOX` (the state's bbox), which `docker-compose` interpolates into the backend.
That:
- runs the legacy single-region geocoder behavior (strips the state token, fills the `…, IA` label
  fallback) — needed because a single-state extract lacks state-level admin boundaries; and
- **frames the initial map on that state** (`/coverage/bounds` returns the state's extent).

Selecting `US` writes `GEOCODER_COUNTRY=us` instead, so the geocoder disambiguates by state and the map
frames the **entire continental US**. Absent `infra/.env`, the backend defaults to whole-country US
(FR-002). The single-state TIGER import is narrowed to just that state (not the whole-US bundle).

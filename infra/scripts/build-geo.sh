#!/usr/bin/env bash
#
# Canonical one-command country provisioning (FR-013). Country-aware (reads
# COUNTRY, default the United States), it builds the full self-hosted geo
# substrate end to end and emits a versioned manifest:
#
#   fetch-extract → routing graph + vector tiles (parallel) → manifest
#   → [full] services up → DB prepare/seed → TIGER → camera import (SOURCE=pbf)
#
# setup.sh is the interactive wrapper around this script (prompts + progress
# panel); both produce an identical-scope stack — extract, routing, tiles,
# geocoder + TIGER, the seeded data-region, AND imported cameras — so default-US
# setup and a country switch yield a fully populated deployment, not a map
# without cameras.
#
# Anonymity note: builds from PUBLIC OSM / Census data only; no user data is
# involved.
#
# Usage:
#   infra/scripts/build-geo.sh                    # full provisioning, whole US
#   COUNTRY=us infra/scripts/build-geo.sh         # explicit country
#   GEO_ARTIFACTS_ONLY=1 infra/scripts/build-geo.sh   # CI: artifacts only
#                                                     # (extract+routing+tiles+manifest)
#
# Resource note: a whole-US build is ~10+ GB of OSM plus the whole-US TIGER
# bundle (~1.8 GB) and a long Nominatim import — run it on a larger/self-hosted
# machine, not a laptop or standard CI runner (see docs/runbooks/geo-stack.md).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${DIR}/../docker-compose.yml"

# Load per-developer config (COUNTRY etc.). REGION_CONFIG is overridable for tests.
REGION_CONFIG="${REGION_CONFIG:-${DIR}/../.region}"
# shellcheck source=/dev/null
[ -f "${REGION_CONFIG}" ] && source "${REGION_CONFIG}"

# Resolve the configured country (default us) → COUNTRY_CODE / COUNTRY_NAME /
# COUNTRY_EXTRACT_URL / COUNTRY_TIGER. Fails fast on an unknown country (FR-009).
# shellcheck source=/dev/null
. "${DIR}/country-registry.sh"

# A leftover single-state .region (STATE_FIPS set, COUNTRY unset — written by
# `setup.sh --region`) would otherwise resolve to us here and silently provision a
# whole-country geocoder scope + whole-US TIGER over a state-sized extract. Refuse
# it: state dev builds go through setup.sh (which scopes everything correctly).
if [ -n "${STATE_FIPS:-}" ] && [ -z "${COUNTRY:-}" ]; then
  echo "error: infra/.region is a single-state dev config (STATE_FIPS=${STATE_FIPS}, no COUNTRY)." >&2
  echo "  build-geo.sh provisions a whole country. For a single-state dev build use:" >&2
  echo "    infra/scripts/setup.sh --region ${REGION:-<state>}" >&2
  echo "  Or set COUNTRY explicitly to provision a whole country." >&2
  exit 1
fi

country_resolve "${COUNTRY:-us}" || exit 1
export COUNTRY="${COUNTRY_CODE}"

# Provenance for geo-manifest.sh: without these it falls back to a hardcoded Iowa
# region/source_url, so a whole-US (or any country) build would emit a manifest
# claiming Iowa provenance with real sha256s (verify would pass and never surface
# the mismatch). Export the actually-fetched country extract so `generate` records
# correct provenance. REGION_URL only sets the default if not already overridden.
export REGION="${REGION:-${COUNTRY_CODE}}"
export REGION_URL="${REGION_URL:-${COUNTRY_EXTRACT_URL}}"

# Default the Nominatim import (the long pole) to ALL cores; docker-compose
# interpolates NOMINATIM_THREADS into the geocoder service (else it falls back to
# 4). Override by exporting NOMINATIM_THREADS / NOMINATIM_SHM / GEO_BUILD_JOBS.
export NOMINATIM_THREADS="${NOMINATIM_THREADS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

LOG_DIR="${LOG_DIR:-${DIR}/../data/build-logs}"
ENV_FILE="${ENV_FILE:-${DIR}/../.env}"
mkdir -p "${LOG_DIR}"

# GEO_PLAN_ONLY=1 prints the ordered execution plan (which services start when,
# what overlaps, what runs in the background) and performs NO Docker work — the
# test seam that lets test/infra/build-geo.bats verify the orchestration offline.
# `_exec` is true only on a real run; `_run` executes a simple command or, in plan
# mode, prints it — so plan and execution share one code path (no drift).
_exec() { [ "${GEO_PLAN_ONLY:-0}" != "1" ]; }
_run() { if _exec; then "$@"; else echo "PLAN: $*"; fi; }

FULL=1
[ "${GEO_ARTIFACTS_ONLY:-0}" = "1" ] && FULL=0

echo "==> Provisioning geo stack for ${COUNTRY_NAME} (${COUNTRY_CODE})"
echo "    Nominatim import threads: ${NOMINATIM_THREADS} (NOMINATIM_THREADS); routing/tiles: ${GEO_BUILD_JOBS:-all cores}"

echo "==> [1/4] Fetch OSM extract"
_run "${DIR}/fetch-extract.sh"

# ── Overlap (full provisioning only) ─────────────────────────────────────────
# The Nominatim OSM import is the multi-hour LONG POLE and only needs the extract
# (now on disk). Start it NOW so it runs CONCURRENTLY with the routing + tiles
# build below — hiding routing/tiles entirely behind the import. Also prefetch the
# ~1.8 GB TIGER bundle in the background (rate-safe: one sequential GET to
# nominatim.org, not parallel chunks) so it's off the critical path too. Both are
# pure wins with no external rate-limit cost.
TIGER_PREFETCH_PID=""
if [ "${FULL}" = "1" ]; then
  # Run the backend in whole-country mode (clears any stale single-state
  # infra/.env left by `setup.sh --region`). docker-compose interpolates these.
  if _exec; then
    {
      echo "# flckd geocoder scope — generated by infra/scripts/build-geo.sh."
      echo "GEOCODER_COUNTRY=${COUNTRY_CODE}"
      echo "GEOCODER_REGION_STATE="
      echo "GEOCODER_VIEWBOX="
    } > "${ENV_FILE}"
  else
    echo "PLAN: write ${ENV_FILE} (GEOCODER_COUNTRY=${COUNTRY_CODE})"
  fi

  echo "==> [overlap] Start geocoder OSM import now (concurrent with routing+tiles)"
  _run docker compose -f "${COMPOSE_FILE}" up -d geocoder

  echo "==> [overlap] Prefetch TIGER county CSVs in the background → ${LOG_DIR}/tiger-prefetch.log"
  if _exec; then
    DOWNLOAD_ONLY=1 "${DIR}/build-geocoder.sh" > "${LOG_DIR}/tiger-prefetch.log" 2>&1 &
    TIGER_PREFETCH_PID=$!
  else
    echo "PLAN: DOWNLOAD_ONLY=1 ${DIR}/build-geocoder.sh &  (background TIGER prefetch)"
  fi
fi

# ── Routing graph + vector tiles, in parallel ────────────────────────────────
# Both read the same extract and write to separate dirs; GEO_BUILD_JOBS (if set)
# caps each one's concurrency. Each writes its own log so output doesn't
# interleave; logs are printed on failure.
echo "==> [2+3/4] Build routing graph (Valhalla) + vector tiles (Planetiler) in parallel"
if _exec; then
  echo "    Routing log → ${LOG_DIR}/routing.log"
  echo "    Tiles log   → ${LOG_DIR}/tiles.log"

  "${DIR}/build-routing-graph.sh" > "${LOG_DIR}/routing.log" 2>&1 &
  ROUTING_PID=$!
  "${DIR}/build-tiles.sh" > "${LOG_DIR}/tiles.log" 2>&1 &
  TILES_PID=$!

  ROUTING_EXIT=0
  TILES_EXIT=0
  wait "${ROUTING_PID}" || ROUTING_EXIT=$?
  wait "${TILES_PID}"   || TILES_EXIT=$?

  if [ "${ROUTING_EXIT}" -ne 0 ] || [ "${TILES_EXIT}" -ne 0 ]; then
    echo "" >&2
    echo "error: parallel build step failed" >&2
    [ "${ROUTING_EXIT}" -ne 0 ] && { echo "--- routing log (last 30 lines) ---" >&2; tail -30 "${LOG_DIR}/routing.log" >&2; }
    [ "${TILES_EXIT}" -ne 0 ]   && { echo "--- tiles log (last 30 lines) ---"   >&2; tail -30 "${LOG_DIR}/tiles.log"   >&2; }
    echo "" >&2
    echo "Full logs: ${LOG_DIR}/routing.log  ${LOG_DIR}/tiles.log" >&2
    exit 1
  fi
  echo "    Routing graph: done"
  echo "    Vector tiles:  done"
else
  echo "PLAN: ${DIR}/build-routing-graph.sh & ${DIR}/build-tiles.sh  (parallel)"
fi

echo "==> [4/4] Write versioned manifest"
_run "${DIR}/geo-manifest.sh" generate

# CI / artifact builds stop here: extract + routing + tiles + manifest, no running
# services (the scheduled build-geo.yml uploads these as release assets).
if [ "${FULL}" != "1" ]; then
  echo "Geo artifacts complete for ${COUNTRY_NAME} (artifacts-only; services not started)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Full provisioning (FR-013): finish the stack, seed the data-region, import
# TIGER house numbers, and gather cameras — the geocoder import + TIGER prefetch
# kicked off above have been running this whole time.
# ---------------------------------------------------------------------------
echo "==> [5/8] Start remaining services (postgres, routing, tiles)"
_run docker compose -f "${COMPOSE_FILE}" up -d postgres routing tileserver

echo "==> [6/8] Prepare database + seed the ${COUNTRY_NAME} data-region"
# `bundle check || bundle install` self-heals a stale bundle_cache volume so
# db:prepare doesn't die on a missing gem. db:prepare runs db/seeds.rb on a fresh
# database (the country data-region); db:seed is idempotent for an existing one.
_run docker compose -f "${COMPOSE_FILE}" run --rm backend \
  sh -ec 'bundle check >/dev/null 2>&1 || bundle install; bin/rails db:prepare db:seed'

echo "==> [7/8] Finish the geocoder OSM import, then import TIGER house numbers"
# The import has been running since [overlap]; wait for it to finish. A
# WHOLE-COUNTRY import takes HOURS — the cap is generous (default 6h). Override
# with GEO_GEOCODER_TIMEOUT (minutes).
if _exec; then
  _geo_timeout=$(( ${GEO_GEOCODER_TIMEOUT:-360} * 60 ))
  echo "    Waiting up to ${GEO_GEOCODER_TIMEOUT:-360} min (override GEO_GEOCODER_TIMEOUT)."
  _t0=$SECONDS
  until curl -sf "http://localhost:8081/status.php" >/dev/null 2>&1; do
    if [ $(( SECONDS - _t0 )) -gt "${_geo_timeout}" ]; then
      echo "error: geocoder did not become healthy within ${GEO_GEOCODER_TIMEOUT:-360} min." >&2
      echo "  A whole-US import can exceed this on modest hardware — raise GEO_GEOCODER_TIMEOUT." >&2
      echo "  Check: docker compose -f ${COMPOSE_FILE} logs geocoder" >&2
      exit 1
    fi
    sleep 10
  done
  # Reap the background TIGER prefetch so its CSVs are cached before the import
  # (build-geocoder.sh then skips straight to add-data). A failed prefetch is
  # non-fatal — the full run below just re-downloads.
  if [ -n "${TIGER_PREFETCH_PID}" ]; then
    wait "${TIGER_PREFETCH_PID}" || echo "warn: TIGER prefetch did not complete; will re-download." >&2
  fi
else
  echo "PLAN: wait for geocoder healthy (up to ${GEO_GEOCODER_TIMEOUT:-360} min), reap TIGER prefetch"
fi
# build-geocoder.sh skips itself automatically for a tiger:false country, and uses
# the prefetched CSVs when present.
_run "${DIR}/build-geocoder.sh"

echo "==> [8/8] Import cameras for ${COUNTRY_NAME} from the OSM extract (offline; no API)"
# Filter ALPR nodes out of the extract already on disk into the backend's read
# path, then import them (SOURCE=pbf). No Overpass API → no rate limit.
if _exec; then
  CAMERA_GEOJSON="$(cd "${DIR}/../.." && pwd)/backend/storage/cameras.geojson"
  OUT="${CAMERA_GEOJSON}" "${DIR}/build-cameras.sh"
  docker compose -f "${COMPOSE_FILE}" run --rm -e SOURCE=pbf backend bin/rails camera_data:import
else
  echo "PLAN: build-cameras.sh + camera_data:import SOURCE=pbf"
fi

echo "Geo provisioning complete for ${COUNTRY_NAME} (${COUNTRY_CODE}) — routing, tiles,"
echo "geocoder + TIGER, the seeded data-region, and imported cameras are all in place."

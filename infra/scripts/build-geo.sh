#!/usr/bin/env bash
#
# Build the full self-hosted geo substrate for a region, end to end, and emit a
# versioned manifest. This is the one command the scheduled rebuild pipeline runs
# (.github/workflows/build-geo.yml) — it chains the individual scripts so the
# routing graph, vector tiles, and manifest are produced from one fresh OSM
# extract (ADR 0001 — OSM substrate automation).
#
# Anonymity note: builds from PUBLIC OSM data only; no user data is involved.
#
# Usage:
#   infra/scripts/build-geo.sh                      # default: Iowa launch region
#   REGION=california \
#   REGION_URL=https://download.geofabrik.de/north-america/us/california-latest.osm.pbf \
#     infra/scripts/build-geo.sh
#
# Resource note: the Iowa launch region fits a standard CI runner (~1 GB of
# artifacts). A full-US build needs substantially more RAM/disk — run it on a
# larger/self-hosted runner (see docs/runbooks/geo-stack.md).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Load per-developer region config written by infra/scripts/setup.sh (if present).
REGION_CONFIG="${DIR}/../.region"
# shellcheck source=/dev/null
[ -f "${REGION_CONFIG}" ] && source "${REGION_CONFIG}"

LOG_DIR="${DIR}/../data/build-logs"
mkdir -p "${LOG_DIR}"

echo "==> [1/4] Fetch OSM extract"
"${DIR}/fetch-extract.sh"

# Steps 2 and 3 are independent: both read from the same extract.osm.pbf and
# write to separate directories (routing/data and tiles/data). Run them in
# parallel — Planetiler also downloads its own Natural Earth sources during the
# build, so there's real download-level parallelism too.
#
# Each job writes to its own log file so output doesn't interleave. The logs
# are printed on failure to aid debugging.

echo "==> [2+3/4] Build routing graph (Valhalla) + vector tiles (Planetiler) in parallel"
echo "    Routing log → ${LOG_DIR}/routing.log"
echo "    Tiles log   → ${LOG_DIR}/tiles.log"

"${DIR}/build-routing-graph.sh" > "${LOG_DIR}/routing.log" 2>&1 &
ROUTING_PID=$!

"${DIR}/build-tiles.sh" > "${LOG_DIR}/tiles.log" 2>&1 &
TILES_PID=$!

# Wait for both and collect exit codes. With set -e, background jobs don't
# trigger early exit — we collect the codes explicitly and check below.
ROUTING_EXIT=0
TILES_EXIT=0
wait "${ROUTING_PID}" || ROUTING_EXIT=$?
wait "${TILES_PID}"   || TILES_EXIT=$?

if [ "${ROUTING_EXIT}" -ne 0 ] || [ "${TILES_EXIT}" -ne 0 ]; then
  echo ""
  echo "error: parallel build step failed" >&2
  if [ "${ROUTING_EXIT}" -ne 0 ]; then
    echo "--- routing log (last 30 lines) ---" >&2
    tail -30 "${LOG_DIR}/routing.log" >&2
  fi
  if [ "${TILES_EXIT}" -ne 0 ]; then
    echo "--- tiles log (last 30 lines) ---" >&2
    tail -30 "${LOG_DIR}/tiles.log" >&2
  fi
  echo "" >&2
  echo "Full logs: ${LOG_DIR}/routing.log  ${LOG_DIR}/tiles.log" >&2
  exit 1
fi

echo "    Routing graph: done"
echo "    Vector tiles:  done"

echo "==> [4/4] Write versioned manifest"
"${DIR}/geo-manifest.sh" generate

echo "Geo build complete for region '${REGION:-iowa}'."

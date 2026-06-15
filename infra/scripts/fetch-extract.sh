#!/usr/bin/env bash
#
# Fetch a US metro OSM extract for the self-hosted geo stack.
#
# Anonymity note: this downloads PUBLIC map data only (no user data leaves this
# machine). The extract feeds the routing graph, the geocoder index, and the
# vector tiles — all of which then run on our own infrastructure so a user's
# origin/destination/route is never sent to a third party (FR-012a).
#
# Usage:
#   infra/scripts/fetch-extract.sh                  # default: Iowa (launch region)
#   REGION_URL=https://download.geofabrik.de/north-america/us/california-latest.osm.pbf \
#     infra/scripts/fetch-extract.sh
#
# Iowa is the initial launch region. To expand coverage to more states, fetch
# each state's extract and rebuild the graph/tiles/geocoder — see infra/README.md
# ("Expanding coverage to more states").
#
set -euo pipefail

# Load per-developer region config written by infra/scripts/setup.sh (if present).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION_CONFIG="${SCRIPT_DIR}/../.region"
# shellcheck source=/dev/null
[ -f "${REGION_CONFIG}" ] && source "${REGION_CONFIG}"

REGION_URL="${REGION_URL:-https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf}"
DATA_DIR="${DATA_DIR:-$(cd "$(dirname "$0")/.." && pwd)/data}"
EXTRACT_PATH="${DATA_DIR}/extract.osm.pbf"

mkdir -p "${DATA_DIR}"

# Skip the (large) re-download when the same region's extract is already on disk.
# A sibling marker records the URL of the cached file so a region change (a
# different REGION_URL) still forces a fresh download. Override with FORCE=1.
URL_MARKER="${EXTRACT_PATH}.url"
if [ "${FORCE:-0}" != "1" ] && [ -s "${EXTRACT_PATH}" ] \
   && [ -f "${URL_MARKER}" ] && [ "$(cat "${URL_MARKER}")" = "${REGION_URL}" ]; then
  echo "Extract already present for this region — skipping download (set FORCE=1 to re-fetch)."
  echo "  at: ${EXTRACT_PATH} ($(du -h "${EXTRACT_PATH}" | cut -f1))"
  echo "Next: infra/scripts/build-routing-graph.sh && infra/scripts/build-tiles.sh"
  exit 0
fi

echo "Fetching OSM extract:"
echo "  from: ${REGION_URL}"
echo "  to:   ${EXTRACT_PATH}"

if command -v curl >/dev/null 2>&1; then
  curl -fSL --retry 3 -o "${EXTRACT_PATH}" "${REGION_URL}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${EXTRACT_PATH}" "${REGION_URL}"
else
  echo "error: need curl or wget" >&2
  exit 1
fi

printf '%s\n' "${REGION_URL}" > "${URL_MARKER}"
echo "Done. Extract size: $(du -h "${EXTRACT_PATH}" | cut -f1)"
echo "Next: infra/scripts/build-routing-graph.sh && infra/scripts/build-tiles.sh"

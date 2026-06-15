#!/usr/bin/env bash
#
# Fetch the configured country's whole-country OSM extract for the self-hosted
# geo stack (default: the United States — the whole-US Geofabrik PBF).
#
# Anonymity note: this downloads PUBLIC map data only (no user data leaves this
# machine). The extract feeds the routing graph, the geocoder index, and the
# vector tiles — all of which then run on our own infrastructure so a user's
# origin/destination/route is never sent to a third party (FR-012a).
#
# Usage:
#   infra/scripts/fetch-extract.sh                  # default: the whole US
#   COUNTRY=us infra/scripts/fetch-extract.sh        # explicit country
#   REGION_URL=https://download.geofabrik.de/north-america/us/california-latest.osm.pbf \
#     infra/scripts/fetch-extract.sh                 # explicit override (dev: a sub-region)
#
# The country drives the default extract URL via the country registry
# (country-registry.sh); an unknown / un-provisioned country fails fast (FR-009).
# REGION_URL stays as an explicit override for a cheaper dev sub-region build.
#
set -euo pipefail

# Load per-developer region config written by infra/scripts/setup.sh (if present).
# REGION_CONFIG is overridable (tests point it elsewhere); explicit COUNTRY /
# REGION_URL in the environment still win because .region (country mode) carries
# only COUNTRY, not a clobbering REGION_URL.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION_CONFIG="${REGION_CONFIG:-${SCRIPT_DIR}/../.region}"
# shellcheck source=/dev/null
[ -f "${REGION_CONFIG}" ] && source "${REGION_CONFIG}"

# Resolve the configured country (default us) to its whole-country extract URL.
# Validates the country first, so an unknown code fails even when REGION_URL is
# set (the override only redirects WHERE we download, not WHETHER the country is
# supported).
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/country-registry.sh"
country_resolve "${COUNTRY:-us}" || exit 1

REGION_URL="${REGION_URL:-${COUNTRY_EXTRACT_URL}}"
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

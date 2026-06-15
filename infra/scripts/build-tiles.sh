#!/usr/bin/env bash
#
# Build self-hosted vector tiles (Protomaps PMTiles) from the OSM extract. The
# frontend's MapLibre style points at our own tileserver — never a third-party
# tile/CDN — so map panning does not leak the area a user is viewing (FR-012a).
#
# Output: infra/tiles/data/tiles.pmtiles, served by the `tileserver` compose
# service (Martin / tileserver-gl) and referenced by VITE_MAP_STYLE_URL.
#
# Usage: infra/scripts/build-tiles.sh
#
# Parallelism: Planetiler is multi-threaded and uses all cores by default. For a
# whole-US build give the JVM a large heap (PLANETILER_XMX, e.g. 16g) and cap
# threads with GEO_BUILD_JOBS when sharing the box with the routing/geocoder build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTRACT="${ROOT}/data/extract.osm.pbf"
TILES_DATA="${ROOT}/tiles/data"
# Pinned by digest for reproducible tile builds; override with PLANETILER_IMAGE.
PLANETILER_IMAGE="${PLANETILER_IMAGE:-ghcr.io/onthegomap/planetiler:latest@sha256:61eebbcf6a37339eaf6be9b8ca5b5b54e0cf8db47e6cdd5d718b7754b78cd5e5}"

[ -f "${EXTRACT}" ] || { echo "error: ${EXTRACT} not found — run fetch-extract.sh first" >&2; exit 1; }
mkdir -p "${TILES_DATA}"
cp -f "${EXTRACT}" "${TILES_DATA}/extract.osm.pbf"

# Optional JVM heap (PLANETILER_XMX) and thread cap (GEO_BUILD_JOBS). Unset → JVM
# default heap + all cores.
DOCKER_ENV=()
[ -n "${PLANETILER_XMX:-}" ] && DOCKER_ENV+=(-e "JAVA_TOOL_OPTIONS=-Xmx${PLANETILER_XMX}")
THREADS_FLAG=()
[ -n "${GEO_BUILD_JOBS:-}" ] && THREADS_FLAG+=("--threads=${GEO_BUILD_JOBS}")

echo "Building PMTiles from the extract…"
# ${arr[@]+"${arr[@]}"} safely expands an empty array under `set -u` (bash 3.2).
docker run --rm ${DOCKER_ENV[@]+"${DOCKER_ENV[@]}"} -v "${TILES_DATA}:/data" "${PLANETILER_IMAGE}" \
  --osm-path=/data/extract.osm.pbf \
  --output=/data/tiles.pmtiles \
  --download \
  --download-dir=/data/sources \
  --tmpdir=/data/tmp \
  ${THREADS_FLAG[@]+"${THREADS_FLAG[@]}"} \
  --force

echo "Done. tiles.pmtiles is in ${TILES_DATA}."
echo "Enable the 'tileserver' service in infra/docker-compose.yml and set frontend VITE_MAP_STYLE_URL to its style.json."

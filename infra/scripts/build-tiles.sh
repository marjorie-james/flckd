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
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTRACT="${ROOT}/data/extract.osm.pbf"
TILES_DATA="${ROOT}/tiles/data"
# Pinned by digest for reproducible tile builds; override with PLANETILER_IMAGE.
PLANETILER_IMAGE="${PLANETILER_IMAGE:-ghcr.io/onthegomap/planetiler:latest@sha256:61eebbcf6a37339eaf6be9b8ca5b5b54e0cf8db47e6cdd5d718b7754b78cd5e5}"

[ -f "${EXTRACT}" ] || { echo "error: ${EXTRACT} not found — run fetch-extract.sh first" >&2; exit 1; }
mkdir -p "${TILES_DATA}"
cp -f "${EXTRACT}" "${TILES_DATA}/extract.osm.pbf"

echo "Building PMTiles from the extract…"
docker run --rm -v "${TILES_DATA}:/data" "${PLANETILER_IMAGE}" \
  --osm-path=/data/extract.osm.pbf \
  --output=/data/tiles.pmtiles \
  --download \
  --download-dir=/data/sources \
  --tmpdir=/data/tmp \
  --force

echo "Done. tiles.pmtiles is in ${TILES_DATA}."
echo "Enable the 'tileserver' service in infra/docker-compose.yml and set frontend VITE_MAP_STYLE_URL to its style.json."

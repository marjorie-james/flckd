#!/usr/bin/env bash
#
# Build the camera GeoJSON for the PBF-derived ALPR substrate (ADR 0002).
#
# Filters ALPR/surveillance camera nodes out of the OSM PBF extract the geo
# stack already downloads, and exports them as a GeoJSON FeatureCollection that
# CameraData::Sources::OsmExtractFile imports into the `cameras` table. This is
# the DEFAULT camera source; the live Overpass API remains as an escape hatch
# (CAMERA_OSM_SOURCE=overpass — see docs/runbooks/geo-stack.md).
#
# CADENCE: run this DAILY (independent of the monthly heavy geo build). It's
# cheap — a tag-filter + export over an extract that's already on disk, or a
# fresh small re-download. Camera data then lags OSM by <=~24h, well inside the
# 3-missed-refresh staleness window (FR-008/009).
#
# Anonymity note: operates on PUBLIC OSM data only — no user data involved.
#
# Dependency: osmium-tool (https://osmcode.org/osmium-tool/). Uses the host
# binary when present (CI installs it: apt-get install -y osmium-tool); otherwise
# falls back to a small pinned image built from infra/osmium/Dockerfile, so dev
# machines need no host install. Force one path with OSMIUM_MODE=host|docker.
#
# Usage:
#   infra/scripts/build-cameras.sh                       # uses infra/data/extract.osm.pbf
#   EXTRACT_PATH=/path/to/region.osm.pbf OUT=/path/cameras.geojson \
#     infra/scripts/build-cameras.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$(dirname "$0")/.." && pwd)/data}"
EXTRACT_PATH="${EXTRACT_PATH:-${DATA_DIR}/extract.osm.pbf}"
OUT="${OUT:-${DATA_DIR}/cameras.geojson}"
TMP_PBF="${DATA_DIR}/surveillance.osm.pbf"
OSMIUM_IMAGE="${OSMIUM_IMAGE:-flckd-osmium:bookworm}"

# Run osmium from the host binary when available, else from the pinned image.
# The image bind-mounts the repo at its real path so the absolute EXTRACT_PATH/
# OUT/TMP_PBF arguments resolve identically inside the container (they all live
# under the repo). Paths outside the repo require host osmium (OSMIUM_MODE=host).
osmium_run() {
  if [ "${OSMIUM_MODE:-auto}" != "docker" ] && command -v osmium >/dev/null 2>&1; then
    osmium "$@"
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: need osmium-tool or docker to build the camera extract." >&2
    exit 1
  fi
  if ! docker image inspect "${OSMIUM_IMAGE}" >/dev/null 2>&1; then
    echo "Building ${OSMIUM_IMAGE} (one-time)…" >&2
    docker build -q -t "${OSMIUM_IMAGE}" "${REPO_ROOT}/infra/osmium" >&2
  fi
  docker run --rm -v "${REPO_ROOT}:${REPO_ROOT}" -w "${PWD}" "${OSMIUM_IMAGE}" osmium "$@"
}

if [ ! -f "${EXTRACT_PATH}" ]; then
  echo "error: OSM extract not found at ${EXTRACT_PATH}" >&2
  echo "       run infra/scripts/fetch-extract.sh first." >&2
  exit 1
fi

echo "Filtering surveillance nodes out of ${EXTRACT_PATH}"
# Coarse filter to the man_made=surveillance superset (small); the exact
# ALPR/Flock narrowing matches the Overpass QL and is applied at import time in
# OsmExtractFile, so the two mechanisms stay in lockstep.
osmium_run tags-filter --overwrite -o "${TMP_PBF}" "${EXTRACT_PATH}" n/man_made=surveillance

echo "Exporting GeoJSON → ${OUT}"
# --add-unique-id=type_id writes each feature's OSM id as "n<nodeid>", which
# OsmExtractFile turns back into the canonical osm:node/<id> external_ref.
osmium_run export --overwrite -f geojson --add-unique-id=type_id -o "${OUT}" "${TMP_PBF}"

rm -f "${TMP_PBF}"
echo "Done. $(grep -c '"Feature"' "${OUT}" 2>/dev/null || echo '?') candidate features in ${OUT}"
echo "Deliver this file to the app host at CAMERA_OSM_GEOJSON_PATH (default storage/cameras.geojson)."

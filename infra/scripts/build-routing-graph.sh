#!/usr/bin/env bash
#
# Build the Valhalla routing graph (tiles) from the OSM extract. Valhalla is the
# routing engine because it supports excluding individual road segments
# (exclude_polygons / costing), which is exactly how camera avoidance works:
# exclude the specific monitored segment, not a radius (Constitution Principle:
# segment-exclusion, not radius).
#
# Runs Valhalla's tools in a container so no host toolchain is needed. Output
# goes to infra/routing/data and is mounted by the `routing` compose service.
#
# Usage: infra/scripts/build-routing-graph.sh
#
# Parallelism: GEO_BUILD_JOBS caps the Valhalla build concurrency (mjolnir). Unset
# → Valhalla uses all cores (its default). Set it to share cores when this runs
# concurrently with the tile build / Nominatim import on the same box.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTRACT="${ROOT}/data/extract.osm.pbf"
ROUTING_DATA="${ROOT}/routing/data"
# Pinned by digest for reproducible graph builds; override with VALHALLA_IMAGE.
IMAGE="${VALHALLA_IMAGE:-ghcr.io/valhalla/valhalla:latest@sha256:a18ece289efc24a08818f2de9d07d49d0454b83aa574352ff1832e31b104d8a6}"

[ -f "${EXTRACT}" ] || { echo "error: ${EXTRACT} not found — run fetch-extract.sh first" >&2; exit 1; }
mkdir -p "${ROUTING_DATA}"
cp -f "${EXTRACT}" "${ROUTING_DATA}/extract.osm.pbf"

# Cap concurrency only when GEO_BUILD_JOBS is set; otherwise let Valhalla default
# to all cores. Passed into the container so the inner build config honors it.
CONCURRENCY_FLAG=""
if [ -n "${GEO_BUILD_JOBS:-}" ]; then
  CONCURRENCY_FLAG="--mjolnir-concurrency ${GEO_BUILD_JOBS}"
fi

echo "Building Valhalla graph in ${ROUTING_DATA} (this can take a while)…"
docker run --rm -e CONCURRENCY_FLAG="${CONCURRENCY_FLAG}" \
  -v "${ROUTING_DATA}:/data" -w /data "${IMAGE}" bash -lc '
  set -e
  # shellcheck disable=SC2086
  valhalla_build_config --mjolnir-tile-dir /data/valhalla_tiles \
    --mjolnir-tile-extract /data/valhalla_tiles.tar ${CONCURRENCY_FLAG} > /data/valhalla.json
  valhalla_build_tiles -c /data/valhalla.json /data/extract.osm.pbf
  find /data/valhalla_tiles | sort -n | valhalla_build_extract -c /data/valhalla.json -v --overwrite
'

echo "Done. The routing service will serve from ${ROUTING_DATA}."
echo "Enable the 'routing' service in infra/docker-compose.yml and: docker compose -f infra/docker-compose.yml up -d routing"

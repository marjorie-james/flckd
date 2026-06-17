#!/usr/bin/env bash
#
# Provision the self-hosted geo substrate (routing graph + vector tiles + geocoder
# OSM import) directly ON a Kamal accessory host, in place, and reboot each
# accessory so it picks the data up. This is the production analogue of the dev
# build-geo.sh: same artifacts, but built on the (amd64) host into the dirs that
# back the Kamal `directories:` mounts instead of into infra/*/data on a dev box.
#
# Why build on the host (not locally + scp, as deploy-geo.yml does)?
#   The valhalla / planetiler images are amd64; on an arm64 dev machine they run
#   under emulation (slow), and the built artifacts (hundreds of MB) would then
#   have to be copied up. On a co-located single box the host is amd64 and already
#   has the data dirs — so we build natively, in place, with no transfer.
#
# IDEMPOTENT: each accessory is skipped when its artifact is already present, so
# this is safe to run on every deploy (it no-ops once the substrate exists). It is
# wired into .kamal/hooks/post-deploy so a fresh `kamal setup` provisions geo data
# automatically; set GEO_PROVISION=skip to bypass it.
#
# Anonymity note: builds from PUBLIC OSM data only (Geofabrik extract); nothing
# user-related is involved and everything stays on our own host (FR-012a).
#
# Usage:
#   infra/scripts/provision-geo-host.sh [user@host]
#     - host defaults to the routing accessory host parsed from backend/config/deploy.yml
#     - REGION_URL / COUNTRY come from infra/.region (override REGION_URL to test a smaller area)
#     - FORCE=1 rebuilds even when artifacts already exist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"               # -> infra/
REPO="$(cd "${ROOT}/.." && pwd)"
DEPLOY_YML="${DEPLOY_YML:-${REPO}/backend/config/deploy.yml}"
# shellcheck source=infra/scripts/lib-deploy-host.sh
. "${ROOT}/scripts/lib-deploy-host.sh"

# Build images — pinned to match the dev build scripts / deploy.yml exactly so the
# host graph/tiles are byte-for-byte what dev produces (no prod/dev engine drift).
VALHALLA_IMAGE="${VALHALLA_IMAGE:-ghcr.io/valhalla/valhalla:latest@sha256:a18ece289efc24a08818f2de9d07d49d0454b83aa574352ff1832e31b104d8a6}"
PLANETILER_IMAGE="${PLANETILER_IMAGE:-ghcr.io/onthegomap/planetiler:latest@sha256:61eebbcf6a37339eaf6be9b8ca5b5b54e0cf8db47e6cdd5d718b7754b78cd5e5}"

# ── Region (what to build) — the DEPLOY scope, decoupled from local dev ──────────
# The deploy scope is INDEPENDENT of infra/.region (your local docker-compose dev
# scope), so you can develop against one state and deploy a different state or the
# whole US. Precedence:
#   1. explicit env: GEO_REGION_URL (a single Geofabrik extract) or GEO_COUNTRY (a
#      whole-country build via the registry) — set per-invocation to choose at deploy time
#   2. the deploy-scope file backend/.kamal/geo.env (gitignored; persistent choice)
#   3. infra/.region (local dev scope) — fallback only, so existing setups still work
#   4. the country registry default (whole US)
GEO_ENV="${GEO_ENV:-${REPO}/backend/.kamal/geo.env}"
# shellcheck source=/dev/null
[ -f "${GEO_ENV}" ] && source "${GEO_ENV}"
# Only fall back to the local dev scope when the deploy scope picked neither.
if [ -z "${GEO_REGION_URL:-}" ] && [ -z "${GEO_COUNTRY:-}" ]; then
  REGION_CONFIG="${REGION_CONFIG:-${ROOT}/.region}"
  # shellcheck source=/dev/null
  [ -f "${REGION_CONFIG}" ] && source "${REGION_CONFIG}"
fi
. "${ROOT}/scripts/country-registry.sh"
country_resolve "${GEO_COUNTRY:-${COUNTRY:-us}}" || exit 1
REGION_URL="${GEO_REGION_URL:-${REGION_URL:-${COUNTRY_EXTRACT_URL}}}"
REGION_LABEL="${GEO_REGION_LABEL:-${REGION_LABEL:-${COUNTRY_NAME}}}"

# Test seam: print the resolved deploy scope and exit BEFORE any host/SSH work, so
# test/infra/deploy-scope-cross-check.bats can assert this build scope agrees with
# what deploy-scope-env.sh frames (guards against the two resolvers drifting).
if [ "${PROVISION_GEO_SELFTEST:-0}" = "1" ]; then
  echo "REGION_URL=${REGION_URL}"
  echo "REGION_LABEL=${REGION_LABEL}"
  exit 0
fi

# ── Target host (resolved by infra/scripts/lib-deploy-host.sh) ───────────────
resolve_target_host "${1:-${GEO_HOST:-}}"

echo "==> Provisioning geo substrate for ${REGION_LABEL} on ${TARGET_HOST}"
echo "    extract: ${REGION_URL}"

# True iff the named accessory container exists on the host.
accessory_exists() {  # <container>
  sshx "docker inspect $1 >/dev/null 2>&1"
}

# Resolve the on-host dir backing an accessory's container path via docker inspect
# (robust to wherever Kamal placed the bind source). Echoes the host path.
accessory_dir() {  # <container> <container-path>
  sshx "docker inspect $1 --format '{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Source}}{{end}}{{end}}'" 2>/dev/null
}

# Resolve an accessory's host data dir, distinguishing two cases that the old
# `accessory_dir ... || true` collapsed into a silent skip:
#   - container ABSENT  → echo nothing (legitimate skip; the per-step `[ -n … ]`
#     guards no-op the missing accessory, e.g. a partial setup)
#   - container PRESENT but the data mount can't be resolved → LOUD failure
#     (exit 1). Otherwise a present-but-unmounted accessory would resolve to an
#     empty dir, every step would skip, and the script would print success and
#     exit 0 with the geo substrate never built — an invisible failure.
resolve_accessory_dir() {  # <container> <container-path>
  if ! accessory_exists "$1"; then
    return 0  # absent → graceful skip
  fi
  local dir
  dir="$(accessory_dir "$1" "$2" || true)"
  if [ -z "${dir}" ]; then
    echo "error: accessory ${1} exists but its data mount (${2}) could not be resolved." >&2
    echo "  The container is up but the expected bind mount is missing — refusing to" >&2
    echo "  report a false success. Check the accessory's Kamal directories: mapping." >&2
    exit 1
  fi
  printf '%s' "${dir}"
}

ROUTING_DIR="$(resolve_accessory_dir flckd-backend-routing /data)"
TILES_DIR="$(resolve_accessory_dir flckd-backend-tiles /data)"
GEOCODER_DIR="$(resolve_accessory_dir flckd-backend-geocoder /nominatim/import)"
echo "    routing  data dir: ${ROUTING_DIR:-<accessory not found>}"
echo "    tiles    data dir: ${TILES_DIR:-<accessory not found>}"
echo "    geocoder import  : ${GEOCODER_DIR:-<accessory not found>}"

# Shared build scratch on the host; the extract is downloaded once and reused by
# all three accessories. MUST be an absolute path: docker `-v <src>:/dst` treats a
# relative/bare src as a NAMED VOLUME (empty), not a host bind mount, so resolve
# the deploy user's $HOME on the host and anchor the dir there.
resolve_remote_home
BUILD_DIR="${GEO_BUILD_DIR:-${HOST_HOME%/}/geo-build}"

# ── 0. Get the OSM extract onto the host (cached) ─────────────────────────────
# Download on THIS machine (the one running kamal — it has general internet) and
# stream the file to the host. Geofabrik commonly throttles datacenter IPs to a
# hang, so we do not rely on the host reaching it directly. Cached on the host
# between runs; FORCE=1 re-fetches.
echo "==> [0/4] Ensure OSM extract on host (${BUILD_DIR}/extract.osm.pbf)"
sshx "mkdir -p '${BUILD_DIR}'"
# Mirror fetch-extract.sh: a sibling URL marker records which region the cached
# extract is for, so a deploy-scope change (different REGION_URL) forces a fresh
# download instead of silently reusing the previous region's extract. The cache
# hit requires BOTH the extract present AND the stored URL matching REGION_URL.
EXTRACT_MARKER="${BUILD_DIR}/extract.osm.pbf.url"
if [ "${FORCE:-0}" != "1" ] \
   && sshx "test -s '${BUILD_DIR}/extract.osm.pbf'" \
   && sshx "test -f '${EXTRACT_MARKER}' && [ \"\$(cat '${EXTRACT_MARKER}')\" = '${REGION_URL}' ]"; then
  echo "    extract already on host for this region — skipping download"
else
  echo "    downloading locally: ${REGION_URL}"
  LOCAL_EXTRACT="$(mktemp "${TMPDIR:-/tmp}/flckd-extract.XXXXXX")"
  trap 'rm -f "${LOCAL_EXTRACT}"' EXIT
  # Geofabrik's download proxy intermittently 502/503s; retry generously on all
  # transient errors so a brief hiccup doesn't abort the whole provisioning.
  curl -fSL --retry 6 --retry-delay 5 --retry-all-errors -o "${LOCAL_EXTRACT}" "${REGION_URL}"
  echo "    streaming $(du -h "${LOCAL_EXTRACT}" | cut -f1) to ${TARGET_HOST}…"
  scp "${SSH_OPTS[@]}" "${LOCAL_EXTRACT}" "${TARGET_HOST}:${BUILD_DIR}/extract.osm.pbf"
  rm -f "${LOCAL_EXTRACT}"
  trap - EXIT
  # Record the region marker only after the extract is in place, so an aborted
  # transfer never leaves a marker that would mask a missing/partial extract.
  sshx "printf '%s\n' '${REGION_URL}' > '${EXTRACT_MARKER}'"
  echo "    extract in place on host."
fi

# The accessory data dirs are owned by container-root (the accessories write there
# as root), so we never cp into them from the host. Instead each build container
# mounts the (deploy-owned) build dir read-only at /src for the extract and writes
# its output into the accessory dir at /data as root.

# ── 1. Routing graph (Valhalla) ──────────────────────────────────────────────
# build-routing-graph.sh, run on the host straight into the routing data dir.
# Gate on a completion MARKER written only after the build AND the accessory
# restart succeed, not on the mere presence of valhalla_tiles.tar — a build killed
# mid-write leaves a non-empty-but-truncated tar that `test -s` would wrongly
# accept, and writing the marker last lets a failed restart self-heal on re-run.
# The marker lives in the (deploy-owned) data dir; valhalla_service ignores it.
echo "==> [1/4] Routing graph (Valhalla)"
# The completion marker also encodes the region (REGION_URL) so a deploy-scope
# change rebuilds rather than serving the previous region's graph: rebuild when
# the marker is absent OR its stored URL differs from the resolved REGION_URL.
if [ -n "${ROUTING_DIR}" ] && { [ "${FORCE:-0}" = "1" ] || ! sshx "test -f '${ROUTING_DIR}/.graph-complete' && [ \"\$(cat '${ROUTING_DIR}/.graph-complete')\" = '${REGION_URL}' ]"; }; then
  echo "    stopping routing accessory, building graph, restarting…"
  sshx "set -e; \
    rm -f '${ROUTING_DIR}/.graph-complete'; \
    docker stop flckd-backend-routing >/dev/null 2>&1 || true; \
    docker run --rm -v '${ROUTING_DIR}:/data' -v '${BUILD_DIR}:/src:ro' -w /data ${VALHALLA_IMAGE} bash -lc ' \
      set -e; \
      valhalla_build_config --mjolnir-tile-dir /data/valhalla_tiles --mjolnir-tile-extract /data/valhalla_tiles.tar > /data/valhalla.json; \
      valhalla_build_tiles -c /data/valhalla.json /src/extract.osm.pbf; \
      find /data/valhalla_tiles | sort -n | valhalla_build_extract -c /data/valhalla.json -v --overwrite; \
      rm -rf /data/valhalla_tiles'; \
    docker start flckd-backend-routing >/dev/null; \
    printf '%s\n' '${REGION_URL}' > '${ROUTING_DIR}/.graph-complete'"
  echo "    routing graph built."
else
  echo "    routing graph already built for this region (completion marker matches) — skipping (FORCE=1 to rebuild)."
fi

# ── 2. Vector tiles (Planetiler → PMTiles) ───────────────────────────────────
# Scratch (downloads + tmp) goes under /src (the build dir), so the accessory dir
# only ever receives the finished tiles.pmtiles.
echo "==> [2/4] Vector tiles (Planetiler → PMTiles)"
# Same completion-marker gate as routing: a half-written tiles.pmtiles from an
# interrupted Planetiler run would pass `test -s` but be unusable. The marker also
# encodes REGION_URL so a deploy-scope change rebuilds the tiles for the new region.
if [ -n "${TILES_DIR}" ] && { [ "${FORCE:-0}" = "1" ] || ! sshx "test -f '${TILES_DIR}/.tiles-complete' && [ \"\$(cat '${TILES_DIR}/.tiles-complete')\" = '${REGION_URL}' ]"; }; then
  echo "    building tiles.pmtiles…"
  sshx "set -e; \
    rm -f '${TILES_DIR}/.tiles-complete'; \
    docker run --rm -v '${TILES_DIR}:/data' -v '${BUILD_DIR}:/src' ${PLANETILER_IMAGE} \
      --osm-path=/src/extract.osm.pbf --output=/data/tiles.pmtiles \
      --download --download-dir=/src/sources --tmpdir=/src/tmp --force; \
    docker run --rm -v '${BUILD_DIR}:/src' --entrypoint sh ${PLANETILER_IMAGE} -c 'rm -rf /src/tmp /src/sources' || true; \
    docker restart flckd-backend-tiles >/dev/null; \
    printf '%s\n' '${REGION_URL}' > '${TILES_DIR}/.tiles-complete'"
  echo "    tiles built."
else
  echo "    tiles already built for this region (completion marker matches) — skipping (FORCE=1 to rebuild)."
fi

# ── 3. Geocoder OSM import (Nominatim imports on boot) ────────────────────────
# Nominatim imports PBF_PATH on first boot when its DB is empty. Place the extract
# (via a root helper, since the import dir is root-owned) and reboot; the import
# then runs in the background (~minutes for a state). We do NOT block on it here —
# the container stays up and status.php reports not-ready until the import
# finishes. TIGER house numbers + Wikipedia importance are a follow-on
# (build-geocoder.sh) once the import is healthy.
echo "==> [3/4] Geocoder OSM import (Nominatim)"
# The import runs asynchronously on container boot; status.php reports ready only
# once it has finished. Gate on READINESS, not just the extract's presence, so a
# completed import is correctly skipped — and so a failed import isn't masked by
# the extract still sitting on disk. We deliberately do NOT restart an import
# that's merely still in progress (that would interrupt it); a genuinely stuck
# import is recovered with FORCE=1. status.php is the geocoder's own host port
# (deploy.yml geocoder: 127.0.0.1:8081).
_geocoder_ready() { sshx "curl -sf --max-time 5 http://127.0.0.1:8081/status.php >/dev/null 2>&1"; }
if [ -z "${GEOCODER_DIR}" ]; then
  echo "    geocoder accessory not found — skipping."
elif [ "${FORCE:-0}" != "1" ] && _geocoder_ready; then
  echo "    geocoder already imported (status.php ready) — skipping."
elif [ "${FORCE:-0}" != "1" ] && sshx "test -s '${GEOCODER_DIR}/extract.osm.pbf'"; then
  echo "    extract placed but status.php not ready — import is in progress or needs"
  echo "    attention; not restarting (would interrupt an in-flight import)."
  echo "    Watch: docker logs -f flckd-backend-geocoder ; FORCE=1 to rebuild."
else
  echo "    placing extract + rebooting geocoder (import runs in the background)…"
  sshx "set -e; \
    docker run --rm -v '${BUILD_DIR}:/src:ro' -v '${GEOCODER_DIR}:/dst' ${VALHALLA_IMAGE} \
      cp -f /src/extract.osm.pbf /dst/extract.osm.pbf; \
    docker restart flckd-backend-geocoder >/dev/null"
  echo "    geocoder import kicked off (watch: docker logs -f flckd-backend-geocoder)."
fi

# ── 4. Camera dataset (PBF-derived ALPR substrate → cameras table) ────────────
# The local dev setup.sh builds the camera GeoJSON (infra/scripts/build-cameras.sh)
# and imports it; production setup must do the same, or the cameras table stays
# empty and the map shows no cameras / clustering bubbles. We reuse the extract
# step [0] already put on the host: filter man_made=surveillance nodes into a
# GeoJSON with osmium (run from our own pinned image, built on the host from
# infra/osmium/Dockerfile over stdin — no third-party image, FR-012a), publish it
# into the PERSISTENT `flckd-cameras` named volume (mounted into the app roles at
# CAMERA_OSM_GEOJSON_PATH via deploy.yml `volumes:`), and run camera_data:import
# SOURCE=pbf — which imports the nodes and snaps each to its monitored road segment
# via Valhalla (already up). The volume survives deploys, so the daily DataRefreshJob
# (job container) keeps re-reading it instead of finding the file gone with the
# replaced container. The import is idempotent (add/update). Skip with CAMERAS=skip.
echo "==> [4/4] Camera dataset (PBF-derived surveillance nodes → import)"
# Resolve the live web container (the one running the app image; never a
# *_replaced_* drain container from an in-flight deploy).
WEB_CONTAINER="$(sshx "docker ps --format '{{.Names}}' | grep '^flckd-backend-web-' | grep -v '_replaced_' | head -1" || true)"
if [ "${CAMERAS:-}" = "skip" ]; then
  echo "    CAMERAS=skip — leaving the cameras table as-is."
elif [ -z "${WEB_CONTAINER}" ]; then
  echo "    web container not found — skipping camera import (run app setup first,"
  echo "    then re-run infra/scripts/provision-geo-host.sh)."
else
  echo "    building osmium image on host + filtering surveillance nodes…"
  # Build our osmium image on the host from the Dockerfile over stdin (no context).
  sshx "docker build -q -t flckd-osmium:bookworm -" < "${REPO}/infra/osmium/Dockerfile" >/dev/null
  # Coarse man_made=surveillance filter → GeoJSON in the (deploy-owned) build dir,
  # so the host can read the feature count directly. The exact ALPR narrowing
  # happens at import time in OsmExtractFile, matching the Overpass path.
  sshx "set -e; \
    docker run --rm -v '${BUILD_DIR}:/src' flckd-osmium:bookworm sh -c ' \
      osmium tags-filter --overwrite -o /src/surveillance.osm.pbf /src/extract.osm.pbf n/man_made=surveillance && \
      osmium export --overwrite -f geojson --add-unique-id=type_id -o /src/cameras.geojson /src/surveillance.osm.pbf && \
      rm -f /src/surveillance.osm.pbf'"
  CAM_FEATURES="$(sshx "grep -c '\"Feature\"' '${BUILD_DIR}/cameras.geojson' 2>/dev/null || echo 0")"
  echo "    ${CAM_FEATURES} surveillance features in cameras.geojson"
  # Fail closed on an implausibly empty export (a wrong/partial extract): importing
  # zero would, on the daily refresh cadence, eventually auto-retire the whole set
  # (FR-008/009). Override for a genuinely camera-free region with ALLOW_EMPTY=1.
  if [ "${CAM_FEATURES:-0}" -lt "${MIN_CAMERA_FEATURES:-1}" ] && [ "${ALLOW_EMPTY:-0}" != "1" ]; then
    echo "    error: ${CAM_FEATURES} features (< ${MIN_CAMERA_FEATURES:-1}) — refusing to import an" >&2
    echo "    empty camera set. Check the extract; set ALLOW_EMPTY=1 to override." >&2
    exit 1
  fi
  # Publish into the persistent named volume the app roles mount (via a writer
  # container — the volume is root-owned; the app mounts it read-only). Then import
  # in the web container, which reads it at CAMERA_OSM_GEOJSON_PATH and snaps via
  # Valhalla. The volume (not the replaced container) is what survives deploys.
  echo "    publishing cameras.geojson → flckd-cameras volume + importing into ${WEB_CONTAINER}…"
  sshx "set -e; \
    docker run --rm -v '${BUILD_DIR}:/src:ro' -v flckd-cameras:/dst flckd-osmium:bookworm \
      cp /src/cameras.geojson /dst/cameras.geojson; \
    docker exec -e SOURCE=pbf '${WEB_CONTAINER}' bin/rails camera_data:import"
  echo "    camera import complete."
fi

echo "==> Geo provisioning done for ${REGION_LABEL} on ${TARGET_HOST}."
echo "    routing + tiles are live; the geocoder import completes in the background."

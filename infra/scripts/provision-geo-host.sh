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

# ── Target host ──────────────────────────────────────────────────────────────
# Default to the routing accessory's host from deploy.yml (single-box deploys use
# the same host for every accessory).
GEO_HOST="${1:-${GEO_HOST:-}}"
if [ -z "${GEO_HOST}" ]; then
  GEO_HOST="$(awk '/^[[:space:]]*routing:/{f=1} f&&/host:/{print $2; exit}' "${DEPLOY_YML}")"
fi
[ -n "${GEO_HOST}" ] || { echo "provision-geo-host: could not determine GEO_HOST (pass user@host or set in deploy.yml)" >&2; exit 1; }

# deploy.yml host values are bare addresses; the SSH user comes from `ssh.user:`
# (Kamal applies it for us, but our own ssh calls must add it). Prepend it when the
# resolved host carries no explicit `user@`. Override with SSH_USER.
if [ "${GEO_HOST}" = "${GEO_HOST#*@}" ]; then
  SSH_USER="${SSH_USER:-$(awk '/^ssh:/{f=1} f&&/user:/{print $2; exit}' "${DEPLOY_YML}")}"
  GEO_HOST="${SSH_USER:-deploy}@${GEO_HOST}"
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes)
sshx() { ssh "${SSH_OPTS[@]}" "${GEO_HOST}" "$@"; }

echo "==> Provisioning geo substrate for ${REGION_LABEL} on ${GEO_HOST}"
echo "    extract: ${REGION_URL}"

# Resolve the on-host dir backing an accessory's container path via docker inspect
# (robust to wherever Kamal placed the bind source). Echoes the host path.
accessory_dir() {  # <container> <container-path>
  sshx "docker inspect $1 --format '{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Source}}{{end}}{{end}}'" 2>/dev/null
}

ROUTING_DIR="$(accessory_dir flckd-backend-routing /data)"
TILES_DIR="$(accessory_dir flckd-backend-tiles /data)"
GEOCODER_DIR="$(accessory_dir flckd-backend-geocoder /nominatim/import)"
echo "    routing  data dir: ${ROUTING_DIR:-<accessory not found>}"
echo "    tiles    data dir: ${TILES_DIR:-<accessory not found>}"
echo "    geocoder import  : ${GEOCODER_DIR:-<accessory not found>}"

# Shared build scratch on the host; the extract is downloaded once and reused by
# all three accessories. MUST be an absolute path: docker `-v <src>:/dst` treats a
# relative/bare src as a NAMED VOLUME (empty), not a host bind mount, so resolve
# the deploy user's $HOME on the host and anchor the dir there.
HOST_HOME="$(sshx 'echo "$HOME"')"
BUILD_DIR="${GEO_BUILD_DIR:-${HOST_HOME%/}/geo-build}"

# ── 0. Get the OSM extract onto the host (cached) ─────────────────────────────
# Download on THIS machine (the one running kamal — it has general internet) and
# stream the file to the host. Geofabrik commonly throttles datacenter IPs to a
# hang, so we do not rely on the host reaching it directly. Cached on the host
# between runs; FORCE=1 re-fetches.
echo "==> [0/3] Ensure OSM extract on host (${BUILD_DIR}/extract.osm.pbf)"
sshx "mkdir -p '${BUILD_DIR}'"
if [ "${FORCE:-0}" != "1" ] && sshx "test -s '${BUILD_DIR}/extract.osm.pbf'"; then
  echo "    extract already on host — skipping download"
else
  echo "    downloading locally: ${REGION_URL}"
  LOCAL_EXTRACT="$(mktemp "${TMPDIR:-/tmp}/flckd-extract.XXXXXX")"
  trap 'rm -f "${LOCAL_EXTRACT}"' EXIT
  # Geofabrik's download proxy intermittently 502/503s; retry generously on all
  # transient errors so a brief hiccup doesn't abort the whole provisioning.
  curl -fSL --retry 6 --retry-delay 5 --retry-all-errors -o "${LOCAL_EXTRACT}" "${REGION_URL}"
  echo "    streaming $(du -h "${LOCAL_EXTRACT}" | cut -f1) to ${GEO_HOST}…"
  scp "${SSH_OPTS[@]}" "${LOCAL_EXTRACT}" "${GEO_HOST}:${BUILD_DIR}/extract.osm.pbf"
  rm -f "${LOCAL_EXTRACT}"
  trap - EXIT
  echo "    extract in place on host."
fi

# The accessory data dirs are owned by container-root (the accessories write there
# as root), so we never cp into them from the host. Instead each build container
# mounts the (deploy-owned) build dir read-only at /src for the extract and writes
# its output into the accessory dir at /data as root.

# ── 1. Routing graph (Valhalla) ──────────────────────────────────────────────
# build-routing-graph.sh, run on the host straight into the routing data dir.
echo "==> [1/3] Routing graph (Valhalla)"
if [ -n "${ROUTING_DIR}" ] && { [ "${FORCE:-0}" = "1" ] || ! sshx "test -s '${ROUTING_DIR}/valhalla_tiles.tar'"; }; then
  echo "    stopping routing accessory, building graph, restarting…"
  sshx "set -e; \
    docker stop flckd-backend-routing >/dev/null 2>&1 || true; \
    docker run --rm -v '${ROUTING_DIR}:/data' -v '${BUILD_DIR}:/src:ro' -w /data ${VALHALLA_IMAGE} bash -lc ' \
      set -e; \
      valhalla_build_config --mjolnir-tile-dir /data/valhalla_tiles --mjolnir-tile-extract /data/valhalla_tiles.tar > /data/valhalla.json; \
      valhalla_build_tiles -c /data/valhalla.json /src/extract.osm.pbf; \
      find /data/valhalla_tiles | sort -n | valhalla_build_extract -c /data/valhalla.json -v --overwrite; \
      rm -rf /data/valhalla_tiles'; \
    docker start flckd-backend-routing >/dev/null"
  echo "    routing graph built."
else
  echo "    valhalla_tiles.tar already present — skipping (FORCE=1 to rebuild)."
fi

# ── 2. Vector tiles (Planetiler → PMTiles) ───────────────────────────────────
# Scratch (downloads + tmp) goes under /src (the build dir), so the accessory dir
# only ever receives the finished tiles.pmtiles.
echo "==> [2/3] Vector tiles (Planetiler → PMTiles)"
if [ -n "${TILES_DIR}" ] && { [ "${FORCE:-0}" = "1" ] || ! sshx "test -s '${TILES_DIR}/tiles.pmtiles'"; }; then
  echo "    building tiles.pmtiles…"
  sshx "set -e; \
    docker run --rm -v '${TILES_DIR}:/data' -v '${BUILD_DIR}:/src' ${PLANETILER_IMAGE} \
      --osm-path=/src/extract.osm.pbf --output=/data/tiles.pmtiles \
      --download --download-dir=/src/sources --tmpdir=/src/tmp --force; \
    docker restart flckd-backend-tiles >/dev/null"
  echo "    tiles built."
else
  echo "    tiles.pmtiles already present — skipping (FORCE=1 to rebuild)."
fi

# ── 3. Geocoder OSM import (Nominatim imports on boot) ────────────────────────
# Nominatim imports PBF_PATH on first boot when its DB is empty. Place the extract
# (via a root helper, since the import dir is root-owned) and reboot; the import
# then runs in the background (~minutes for a state). We do NOT block on it here —
# the container stays up and status.php reports not-ready until the import
# finishes. TIGER house numbers + Wikipedia importance are a follow-on
# (build-geocoder.sh) once the import is healthy.
echo "==> [3/3] Geocoder OSM import (Nominatim)"
if [ -n "${GEOCODER_DIR}" ] && { [ "${FORCE:-0}" = "1" ] || ! sshx "test -s '${GEOCODER_DIR}/extract.osm.pbf'"; }; then
  echo "    placing extract + rebooting geocoder (import runs in the background)…"
  sshx "set -e; \
    docker run --rm -v '${BUILD_DIR}:/src:ro' -v '${GEOCODER_DIR}:/dst' ${VALHALLA_IMAGE} \
      cp -f /src/extract.osm.pbf /dst/extract.osm.pbf; \
    docker restart flckd-backend-geocoder >/dev/null"
  echo "    geocoder import kicked off (watch: docker logs -f flckd-backend-geocoder)."
else
  echo "    extract already in place for the geocoder — skipping."
fi

echo "==> Geo provisioning done for ${REGION_LABEL} on ${GEO_HOST}."
echo "    routing + tiles are live; the geocoder import completes in the background."

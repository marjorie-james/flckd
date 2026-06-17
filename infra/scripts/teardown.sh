#!/usr/bin/env bash
#
# flckd teardown — reset the local dev environment to a fresh state.
# Run from the repo root:  ./infra/scripts/teardown.sh
#
# The local stack is Docker-only, so a full reset is two things:
#   1. Tear down the compose stack and its named volumes. Removing the volumes
#      wipes the Postgres database (pg_data) and the one-time Nominatim OSM
#      import (nominatim_data) — i.e. the database returns to a fresh state.
#   2. Delete the generated geo data on disk (rebuildable from public OSM by the
#      build scripts): the OSM extract, routing graph, vector tiles, TIGER cache,
#      build manifest, and the filtered cameras GeoJSON.
#
# After this, `infra/scripts/setup.sh` (or build-geo.sh) rebuilds everything from
# scratch. The selected region (infra/.region) is kept by default so you don't
# have to re-pick a state — pass --purge-region to drop it too.
#
# Flags:
#   -y, --yes         Don't prompt for confirmation.
#   -n, --dry-run     Print what would be removed without removing anything.
#       --keep-data   Keep the downloaded/generated geo data on disk (only tear
#                     down containers + volumes). Faster re-up, no re-download.
#       --purge-region  Also delete infra/.region and infra/.env (forces a re-pick
#                     on next setup; clears the stale geocoder scope).
#   -h, --help        Show this help.
#
set -euo pipefail

# ── ANSI colour helpers (match setup.sh) ───────────────────────────────────────
RED=$'\e[0;31m'; YELLOW=$'\e[0;33m'; GREEN=$'\e[0;32m'
CYAN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'

info()    { echo "${CYAN}  →${RESET}  $*"; }
success() { echo "${GREEN}  ✓${RESET}  $*"; }
warn()    { echo "${YELLOW}  !${RESET}  $*"; }
error()   { echo "${RED}  ✗  $*${RESET}" >&2; }
header()  { echo; echo "${BOLD}${CYAN}$*${RESET}"; echo; }
divider() { echo "${DIM}──────────────────────────────────────────${RESET}"; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# ── Parse flags ────────────────────────────────────────────────────────────────
ASSUME_YES=false
DRY_RUN=false
KEEP_DATA=false
PURGE_REGION=false
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)        ASSUME_YES=true ;;
    -n|--dry-run)    DRY_RUN=true ;;
    --keep-data)     KEEP_DATA=true ;;
    --purge-region)  PURGE_REGION=true ;;
    -h|--help)       usage 0 ;;
    *) error "Unknown option: $1"; echo; usage 1 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"
REGION_CONFIG="${SCRIPT_DIR}/../.region"
# The geocoder-scope file written by setup.sh/build-geo.sh. A stale single-state
# GEOCODER_REGION_STATE/VIEWBOX left here is interpolated by docker compose later,
# so --purge-region must drop it alongside infra/.region.
ENV_FILE="${SCRIPT_DIR}/../.env"

# Generated, rebuildable geo data on disk (all gitignored — see .gitignore).
DATA_PATHS=(
  "${REPO_ROOT}/infra/data"
  "${REPO_ROOT}/infra/routing/data"
  "${REPO_ROOT}/infra/tiles/data"
  "${REPO_ROOT}/infra/build"
  "${REPO_ROOT}/backend/storage/cameras.geojson"
)

# du -sh that tolerates a missing path (prints nothing if absent).
_size_of() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1 || true; }

# ── Plan ───────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo
echo "${BOLD}${CYAN}  flckd — teardown${RESET}"
echo "${DIM}  Reset the local dev environment to a fresh state${RESET}"
divider
echo
echo "  This will:"
echo "    ${BOLD}1.${RESET} Stop and remove the Docker compose stack ${DIM}(containers, network)${RESET}"
echo "    ${BOLD}2.${RESET} Remove its named volumes ${DIM}(Postgres DB + Nominatim import → fresh DB)${RESET}"
if [ "${KEEP_DATA}" = "true" ]; then
  echo "    ${BOLD}3.${RESET} ${DIM}Keep generated geo data on disk (--keep-data)${RESET}"
else
  echo "    ${BOLD}3.${RESET} Delete generated geo data on disk ${DIM}(rebuildable from public OSM)${RESET}"
  for p in "${DATA_PATHS[@]}"; do
    if [ -e "$p" ]; then
      sz="$(_size_of "$p")"
      printf '         %s %s%s%s\n' "${DIM}•${RESET}" "${p#"${REPO_ROOT}/"}" "${sz:+  ${DIM}(}" "${sz:+${sz})${RESET}}"
    fi
  done
fi
if [ "${PURGE_REGION}" = "true" ]; then
  echo "    ${BOLD}4.${RESET} Delete ${BOLD}infra/.region${RESET} + ${BOLD}infra/.env${RESET} ${DIM}(you'll re-pick a state next setup)${RESET}"
else
  echo "    ${BOLD}4.${RESET} ${DIM}Keep infra/.region + infra/.env (selected region/scope preserved)${RESET}"
fi
echo
divider

if [ "${DRY_RUN}" = "true" ]; then
  echo
  warn "Dry run — nothing was removed."
  echo
  exit 0
fi

# ── Confirm ────────────────────────────────────────────────────────────────────
if [ "${ASSUME_YES}" != "true" ]; then
  echo
  printf '%s' "  Tear everything down? [y/${GREEN}N${RESET}]: "
  read -r CONFIRM </dev/tty || CONFIRM=""
  if [[ ! "${CONFIRM:-n}" =~ ^[Yy] ]]; then
    echo
    warn "Aborted. Nothing was removed."
    echo
    exit 0
  fi
fi

# ── Step 1+2: compose down -v ──────────────────────────────────────────────────
header "Tearing down the Docker stack"

if ! command -v docker >/dev/null 2>&1; then
  warn "docker not found — skipping container/volume teardown."
elif ! docker info >/dev/null 2>&1; then
  warn "Docker daemon not running — skipping container/volume teardown."
  echo "    Start Docker and re-run, or remove volumes later with:"
  echo "      docker compose -f infra/docker-compose.yml down -v --remove-orphans"
else
  info "docker compose down -v --remove-orphans…"
  # -v removes the named volumes (pg_data, nominatim_data, bundle_cache,
  # frontend_node_modules); --remove-orphans cleans up any stragglers.
  if docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans; then
    success "Stack and volumes removed (database is now fresh)."
  else
    error "compose down failed (see output above)."
    exit 1
  fi
fi

# ── Step 3: remove generated geo data ──────────────────────────────────────────
if [ "${KEEP_DATA}" = "true" ]; then
  header "Keeping generated geo data (--keep-data)"
  info "Left on disk: infra/data, infra/routing/data, infra/tiles/data, infra/build, backend/storage/cameras.geojson"
else
  header "Removing generated geo data"
  removed_any=false
  for p in "${DATA_PATHS[@]}"; do
    if [ -e "$p" ]; then
      rm -rf "$p"
      success "Removed ${p#"${REPO_ROOT}/"}"
      removed_any=true
    fi
  done
  [ "${removed_any}" = "false" ] && info "No generated geo data found — already clean."
fi

# ── Step 4: optionally remove region config ────────────────────────────────────
if [ "${PURGE_REGION}" = "true" ]; then
  header "Removing region config"
  if [ -f "${REGION_CONFIG}" ]; then
    rm -f "${REGION_CONFIG}"
    success "Removed infra/.region"
  else
    info "infra/.region not present."
  fi
  if [ -f "${ENV_FILE}" ]; then
    rm -f "${ENV_FILE}"
    success "Removed infra/.env"
  else
    info "infra/.env not present."
  fi
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo
divider
echo
success "Teardown complete — local environment reset."
echo
echo "  Rebuild from scratch with the setup wizard:"
echo "    ${BOLD}infra/scripts/setup.sh${RESET}"
if [ "${KEEP_DATA}" = "true" ]; then
  echo
  echo "  ${DIM}(geo data kept — 'docker compose -f infra/docker-compose.yml up -d'"
  echo "   will reuse it; the database/geocoder will re-import on first up.)${RESET}"
fi
echo
divider
echo

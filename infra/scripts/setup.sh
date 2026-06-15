#!/usr/bin/env bash
#
# flckd setup wizard — configure the app for local development.
# Run from the repo root:  ./infra/scripts/setup.sh
#
# What it does:
#   1. Checks prerequisites (Docker).
#   2. Asks for a two-letter state code (the only user input).
#   3. Writes infra/.region (sourced by the build scripts).
#   4. Runs the full geo build and starts the app — no further input.
#
# Flags:
#   -v           Verbose: stream all build output instead of showing the progress panel.
#   --region X   Skip the prompt. X = two-letter USPS code (e.g. IA) or FIPS code (e.g. 19).
#                Also: FLCKD_REGION=X ./infra/scripts/setup.sh
#
set -euo pipefail

# ── Parse flags ────────────────────────────────────────────────────────────────
VERBOSE=false
REGION_ARG="${FLCKD_REGION:-}"
# An EXPLICIT --country flag (distinct from an inherited COUNTRY env var, which is
# only a fallback) so an explicit --region always wins over a stray COUNTRY in the
# shell.
COUNTRY_FLAG=""
COUNTRY_ENV="${COUNTRY:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=true ;;
    --region) shift; REGION_ARG="${1:-}" ;;
    --region=*) REGION_ARG="${1#--region=}" ;;
    --country) shift; COUNTRY_FLAG="${1:-}" ;;
    --country=*) COUNTRY_FLAG="${1#--country=}" ;;
  esac
  shift
done

# Default the Nominatim import to ALL of this machine's cores (the OSM import is
# the long pole). docker-compose interpolates NOMINATIM_THREADS into the geocoder
# service; without this it would fall back to a conservative 4. Override by
# exporting NOMINATIM_THREADS yourself.
export NOMINATIM_THREADS="${NOMINATIM_THREADS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

# ── ANSI colour helpers ────────────────────────────────────────────────────────
RED=$'\e[0;31m'; YELLOW=$'\e[0;33m'; GREEN=$'\e[0;32m'
CYAN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'

info()    { echo "${CYAN}  →${RESET}  $*"; }
success() { echo "${GREEN}  ✓${RESET}  $*"; }
warn()    { echo "${YELLOW}  !${RESET}  $*"; }
error()   { echo "${RED}  ✗  $*${RESET}" >&2; }
header()  { echo; echo "${BOLD}${CYAN}$*${RESET}"; echo; }
divider() { echo "${DIM}──────────────────────────────────────────${RESET}"; }

# ── ETA estimates ──────────────────────────────────────────────────────────────
# Rough per-build-step duration estimates (seconds), used for the wizard's ETA
# display. These are WILDLY hardware-dependent (CPU, disk IOPS, network) and shown
# as "~" approximations — a whole-country (US) build differs from a single state by
# ~10x, dominated by the Nominatim OSM import + TIGER. Order matches _T_NAMES below.
_expected_secs() { # $1 = scope (country|state) → 10 space-separated seconds
  if [ "$1" = "country" ]; then
    #    prereq cfg  extract routing manif  db  cams  svc   geocoder tiger
    echo "5     1    1800    3600    10    120  20    20    14400    5400"
  else
    echo "5     1    90      360     5     90   20    15    1500     240"
  fi
}

# _fmt_eta SECONDS → "H:MM:SS" (≥1h) or "M:SS". Used for elapsed + remaining.
_fmt_eta() {
  local s="${1:-0}"
  if [ "$s" -ge 3600 ]; then
    printf '%d:%02d:%02d' "$((s/3600))" "$(((s%3600)/60))" "$((s%60))"
  else
    printf '%d:%02d' "$((s/60))" "$((s%60))"
  fi
}

# _est_remaining OVERLAP_ELAPSED → estimated remaining seconds. Reads the panel
# state (_T_STATES, _T_EXPECT, _CUR_ELAPSED). Done/failed steps contribute 0; the
# running step contributes its estimate minus its elapsed; pending steps their
# full estimate. The geocoder OSM import (step 8) starts EARLY (overlap) and runs
# during the routing/tiles/DB steps, so while it is still pending its estimate is
# credited by OVERLAP_ELAPSED — keeping the total ETA from reading pessimistically.
_est_remaining() {
  local overlap="${1:-0}" rem=0 j e d
  for j in 0 1 2 3 4 5 6 7 8 9; do
    case "${_T_STATES[$j]:-pending}" in
      done|failed) ;;
      running)
        d=$(( ${_T_EXPECT[$j]:-0} - ${_CUR_ELAPSED:-0} ))
        [ "$d" -gt 0 ] && rem=$(( rem + d ))
        ;;
      *)
        e=${_T_EXPECT[$j]:-0}
        if [ "$j" = "8" ]; then e=$(( e - overlap )); [ "$e" -lt 0 ] && e=0; fi
        rem=$(( rem + e ))
        ;;
    esac
  done
  echo "$rem"
}

# ── Panel geometry (shared by picker and build panels) ─────────────────────────
# Inner content between │ and │ = 46 visible chars → total line = 50 chars
_SEP=$(printf '─%.0s' {1..46})

# Restore cursor on any exit (Ctrl-C, error, or clean finish)
trap 'tput cnorm 2>/dev/null || true' EXIT

# ── State code resolution ──────────────────────────────────────────────────────
# _resolve_code CODE: match a state by its two-letter USPS abbreviation (e.g. IA)
# or two-digit FIPS code (e.g. 19), case-insensitive. On a match, sets the global
# SELECTED_IDX (0-based index into STATES) and returns 0. Returns 1 on no match.
_resolve_code() {
  local q; q=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
  local i entry fips usps
  for i in "${!STATES[@]}"; do
    # Format: "Display Label|geofabrik-slug|state-fips|usps-code|viewbox"
    entry="${STATES[$i]}"
    IFS='|' read -r _ _ fips usps _ <<< "${entry}"
    if [ "$q" = "$usps" ] || [ "$q" = "$fips" ]; then
      SELECTED_IDX="$i"; return 0
    fi
  done
  return 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION_CONFIG="${REGION_CONFIG:-${SCRIPT_DIR}/../.region}"

# Country registry (bash mirror of Geocoding::CountryRegistry) for the default
# whole-country path.
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/country-registry.sh"

# ── Welcome ────────────────────────────────────────────────────────────────────
{ [ "${SETUP_DRY_RUN:-0}" = "1" ] || [ "${SETUP_SELFTEST:-0}" = "1" ]; } || clear
echo
echo "${BOLD}${CYAN}  flckd — setup wizard${RESET}"
echo "${DIM}  Anonymous, camera-avoiding route planner${RESET}"
divider

# ── Deployment scope ───────────────────────────────────────────────────────────
# By DEFAULT the deployment covers a whole country, defaulting to the United
# States — no input required (FR-002). `--region <state>` (or FLCKD_REGION) is an
# explicit DEV override that builds a single state's cheaper sub-region stack.

# Format: "Display Label|geofabrik-slug|state-fips|usps-code|viewbox"
# FIPS codes are the 2-digit US Census state identifiers used by TIGER/Line
# data downloads. USPS codes are the two-letter postal abbreviations.
# viewbox is the state's bounding box in Nominatim order — min_lng,max_lat,
# max_lng,min_lat (left,top,right,bottom) — used as GEOCODER_VIEWBOX (bounded
# geocoder search) AND the initial map framing for a single-state dev build.
STATES=(
  "Alabama|alabama|01|AL|-88.5,35.0,-84.9,30.2"
  "Alaska|alaska|02|AK|-170.0,71.5,-129.9,51.2"
  "Arizona|arizona|04|AZ|-114.8,37.0,-109.0,31.3"
  "Arkansas|arkansas|05|AR|-94.6,36.5,-89.6,33.0"
  "California|california|06|CA|-124.4,42.0,-114.1,32.5"
  "Colorado|colorado|08|CO|-109.06,41.0,-102.04,36.99"
  "Connecticut|connecticut|09|CT|-73.7,42.05,-71.8,40.98"
  "Delaware|delaware|10|DE|-75.8,39.84,-75.0,38.45"
  "District of Columbia|district-of-columbia|11|DC|-77.12,39.0,-76.91,38.79"
  "Florida|florida|12|FL|-87.6,31.0,-80.0,24.5"
  "Georgia|georgia|13|GA|-85.6,35.0,-80.8,30.4"
  "Hawaii|hawaii|15|HI|-160.3,22.3,-154.8,18.9"
  "Idaho|idaho|16|ID|-117.24,49.0,-111.04,42.0"
  "Illinois|illinois|17|IL|-91.5,42.5,-87.0,36.97"
  "Indiana|indiana|18|IN|-88.1,41.76,-84.8,37.77"
  "Iowa|iowa|19|IA|-96.7,43.6,-90.0,40.3"
  "Kansas|kansas|20|KS|-102.05,40.0,-94.6,36.99"
  "Kentucky|kentucky|21|KY|-89.6,39.15,-81.9,36.5"
  "Louisiana|louisiana|22|LA|-94.04,33.0,-88.8,28.9"
  "Maine|maine|23|ME|-71.1,47.5,-66.9,43.0"
  "Maryland|maryland|24|MD|-79.5,39.7,-75.0,37.9"
  "Massachusetts|massachusetts|25|MA|-73.5,42.9,-69.9,41.2"
  "Michigan|michigan|26|MI|-90.4,48.3,-82.4,41.7"
  "Minnesota|minnesota|27|MN|-97.24,49.4,-89.5,43.5"
  "Mississippi|mississippi|28|MS|-91.7,35.0,-88.1,30.2"
  "Missouri|missouri|29|MO|-95.8,40.6,-89.1,36.0"
  "Montana|montana|30|MT|-116.05,49.0,-104.04,44.36"
  "Nebraska|nebraska|31|NE|-104.05,43.0,-95.3,40.0"
  "Nevada|nevada|32|NV|-120.0,42.0,-114.04,35.0"
  "New Hampshire|new-hampshire|33|NH|-72.6,45.3,-70.6,42.7"
  "New Jersey|new-jersey|34|NJ|-75.6,41.4,-73.9,38.9"
  "New Mexico|new-mexico|35|NM|-109.05,37.0,-103.0,31.33"
  "New York|new-york|36|NY|-79.8,45.0,-71.9,40.5"
  "North Carolina|north-carolina|37|NC|-84.3,36.6,-75.5,33.8"
  "North Dakota|north-dakota|38|ND|-104.05,49.0,-96.55,45.94"
  "Ohio|ohio|39|OH|-84.82,42.0,-80.5,38.4"
  "Oklahoma|oklahoma|40|OK|-103.0,37.0,-94.43,33.6"
  "Oregon|oregon|41|OR|-124.6,46.3,-116.46,41.99"
  "Pennsylvania|pennsylvania|42|PA|-80.52,42.3,-74.7,39.7"
  "Rhode Island|rhode-island|44|RI|-71.9,42.02,-71.1,41.1"
  "South Carolina|south-carolina|45|SC|-83.4,35.2,-78.5,32.0"
  "South Dakota|south-dakota|46|SD|-104.06,45.95,-96.44,42.48"
  "Tennessee|tennessee|47|TN|-90.31,36.7,-81.65,35.0"
  "Texas|texas|48|TX|-106.65,36.5,-93.51,25.84"
  "Utah|utah|49|UT|-114.05,42.0,-109.04,37.0"
  "Vermont|vermont|50|VT|-73.44,45.02,-71.5,42.73"
  "Virginia|virginia|51|VA|-83.68,39.47,-75.24,36.54"
  "Washington|washington|53|WA|-124.85,49.0,-116.92,45.54"
  "West Virginia|west-virginia|54|WV|-82.65,40.64,-77.72,37.2"
  "Wisconsin|wisconsin|55|WI|-92.89,47.08,-86.8,42.49"
  "Wyoming|wyoming|56|WY|-111.06,45.01,-104.05,40.99"
)

DEFAULT_CODE="IA"  # Iowa — the wizard's default selection (cheap, fast dev build)

# SCOPE_MODE is "state" (a single US state) or "country" (the whole country, US).
# Each mode populates the variables that _write_region_config / _write_env and the
# build steps consume.
SCOPE_MODE=""
COUNTRY_FOR_CONFIG=""
STATE_FIPS=""
REGION_SLUG=""
STATE_VIEWBOX=""

# _select_state IDX: populate the state-mode variables from STATES[IDX].
_select_state() {
  SCOPE_MODE="state"
  local entry="${STATES[$1]}" label slug fips usps viewbox
  IFS='|' read -r label slug fips usps viewbox <<< "${entry}"
  REGION_LABEL="${label}"
  REGION_SLUG="${slug}"
  STATE_FIPS="${fips}"
  STATE_USPS="${usps}"
  STATE_VIEWBOX="${viewbox}"
  REGION_URL="https://download.geofabrik.de/north-america/us/${slug}-latest.osm.pbf"
}

# _select_country CODE: populate the country-mode variables (fail fast on unknown).
_select_country() {
  if ! country_resolve "${1:-us}"; then
    error "Cannot configure an un-provisioned country."
    exit 1
  fi
  SCOPE_MODE="country"
  COUNTRY_FOR_CONFIG="${COUNTRY_CODE}"
  REGION_LABEL="${COUNTRY_NAME}"
  REGION_URL="${COUNTRY_EXTRACT_URL}"
}

# "US"/"USA" (case-insensitive) selects the whole country; anything else is a
# state code (USPS or FIPS).
_is_country_token() {
  case "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')" in
    US|USA) return 0 ;;
    *) return 1 ;;
  esac
}

# Precedence: an explicit --country flag, then an explicit --region (so it beats a
# stray inherited COUNTRY env var), then an inherited COUNTRY env, then interactive.
if [ -n "$COUNTRY_FLAG" ]; then
  # Explicit --country → whole country.
  _select_country "$COUNTRY_FLAG"
elif [ -n "$REGION_ARG" ]; then
  # Explicit --region / FLCKD_REGION → a single state (or "US" for the country).
  if _is_country_token "$REGION_ARG"; then
    _select_country "us"
  elif _resolve_code "$REGION_ARG"; then
    _select_state "$SELECTED_IDX"
  else
    error "Unknown state code '${REGION_ARG}'."
    echo "  Expected a two-letter code (e.g. ${BOLD}IA${RESET}), a 2-digit FIPS code (e.g. ${BOLD}19${RESET}), or ${BOLD}US${RESET} for the whole country."
    exit 1
  fi
elif [ -n "$COUNTRY_ENV" ]; then
  # Inherited COUNTRY env (fallback) → whole country.
  _select_country "$COUNTRY_ENV"
else
  # Interactive: default to Iowa; accept any state code, or US for the whole
  # country. Non-interactive (no TTY, dry-run, or selftest) uses the default
  # without prompting.
  if [ "${SETUP_DRY_RUN:-0}" != "1" ] && [ "${SETUP_SELFTEST:-0}" != "1" ] && [ -r /dev/tty ]; then
    echo
    while true; do
      printf '%s' "  Enter a 2-letter state, or ${BOLD}US${RESET} for the whole country [${DEFAULT_CODE}]: "
      read -r input </dev/tty || input=""
      input="$(printf '%s' "${input:-$DEFAULT_CODE}" | tr -d '[:space:]')"
      if _is_country_token "$input"; then _select_country "us"; break; fi
      if _resolve_code "$input"; then _select_state "$SELECTED_IDX"; break; fi
      warn "Unknown entry '${input}' — enter a state code (e.g. IA, CA, NY) or US."
    done
  else
    _resolve_code "$DEFAULT_CODE" && _select_state "$SELECTED_IDX"
  fi
fi

echo
if [ "${SCOPE_MODE}" = "country" ]; then
  success "Configured country: ${BOLD}${COUNTRY_NAME}${RESET}  ${DIM}(${COUNTRY_CODE})${RESET}"
else
  success "Selected state: ${BOLD}${REGION_LABEL}${RESET}  ${DIM}(${STATE_USPS}, single-state build)${RESET}"
fi

ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/../.env}"

# Geocoder OSM-import wait cap (minutes). A WHOLE-COUNTRY import takes HOURS; a
# single state is ~20-35 min. Override with GEO_GEOCODER_TIMEOUT=<minutes>.
if [ "${SCOPE_MODE}" = "country" ]; then
  GEO_TIMEOUT_MIN="${GEO_GEOCODER_TIMEOUT:-360}"
else
  GEO_TIMEOUT_MIN="${GEO_GEOCODER_TIMEOUT:-35}"
fi

# _write_region_config: write infra/.region (sourced by the build scripts) AND
# infra/.env (interpolated by docker-compose into the backend's geocoder env, so
# the app runs turnkey in the chosen scope — no manual env edits). Called as a
# wizard build step below.
_write_region_config() {
  {
    cat <<EOF
# flckd region config — generated by infra/scripts/setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Edit this file or re-run the wizard to change the deployment scope.
#
# SECURITY NOTE: this file is sourced as shell code by infra/scripts/build-geo.sh,
# infra/scripts/fetch-extract.sh, and infra/scripts/build-geocoder.sh.
# Keep it to plain KEY="VALUE" assignments only.
# Do not add subshells, pipes, or command substitutions.
EOF
    if [ "${SCOPE_MODE}" = "country" ]; then
      cat <<EOF
COUNTRY="${COUNTRY_FOR_CONFIG}"
REGION_LABEL="${REGION_LABEL}"
EOF
    else
      cat <<EOF
REGION="${REGION_SLUG}"
REGION_LABEL="${REGION_LABEL}"
REGION_URL="${REGION_URL}"
STATE_FIPS="${STATE_FIPS}"
EOF
    fi
  } > "${REGION_CONFIG}"

  _write_env
}

# _write_env: write infra/.env — the backend's geocoder scope, interpolated by
# docker-compose. Country mode → GEOCODER_COUNTRY (whole-country viewbox + map
# framing). State mode → GEOCODER_REGION_STATE (legacy single-region geocoding) +
# GEOCODER_VIEWBOX (the state's bbox; also frames the map on that state).
_write_env() {
  {
    echo "# flckd geocoder scope — generated by infra/scripts/setup.sh. Do not edit by hand;"
    echo "# re-run the wizard. docker-compose interpolates these into the backend service."
    if [ "${SCOPE_MODE}" = "country" ]; then
      echo "GEOCODER_COUNTRY=${COUNTRY_FOR_CONFIG}"
      echo "GEOCODER_REGION_STATE="
      echo "GEOCODER_VIEWBOX="
    else
      echo "GEOCODER_COUNTRY="
      echo "GEOCODER_REGION_STATE=${REGION_LABEL}"
      echo "GEOCODER_VIEWBOX=${STATE_VIEWBOX}"
    fi
  } > "${ENV_FILE}"
}

# Self-test (tests): exercise the ETA helpers for the resolved scope and exit.
# Lets test/infra bats verify the duration math + formatting offline.
if [ "${SETUP_SELFTEST:-0}" = "1" ]; then
  _total=0
  for _v in $(_expected_secs "${SCOPE_MODE}"); do _total=$(( _total + _v )); done
  echo "scope=${SCOPE_MODE}"
  echo "fmt 90=$(_fmt_eta 90)"
  echo "fmt 1500=$(_fmt_eta 1500)"
  echo "fmt 14400=$(_fmt_eta 14400)"
  echo "total=$(_fmt_eta "${_total}") (${_total}s)"
  echo "threads=${NOMINATIM_THREADS}"

  # Exercise _est_remaining with a fixed panel state: steps 0-1 done, step 2
  # running (30s in), 3-9 pending. The geocoder import is step 8 (est 1500s).
  _T_STATES=("done" "done" "running" "pending" "pending" "pending" "pending" "pending" "pending" "pending")
  _T_EXPECT=(5 1 90 360 5 90 20 15 1500 240)
  _CUR_ELAPSED=30
  echo "rem_no_overlap=$(_est_remaining 0)"
  echo "rem_overlap1000=$(_est_remaining 1000)"
  exit 0
fi

# Dry run (tests): resolve scope, write the config + env, and exit before any
# Docker work. Lets test/infra bats verify scope handling offline.
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
  _write_region_config
  echo "DRY RUN: scope=${SCOPE_MODE} wrote ${REGION_CONFIG} and ${ENV_FILE}"
  exit 0
fi

  COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"
  LOG_DIR="${SCRIPT_DIR}/../data/build-logs"
  mkdir -p "${LOG_DIR}"

  # _check_prereqs: verify Docker is installed + running and curl is available
  # (curl is needed for the geocoder health check). Prints a diagnostic and
  # returns non-zero on the first failure. Run as the first wizard step below.
  _check_prereqs() {
    if ! command -v docker >/dev/null 2>&1; then
      echo "Docker is not installed — install Docker Desktop: https://docs.docker.com/get-docker/"
      return 1
    fi
    if ! docker info >/dev/null 2>&1; then
      echo "Docker daemon is not running — start Docker Desktop and re-run."
      return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
      echo "curl is required for the geocoder health check — install it (e.g. brew install curl)."
      return 1
    fi
    docker --version 2>/dev/null | head -1
    echo "Docker daemon running; curl available."

    # Soft memory check — not fatal, just a heads-up. The geo build runs
    # Nominatim (OSM import), Planetiler (JVM tile build), Valhalla, and Postgres
    # together; with the common Docker Desktop default of 2–4 GB one of them gets
    # OOM-killed mid-import, which surfaces as a confusing later-step failure
    # rather than "out of memory". `docker info` reports the bytes the daemon can
    # use (the Docker Desktop VM allocation on macOS/Windows).
    local mem_bytes mem_gib
    mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    if [ "${mem_bytes:-0}" -gt 0 ] 2>/dev/null; then
      mem_gib=$(( mem_bytes / 1024 / 1024 / 1024 ))
      if [ "$mem_gib" -lt 6 ]; then
        echo "WARNING: Docker has only ~${mem_gib} GB of memory available."
        echo "         The geo build needs ~6 GB+ (Nominatim/Planetiler can be OOM-killed below that)."
        echo "         Raise it in Docker Desktop → Settings → Resources → Memory, then re-run."
      else
        echo "Docker memory: ~${mem_gib} GB available."
      fi
    fi
    return 0
  }

  # ── Verbose mode: stream all output directly ─────────────────────────────────
  if [ "${VERBOSE}" = "true" ]; then
    echo
    info "Checking prerequisites…"
    if ! _check_prereqs; then echo; error "Prerequisite check failed (see above)."; exit 1; fi
    info "Writing region config…"
    _write_region_config
    echo
    info "Starting geo build for ${BOLD}${REGION_LABEL}${RESET}…"
    echo
    # Artifacts only (extract + routing + tiles + manifest); the wizard runs the
    # service/DB/camera/TIGER steps itself below, so build-geo.sh must NOT also
    # provision them (it would double-provision).
    GEO_ARTIFACTS_ONLY=1 "${SCRIPT_DIR}/build-geo.sh"

    # OVERLAP: the extract is on disk now, so start the geocoder's OSM import to
    # run concurrently with the DB/camera steps below (and the wait). Fire-and-
    # forget; the wait below surfaces any failure. _GEOCODER_T0 makes the wait
    # count the whole import.
    _GEOCODER_T0=$SECONDS
    docker compose -f "${COMPOSE_FILE}" up -d geocoder >/dev/null 2>&1 || true

    echo
    info "Preparing database (self-healing the gem bundle if it's stale)…"
    # `bundle check || bundle install` repairs a stale bundle_cache volume (e.g.
    # after a dependency bump) so db:prepare doesn't die on a missing gem.
    if ! docker compose -f "${COMPOSE_FILE}" run --rm backend \
         sh -ec 'bundle check >/dev/null 2>&1 || bundle install; bin/rails db:prepare'; then
      echo
      error "Database preparation failed (see output above)."
      echo "  Hint: check that the postgres container started —"
      echo "        docker compose -f infra/docker-compose.yml ps postgres"
      exit 1
    fi

    info "Importing fixture cameras…"
    if ! docker compose -f "${COMPOSE_FILE}" run --rm -e SOURCE=fixture backend bin/rails camera_data:import; then
      echo
      error "Fixture camera import failed (see output above)."
      exit 1
    fi

    info "Starting services…"
    docker compose -f "${COMPOSE_FILE}" up -d

    info "Waiting for geocoder OSM import (up to ${GEO_TIMEOUT_MIN} min)…"
    # Count from the overlap start (above) so the timeout budgets the whole import.
    _t0_geo=${_GEOCODER_T0:-$SECONDS}
    printf '    '
    while ! curl -sf "http://localhost:8081/status.php" >/dev/null 2>&1; do
      _e_geo=$(( SECONDS - _t0_geo ))
      if [ $_e_geo -gt $(( GEO_TIMEOUT_MIN * 60 )) ]; then
        echo
        error "Geocoder timed out (${GEO_TIMEOUT_MIN} min — raise GEO_GEOCODER_TIMEOUT). Check logs:"
        echo "    docker compose -f infra/docker-compose.yml logs geocoder"
        exit 1
      fi
      printf '.'
      sleep 10
    done
    echo
    success "Geocoder ready."

    info "Importing TIGER address data…"
    "${SCRIPT_DIR}/build-geocoder.sh"

  # ── Panel mode: one unified checklist covering every automated step ───────────
  else

    # Spinner — rotating half-circle frames. These are ambiguous-width glyphs
    # (same width class as the ✓/✗/○ status icons), so the icon column stays a
    # uniform width. Braille spinners render double-width in some terminals,
    # which pushed the running row's timer/border one column to the right.
    _SPIN=('◐' '◓' '◑' '◒')

    # Step names (display order = array order, 0-based)
    _T_NAMES=(
      "Check prerequisites"
      "Write region config"
      "Download OSM extract"
      "Build routing + tiles"
      "Write geo manifest"
      "Prepare database"
      "Import fixture cameras"
      "Start services"
      "Geocoder OSM import"
      "TIGER address data"
    )
    _T_STATES=("pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending" "pending")
    _T_TIMES=("" "" "" "" "" "" "" "" "" "")
    # Per-step duration estimates (seconds) for the ETA display, scoped to the
    # build size. _CUR_ELAPSED is the running step's elapsed seconds (set by
    # _run_step/_wait_geocoder) so the panel can show remaining = sum of pending
    # estimates + the current step's remaining estimate.
    read -r -a _T_EXPECT <<< "$(_expected_secs "${SCOPE_MODE}")"
    _CUR_ELAPSED=0

    _PANEL_H=16      # top border + title + divider + 10 rows + divider + total + bottom border
    _PANEL_LIVE=false

    # _draw_panel [frame_idx] [running_elapsed]
    # Redraws the 14-line status panel in-place once it has been printed once.
    _draw_panel() {
      local frame="${1:-0}" at="${2:-}"

      if [ "$_PANEL_LIVE" = "true" ]; then
        printf "\033[%dA\r" "$_PANEL_H"
      else
        _PANEL_LIVE=true
      fi

      local _pt; printf -v _pt "%-32s" "setup"
      printf "  ╭%s╮\n" "$_SEP"
      printf "  │  ${BOLD}${CYAN}flckd${RESET}  ·  %s  │\n" "$_pt"
      printf "  ├%s┤\n" "$_SEP"

      for i in 0 1 2 3 4 5 6 7 8 9; do
        # Right-pad the step number to 2 cols so step 10 doesn't shift the row
        # (each row must stay exactly ${#_SEP} visible chars between the borders).
        local n; printf -v n "%2s" "$((i+1))"
        local nm; printf -v nm "%-25s" "${_T_NAMES[$i]}"
        local st="${_T_STATES[$i]}"

        case "$st" in
          running)
            local fr="${_SPIN[$((frame % ${#_SPIN[@]}))]}"
            local at_t; printf -v at_t "%8s" "$at"
            printf "  │  %s  ${CYAN}%s${RESET}  %s  ${DIM}%s${RESET}  │\n" \
              "$n" "$fr" "$nm" "$at_t"
            ;;
          done)
            local tm; printf -v tm "%8s" "${_T_TIMES[$i]}"
            printf "  │  %s  ${GREEN}✓${RESET}  %s  ${DIM}%s${RESET}  │\n" \
              "$n" "$nm" "$tm"
            ;;
          failed)
            local tm; printf -v tm "%8s" "${_T_TIMES[$i]}"
            printf "  │  %s  ${RED}✗${RESET}  %s  ${DIM}%s${RESET}  │\n" \
              "$n" "$nm" "$tm"
            ;;
          *)
            # Pending: show the step's ~estimated duration in the time column.
            local ex; printf -v ex "%8s" "~$(_fmt_eta "${_T_EXPECT[$i]:-0}")"
            printf "  │  %s  ${DIM}○${RESET}  %s  ${DIM}%s${RESET}  │\n" \
              "$n" "$nm" "$ex"
            ;;
        esac
      done

      # Overall ETA: elapsed + estimated remaining (sum of pending estimates plus
      # the running step's remaining estimate). Rough — wildly hardware-dependent.
      local _te=$(( SECONDS - _TOTAL_START ))
      # Credit the geocoder import's overlap time (it started at step 3) so the
      # total ETA reflects work already done concurrently.
      local _ov=0; [ -n "${_GEOCODER_T0:-}" ] && _ov=$(( SECONDS - _GEOCODER_T0 ))
      local _rem; _rem=$(_est_remaining "$_ov")
      local _val; printf -v _val "%s / %s" "$(_fmt_eta "$_te")" "$(_fmt_eta "$_rem")"
      printf "  ├%s┤\n" "$_SEP"
      # ASCII-only separators so printf padding (byte count) == display columns.
      printf "  │  ${DIM}%-24s%18s${RESET}  │\n" "Elapsed / est. remaining" "$_val"
      printf "  ╰%s╯\n" "$_SEP"
    }

    # _run_step IDX CMD [ARGS...]
    # Runs CMD in the background, animates the panel spinner for that step,
    # then marks it done (✓) or failed (✗). Exits the whole script on failure.
    _run_step() {
      local idx="$1"; shift
      local log; log=$(mktemp)
      local t0=$SECONDS frame=0
      _T_STATES[$idx]="running"

      "$@" >"$log" 2>&1 &
      local pid=$!
      tput civis 2>/dev/null || true

      while kill -0 "$pid" 2>/dev/null; do
        local e=$(( SECONDS - t0 ))
        local et; printf -v et "%d:%02d" $((e/60)) $((e%60))
        _CUR_ELAPSED=$e
        _draw_panel "$frame" "$et"
        frame=$(( frame + 1 ))
        sleep 0.1
      done

      # Capture the job's exit code without letting `set -e` abort on a
      # failed `wait` — `|| rc=$?` suppresses errexit so the failure-handling
      # block below actually runs (otherwise the script dies silently).
      local rc=0
      wait "$pid" || rc=$?
      local e=$(( SECONDS - t0 ))
      local et; printf -v et "%d:%02d" $((e/60)) $((e%60))
      tput cnorm 2>/dev/null || true

      if [ $rc -eq 0 ]; then
        _T_STATES[$idx]="done"
        _T_TIMES[$idx]="$et"
        _draw_panel 0
        rm -f "$log"
      else
        _T_STATES[$idx]="failed"
        _T_TIMES[$idx]="$et"
        _draw_panel 0
        echo
        echo
        error "Step $((idx + 1)) (${_T_NAMES[$idx]}) failed. Last output:"
        tail -20 "$log" | sed 's/^/    /'
        echo
        # Step-specific recovery hints
        case "$idx" in
          0) echo "  Hint: install/start Docker Desktop and ensure curl is available —"
             echo "        Docker: https://docs.docker.com/get-docker/" ;;
          1) echo "  Hint: could not write infra/.region — check filesystem permissions." ;;
          2) echo "  Hint: check network connectivity and available disk space." ;;
          3) echo "  Hint: check Docker resources and available disk space."
             echo "        Routing log: ${LOG_DIR}/routing.log"
             echo "        Tiles log:   ${LOG_DIR}/tiles.log" ;;
          5) echo "  Hint: this step also syncs the gem bundle; if that's the failure,"
             echo "        rebuild the backend image: docker compose -f infra/docker-compose.yml build backend"
             echo "        Else check postgres: docker compose -f infra/docker-compose.yml ps postgres" ;;
          6) echo "  Hint: verify the backend image is up to date —"
             echo "        docker compose -f infra/docker-compose.yml build backend" ;;
          7) echo "  Hint: check for port conflicts —"
             echo "        docker compose -f infra/docker-compose.yml ps" ;;
          9) echo "  Hint: the geocoder must be healthy before TIGER imports."
             echo "        Check status: curl -sf http://localhost:8081/status.php"
             echo "        Retry manually: infra/scripts/build-geocoder.sh" ;;
        esac
        echo
        rm -f "$log"
        exit 1
      fi
    }

    # _build_routing_tiles
    # Runs build-routing-graph.sh and build-tiles.sh in parallel (they both read
    # the same extract and write to separate directories). Called via _run_step so
    # it runs in a subshell; each child writes its own log file.
    _build_routing_tiles() {
      "${SCRIPT_DIR}/build-routing-graph.sh" > "${LOG_DIR}/routing.log" 2>&1 &
      local routing_pid=$!
      "${SCRIPT_DIR}/build-tiles.sh" > "${LOG_DIR}/tiles.log" 2>&1 &
      local tiles_pid=$!
      wait "$routing_pid" || { wait "$tiles_pid" 2>/dev/null || true; return 1; }
      wait "$tiles_pid" || return 1
    }

    # _wait_geocoder
    # Polls Nominatim's /status.php until healthy (up to GEO_TIMEOUT_MIN min —
    # hours for a whole-country import, ~35 min for a single state).
    # Uses step index 8 ("Geocoder OSM import").
    # Animates the spinner every 0.1s; checks curl every 5s to avoid hammering.
    _wait_geocoder() {
      local idx=8
      # Count from when the geocoder import was started (the overlap, step 3), so
      # the displayed elapsed + ETA reflect the whole import, not just the residual
      # wait — and the timeout budgets the total import time. Falls back to now.
      local t0=${_GEOCODER_T0:-$SECONDS} frame=0 tick=0
      local timeout=$(( GEO_TIMEOUT_MIN * 60 ))
      _T_STATES[$idx]="running"
      tput civis 2>/dev/null || true

      while true; do
        local e=$(( SECONDS - t0 ))
        local et; printf -v et "%d:%02d" $((e/60)) $((e%60))
        _CUR_ELAPSED=$e

        if [ $e -gt $timeout ]; then
          tput cnorm 2>/dev/null || true
          _T_STATES[$idx]="failed"
          _T_TIMES[$idx]="$et"
          _draw_panel 0
          echo
          echo
          error "Geocoder timed out (${GEO_TIMEOUT_MIN} min — raise GEO_GEOCODER_TIMEOUT). Check logs:"
          echo "    docker compose -f infra/docker-compose.yml logs geocoder"
          exit 1
        fi

        # Every ~5 s: verify the container is still alive, then check health.
        if [ $(( tick % 50 )) -eq 0 ]; then
          # After a 30 s grace period for startup, bail if the container exited.
          if [ $tick -gt 300 ]; then
            local cid cstatus
            cid=$(docker compose -f "${COMPOSE_FILE}" ps -q geocoder 2>/dev/null || true)
            if [ -n "$cid" ]; then
              cstatus=$(docker inspect --format '{{.State.Status}}' "$cid" 2>/dev/null || true)
              if [ "$cstatus" = "exited" ] || [ "$cstatus" = "dead" ]; then
                tput cnorm 2>/dev/null || true
                _T_STATES[$idx]="failed"
                _T_TIMES[$idx]="$et"
                _draw_panel 0
                echo
                echo
                error "Geocoder container stopped unexpectedly. Check logs:"
                echo "    docker compose -f infra/docker-compose.yml logs geocoder"
                exit 1
              fi
            fi
          fi

          if curl -sf "http://localhost:8081/status.php" >/dev/null 2>&1; then
            tput cnorm 2>/dev/null || true
            _T_STATES[$idx]="done"
            _T_TIMES[$idx]="$et"
            _draw_panel 0
            return 0
          fi
        fi

        _draw_panel "$frame" "$et"
        frame=$(( frame + 1 ))
        tick=$(( tick + 1 ))
        sleep 0.1
      done
    }

    # ── Draw initial panel then run each step ──────────────────────────────────
    _TOTAL_START=$SECONDS
    echo
    _draw_panel

    # 1 — Check prerequisites (Docker installed + running, curl available)
    _run_step 0 _check_prereqs

    # 2 — Write infra/.region for the selected state (build scripts source it)
    _run_step 1 _write_region_config

    # 3 — Download the OSM extract for the selected state
    _run_step 2 "${SCRIPT_DIR}/fetch-extract.sh"

    # OVERLAP: the extract is on disk, so start the geocoder's OSM import NOW — it
    # runs concurrently with the routing+tiles / DB / camera steps below, hiding
    # the long pole. Fire-and-forget; step 9 (_wait_geocoder) waits for it and
    # surfaces any failure. _GEOCODER_T0 lets that step show the true import
    # elapsed + ETA (counting the overlap), not just the residual wait.
    _GEOCODER_T0=$SECONDS
    docker compose -f "${COMPOSE_FILE}" up -d geocoder >/dev/null 2>&1 || true

    # 4 — Build routing graph (Valhalla) + vector tiles (Planetiler) in parallel
    _run_step 3 _build_routing_tiles

    # 5 — Write versioned geo manifest
    _run_step 4 "${SCRIPT_DIR}/geo-manifest.sh" generate

    # 6 — Prepare the database schema. Self-heals a stale bundle_cache volume
    #     first (`bundle check || bundle install`) so a dependency bump doesn't
    #     break db:prepare with a "Could not find <gem>" error.
    _run_step 5 docker compose -f "${COMPOSE_FILE}" run --rm backend \
      sh -ec 'bundle check >/dev/null 2>&1 || bundle install; bin/rails db:prepare'

    # 7 — Seed fixture cameras
    _run_step 6 docker compose -f "${COMPOSE_FILE}" run --rm -e SOURCE=fixture backend bin/rails camera_data:import

    # 8 — Start all services
    _run_step 7 docker compose -f "${COMPOSE_FILE}" up -d

    # 9 — Wait for Nominatim to finish its OSM import (~20 min first run)
    _wait_geocoder

    # 10 — Import TIGER/Line address data for house-number geocoding
    _run_step 9 "${SCRIPT_DIR}/build-geocoder.sh"

  fi  # end panel/verbose branch

  # ── Optional: load real ALPR cameras from the OSM extract ────────────────────
  # Only 5 demo "fixture" cameras were imported above. The real ALPR/Flock data
  # lives in OpenStreetMap — the same substrate community maps (e.g. DeFlock)
  # use. We read it from the OSM extract already on disk (ADR 0002): filter the
  # camera nodes out with osmium and import the GeoJSON. No Overpass API, so no
  # rate limit and no network beyond the extract we already downloaded.
  CAMERA_GEOJSON="$(cd "${SCRIPT_DIR}/../.." && pwd)/backend/storage/cameras.geojson"
  echo
  info "Loading real ALPR cameras for ${REGION_LABEL} from the OSM extract (offline; no API)…"
  # Build the GeoJSON straight into the backend container's read path
  # (backend/ is mounted at /app, so CAMERA_OSM_GEOJSON_PATH=storage/cameras.geojson),
  # then import it. SOURCE=pbf reads that file and prints the resulting camera count.
  if OUT="${CAMERA_GEOJSON}" "${SCRIPT_DIR}/build-cameras.sh" \
     && docker compose -f "${COMPOSE_FILE}" run --rm -e SOURCE=pbf \
          backend bin/rails camera_data:import; then
    success "Real cameras imported from the OSM extract (see the count above)."
  else
    warn "Camera import did not complete — the map shows only the 5 demo cameras. Retry:"
    echo "    OUT=backend/storage/cameras.geojson infra/scripts/build-cameras.sh && \\"
    echo "    docker compose -f infra/docker-compose.yml run --rm -e SOURCE=pbf backend bin/rails camera_data:import"
  fi

  echo
  divider
  echo
  success "flckd is ready."
  echo
  echo "  Frontend:  ${CYAN}http://localhost:5173${RESET}"
  echo "  Backend:   ${CYAN}http://localhost:3000/api/v1/health${RESET}"

echo
divider
echo

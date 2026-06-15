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
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=true ;;
    --region) shift; REGION_ARG="${1:-}" ;;
    --region=*) REGION_ARG="${1#--region=}" ;;
  esac
  shift
done

# ── ANSI colour helpers ────────────────────────────────────────────────────────
RED=$'\e[0;31m'; YELLOW=$'\e[0;33m'; GREEN=$'\e[0;32m'
CYAN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'

info()    { echo "${CYAN}  →${RESET}  $*"; }
success() { echo "${GREEN}  ✓${RESET}  $*"; }
warn()    { echo "${YELLOW}  !${RESET}  $*"; }
error()   { echo "${RED}  ✗  $*${RESET}" >&2; }
header()  { echo; echo "${BOLD}${CYAN}$*${RESET}"; echo; }
divider() { echo "${DIM}──────────────────────────────────────────${RESET}"; }

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
  local i entry usps rest fips
  for i in "${!STATES[@]}"; do
    # Format: "Display Label|geofabrik-slug|state-fips|usps-code"
    entry="${STATES[$i]}"
    usps="${entry##*|}"        # last field
    rest="${entry%|*}"         # drop the USPS field
    fips="${rest##*|}"         # FIPS is now the last field
    if [ "$q" = "$usps" ] || [ "$q" = "$fips" ]; then
      SELECTED_IDX="$i"; return 0
    fi
  done
  return 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGION_CONFIG="${SCRIPT_DIR}/../.region"

# ── Welcome ────────────────────────────────────────────────────────────────────
clear
echo
echo "${BOLD}${CYAN}  flckd — setup wizard${RESET}"
echo "${DIM}  Anonymous, camera-avoiding route planner${RESET}"
divider

# ── State selection (the only input) ───────────────────────────────────────────

# Format: "Display Label|geofabrik-slug|state-fips|usps-code"
# FIPS codes are the 2-digit US Census state identifiers used by TIGER/Line
# data downloads (infra/scripts/build-geocoder.sh). USPS codes are the
# two-letter postal abbreviations typed at the prompt below.
STATES=(
  "Alabama|alabama|01|AL"
  "Alaska|alaska|02|AK"
  "Arizona|arizona|04|AZ"
  "Arkansas|arkansas|05|AR"
  "California|california|06|CA"
  "Colorado|colorado|08|CO"
  "Connecticut|connecticut|09|CT"
  "Delaware|delaware|10|DE"
  "District of Columbia|district-of-columbia|11|DC"
  "Florida|florida|12|FL"
  "Georgia|georgia|13|GA"
  "Hawaii|hawaii|15|HI"
  "Idaho|idaho|16|ID"
  "Illinois|illinois|17|IL"
  "Indiana|indiana|18|IN"
  "Iowa|iowa|19|IA"
  "Kansas|kansas|20|KS"
  "Kentucky|kentucky|21|KY"
  "Louisiana|louisiana|22|LA"
  "Maine|maine|23|ME"
  "Maryland|maryland|24|MD"
  "Massachusetts|massachusetts|25|MA"
  "Michigan|michigan|26|MI"
  "Minnesota|minnesota|27|MN"
  "Mississippi|mississippi|28|MS"
  "Missouri|missouri|29|MO"
  "Montana|montana|30|MT"
  "Nebraska|nebraska|31|NE"
  "Nevada|nevada|32|NV"
  "New Hampshire|new-hampshire|33|NH"
  "New Jersey|new-jersey|34|NJ"
  "New Mexico|new-mexico|35|NM"
  "New York|new-york|36|NY"
  "North Carolina|north-carolina|37|NC"
  "North Dakota|north-dakota|38|ND"
  "Ohio|ohio|39|OH"
  "Oklahoma|oklahoma|40|OK"
  "Oregon|oregon|41|OR"
  "Pennsylvania|pennsylvania|42|PA"
  "Rhode Island|rhode-island|44|RI"
  "South Carolina|south-carolina|45|SC"
  "South Dakota|south-dakota|46|SD"
  "Tennessee|tennessee|47|TN"
  "Texas|texas|48|TX"
  "Utah|utah|49|UT"
  "Vermont|vermont|50|VT"
  "Virginia|virginia|51|VA"
  "Washington|washington|53|WA"
  "West Virginia|west-virginia|54|WV"
  "Wisconsin|wisconsin|55|WI"
  "Wyoming|wyoming|56|WY"
)

DEFAULT_CODE="IA"  # Iowa — the launch region

# Resolve the state code: from --region / $FLCKD_REGION if given, else prompt.
# This is the ONLY interactive input the wizard takes.
SELECTED_IDX=""
if [ -n "$REGION_ARG" ]; then
  if ! _resolve_code "$REGION_ARG"; then
    error "Unknown state code '${REGION_ARG}'."
    echo "  Expected a two-letter code (e.g. ${BOLD}IA${RESET}) or a 2-digit FIPS code (e.g. ${BOLD}19${RESET})."
    exit 1
  fi
else
  echo
  while true; do
    printf '%s' "  Enter state [${DEFAULT_CODE}]: "
    read -r input </dev/tty || input=""
    input="$(printf '%s' "${input:-$DEFAULT_CODE}" | tr -d '[:space:]')"
    if _resolve_code "$input"; then
      break
    fi
    warn "Unknown state code '${input}' — enter a two-letter state code (e.g. IA, CA, NY)."
  done
fi

SELECTED_ENTRY="${STATES[$SELECTED_IDX]}"
REGION_LABEL="${SELECTED_ENTRY%%|*}"
_entry_rest="${SELECTED_ENTRY#*|}"
REGION_SLUG="${_entry_rest%%|*}"
_entry_no_usps="${SELECTED_ENTRY%|*}"
STATE_FIPS="${_entry_no_usps##*|}"
REGION_URL="https://download.geofabrik.de/north-america/us/${REGION_SLUG}-latest.osm.pbf"

echo
success "Selected: ${BOLD}${REGION_LABEL}${RESET}  ${DIM}(${SELECTED_ENTRY##*|})${RESET}"

# _write_region_config: write infra/.region for the selected state. Called as a
# wizard build step below (so it shows as a completed step instead of printing
# the config contents here). The build scripts source this file.
_write_region_config() {
  cat > "${REGION_CONFIG}" <<EOF
# flckd region config — generated by infra/scripts/setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Edit this file or re-run the wizard to change regions.
#
# SECURITY NOTE: this file is sourced as shell code by infra/scripts/build-geo.sh,
# infra/scripts/fetch-extract.sh, and infra/scripts/build-geocoder.sh.
# Keep it to plain KEY="VALUE" assignments only.
# Do not add subshells, pipes, or command substitutions.
REGION="${REGION_SLUG}"
REGION_LABEL="${REGION_LABEL}"
REGION_URL="${REGION_URL}"
STATE_FIPS="${STATE_FIPS}"
EOF
}

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
    "${SCRIPT_DIR}/build-geo.sh"

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

    info "Waiting for geocoder OSM import (up to 35 min)…"
    _t0_geo=$SECONDS
    printf '    '
    while ! curl -sf "http://localhost:8081/status.php" >/dev/null 2>&1; do
      _e_geo=$(( SECONDS - _t0_geo ))
      if [ $_e_geo -gt $(( 35 * 60 )) ]; then
        echo
        error "Geocoder timed out (35 min). Check logs:"
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
            printf "  │  %s  ${DIM}○  %s${RESET}            │\n" \
              "$n" "$nm"
            ;;
        esac
      done

      local _te=$(( SECONDS - _TOTAL_START ))
      local _te_s; printf -v _te_s "%d:%02d" $((_te/60)) $((_te%60))
      local _te_fmt; printf -v _te_fmt "%8s" "$_te_s"
      printf "  ├%s┤\n" "$_SEP"
      printf "  │  %-34s${DIM}%s${RESET}  │\n" "Total elapsed" "$_te_fmt"
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
    # Polls Nominatim's /status.php until healthy (up to 35 min).
    # Uses step index 8 ("Geocoder OSM import").
    # Animates the spinner every 0.1s; checks curl every 5s to avoid hammering.
    _wait_geocoder() {
      local idx=8
      local t0=$SECONDS frame=0 tick=0
      local timeout=$(( 35 * 60 ))
      _T_STATES[$idx]="running"
      tput civis 2>/dev/null || true

      while true; do
        local e=$(( SECONDS - t0 ))
        local et; printf -v et "%d:%02d" $((e/60)) $((e%60))

        if [ $e -gt $timeout ]; then
          tput cnorm 2>/dev/null || true
          _T_STATES[$idx]="failed"
          _T_TIMES[$idx]="$et"
          _draw_panel 0
          echo
          echo
          error "Geocoder timed out (35 min). Check logs:"
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

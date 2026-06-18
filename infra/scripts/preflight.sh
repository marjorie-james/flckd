#!/usr/bin/env bash
#
# flckd local preflight — actionable Docker checks for first-time setup.
#
# Unlike preflight-host.sh (read-only pre-DEPLOY checks over SSH), this is the
# LOCAL, first-run helper that makes ./setup.sh friendly for a non-technical
# user. Instead of just printing "Docker is not installed", it:
#
#   1. opens the Docker Desktop download page in the browser when Docker is
#      missing (and tells the user exactly what to do next), and
#   2. starts Docker Desktop for them and waits for the daemon when Docker is
#      installed but not running, and
#   3. flags a low Docker memory allotment with the exact click-path to fix it.
#
# It is SOURCE-able (setup.sh sources it and calls pf_ensure_docker interactively
# before the build panel, so these messages aren't buried in a backgrounded
# step). Run directly it performs the same check and exits with its status:
#
#   infra/scripts/preflight.sh
#
# Every helper is best-effort and never aborts the caller on its own — the one
# decision is pf_ensure_docker's return code (0 = ready, 1 = the user must act).

# ── Tunables (overridable via env) ──────────────────────────────────────────
# Memory floor (GiB). Below this the geo build can OOM-kill Nominatim/Planetiler
# mid-import; the README documents ~6 GB for a single state.
PF_MIN_MEM_GIB="${FLCKD_MIN_MEM_GIB:-6}"
# How long to wait (seconds) for the Docker daemon after auto-starting it.
PF_DOCKER_WAIT="${FLCKD_DOCKER_WAIT:-120}"
PF_DOCKER_GET_URL="https://docs.docker.com/get-docker/"

# ── Minimal colour helpers (pf_ prefix; independent of setup.sh's) ──────────
_PF_CYAN=$'\e[0;36m'; _PF_GREEN=$'\e[0;32m'; _PF_YELLOW=$'\e[0;33m'
_PF_RED=$'\e[0;31m'; _PF_RESET=$'\e[0m'
_pf_info()    { echo "${_PF_CYAN}  →${_PF_RESET}  $*"; }
_pf_success() { echo "${_PF_GREEN}  ✓${_PF_RESET}  $*"; }
_pf_warn()    { echo "${_PF_YELLOW}  !${_PF_RESET}  $*"; }
_pf_error()   { echo "${_PF_RED}  ✗  $*${_PF_RESET}" >&2; }

# pf_open_url URL — open URL in the user's default browser, cross-platform and
# best-effort. Backgrounded so a slow handler never stalls setup; always 0.
pf_open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 &        # macOS
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &    # Linux desktop
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$url" >/dev/null 2>&1 &  # WSL/Git-Bash on Windows
  fi
  return 0
}

# pf_docker_mem_gib — GiB the Docker daemon can use (the Docker Desktop VM
# allotment on macOS/Windows). Echoes an integer; 0 when unknown.
pf_docker_mem_gib() {
  local b
  b=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  if [ "${b:-0}" -gt 0 ] 2>/dev/null; then
    echo $(( b / 1024 / 1024 / 1024 ))
  else
    echo 0
  fi
}

# pf_try_start_docker — best-effort launch of the Docker daemon for the user.
# Returns non-zero if we don't know how to start it on this platform (the caller
# then asks the user to start it by hand).
pf_try_start_docker() {
  case "$(uname -s 2>/dev/null)" in
    Darwin)
      open -a Docker >/dev/null 2>&1 || open -a "Docker Desktop" >/dev/null 2>&1 || return 1 ;;
    Linux)
      # Docker Desktop on Linux registers a user service; a plain dockerd install
      # is usually already running, so this path is only the Desktop case.
      systemctl --user start docker-desktop >/dev/null 2>&1 || return 1 ;;
    *)
      return 1 ;;
  esac
}

# pf_wait_for_docker [TIMEOUT_SECS] — poll `docker info` until the daemon answers
# or the timeout elapses. 0 = ready, 1 = timed out.
pf_wait_for_docker() {
  local timeout="${1:-$PF_DOCKER_WAIT}" t0=$SECONDS
  while ! docker info >/dev/null 2>&1; do
    [ $(( SECONDS - t0 )) -ge "$timeout" ] && return 1
    printf '.'
    sleep 2
  done
  return 0
}

# pf_ensure_docker — the one decision. Returns 0 when Docker is installed and
# running (memory is only a soft warning); returns 1 when the user must act
# (Docker missing, or it wouldn't start), having already opened the download
# page / attempted a start and printed what to do next.
pf_ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    _pf_error "Docker isn't installed yet — it's the one thing flckd needs."
    _pf_info "Opening the Docker Desktop download page in your browser:"
    _pf_info "  ${PF_DOCKER_GET_URL}"
    pf_open_url "${PF_DOCKER_GET_URL}"
    _pf_info "Install Docker Desktop, start it (wait for the whale icon to settle),"
    _pf_info "then run this setup again."
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    _pf_info "Docker is installed but not running — starting it for you…"
    if pf_try_start_docker; then
      printf '    '
      if pf_wait_for_docker "${PF_DOCKER_WAIT}"; then
        echo
        _pf_success "Docker is running."
      else
        echo
        _pf_error "Docker didn't finish starting in time."
        _pf_info "Open Docker Desktop yourself, wait for it to say it's running, then re-run setup."
        return 1
      fi
    else
      _pf_error "Couldn't start Docker automatically on this platform."
      _pf_info "Open Docker Desktop yourself, wait for it to say it's running, then re-run setup."
      return 1
    fi
  fi

  # Soft memory check — informative, never fatal (matches setup.sh's own warning).
  local mem; mem=$(pf_docker_mem_gib)
  if [ "${mem:-0}" -gt 0 ] && [ "${mem}" -lt "${PF_MIN_MEM_GIB}" ]; then
    _pf_warn "Docker has only ~${mem} GB of memory; the geo build wants ~${PF_MIN_MEM_GIB} GB+."
    _pf_info "Raise it in Docker Desktop → Settings → Resources → Memory, then re-run."
  fi
  return 0
}

# Run the check when executed directly (not when sourced by setup.sh / tests).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  pf_ensure_docker
fi

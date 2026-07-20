#!/usr/bin/env bash
# Shared host-targeting helpers for the deploy scripts that act on a Kamal host
# over SSH (provision-geo-host.sh, deploy-frontend.sh). SOURCED, not executed —
# it defines functions and an SSH_OPTS array but runs nothing on its own.
#
# The caller must set DEPLOY_YML (path to backend/config/deploy.yml) before
# calling these. Optional inputs honoured: SSH_USER (override the ssh user),
# GEO_HOST / TARGET_HOST (a pre-set target, used when no host arg is passed).
#
# After `resolve_target_host [user@host]`:
#   TARGET_HOST   the `user@addr` to ssh to (ssh.user prepended if the value was bare)
#   sshx <cmd…>   run a command on TARGET_HOST
# After `resolve_remote_home`:
#   HOST_HOME     the remote $HOME (absolute; guaranteed non-empty)

# shellcheck disable=SC2034  # SSH_OPTS is consumed by sshx() and callers' scp.
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes)

# Echo the first `host:` value inside a named deploy.yml block (a role or
# accessory key, e.g. "routing", or the top-level "proxy"). Empty if not found.
_deploy_yml_host() {  # <block-key>
  awk -v key="$1" '
    $0 ~ "^[[:space:]]*" key ":" { f = 1 }
    f && /host:/ { print $2; exit }
  ' "${DEPLOY_YML}"
}

# Resolve TARGET_HOST from (in order) the arg, a pre-set TARGET_HOST/GEO_HOST, or
# the routing accessory host in deploy.yml — then prepend the ssh user (from
# ssh.user, or $SSH_USER, default "deploy") when the value carries no `user@`.
# deploy.yml host values are bare addresses; Kamal adds the user via ssh.user, but
# our own ssh/scp calls must include it.
# Load FLCKD_HOST from .kamal/secrets.env (gitignored) when it isn't already in the
# environment. The host IP is kept OUT of git: deploy.yml references it as
# `<%= ENV.fetch("FLCKD_HOST") %>`, and these shell scripts (which don't render ERB)
# read the same value from secrets.env so `host:` parsing never leaks the ERB tag.
_load_flckd_host_from_secrets() {
  [ -n "${FLCKD_HOST:-}" ] && return 0
  # Build the path with dirname only (no `cd ... && pwd`): a failing `cd` inside a
  # command substitution makes the enclosing assignment non-zero, which aborts the
  # sourcing script under `set -e`. dirname never fails, and the shell resolves the
  # `../` when the path is used.
  local _sf
  _sf="$(dirname "${DEPLOY_YML}")/../.kamal/secrets.env"
  [ -f "${_sf}" ] || return 0
  # Grab only FLCKD_HOST; do not source the whole secrets file into these scripts.
  FLCKD_HOST="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?FLCKD_HOST=["'\'']?([^"'\''[:space:]]+).*/\2/p' "${_sf}" | tail -1)"
  [ -n "${FLCKD_HOST}" ] && export FLCKD_HOST || true
}

resolve_target_host() {  # [user@host]
  _load_flckd_host_from_secrets
  TARGET_HOST="${1:-${TARGET_HOST:-${GEO_HOST:-${FLCKD_HOST:-}}}}"
  # Never fall back to the deploy.yml host when it is the un-rendered ERB tag.
  case "${TARGET_HOST}" in *'<%'*) TARGET_HOST="";; esac
  if [ -z "${TARGET_HOST}" ]; then
    local _parsed; _parsed="$(_deploy_yml_host routing)"
    case "${_parsed}" in *'<%'*) _parsed="";; esac
    TARGET_HOST="${_parsed}"
  fi
  [ -n "${TARGET_HOST}" ] || {
    echo "lib-deploy-host: could not determine the target host (pass user@host, export FLCKD_HOST, or set it in .kamal/secrets.env)" >&2
    return 1
  }
  if [ "${TARGET_HOST}" = "${TARGET_HOST#*@}" ]; then
    local _user
    _user="${SSH_USER:-$(awk '/^ssh:/{f=1} f&&/user:/{print $2; exit}' "${DEPLOY_YML}")}"
    TARGET_HOST="${_user:-deploy}@${TARGET_HOST}"
  fi
}

sshx() { ssh "${SSH_OPTS[@]}" "${TARGET_HOST}" "$@"; }

# Resolve the remote $HOME to an absolute, non-empty value. Guard it: an empty
# value would let callers build root-relative paths (e.g. an `rm -rf /…`).
resolve_remote_home() {
  HOST_HOME="$(sshx 'echo "$HOME"')"
  : "${HOST_HOME:?lib-deploy-host: could not resolve the remote \$HOME}"
}

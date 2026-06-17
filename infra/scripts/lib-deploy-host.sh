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
resolve_target_host() {  # [user@host]
  TARGET_HOST="${1:-${TARGET_HOST:-${GEO_HOST:-}}}"
  [ -n "${TARGET_HOST}" ] || TARGET_HOST="$(_deploy_yml_host routing)"
  [ -n "${TARGET_HOST}" ] || {
    echo "lib-deploy-host: could not determine the target host (pass user@host or set it in deploy.yml)" >&2
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

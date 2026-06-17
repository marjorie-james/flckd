#!/usr/bin/env bash
#
# Pre-deploy host preflight — fast, READ-ONLY checks that catch the environmental
# problems which otherwise surface as a cryptic "target failed to become healthy"
# 30s into `kamal setup`/`kamal deploy`.
#
# The headline check is container DNS. kamal-proxy resolves the app container by
# name/ID and health-checks it; if the host hands containers an unreachable
# upstream resolver (e.g. an IPv6-only nameserver on a box with no IPv6 egress),
# that lookup fails with "network is unreachable" and the deploy aborts while the
# app itself is perfectly healthy. We reproduce the proxy's situation with a
# throwaway container and fail fast with the fix instead of letting you burn a
# 30s health timeout chasing a ghost.
#
# READ-ONLY: runs only `docker run --rm busybox …` probes; changes nothing. Safe
# to run any time, and wired (soft, non-fatal) into bin/kamal-docker before
# setup/deploy. Set PREFLIGHT=skip there to bypass.
#
# Usage:
#   infra/scripts/preflight-host.sh [user@host]
#     - host defaults to the routing accessory host parsed from backend/config/deploy.yml
#     - exit 0 = all good; exit 1 = a check failed (message says what to do)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"               # -> infra/
REPO="$(cd "${ROOT}/.." && pwd)"
DEPLOY_YML="${DEPLOY_YML:-${REPO}/backend/config/deploy.yml}"
# shellcheck source=infra/scripts/lib-deploy-host.sh
. "${ROOT}/scripts/lib-deploy-host.sh"

resolve_target_host "${1:-${GEO_HOST:-}}"
echo "==> Preflight on ${TARGET_HOST}"

fail=0

# 1. Docker reachable over SSH at all.
if ! sshx "docker version --format '{{.Server.Version}}'" >/dev/null 2>&1; then
  echo "    FAIL: cannot reach Docker on the host over SSH." >&2
  echo "          Check SSH access + that Docker is installed and running." >&2
  exit 1
fi

# 2. Container DNS — the canary for the IPv6-resolver / host-egress trap. A
#    default-bridge container inherits the host's resolver setup, exactly like a
#    misconfigured kamal-proxy does, so this reproduces the proxy's failure mode.
echo "    [dns] resolving an external name from a throwaway container…"
if sshx "docker run --rm busybox nslookup -type=a cloudflare.com >/dev/null 2>&1"; then
  echo "    [dns] OK"
else
  fail=1
  echo "    [dns] FAIL: a container cannot resolve DNS." >&2
  echo "          This is the #1 cause of 'target failed to become healthy': the host's" >&2
  echo "          upstream resolver is unreachable from containers (often an IPv6-only" >&2
  echo "          nameserver with no IPv6 egress)." >&2
  echo "          Fix: infra/scripts/bootstrap-host.sh ${TARGET_HOST}" >&2
  echo "          (pins Docker to an IPv4 resolver via /etc/docker/daemon.json)." >&2
fi

# 3. Caddy edge owns :80/:443? Then kamal-proxy must run no-publish. We don't fail
#    on this (a standalone, no-Caddy deploy legitimately publishes), just warn if
#    the edge is up but deploy.yml still wants the proxy to grab the ports.
if sshx "docker ps --format '{{.Names}}' | grep -qx flckd-caddy" 2>/dev/null; then
  if ! grep -A6 '^proxy:' "${DEPLOY_YML}" | grep -qE '^\s*run:'; then
    echo "    [proxy] WARN: flckd-caddy is on :80/:443 but deploy.yml proxy has no 'run:'" >&2
    echo "            block — kamal-proxy may try to publish those ports and collide." >&2
    echo "            Add 'proxy.run.publish: false' (see docs/runbooks/frontend-caddy.md)." >&2
  else
    echo "    [proxy] OK: edge present and deploy.yml sets proxy.run (no-publish path)."
  fi
fi

if [ "${fail}" -ne 0 ]; then
  echo "==> Preflight FAILED — fix the above before deploying." >&2
  exit 1
fi
echo "==> Preflight OK."

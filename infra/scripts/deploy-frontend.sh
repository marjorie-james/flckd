#!/usr/bin/env bash
#
# Deploy the static frontend + the Caddy single-origin edge onto the VPS.
#
# Architecture (see docs/runbooks/frontend-caddy.md): Caddy is the public edge on
# :80/:443. It serves the static bundle and reverse-proxies same-origin /api and
# /tiles to the backend services over the `kamal` Docker network, so the whole app
# is one origin (no CORS; the route never leaves our box, FR-012a). Kamal-proxy
# stays behind Caddy for zero-downtime backend deploys.
#
# This script: (1) builds the frontend if needed, (2) streams dist/ + the
# Caddyfile to the host, (3) boots or reloads the Caddy container. dist is served
# from a host bind mount, so a frontend-only update is just a re-sync + reload —
# no rebuild of anything else. Idempotent and re-runnable.
#
# Config comes from backend/.kamal/frontend.env (gitignored; see .example):
#   FLCKD_DOMAIN  apex domain (flckd.com)
#   ACME_EMAIL    Let's Encrypt contact
#   API_HOST      Host header kamal-proxy routes the backend on (deploy.yml proxy.host)
#
# Usage: infra/scripts/deploy-frontend.sh [user@host]   (host defaults to deploy.yml)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"      # -> infra/
REPO="$(cd "${ROOT}/.." && pwd)"
DEPLOY_YML="${DEPLOY_YML:-${REPO}/backend/config/deploy.yml}"
DIST="${REPO}/frontend/dist"
CADDYFILE="${ROOT}/caddy/Caddyfile"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2}"

# ── Config ───────────────────────────────────────────────────────────────────
FRONTEND_ENV="${FRONTEND_ENV:-${REPO}/backend/.kamal/frontend.env}"
# shellcheck source=/dev/null
[ -f "${FRONTEND_ENV}" ] && source "${FRONTEND_ENV}"
: "${FLCKD_DOMAIN:?set FLCKD_DOMAIN (backend/.kamal/frontend.env or env)}"
: "${ACME_EMAIL:?set ACME_EMAIL}"
API_HOST="${API_HOST:-$(awk '/^[[:space:]]*proxy:/{f=1} f&&/host:/{print $2; exit}' "${DEPLOY_YML}")}"
: "${API_HOST:?could not determine API_HOST (deploy.yml proxy.host)}"

# ── Target host (mirror provision-geo-host.sh) ───────────────────────────────
GEO_HOST="${1:-${GEO_HOST:-}}"
[ -n "${GEO_HOST}" ] || GEO_HOST="$(awk '/^[[:space:]]*routing:/{f=1} f&&/host:/{print $2; exit}' "${DEPLOY_YML}")"
[ -n "${GEO_HOST}" ] || { echo "deploy-frontend: could not determine host (pass user@host)" >&2; exit 1; }
if [ "${GEO_HOST}" = "${GEO_HOST#*@}" ]; then
  SSH_USER="${SSH_USER:-$(awk '/^ssh:/{f=1} f&&/user:/{print $2; exit}' "${DEPLOY_YML}")}"
  GEO_HOST="${SSH_USER:-deploy}@${GEO_HOST}"
fi
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes)
sshx() { ssh "${SSH_OPTS[@]}" "${GEO_HOST}" "$@"; }

echo "==> Deploying frontend + Caddy edge to ${GEO_HOST}"
echo "    domain: ${FLCKD_DOMAIN} (www → apex)   api host: ${API_HOST}"

# ── 1. Build the frontend if dist is missing (or FORCE_BUILD=1) ──────────────
if [ "${FORCE_BUILD:-0}" = "1" ] || [ ! -f "${DIST}/index.html" ]; then
  echo "==> [1/3] Building frontend (container toolchain)…"
  docker compose -f "${ROOT}/docker-compose.yml" run --rm --no-deps frontend \
    sh -c 'pnpm install --frozen-lockfile && pnpm build'
else
  echo "==> [1/3] Using existing build at frontend/dist (FORCE_BUILD=1 to rebuild)."
fi

# ── 2. Stream dist + Caddyfile to the host ───────────────────────────────────
HOST_HOME="$(sshx 'echo "$HOME"')"
: "${HOST_HOME:?deploy-frontend: could not resolve the remote \$HOME — refusing to use a root-relative path}"
DIST_DIR="${HOST_HOME%/}/flckd-frontend/dist"
CADDY_DIR="${HOST_HOME%/}/flckd-caddy"
echo "==> [2/3] Streaming dist/ (${DIST_DIR}) and Caddyfile…"
sshx "mkdir -p '${DIST_DIR}' '${CADDY_DIR}'"
# Extract into a staging dir first so a failed transfer never empties the live
# dist; then swap by CONTENTS (not by replacing the directory). A running Caddy
# bind-mounts ${DIST_DIR}, so replacing the directory inode would leave it serving
# the old files until restart — clearing + copying into the same inode is seen live.
sshx "rm -rf '${DIST_DIR}.new' && mkdir -p '${DIST_DIR}.new'"
tar -C "${DIST}" -czf - . | sshx "tar -C '${DIST_DIR}.new' -xzf -"
sshx "find '${DIST_DIR}' -mindepth 1 -delete && cp -a '${DIST_DIR}.new/.' '${DIST_DIR}/' && rm -rf '${DIST_DIR}.new'"
tar -C "$(dirname "${CADDYFILE}")" -czf - "$(basename "${CADDYFILE}")" | sshx "tar -C '${CADDY_DIR}' -xzf -"

# ── 3. Boot or reload Caddy ──────────────────────────────────────────────────
echo "==> [3/3] Booting/reloading Caddy…"
if sshx "docker ps --format '{{.Names}}' | grep -qx flckd-caddy"; then
  # Update the running edge in place (certs + listeners stay up).
  sshx "docker cp '${CADDY_DIR}/Caddyfile' flckd-caddy:/etc/caddy/Caddyfile && \
    docker exec -e FLCKD_DOMAIN='${FLCKD_DOMAIN}' -e ACME_EMAIL='${ACME_EMAIL}' -e API_HOST='${API_HOST}' \
      flckd-caddy caddy reload --config /etc/caddy/Caddyfile"
  echo "    reloaded."
else
  sshx "docker rm -f flckd-caddy 2>/dev/null; docker run -d --name flckd-caddy --restart unless-stopped \
    --network kamal -p 80:80 -p 443:443 \
    -e FLCKD_DOMAIN='${FLCKD_DOMAIN}' -e ACME_EMAIL='${ACME_EMAIL}' -e API_HOST='${API_HOST}' \
    -v '${DIST_DIR}:/srv/dist:ro' \
    -v '${CADDY_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro' \
    -v flckd-caddy-data:/data -v flckd-caddy-config:/config \
    ${CADDY_IMAGE}"
  echo "    booted."
fi

echo "==> Done. Caddy is the edge on ${FLCKD_DOMAIN}; it auto-provisions TLS once DNS resolves to this host."

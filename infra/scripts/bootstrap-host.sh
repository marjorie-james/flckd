#!/usr/bin/env bash
#
# One-time host bootstrap — run ONCE per Kamal host before the first `kamal setup`.
#
# Today this fixes the one environmental gotcha that bit a fresh VPS deploy: some
# providers (seen on Vultr) ship /etc/resolv.conf with an IPv6-only upstream
# resolver that Docker containers cannot reach. The failure is brutal to diagnose
# — `kamal setup` aborts with "target failed to become healthy", the app looks
# perfectly fine, and only the kamal-proxy logs reveal the real cause:
#
#   Healthcheck failed ... lookup <container> on [2001:...::6]:53:
#   dial udp [2001:...::6]:53: connect: network is unreachable
#
# kamal-proxy can't resolve the app container because its DNS escapes to an
# unreachable upstream. The fix is to pin the Docker daemon to a reachable IPv4
# resolver, which Docker then injects into containers (and uses as the embedded-DNS
# forwarder) in place of the host's unusable IPv6 nameserver.
#
# This script merges {"dns": [...]} into /etc/docker/daemon.json on the host
# (preserving any existing keys) and restarts Docker ONLY if the file changed.
# It is IDEMPOTENT: a no-op once the resolver is already set.
#
# WARNING: restarting Docker bounces every container on the host. That's why this
# is a *bootstrap* step — run it before `kamal setup`, when nothing is running yet.
# On a host that's already serving, schedule the restart in a maintenance window
# (or set DOCKER_DNS and apply the daemon.json change by hand).
#
# Usage:
#   infra/scripts/bootstrap-host.sh [user@host]
#     - host defaults to the routing accessory host parsed from backend/config/deploy.yml
#     - DOCKER_DNS overrides the resolvers (default "1.1.1.1 8.8.8.8")
#     - requires sudo on the host (key-only, non-interactive: passwordless sudo,
#       or run the printed commands yourself)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"               # -> infra/
REPO="$(cd "${ROOT}/.." && pwd)"
DEPLOY_YML="${DEPLOY_YML:-${REPO}/backend/config/deploy.yml}"
# shellcheck source=infra/scripts/lib-deploy-host.sh
. "${ROOT}/scripts/lib-deploy-host.sh"

# Resolvers to pin. IPv4 so they're reachable from the default Docker bridge even
# when the host has no working IPv6 egress.
read -r -a DNS_SERVERS <<<"${DOCKER_DNS:-1.1.1.1 8.8.8.8}"

resolve_target_host "${1:-${GEO_HOST:-}}"
echo "==> Bootstrapping Docker DNS on ${TARGET_HOST} (resolvers: ${DNS_SERVERS[*]})"

# Build the JSON array of resolvers ("1.1.1.1", "8.8.8.8").
_dns_json=""
for s in "${DNS_SERVERS[@]}"; do _dns_json="${_dns_json:+${_dns_json}, }\"${s}\""; done

# Merge on the host with python3 (present on the Debian/Ubuntu images Docker runs
# on): load daemon.json if it exists, set "dns", write back only when it changed,
# and report CHANGED/UNCHANGED so we restart Docker only when needed. We never
# clobber other keys the operator may have set.
remote_merge=$(cat <<PY
import json, os, sys
path = "/etc/docker/daemon.json"
want = [${_dns_json}]
try:
    with open(path) as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
except ValueError:
    sys.stderr.write("daemon.json exists but is not valid JSON — refusing to overwrite; fix it by hand\n")
    sys.exit(2)
if cfg.get("dns") == want:
    print("UNCHANGED")
    sys.exit(0)
cfg["dns"] = want
os.makedirs("/etc/docker", exist_ok=True)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("CHANGED")
PY
)

echo "==> Merging dns into /etc/docker/daemon.json (sudo)…"
result="$(sshx "sudo python3 - <<'EOF'
${remote_merge}
EOF")"
echo "    ${result}"

if [ "${result}" = "CHANGED" ]; then
  echo "==> daemon.json changed — restarting Docker (this bounces all containers)…"
  sshx "sudo systemctl restart docker"
  echo "    Docker restarted."
else
  echo "    Docker DNS already pinned — nothing to do."
fi

echo "==> Verifying a container can resolve + reach its resolver…"
if sshx "docker run --rm busybox sh -c 'nslookup -type=a cloudflare.com >/dev/null 2>&1'"; then
  echo "    OK: container DNS works."
else
  echo "    WARN: a throwaway container still cannot resolve. Check host egress/firewall." >&2
fi

echo "==> Host bootstrap done for ${TARGET_HOST}. Safe to run \`kamal setup\` now."

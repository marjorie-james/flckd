#!/usr/bin/env bash
#
# Vultr Option B (docs/runbooks/vultr-whole-us.md sec 2.2), automated.
#
# Format + mount the attached NVMe block volume and point Docker's data-root at
# it BEFORE Docker is installed, so the whole-US Nominatim import (250-350 GB)
# lands on the big NVMe block volume instead of the small bundled disk - the #1
# failure mode the runbook warns about.
#
# Runs as a Vultr "boot" startup script, so it MUST be idempotent (re-runs on
# every boot) and MUST NOT reformat a volume that already holds data.
set -euo pipefail

DEVICE="${BLOCK_DEVICE:-/dev/vdb}" # Vultr attaches block storage as /dev/vdb
MOUNT="/mnt/blockstore"
DOCKER_ROOT="${MOUNT}/docker"

log() { echo "[mount-docker-volume] $*"; }

# 1. Wait for the attached block device (attach can lag the first boot).
for _ in $(seq 1 30); do
  [ -b "$DEVICE" ] && break
  log "waiting for $DEVICE ..."
  sleep 5
done
if [ ! -b "$DEVICE" ]; then
  log "ERROR: $DEVICE never appeared - is the block volume attached? (see README)"
  exit 1
fi

# 2. Format ONCE. Guard on an existing filesystem so a reboot never wipes data.
if ! blkid "$DEVICE" >/dev/null 2>&1; then
  log "no filesystem on $DEVICE - creating ext4 (first run)"
  mkfs.ext4 -F "$DEVICE"
else
  log "$DEVICE already has a filesystem - skipping mkfs"
fi

# 3. Persist the mount by UUID (device names can renumber across reboots).
mkdir -p "$MOUNT"
UUID="$(blkid -s UUID -o value "$DEVICE")"
if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=${UUID} ${MOUNT} ext4 defaults,nofail 0 2" >>/etc/fstab
  log "added fstab entry for UUID=${UUID}"
fi
mountpoint -q "$MOUNT" || mount "$MOUNT"

# 4. Point Docker's data-root at the volume. Merge-preserve existing keys so a
#    later infra/scripts/bootstrap-host.sh {"dns":...} write (or vice-versa)
#    does not clobber this, and this does not clobber that.
mkdir -p "$DOCKER_ROOT" /etc/docker
python3 - "$DOCKER_ROOT" <<'PY'
import json, os, sys
path = "/etc/docker/daemon.json"
root = sys.argv[1]
cfg = {}
if os.path.exists(path):
    try:
        cfg = json.load(open(path))
    except ValueError:
        cfg = {}
if cfg.get("data-root") != root:
    cfg["data-root"] = root
    json.dump(cfg, open(path, "w"), indent=2)
    print("[mount-docker-volume] set data-root ->", root)
else:
    print("[mount-docker-volume] data-root already", root)
PY

# 5. If Docker is already installed AND running on the OLD root, migrate once and
#    restart. On a fresh Terraform box Docker is not installed yet (Kamal installs
#    it later and uses data-root from the start), so this is usually a no-op.
if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
  cur="$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo '')"
  if [ "$cur" != "$DOCKER_ROOT" ] && [ -d /var/lib/docker ] && [ -z "$(ls -A "$DOCKER_ROOT" 2>/dev/null)" ]; then
    log "migrating existing Docker data-root $cur -> $DOCKER_ROOT"
    systemctl stop docker
    rsync -aP /var/lib/docker/ "$DOCKER_ROOT/"
    systemctl start docker
  fi
fi

log "done - Docker data-root -> $DOCKER_ROOT on $DEVICE (mounted at $MOUNT)"

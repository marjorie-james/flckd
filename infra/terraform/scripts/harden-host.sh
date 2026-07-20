#!/usr/bin/env bash
#
# Host hardening - complements the Vultr network firewall (vultr_firewall_group
# in main.tf) with OS-level defenses. Runs as part of the combined Vultr "boot"
# startup script (assembled in main.tf), so it MUST be IDEMPOTENT and boot-safe:
# it re-runs on every boot and must be a near no-op once applied.
#
# Scope (deliberately conservative to avoid ever locking yourself out):
#   1. sshd: key-only auth (no passwords), but KEEP key-based root login so the
#      documented `ssh root@<ip>` + infra/scripts/bootstrap-host.sh flow still
#      works (outputs.tf -> next_steps). Never disables root outright.
#   2. fail2ban: ban brute-forcers hitting sshd.
#   3. unattended-upgrades: apply security patches automatically.
#   4. sysctl: standard network-stack hardening.
#
# NOT done here: host ufw/iptables. The Vultr firewall group already filters at
# the network edge (SSH -> admin CIDRs only; 80/443 open). A second host firewall
# is redundant and a lockout hazard, so it is intentionally omitted.
#
# NOTE: this script is spliced into the boot script inside a `( ... )` subshell, so
# its `set -euo pipefail` and any `exit` are isolated to this phase and cannot
# abort the mount phase (see main.tf local.boot_script).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

log() { echo "[harden-host] $*"; }

# -- 1. SSH hardening (drop-in; base sshd_config untouched) -------------------
# Ubuntu ships /etc/ssh/sshd_config.d/50-cloud-init.conf with
# `PasswordAuthentication yes`. sshd uses FIRST-match-wins, so our drop-in must
# sort BEFORE 50-cloud-init.conf or our `PasswordAuthentication no` is ignored.
# Use a 00- prefix and remove any legacy 60- file from earlier boots.
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-flckd-hardening.conf"
mkdir -p /etc/ssh/sshd_config.d
rm -f /etc/ssh/sshd_config.d/60-flckd-hardening.conf
read -r -d '' SSHD_WANT <<'EOF' || true
# Managed by infra/terraform/scripts/harden-host.sh - do not edit by hand.
# Key-only auth. Root stays reachable BY KEY for the bootstrap flow.
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
EOF

if [ ! -f "$SSHD_DROPIN" ] || [ "$(cat "$SSHD_DROPIN")" != "$SSHD_WANT" ]; then
  printf '%s\n' "$SSHD_WANT" >"${SSHD_DROPIN}.tmp"
  # Validate the FULL merged config before adopting the drop-in - a bad sshd
  # config that survives a reload can lock you out.
  if sshd -t -f /etc/ssh/sshd_config >/dev/null 2>&1 && \
     mv "${SSHD_DROPIN}.tmp" "$SSHD_DROPIN" && \
     sshd -t >/dev/null 2>&1; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    log "sshd hardening applied + reloaded"
  else
    rm -f "${SSHD_DROPIN}.tmp" "$SSHD_DROPIN"
    log "WARN: sshd config validation failed - left sshd untouched"
  fi
else
  log "sshd hardening already in place"
fi

# -- 2. fail2ban (install once; jail sshd) ------------------------------------
if ! command -v fail2ban-client >/dev/null 2>&1; then
  log "installing fail2ban"
  apt-get update -qq && apt-get install -y -qq fail2ban || log "WARN: fail2ban install failed"
fi
JAIL="/etc/fail2ban/jail.d/flckd-sshd.local"
read -r -d '' JAIL_WANT <<'EOF' || true
# Managed by infra/terraform/scripts/harden-host.sh.
[sshd]
enabled  = true
mode     = aggressive
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
if command -v fail2ban-client >/dev/null 2>&1; then
  if [ ! -f "$JAIL" ] || [ "$(cat "$JAIL")" != "$JAIL_WANT" ]; then
    printf '%s\n' "$JAIL_WANT" >"$JAIL"
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban 2>/dev/null || true
    log "fail2ban sshd jail configured"
  else
    log "fail2ban jail already in place"
  fi
fi

# -- 3. Automatic security updates --------------------------------------------
if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
  log "installing unattended-upgrades"
  apt-get update -qq && apt-get install -y -qq unattended-upgrades || log "WARN: unattended-upgrades install failed"
fi
AUTO="/etc/apt/apt.conf.d/20flckd-auto-upgrades"
read -r -d '' AUTO_WANT <<'EOF' || true
// Managed by infra/terraform/scripts/harden-host.sh.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
if [ ! -f "$AUTO" ] || [ "$(cat "$AUTO")" != "$AUTO_WANT" ]; then
  printf '%s\n' "$AUTO_WANT" >"$AUTO"
  log "unattended security upgrades enabled"
else
  log "unattended-upgrades already configured"
fi

# -- 4. Kernel / network sysctl hardening -------------------------------------
SYSCTL="/etc/sysctl.d/60-flckd-hardening.conf"
read -r -d '' SYSCTL_WANT <<'EOF' || true
# Managed by infra/terraform/scripts/harden-host.sh.
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
EOF
if [ ! -f "$SYSCTL" ] || [ "$(cat "$SYSCTL")" != "$SYSCTL_WANT" ]; then
  printf '%s\n' "$SYSCTL_WANT" >"$SYSCTL"
  sysctl --system >/dev/null 2>&1 || true
  log "sysctl hardening applied"
else
  log "sysctl hardening already in place"
fi

log "done - host hardening complete"

#!/usr/bin/env bats
# Behavioral tests for infra/scripts/preflight.sh — the actionable, first-run
# Docker preflight (open download page when missing, auto-start + wait when
# stopped, soft low-memory warning). The bats image has no real Docker, so we
# drive everything with stubs on PATH. Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/preflight.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/preflight.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # A URL opener stub shared by all platforms; records the URL it was asked to open.
  for name in open xdg-open; do
    cat > "${BATS_TEST_TMPDIR}/bin/${name}" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/opened_urls"
exit 0
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/${name}"
  done
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# Write a `docker` stub controllable via env: DOCKER_INFO_RC governs `docker info`
# (the running check), DOCKER_MEMTOTAL feeds `docker info --format {{.MemTotal}}`.
_make_docker_stub() {
  cat > "${BATS_TEST_TMPDIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "info" ]; then
  if [ "$2" = "--format" ]; then echo "${DOCKER_MEMTOTAL:-0}"; exit 0; fi
  exit "${DOCKER_INFO_RC:-0}"
fi
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
}

# ---------------------------------------------------------------------------
# Docker missing → open the download page and return non-zero (user must act).
# (No docker stub on PATH, and the bats image ships no real Docker.)
# ---------------------------------------------------------------------------
@test "docker missing: opens the download page and fails" {
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" bash -c "
    source '${SCRIPT}'
    pf_ensure_docker
  "
  assert_failure
  assert_output --partial "isn't installed"
  run grep -F "get-docker" "${BATS_TEST_TMPDIR}/opened_urls"
  assert_success
}

# ---------------------------------------------------------------------------
# Docker installed + running + ample memory → ready (return 0), no warning.
# ---------------------------------------------------------------------------
@test "docker running with ample memory: ready, no memory warning" {
  _make_docker_stub
  # 16 GiB in bytes.
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
    DOCKER_INFO_RC=0 DOCKER_MEMTOTAL=$((16 * 1024 * 1024 * 1024)) bash -c "
    source '${SCRIPT}'
    pf_ensure_docker
  "
  assert_success
  refute_output --partial "only ~"
}

# ---------------------------------------------------------------------------
# Docker running but under the memory floor → still ready (0) but warns + gives
# the exact click-path to raise it.
# ---------------------------------------------------------------------------
@test "docker running with low memory: ready but warns with the fix" {
  _make_docker_stub
  # 3 GiB — below the 6 GiB floor.
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
    DOCKER_INFO_RC=0 DOCKER_MEMTOTAL=$((3 * 1024 * 1024 * 1024)) bash -c "
    source '${SCRIPT}'
    pf_ensure_docker
  "
  assert_success
  assert_output --partial "only ~3 GB"
  assert_output --partial "Resources"
}

# ---------------------------------------------------------------------------
# Docker installed but the daemon won't come up (and we can't auto-start it on
# this platform) → fail fast with guidance, bounded by FLCKD_DOCKER_WAIT=0.
# ---------------------------------------------------------------------------
@test "docker installed but not running and unstartable: fails with guidance" {
  _make_docker_stub
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
    DOCKER_INFO_RC=1 FLCKD_DOCKER_WAIT=0 bash -c "
    source '${SCRIPT}'
    pf_ensure_docker
  "
  assert_failure
  assert_output --partial "not running"
  assert_output --partial "re-run setup"
}

# ---------------------------------------------------------------------------
# pf_docker_mem_gib converts MemTotal bytes to whole GiB (and 0 when unknown).
# ---------------------------------------------------------------------------
@test "pf_docker_mem_gib reports whole GiB" {
  _make_docker_stub
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
    DOCKER_MEMTOTAL=$((8 * 1024 * 1024 * 1024)) bash -c "
    source '${SCRIPT}'
    pf_docker_mem_gib
  "
  assert_success
  assert_output "8"
}

# ---------------------------------------------------------------------------
# pf_wait_for_docker honors its timeout when the daemon never answers.
# ---------------------------------------------------------------------------
@test "pf_wait_for_docker times out when the daemon never answers" {
  _make_docker_stub
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" DOCKER_INFO_RC=1 bash -c "
    source '${SCRIPT}'
    pf_wait_for_docker 0
  "
  assert_failure
}

# ---------------------------------------------------------------------------
# Sourcing the script must NOT auto-run the check (only direct execution does).
# ---------------------------------------------------------------------------
@test "sourcing does not auto-run the check" {
  _make_docker_stub
  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" DOCKER_INFO_RC=1 bash -c "
    source '${SCRIPT}'
    echo SOURCED_OK
  "
  assert_success
  assert_output "SOURCED_OK"
}

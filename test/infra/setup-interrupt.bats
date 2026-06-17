#!/usr/bin/env bats
# Behavioral tests for infra/scripts/setup.sh's interrupt cleanup (_on_interrupt).
# A Ctrl-C (INT/TERM) during a long step must NOT leak the detached compose stack
# (notably the multi-hour Nominatim import) or the current step's mktemp log.
#
# These exercise the source-only seam (SETUP_SOURCE_ONLY=1): the script is SOURCED
# so its functions + the promoted _CUR_PID/_CUR_LOG/_STARTED_SERVICES vars are
# defined, but no main flow / real Docker / real signal is involved. Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/setup-interrupt.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/setup.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  # Prepend stubs (docker records its args) and a local tput/kill that record too.
  export PATH="${BATS_TEST_DIRNAME}/stubs:${BATS_TEST_TMPDIR}/bin:${PATH}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  cat > "${BATS_TEST_TMPDIR}/bin/tput" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/tput_calls"
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/tput"

  # A fixed compose file path so the recorded `docker compose ... stop` is stable.
  export COMPOSE_FILE="${BATS_TEST_TMPDIR}/docker-compose.yml"
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# _on_interrupt, with services started, stops THIS project's compose stack, removes
# the current step's temp log, and exits 130 — without ever calling `down -v`.
@test "on_interrupt stops the compose stack, removes the temp log, exits 130" {
  local log; log="$(mktemp "${BATS_TEST_TMPDIR}/curlog.XXXXXX")"
  [ -f "${log}" ]

  run bash -c "
    set -euo pipefail
    SETUP_SOURCE_ONLY=1 . '${SCRIPT}'
    _STARTED_SERVICES=1
    _CUR_LOG='${log}'
    _CUR_PID=''
    _on_interrupt
  "

  assert_failure 130
  assert_output --partial "setup interrupted"

  # The detached stack it started was stopped (and ONLY stopped — never down -v).
  run grep -F "compose -f ${COMPOSE_FILE} stop" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success
  refute_output --partial "down"

  # The current step's mktemp log was cleaned up.
  assert [ ! -f "${log}" ]
}

# When _CUR_PID is set, the running step's background job is actually killed.
# (kill is a bash builtin, so a PATH stub wouldn't shadow it — assert on the
# observable instead: a real backgrounded process is dead after the handler runs.)
@test "on_interrupt kills the current step's pid when set" {
  sleep 30 &
  local victim=$!

  run bash -c "
    SETUP_SOURCE_ONLY=1 . '${SCRIPT}'
    _STARTED_SERVICES=1
    _CUR_PID='${victim}'
    _CUR_LOG=''
    _on_interrupt
  "
  assert_failure 130

  # The handler killed it; give it a moment, then confirm it's gone.
  wait "${victim}" 2>/dev/null || true
  run kill -0 "${victim}"
  assert_failure
}

# When setup never started detached services, cleanup must NOT touch Docker
# (so an unrelated concurrent stack is left alone).
@test "on_interrupt does not stop docker when no services were started" {
  run bash -c "
    SETUP_SOURCE_ONLY=1 . '${SCRIPT}'
    _STARTED_SERVICES=''
    _CUR_PID=''
    _CUR_LOG=''
    _on_interrupt
  "
  assert_failure 130
  assert [ ! -f "${BATS_TEST_TMPDIR}/docker_calls" ]
}

# The script registers an INT/TERM trap pointing at _on_interrupt.
@test "setup.sh registers an INT/TERM interrupt trap" {
  run grep -E "trap '_on_interrupt' INT TERM" "${SCRIPT}"
  assert_success
}

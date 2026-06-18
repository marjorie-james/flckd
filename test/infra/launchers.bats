#!/usr/bin/env bats
# Behavioral tests for the double-click launchers at the repo root:
#   "Start flckd (Mac).command"   — bash; functionally exercised here
#   "Start flckd (Windows).bat"   — cmd; static assertions only (Windows-only)
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/launchers.bats

bats_load_library bats-support
bats_load_library bats-assert

REPO="${BATS_TEST_DIRNAME}/../.."
MAC="${REPO}/Start flckd (Mac).command"
WIN="${REPO}/Start flckd (Windows).bat"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
}
teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# ---------------------------------------------------------------------------
# The Mac launcher exists, is executable, and is a bash script.
# ---------------------------------------------------------------------------
@test "mac launcher exists, is executable, and is bash" {
  assert [ -f "${MAC}" ]
  assert [ -x "${MAC}" ]
  run head -1 "${MAC}"
  assert_output "#!/bin/bash"
}

# ---------------------------------------------------------------------------
# Run the Mac launcher in a throwaway repo with a stub setup.sh: it must cd to
# its own directory and hand off to ./setup.sh (passing args through).
# ---------------------------------------------------------------------------
@test "mac launcher cds to its dir and runs ./setup.sh with args" {
  cp "${MAC}" "${BATS_TEST_TMPDIR}/launch.command"
  # Stub setup.sh records the working directory and any args it received.
  cat > "${BATS_TEST_TMPDIR}/setup.sh" <<EOF
#!/usr/bin/env bash
pwd > "${BATS_TEST_TMPDIR}/ran_in"
echo "args=\$*" >> "${BATS_TEST_TMPDIR}/ran_in"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/setup.sh"

  # stdin is not a tty under `run`, so the launcher's pause is skipped.
  run bash "${BATS_TEST_TMPDIR}/launch.command" --region CA
  assert_success

  run cat "${BATS_TEST_TMPDIR}/ran_in"
  assert_line "${BATS_TEST_TMPDIR}"
  assert_line "args=--region CA"
}

# ---------------------------------------------------------------------------
# The Mac launcher self-heals a stripped executable bit on setup.sh (the ZIP
# download path drops it). It chmods before invoking, so a non-+x setup.sh runs.
# ---------------------------------------------------------------------------
@test "mac launcher restores the executable bit on setup.sh" {
  cp "${MAC}" "${BATS_TEST_TMPDIR}/launch.command"
  cat > "${BATS_TEST_TMPDIR}/setup.sh" <<EOF
#!/usr/bin/env bash
echo ran > "${BATS_TEST_TMPDIR}/marker"
EOF
  chmod -x "${BATS_TEST_TMPDIR}/setup.sh"   # simulate the ZIP-stripped bit

  run bash "${BATS_TEST_TMPDIR}/launch.command"
  assert_success
  assert [ -f "${BATS_TEST_TMPDIR}/marker" ]
}

# ---------------------------------------------------------------------------
# The Windows launcher exists and points users at the two one-click installers
# (Docker Desktop + Git for Windows), explicitly avoiding WSL, and runs setup.sh.
# ---------------------------------------------------------------------------
@test "windows launcher references the no-WSL prerequisites and setup wizard" {
  assert [ -f "${WIN}" ]
  run cat "${WIN}"
  assert_output --partial "git-scm.com/download/win"
  assert_output --partial "docs.docker.com/get-docker"
  assert_output --partial "bash.exe"
  assert_output --partial "infra/scripts/setup.sh"
  # Makes the no-WSL promise explicit for the reader.
  assert_output --partial "WSL"
}

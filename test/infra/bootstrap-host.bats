#!/usr/bin/env bats
# Behavioral tests for infra/scripts/bootstrap-host.sh — focused on the DOCKER_DNS
# validation that gates the root-run Python heredoc (a crafted DOCKER_DNS would
# otherwise inject arbitrary Python executed as root). Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/bootstrap-host.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/bootstrap-host.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  # Prepend a stub bin with an `ssh` that echoes a benign "UNCHANGED" (so the
  # script never restarts Docker and the verify step succeeds).
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
echo UNCHANGED
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/ssh"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  # A minimal deploy.yml so resolve_target_host finds a host.
  export DEPLOY_YML="${BATS_TEST_TMPDIR}/deploy.yml"
  cat > "${DEPLOY_YML}" <<'EOF'
ssh:
  user: deploy
accessories:
  routing:
    host: 10.0.0.9
EOF
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

@test "default resolvers (1.1.1.1 8.8.8.8) pass validation" {
  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "resolvers: 1.1.1.1 8.8.8.8"
}

@test "explicit valid IPv4 resolvers pass validation" {
  DOCKER_DNS="9.9.9.9 1.0.0.1" run bash "${SCRIPT}"
  assert_success
  assert_output --partial "resolvers: 9.9.9.9 1.0.0.1"
}

@test "a Python-injection payload is rejected before any SSH work" {
  DOCKER_DNS='1.1.1.1"]; import os; os.system("touch /tmp/pwned"); want=["x' \
    run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "invalid DOCKER_DNS resolver"
}

@test "a malformed (non-IPv4) resolver is rejected" {
  DOCKER_DNS="1.1.1.1 not-an-ip" run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "invalid DOCKER_DNS resolver: 'not-an-ip'"
}

@test "an empty DOCKER_DNS is rejected" {
  DOCKER_DNS=" " run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "DOCKER_DNS is empty"
}

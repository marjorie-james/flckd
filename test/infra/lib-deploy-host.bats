#!/usr/bin/env bats
# Behavioral tests for infra/scripts/lib-deploy-host.sh — the deploy.yml host
# parsing and target-host resolution shared by provision-geo-host.sh and
# deploy-frontend.sh. Pure shell (no ssh), so fully offline. Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/lib-deploy-host.bats

bats_load_library bats-support
bats_load_library bats-assert

LIB="${BATS_TEST_DIRNAME}/../../infra/scripts/lib-deploy-host.sh"

setup() {
  BATS_TEST_TMPDIR="$(mktemp -d)"
  export DEPLOY_YML="${BATS_TEST_TMPDIR}/deploy.yml"
  # A representative deploy.yml: bare host addresses, ssh.user, a proxy block, and
  # accessories where postgres precedes routing (so the parser must not grab the
  # earlier postgres host for `routing`).
  cat > "${DEPLOY_YML}" <<'EOF'
service: flckd-backend
ssh:
  user: deploy
servers:
  web:
    - 10.0.0.1
proxy:
  ssl: false
  host: api.example.com
accessories:
  postgres:
    host: 10.0.0.1
  routing:
    host: 10.0.0.9
EOF
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

@test "_deploy_yml_host parses the routing accessory host (not the earlier postgres host)" {
  source "${LIB}"
  run _deploy_yml_host routing
  assert_success
  assert_output "10.0.0.9"
}

@test "_deploy_yml_host parses the top-level proxy host" {
  source "${LIB}"
  run _deploy_yml_host proxy
  assert_success
  assert_output "api.example.com"
}

@test "resolve_target_host defaults to the routing host with ssh.user prepended" {
  source "${LIB}"
  resolve_target_host ""
  assert_equal "${TARGET_HOST}" "deploy@10.0.0.9"
}

@test "resolve_target_host honors an explicit user@host arg verbatim" {
  source "${LIB}"
  resolve_target_host "ops@1.2.3.4"
  assert_equal "${TARGET_HOST}" "ops@1.2.3.4"
}

@test "resolve_target_host prepends a bare arg with the ssh.user" {
  source "${LIB}"
  resolve_target_host "5.6.7.8"
  assert_equal "${TARGET_HOST}" "deploy@5.6.7.8"
}

@test "resolve_target_host lets SSH_USER override ssh.user" {
  source "${LIB}"
  SSH_USER=root resolve_target_host ""
  assert_equal "${TARGET_HOST}" "root@10.0.0.9"
}

@test "resolve_target_host falls back to 'deploy' when ssh.user is absent" {
  cat > "${DEPLOY_YML}" <<'EOF'
accessories:
  routing:
    host: 10.0.0.9
EOF
  source "${LIB}"
  resolve_target_host ""
  assert_equal "${TARGET_HOST}" "deploy@10.0.0.9"
}

@test "_deploy_yml_host echoes nothing for an absent block" {
  source "${LIB}"
  run _deploy_yml_host nonesuch
  assert_success
  assert_output ""
}

@test "resolve_target_host keeps a deploy.yml host that already carries user@" {
  cat > "${DEPLOY_YML}" <<'EOF'
ssh:
  user: deploy
accessories:
  routing:
    host: ops@10.0.0.9
EOF
  source "${LIB}"
  resolve_target_host ""
  assert_equal "${TARGET_HOST}" "ops@10.0.0.9"
}

@test "resolve_target_host fails when no host can be determined" {
  cat > "${DEPLOY_YML}" <<'EOF'
service: flckd-backend
ssh:
  user: deploy
EOF
  source "${LIB}"
  run resolve_target_host ""
  assert_failure
  assert_output --partial "could not determine the target host"
}

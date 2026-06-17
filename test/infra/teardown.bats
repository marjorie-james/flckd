#!/usr/bin/env bats
# Behavioral tests for infra/scripts/teardown.sh — specifically that --purge-region
# removes BOTH infra/.region and infra/.env (a stale infra/.env leaves a single-state
# geocoder scope that docker compose later interpolates), while the default keeps both.
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/teardown.bats

bats_load_library bats-support
bats_load_library bats-assert

REAL_SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/teardown.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  # teardown.sh derives infra/.region + infra/.env from its own location (not env),
  # so run a copy inside an isolated fake repo tree to avoid touching the real repo.
  mkdir -p "${BATS_TEST_TMPDIR}/infra/scripts"
  cp "${REAL_SCRIPT}" "${BATS_TEST_TMPDIR}/infra/scripts/teardown.sh"
  SCRIPT="${BATS_TEST_TMPDIR}/infra/scripts/teardown.sh"

  REGION_FILE="${BATS_TEST_TMPDIR}/infra/.region"
  ENV_FILE="${BATS_TEST_TMPDIR}/infra/.env"
  printf 'COUNTRY="us"\n' > "${REGION_FILE}"
  printf 'GEOCODER_REGION_STATE="iowa"\n' > "${ENV_FILE}"

  # Stub docker so the container/volume teardown no-ops (and the daemon checks pass).
  export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

@test "--purge-region removes BOTH infra/.region and infra/.env" {
  run bash "${SCRIPT}" --yes --keep-data --purge-region
  assert_success
  assert_output --partial "Removed infra/.region"
  assert_output --partial "Removed infra/.env"
  assert [ ! -f "${REGION_FILE}" ]
  assert [ ! -f "${ENV_FILE}" ]
}

@test "default (no --purge-region) keeps both infra/.region and infra/.env" {
  run bash "${SCRIPT}" --yes --keep-data
  assert_success
  assert [ -f "${REGION_FILE}" ]
  assert [ -f "${ENV_FILE}" ]
}

@test "dry-run plan mentions infra/.env under --purge-region" {
  run bash "${SCRIPT}" --dry-run --purge-region
  assert_success
  assert_output --partial "infra/.env"
  # Nothing actually removed.
  assert [ -f "${REGION_FILE}" ]
  assert [ -f "${ENV_FILE}" ]
}

@test "help text documents that --purge-region drops infra/.env" {
  run bash "${SCRIPT}" --help
  assert_success
  assert_output --partial "infra/.env"
}

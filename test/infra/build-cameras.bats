#!/usr/bin/env bats
# Behavioral tests for infra/scripts/build-cameras.sh — the empty-export floor that
# refuses to feed a zero-camera set downstream (an empty match would, on the daily
# cadence, auto-retire the ENTIRE camera set after 3 empties). Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/build-cameras.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/build-cameras.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  # Prepend the osmium stub so the script uses it (OSMIUM_MODE defaults to auto and
  # picks the host binary when present).
  export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"

  # Isolate the data dir + provide a non-empty extract so the file-exists guard passes.
  export DATA_DIR="${BATS_TEST_TMPDIR}/data"
  mkdir -p "${DATA_DIR}"
  export EXTRACT_PATH="${DATA_DIR}/extract.osm.pbf"
  printf 'dummy-extract\n' > "${EXTRACT_PATH}"
  export OUT="${DATA_DIR}/cameras.geojson"
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

@test "a normal (non-empty) export succeeds and reports the feature count" {
  OSMIUM_STUB_FEATURES=3 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "3 candidate features"
  assert [ -s "${OUT}" ]
}

@test "a zero-feature export fails closed (exit 1, no silent empty import)" {
  OSMIUM_STUB_FEATURES=0 run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "refusing to feed an empty camera set"
}

@test "ALLOW_EMPTY=1 overrides the empty-export floor" {
  OSMIUM_STUB_FEATURES=0 ALLOW_EMPTY=1 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "0 candidate features"
}

@test "MIN_CAMERA_FEATURES raises the floor (a too-small set fails)" {
  OSMIUM_STUB_FEATURES=2 MIN_CAMERA_FEATURES=5 run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "refusing to feed an empty camera set"
}

#!/usr/bin/env bats
# Behavioral tests for infra/scripts/geo-manifest.sh provenance (FIX 7): the manifest
# must reflect the actually-built region/source extract. build-geo.sh now exports
# REGION/REGION_URL from the resolved country, so a whole-US build no longer emits a
# manifest claiming hardcoded Iowa provenance (with real sha256s that `verify` passes).
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/geo-manifest.bats

bats_load_library bats-support
bats_load_library bats-assert

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  # geo-manifest.sh derives ROOT (infra/) from its own location and reads artifacts
  # relative to it, so run a copy in an isolated fake infra/ tree with dummy artifacts.
  mkdir -p "${BATS_TEST_TMPDIR}/infra/scripts"
  cp "${BATS_TEST_DIRNAME}/../../infra/scripts/geo-manifest.sh" \
     "${BATS_TEST_TMPDIR}/infra/scripts/geo-manifest.sh"
  SCRIPT="${BATS_TEST_TMPDIR}/infra/scripts/geo-manifest.sh"

  INFRA="${BATS_TEST_TMPDIR}/infra"
  mkdir -p "${INFRA}/data" "${INFRA}/routing/data" "${INFRA}/tiles/data"
  printf 'pbf\n'  > "${INFRA}/data/extract.osm.pbf"
  printf 'json\n' > "${INFRA}/routing/data/valhalla.json"
  printf 'tar\n'  > "${INFRA}/routing/data/valhalla_tiles.tar"
  printf 'tiles\n'> "${INFRA}/tiles/data/tiles.pmtiles"

  export BUILD_DIR="${INFRA}/build"
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

@test "a whole-US build records US provenance, not iowa" {
  REGION="us" \
  REGION_URL="https://download.geofabrik.de/north-america/us-latest.osm.pbf" \
    run bash "${SCRIPT}" generate
  assert_success
  run cat "${BUILD_DIR}/manifest.json"
  assert_output --partial '"region": "us"'
  assert_output --partial 'us-latest.osm.pbf'
  refute_output --partial 'iowa'
}

@test "without REGION/REGION_URL it falls back to the legacy iowa default (documents the gap build-geo.sh closes)" {
  run bash "${SCRIPT}" generate
  assert_success
  run cat "${BUILD_DIR}/manifest.json"
  assert_output --partial '"region": "iowa"'
}

#!/usr/bin/env bats
# Behavioral tests for infra/scripts/fetch-extract.sh (country-aware extract).
# Run via Docker (no local install needed):
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/fetch-extract.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/fetch-extract.sh"

setup() {
  # Prepend stubs so they shadow real curl.
  export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"

  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  # Isolate from the repo's real infra/.region (legacy single-state config).
  export REGION_CONFIG="${BATS_TEST_TMPDIR}/.region"

  # Isolate the download target away from the repo's infra/data.
  export DATA_DIR="${BATS_TEST_TMPDIR}/data"
  mkdir -p "${DATA_DIR}"

  export CURL_STUB_FAIL=0
  # No TIGER fixture — the curl stub writes a dummy extract file for any -o.
  unset TIGER_BUNDLE_FIXTURE || true
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR}"
}

# ---------------------------------------------------------------------------
# US1 — Default/explicit US targets the whole-US Geofabrik extract
# ---------------------------------------------------------------------------

@test "country_unset_defaults_to_the_whole_us_extract" {
  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "north-america/us-latest.osm.pbf"

  # The extract and its URL marker were written.
  assert [ -s "${DATA_DIR}/extract.osm.pbf" ]
  assert [ -f "${DATA_DIR}/extract.osm.pbf.url" ]
  run cat "${DATA_DIR}/extract.osm.pbf.url"
  assert_output --partial "us-latest.osm.pbf"
}

@test "explicit_country_us_targets_the_whole_us_extract" {
  COUNTRY=us run bash "${SCRIPT}"
  assert_success
  assert_output --partial "north-america/us-latest.osm.pbf"
}

# ---------------------------------------------------------------------------
# US1 — Unknown country fails fast with an actionable error (FR-009)
# ---------------------------------------------------------------------------

@test "unknown_country_fails_fast_even_with_region_url_override" {
  # Even with a REGION_URL override, an unknown country is rejected — the
  # override redirects WHERE we download, not WHETHER the country is supported.
  COUNTRY=fr REGION_URL="http://stub.invalid/x.osm.pbf" run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "unknown or un-provisioned country"
  assert [ ! -s "${DATA_DIR}/extract.osm.pbf" ]
}

# ---------------------------------------------------------------------------
# Dev override: REGION_URL points the download at a sub-region extract
# ---------------------------------------------------------------------------

@test "region_url_override_redirects_the_download_for_a_supported_country" {
  COUNTRY=us REGION_URL="https://download.geofabrik.de/north-america/us/california-latest.osm.pbf" \
    run bash "${SCRIPT}"
  assert_success
  assert_output --partial "california-latest.osm.pbf"
}

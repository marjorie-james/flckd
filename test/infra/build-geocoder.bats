#!/usr/bin/env bats
# Behavioral tests for infra/scripts/build-geocoder.sh
# Run via Docker (no local install needed):
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/build-geocoder.bats

# bats_load_library searches BATS_LIB_PATH (set by bats-core/bats-action in CI;
# set to the Homebrew lib dir on macOS when installed via brew install bats-support bats-assert).
bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/build-geocoder.sh"

setup() {
  # Prepend stubs so they shadow real curl/docker
  export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"

  # Isolate all filesystem side-effects to a per-test temp dir
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  # Isolate from the repo's real infra/.region (legacy single-state config).
  export REGION_CONFIG="${BATS_TEST_TMPDIR}/.region"

  # The script writes/reads this state's county CSVs here
  export TIGER_HOST_DIR="${BATS_TEST_TMPDIR}/tiger"
  mkdir -p "${TIGER_HOST_DIR}"

  # Default config: the US country build (all counties, TIGER applies).
  export COUNTRY=us
  export YEAR=2024

  # Build a tiny preprocessed-bundle fixture with counties across TWO state FIPS
  # (19001 = Iowa, 20001 = Kansas), to prove a whole-country build keeps ALL
  # counties across multiple FIPS rather than a single state's.
  local fix="${BATS_TEST_TMPDIR}/fixsrc"
  mkdir -p "${fix}"
  printf 'segment,data\n' > "${fix}/19001.csv"
  printf 'segment,data\n' > "${fix}/20001.csv"
  ( cd "${fix}" && tar czf "${BATS_TEST_TMPDIR}/bundle.tar.gz" 19001.csv 20001.csv )
  export TIGER_BUNDLE_FIXTURE="${BATS_TEST_TMPDIR}/bundle.tar.gz"
  export TIGER_BUNDLE_URL="http://stub.invalid/bundle.tar.gz"  # stub ignores the URL

  # Defaults: download succeeds, geocoder healthy
  export CURL_STUB_FAIL=0
  export GEOCODER_HEALTHY=1
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR}"
}

# ---------------------------------------------------------------------------
# US1 — Whole-country setup: download bundle, extract ALL counties, import
# ---------------------------------------------------------------------------

@test "bundle_download_extracts_all_counties_across_fips_then_imports" {
  run bash "${SCRIPT}"
  assert_success

  # ALL counties kept — across BOTH state FIPS (19xxx and 20xxx), not one state.
  assert [ -f "${TIGER_HOST_DIR}/19001.csv" ]
  assert [ -f "${TIGER_HOST_DIR}/20001.csv" ]

  # The streamed bundle temp file is cleaned up
  assert [ ! -f "${TIGER_HOST_DIR}/.tiger-bundle.tar.gz" ]

  # The bundle download sends a descriptive User-Agent — nominatim.org's CDN
  # rejects curl's default UA with HTTP 403.
  assert [ -f "${BATS_TEST_TMPDIR}/curl_calls" ]
  run grep -q "flckd-setup" "${BATS_TEST_TMPDIR}/curl_calls"
  assert_success

  # Import was invoked
  assert [ -f "${BATS_TEST_TMPDIR}/docker_calls" ]
  run grep -q "nominatim add-data" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success

  # TIGER lookups are activated in BOTH the search frontend (--website) and the
  # SQL functions (--functions) — the latter builds the address rollup, without
  # which house numbers resolve but render a blank display_name.
  run grep -q "nominatim refresh --website --functions" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success

  # Stray numeric word tokens that would shadow house numbers are cleared
  run grep -q "DELETE FROM word" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success

  # Wikipedia importance is loaded + recomputed so place ranking is sane
  # (a county must not outrank the city inside it)
  run grep -q "nominatim refresh --wiki-data" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success
  run grep -q "nominatim refresh --importance" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success
}

# ---------------------------------------------------------------------------
# Post-import activation runs in the right order: import THEN activation steps,
# so the flag/cleanup never run against an empty TIGER table.
# ---------------------------------------------------------------------------

@test "activation_steps_run_after_the_tiger_import" {
  run bash "${SCRIPT}"
  assert_success

  local calls="${BATS_TEST_TMPDIR}/docker_calls"
  local add_line refresh_line delete_line
  add_line=$(grep -n "nominatim add-data" "${calls}" | head -1 | cut -d: -f1)
  refresh_line=$(grep -n "nominatim refresh --website" "${calls}" | head -1 | cut -d: -f1)
  delete_line=$(grep -n "DELETE FROM word" "${calls}" | head -1 | cut -d: -f1)

  assert [ -n "${add_line}" ]
  assert [ "${refresh_line}" -gt "${add_line}" ]
  assert [ "${delete_line}" -gt "${add_line}" ]
}

# ---------------------------------------------------------------------------
# US3 — Resilient Partial Re-Runs: cached CSVs skip the download
# ---------------------------------------------------------------------------

@test "cached_csvs_skip_download_and_still_import" {
  # Pre-populate the cache; a download must NOT be attempted.
  printf 'segment,data\n' > "${TIGER_HOST_DIR}/19001.csv"
  # If the script tried to download, this would make it fail — assert_success
  # below therefore proves the download was skipped.
  export CURL_STUB_FAIL=1

  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "cached"

  run grep -q "nominatim add-data" "${BATS_TEST_TMPDIR}/docker_calls"
  assert_success
}

# ---------------------------------------------------------------------------
# US2 — Failure handling: never import on a failed download
# ---------------------------------------------------------------------------

@test "download_failure_aborts_before_import" {
  export CURL_STUB_FAIL=1

  run bash "${SCRIPT}"
  assert_failure
  if [ -f "${BATS_TEST_TMPDIR}/docker_calls" ]; then
    run grep -q "nominatim add-data" "${BATS_TEST_TMPDIR}/docker_calls"
    assert_failure
  fi
}

# ---------------------------------------------------------------------------
# US4 — Pre-flight: never import against an unhealthy geocoder
# ---------------------------------------------------------------------------

@test "unhealthy_geocoder_skips_import" {
  export GEOCODER_HEALTHY=0

  run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "not healthy"
  if [ -f "${BATS_TEST_TMPDIR}/docker_calls" ]; then
    run grep -q "nominatim add-data" "${BATS_TEST_TMPDIR}/docker_calls"
    assert_failure
  fi
}

# ---------------------------------------------------------------------------
# US1 — tiger:false country: skip the TIGER import entirely (no download/import)
# ---------------------------------------------------------------------------

@test "tiger_false_country_skips_the_whole_import" {
  # Simulate a country whose registry marks tiger:false (none exist at launch,
  # so use the documented test override).
  export TIGER_APPLICABLE=false

  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "does not apply"

  # No download and no import were attempted.
  assert [ ! -f "${BATS_TEST_TMPDIR}/curl_calls" ]
  if [ -f "${BATS_TEST_TMPDIR}/docker_calls" ]; then
    run grep -q "nominatim add-data" "${BATS_TEST_TMPDIR}/docker_calls"
    assert_failure
  fi
}

# ---------------------------------------------------------------------------
# US1 — fail fast on an unknown / un-provisioned country (FR-009)
# ---------------------------------------------------------------------------

@test "unknown_country_fails_fast_before_any_import" {
  export COUNTRY=zz

  run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "unknown or un-provisioned country"
  assert [ ! -f "${BATS_TEST_TMPDIR}/curl_calls" ]
}

# ---------------------------------------------------------------------------
# Dev override — a single-state build (STATE_FIPS set, COUNTRY unset) narrows
# TIGER to just that state, not the whole-US ~3,200-county bundle.
# ---------------------------------------------------------------------------

@test "single_state_dev_build_extracts_only_that_states_counties" {
  unset COUNTRY
  export STATE_FIPS=19
  export REGION_LABEL="Iowa"

  run bash "${SCRIPT}"
  assert_success

  # Only the in-state county (19001) is kept; the out-of-state one (20001) is not.
  assert [ -f "${TIGER_HOST_DIR}/19001.csv" ]
  assert [ ! -f "${TIGER_HOST_DIR}/20001.csv" ]
}

# ---------------------------------------------------------------------------
# DOWNLOAD_ONLY — the prefetch primitive build-geo.sh runs in the background:
# fetch + extract the CSVs, then STOP (no geocoder health check, no import).
# ---------------------------------------------------------------------------

@test "download_only_caches_csvs_and_skips_the_import" {
  export DOWNLOAD_ONLY=1

  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "DOWNLOAD_ONLY"

  # Country (us) → all counties downloaded and cached…
  assert [ -f "${TIGER_HOST_DIR}/19001.csv" ]
  assert [ -f "${TIGER_HOST_DIR}/20001.csv" ]

  # …but NO import was attempted, and the geocoder health check never ran.
  if [ -f "${BATS_TEST_TMPDIR}/docker_calls" ]; then
    run grep -q "nominatim add-data" "${BATS_TEST_TMPDIR}/docker_calls"
    assert_failure
  fi
  if [ -f "${BATS_TEST_TMPDIR}/curl_calls" ]; then
    run grep -q "status.php" "${BATS_TEST_TMPDIR}/curl_calls"
    assert_failure
  fi
}

@test "download_only_skips_when_country_has_no_tiger" {
  export DOWNLOAD_ONLY=1 TIGER_APPLICABLE=false

  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "does not apply"
  assert [ ! -f "${BATS_TEST_TMPDIR}/curl_calls" ]
}

#!/usr/bin/env bats
# Behavioral tests for infra/scripts/setup.sh scope resolution.
# These exercise the dry-run seam (SETUP_DRY_RUN=1): resolve scope, write
# infra/.region + infra/.env, and exit BEFORE any Docker work — offline.
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/setup.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/setup.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  # Isolate the written config/env from the repo's real infra/.region + infra/.env.
  export REGION_CONFIG="${BATS_TEST_TMPDIR}/.region"
  export ENV_FILE="${BATS_TEST_TMPDIR}/.env"
  export SETUP_DRY_RUN=1
  # Ensure no inherited COUNTRY forces country mode for the default test.
  unset COUNTRY || true
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR}"
}

# ---------------------------------------------------------------------------
# Default (no input) → Iowa, the wizard's default selection
# ---------------------------------------------------------------------------

@test "default_is_iowa_single_state" {
  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "Selected state"
  assert_output --partial "Iowa"

  # .region carries the state fields…
  run grep -q 'STATE_FIPS="19"' "${REGION_CONFIG}"
  assert_success
  # …and .env wires the backend into single-state mode + the state's viewbox.
  run grep -q 'GEOCODER_REGION_STATE=Iowa' "${ENV_FILE}"
  assert_success
  run grep -q 'GEOCODER_VIEWBOX=-96.7,43.6,-90.0,40.3' "${ENV_FILE}"
  assert_success
}

# ---------------------------------------------------------------------------
# US is selectable → whole-country mode, framing the entire country
# ---------------------------------------------------------------------------

@test "us_selectable_via_region_token" {
  run bash "${SCRIPT}" --region US
  assert_success
  assert_output --partial "Configured country"
  run grep -q 'COUNTRY="us"' "${REGION_CONFIG}"
  assert_success
  run grep -q 'GEOCODER_COUNTRY=us' "${ENV_FILE}"
  assert_success
  # No single-state viewbox in country mode (whole-country framing).
  run grep -q 'GEOCODER_VIEWBOX=$' "${ENV_FILE}"
  assert_success
}

@test "us_selectable_via_country_flag" {
  run bash "${SCRIPT}" --country us
  assert_success
  assert_output --partial "United States"
  run grep -q 'GEOCODER_COUNTRY=us' "${ENV_FILE}"
  assert_success
}

# ---------------------------------------------------------------------------
# A specific state is selectable and writes its viewbox (turnkey framing)
# ---------------------------------------------------------------------------

@test "specific_state_writes_its_own_viewbox" {
  run bash "${SCRIPT}" --region CA
  assert_success
  assert_output --partial "California"
  run grep -q 'STATE_FIPS="06"' "${REGION_CONFIG}"
  assert_success
  run grep -q 'GEOCODER_REGION_STATE=California' "${ENV_FILE}"
  assert_success
  run grep -q 'GEOCODER_VIEWBOX=-124.4,42.0,-114.1,32.5' "${ENV_FILE}"
  assert_success
}

# ---------------------------------------------------------------------------
# Unknown scope fails fast (FR-009)
# ---------------------------------------------------------------------------

@test "unknown_country_flag_fails_fast" {
  run bash "${SCRIPT}" --country zz
  assert_failure
  assert_output --partial "unknown or un-provisioned country"
  assert [ ! -f "${ENV_FILE}" ]
}

@test "unknown_state_code_fails_fast" {
  run bash "${SCRIPT}" --region ZZ
  assert_failure
  assert_output --partial "Unknown state code"
}

# ---------------------------------------------------------------------------
# Precedence — an explicit --region beats a stray inherited COUNTRY env var
# ---------------------------------------------------------------------------

@test "explicit_region_beats_inherited_country_env" {
  COUNTRY=us run bash "${SCRIPT}" --region CA
  assert_success
  assert_output --partial "California"
  run grep -q 'STATE_FIPS="06"' "${REGION_CONFIG}"
  assert_success
  # Did NOT fall into country mode despite COUNTRY=us in the environment.
  run grep -q '^COUNTRY=' "${REGION_CONFIG}"
  assert_failure
}

@test "inherited_country_env_still_selects_country_when_no_region" {
  COUNTRY=us run bash "${SCRIPT}"
  assert_success
  assert_output --partial "Configured country"
  run grep -q 'GEOCODER_COUNTRY=us' "${ENV_FILE}"
  assert_success
}

# ---------------------------------------------------------------------------
# ETA helpers — the wizard's elapsed/remaining math (rendered in the panel).
# ---------------------------------------------------------------------------

@test "eta: formats sub-hour as M:SS and multi-hour as H:MM:SS" {
  SETUP_SELFTEST=1 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "fmt 90=1:30"
  assert_output --partial "fmt 1500=25:00"
  assert_output --partial "fmt 14400=4:00:00"
}

@test "eta: a whole-country build estimates much longer than a single state" {
  SETUP_SELFTEST=1 run bash "${SCRIPT}"            # default IA (state)
  assert_success
  assert_output --partial "scope=state"
  local state_secs
  state_secs="$(printf '%s\n' "$output" | sed -n 's/.*total=.*(\([0-9]*\)s)/\1/p')"

  SETUP_SELFTEST=1 run bash "${SCRIPT}" --country us
  assert_success
  assert_output --partial "scope=country"
  local country_secs
  country_secs="$(printf '%s\n' "$output" | sed -n 's/.*total=.*(\([0-9]*\)s)/\1/p')"

  assert [ "${country_secs}" -gt "${state_secs}" ]
}

@test "eta: import threads default to the machine's core count" {
  SETUP_SELFTEST=1 run bash "${SCRIPT}"
  assert_success
  # threads=<n> is surfaced and is a positive integer (nproc / hw.ncpu / 4).
  run grep -E "threads=[1-9][0-9]*" <<< "$output"
  assert_success
}

@test "eta: NOMINATIM_THREADS override is honored" {
  NOMINATIM_THREADS=3 SETUP_SELFTEST=1 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "threads=3"
}

@test "eta: the geocoder import overlap is credited to the remaining estimate" {
  SETUP_SELFTEST=1 run bash "${SCRIPT}"
  assert_success
  local no_ov ov
  no_ov="$(printf '%s\n' "$output" | sed -n 's/^rem_no_overlap=\([0-9]*\)$/\1/p')"
  ov="$(printf '%s\n' "$output" | sed -n 's/^rem_overlap1000=\([0-9]*\)$/\1/p')"
  # 1000s of overlapped import time comes straight off the remaining estimate.
  assert [ "$(( no_ov - ov ))" -eq 1000 ]
}

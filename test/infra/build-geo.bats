#!/usr/bin/env bats
# Behavioral tests for infra/scripts/build-geo.sh guards (the parts reachable
# offline, before any Docker work). Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/build-geo.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/build-geo.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  export REGION_CONFIG="${BATS_TEST_TMPDIR}/.region"
  # Isolate side-effect paths so plan-mode runs never touch the repo.
  export ENV_FILE="${BATS_TEST_TMPDIR}/.env"
  export LOG_DIR="${BATS_TEST_TMPDIR}/logs"
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR}"
}

# Line number of the first plan/output line matching a pattern (0 if absent).
_line_of() {
  printf '%s\n' "$output" | grep -n "$1" | head -1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# A single-state .region must be refused — build-geo.sh provisions a whole
# country; state dev builds go through setup.sh (avoids a country-scope/.env
# mismatch over a state-sized extract).
# ---------------------------------------------------------------------------

@test "refuses a single-state .region (STATE_FIPS set, no COUNTRY)" {
  cat > "${REGION_CONFIG}" <<'EOF'
REGION="iowa"
REGION_LABEL="Iowa"
REGION_URL="https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf"
STATE_FIPS="19"
EOF

  run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "single-state dev config"
  assert_output --partial "setup.sh --region"
}

@test "unknown country fails fast" {
  run env COUNTRY=zz bash "${SCRIPT}"
  assert_failure
  assert_output --partial "unknown or un-provisioned country"
}

# ---------------------------------------------------------------------------
# Orchestration (GEO_PLAN_ONLY) — verify the rate-safe parallelism plan offline:
# the geocoder OSM import starts BEFORE routing+tiles (overlap) and the TIGER
# bundle is prefetched in the background.
# ---------------------------------------------------------------------------

@test "plan: geocoder import starts before routing+tiles, with a background TIGER prefetch" {
  run env GEO_PLAN_ONLY=1 bash "${SCRIPT}"
  assert_success

  # Overlap: the geocoder start is planned ahead of the routing/tiles build.
  local geo tiles
  geo="$(_line_of 'Start geocoder OSM import now')"
  tiles="$(_line_of 'Build routing graph')"
  assert [ -n "${geo}" ]
  assert [ -n "${tiles}" ]
  assert [ "${geo}" -lt "${tiles}" ]

  # The ~1.8 GB TIGER bundle is prefetched in the background (rate-safe).
  assert_output --partial "Prefetch TIGER county CSVs in the background"
  assert_output --partial "DOWNLOAD_ONLY=1"

  # The wait step reaps that import instead of starting it cold.
  assert_output --partial "Finish the geocoder OSM import"
}

@test "plan: artifacts-only skips services, overlap, and prefetch" {
  run env GEO_PLAN_ONLY=1 GEO_ARTIFACTS_ONLY=1 bash "${SCRIPT}"
  assert_success
  assert_output --partial "artifacts-only"
  refute_output --partial "Start geocoder OSM import"
  refute_output --partial "Prefetch TIGER"
}

@test "plan: GEO_BUILD_JOBS is surfaced as the routing/tiles concurrency cap" {
  run env GEO_PLAN_ONLY=1 GEO_BUILD_JOBS=4 bash "${SCRIPT}"
  assert_success
  assert_output --partial "routing/tiles: 4"
}

@test "plan: import threads default to the machine's core count" {
  run env GEO_PLAN_ONLY=1 bash "${SCRIPT}"
  assert_success
  assert_output --partial "Nominatim import threads:"
  # default routing/tiles concurrency is uncapped (all cores)
  assert_output --partial "routing/tiles: all cores"
}

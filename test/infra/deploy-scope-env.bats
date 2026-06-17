#!/usr/bin/env bats
# Behavioral tests for infra/scripts/deploy-scope-env.sh — derives the backend's
# single-state env (GEOCODER_REGION_STATE + GEOCODER_VIEWBOX) from the production
# deploy scope. This is what makes a single-state production deploy frame the map
# on that state instead of the whole US (FR-007). It is SOURCED (exports vars).
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/deploy-scope-env.bats

bats_load_library bats-support
bats_load_library bats-assert

SCOPE_SH="${BATS_TEST_DIRNAME}/../../infra/scripts/deploy-scope-env.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  # Isolate from any real geo.env / infra/.region so tests are deterministic.
  export GEO_ENV="${BATS_TEST_TMPDIR}/geo.env.missing"
  export REGION_CONFIG="${BATS_TEST_TMPDIR}/.region.missing"
  # Make sure no inherited scope vars leak in.
  unset GEO_REGION_URL GEO_REGION_LABEL GEO_COUNTRY REGION REGION_URL REGION_LABEL COUNTRY || true
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# Source the script in a subshell and print the two derived vars on one line.
derive() { bash -c "set -euo pipefail; . '${SCOPE_SH}'; printf '%s|%s\n' \"\${GEOCODER_REGION_STATE}\" \"\${GEOCODER_VIEWBOX}\""; }

@test "per-invocation single-state URL frames that state" {
  GEO_REGION_URL="https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf" run derive
  assert_success
  assert_output "Iowa|-96.7,43.6,-90.0,40.3"
}

@test "GEO_COUNTRY=us yields whole-country (empty single-state env)" {
  GEO_COUNTRY=us run derive
  assert_success
  assert_output "|"
}

@test "reads a single-state geo.env file (canonical state name from the registry)" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf\nGEO_REGION_LABEL="New York"\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "New York|-79.8,45.0,-71.9,40.5"
}

# A stray exported REGION (or REGION_URL) must NOT override the geo.env scope:
# the extract URL is authoritative. (Regression: the token loop once tried a bare
# REGION first, so REGION=texas framed Texas while labeling it New York.)
@test "a stray inherited REGION does not override the geo.env scope" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf\nGEO_REGION_LABEL="New York"\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  REGION=texas REGION_URL=https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf \
    GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "New York|-79.8,45.0,-71.9,40.5"
}

# A stray COUNTRY/REGION must not flip a configured state deploy to whole-country.
@test "a stray inherited COUNTRY does not force whole-country over a geo.env state" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  COUNTRY=us GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "Iowa|-96.7,43.6,-90.0,40.3"
}

# The scope files are PARSED, not sourced: an unquoted multi-word label (a common
# mistake) must not abort the deploy. The state still resolves from the URL slug.
@test "an unquoted multi-word GEO_REGION_LABEL does not abort, resolves via slug" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf\nGEO_REGION_LABEL=New York\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "New York|-79.8,45.0,-71.9,40.5"
}

# An embedded command substitution in a scope file must NOT execute (parsed only).
@test "a command substitution in geo.env is not executed" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf\nGEO_REGION_LABEL=$(touch %s/PWNED)\n' \
    "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/geo.env"
  GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "Iowa|-96.7,43.6,-90.0,40.3"
  [ ! -e "${BATS_TEST_TMPDIR}/PWNED" ]
}

# The backend state NAME is the canonical registry label, never the operator's
# free-form label — so geocoding's state-token handling stays correct.
@test "a mislabeled geo.env still yields the canonical state name" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/california-latest.osm.pbf\nGEO_REGION_LABEL="The Golden State"\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "California|-124.4,42.0,-114.1,32.5"
}

@test "reads a whole-country geo.env file" {
  printf 'GEO_COUNTRY=us\n' > "${BATS_TEST_TMPDIR}/geo.env"
  GEO_ENV="${BATS_TEST_TMPDIR}/geo.env" run derive
  assert_success
  assert_output "|"
}

@test "falls back to a single-state infra/.region (dev scope)" {
  printf 'REGION="california"\nREGION_LABEL="California"\nREGION_URL="https://download.geofabrik.de/north-america/us/california-latest.osm.pbf"\nSTATE_FIPS="06"\n' \
    > "${BATS_TEST_TMPDIR}/.region"
  REGION_CONFIG="${BATS_TEST_TMPDIR}/.region" run derive
  assert_success
  assert_output "California|-124.4,42.0,-114.1,32.5"
}

@test "no scope configured at all defaults to whole-country, silently" {
  run derive
  assert_success
  assert_output "|"          # no warning line, just the empty result
}

@test "an unrecognized region warns and falls back to whole-country framing" {
  GEO_REGION_URL="https://example.com/some-county-latest.osm.pbf" run derive
  assert_success
  assert_output --partial "could not resolve a US state"
  # The derived env is still empty (whole-country), so the deploy doesn't fail.
  assert_output --partial "|"
}

# A sub-state extract URL whose slug state_resolve REJECTS must NOT be overridden
# by a free-form GEO_REGION_LABEL. The URL is authoritative (parity with
# provision-geo-host.sh's URL-slug-only built_state), so a label like California
# can no longer "rescue" an unrecognized URL into framing California — the deploy
# falls through to whole-country framing instead.
@test "a sub-state URL is not overridden by GEO_REGION_LABEL (whole-country framing)" {
  GEO_REGION_URL="https://download.geofabrik.de/north-america/us/california/los-angeles-latest.osm.pbf" \
    GEO_REGION_LABEL="California" run derive
  assert_success
  assert_output --partial "could not resolve a US state"
  # Whole-country framing: the derived single-state env is empty (the "|" line),
  # and the label California never leaks into GEOCODER_REGION_STATE.
  assert_output --partial "|"
  refute_output --partial "California|"
}

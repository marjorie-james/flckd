#!/usr/bin/env bats
# Integration test for the file-based injection path that wires the single-state
# scope into the backend: bin/kamal-docker writes .kamal/deploy-scope.env, and
# .kamal/secrets reads it (with sed) so Kamal injects GEOCODER_REGION_STATE +
# GEOCODER_VIEWBOX. deploy-scope-env.bats covers the resolver in isolation; THIS
# file covers the write+read round-trip and guards the two formats against drift.
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/deploy-scope-secrets.bats

bats_load_library bats-support
bats_load_library bats-assert

ROOT="${BATS_TEST_DIRNAME}/../.."
SCOPE_SH="${ROOT}/infra/scripts/deploy-scope-env.sh"
SECRETS_EXAMPLE="${ROOT}/backend/.kamal/secrets.example"
KAMAL_DOCKER="${ROOT}/backend/bin/kamal-docker"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  unset GEO_REGION_URL GEO_REGION_LABEL GEO_COUNTRY REGION REGION_URL REGION_LABEL COUNTRY || true
}
teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# Resolve the scope, write the file EXACTLY as kamal-docker does, then extract
# EXACTLY as .kamal/secrets does (sed | tr), and echo the round-tripped values.
roundtrip() {  # <geo_env>
  local dir; dir="${BATS_TEST_TMPDIR}/rt"; mkdir -p "${dir}/.kamal"
  ( export GEO_ENV="$1" REGION_CONFIG=/nonexistent
    . "${SCOPE_SH}"
    printf 'GEOCODER_REGION_STATE=%s\n' "${GEOCODER_REGION_STATE:-}"
    printf 'GEOCODER_VIEWBOX=%s\n' "${GEOCODER_VIEWBOX:-}"
  ) > "${dir}/.kamal/deploy-scope.env"
  local state viewbox
  state="$(cd "${dir}" && sed -n 's/^GEOCODER_REGION_STATE=//p' .kamal/deploy-scope.env 2>/dev/null | tr -d '\n')"
  viewbox="$(cd "${dir}" && sed -n 's/^GEOCODER_VIEWBOX=//p' .kamal/deploy-scope.env 2>/dev/null | tr -d '\n')"
  printf '%s|%s' "${state}" "${viewbox}"
}

@test "round-trips a single state through deploy-scope.env + the secrets sed" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  assert_equal "$(roundtrip "${BATS_TEST_TMPDIR}/geo.env")" "Iowa|-96.7,43.6,-90.0,40.3"
}

@test "round-trips a multi-word state name (no truncation at the space)" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  assert_equal "$(roundtrip "${BATS_TEST_TMPDIR}/geo.env")" "New York|-79.8,45.0,-71.9,40.5"
}

@test "round-trips a whole-country deploy as empty values" {
  printf 'GEO_COUNTRY=us\n' > "${BATS_TEST_TMPDIR}/geo.env"
  assert_equal "$(roundtrip "${BATS_TEST_TMPDIR}/geo.env")" "|"
}

# Drift guards: the write format (kamal-docker) and the read format (.kamal/secrets)
# must stay aligned. A rename of either key, or a change to the file path, breaks
# injection silently in production — these catch it in CI.
@test "secrets.example reads both keys from .kamal/deploy-scope.env" {
  run grep -F "sed -n 's/^GEOCODER_REGION_STATE=//p' .kamal/deploy-scope.env" "${SECRETS_EXAMPLE}"
  assert_success
  run grep -F "sed -n 's/^GEOCODER_VIEWBOX=//p' .kamal/deploy-scope.env" "${SECRETS_EXAMPLE}"
  assert_success
}

@test "kamal-docker writes both keys into .kamal/deploy-scope.env" {
  run grep -F 'GEOCODER_REGION_STATE=%s' "${KAMAL_DOCKER}"
  assert_success
  run grep -F 'GEOCODER_VIEWBOX=%s' "${KAMAL_DOCKER}"
  assert_success
  run grep -F '.kamal/deploy-scope.env' "${KAMAL_DOCKER}"
  assert_success
}

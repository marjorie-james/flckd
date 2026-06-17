#!/usr/bin/env bats
# Cross-check that the TWO independent deploy-scope resolvers agree:
#   - infra/scripts/provision-geo-host.sh  decides WHAT geo data is BUILT on the host
#   - infra/scripts/deploy-scope-env.sh    decides WHICH region the backend FRAMES
# They re-implement the same precedence (per-invocation GEO_* > geo.env > .region).
# If they ever drift, the app would frame a region different from the one actually
# built — this fails CI before that ships. (Same spirit as country-registry.bats,
# which cross-checks the bash/ruby country mirrors.)
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/deploy-scope-cross-check.bats

bats_load_library bats-support
bats_load_library bats-assert

ROOT="${BATS_TEST_DIRNAME}/../.."
SCOPE_SH="${ROOT}/infra/scripts/deploy-scope-env.sh"
REGISTRY_SH="${ROOT}/infra/scripts/state-registry.sh"
PROVISION="${ROOT}/infra/scripts/provision-geo-host.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  unset GEO_REGION_URL GEO_REGION_LABEL GEO_COUNTRY REGION REGION_URL REGION_LABEL COUNTRY || true
}
teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# The state the BACKEND frames: the canonical label, or "US" for whole-country.
framed_state() {  # <geo_env>
  ( export GEO_ENV="$1" REGION_CONFIG=/nonexistent
    . "${SCOPE_SH}"
    if [ -n "${GEOCODER_VIEWBOX}" ]; then printf '%s' "${GEOCODER_REGION_STATE}"; else printf 'US'; fi )
}

# The state the HOST BUILD targets, derived from provision-geo-host.sh's resolved
# extract URL (via its PROVISION_GEO_SELFTEST seam): canonical label, or "US".
built_state() {  # <geo_env>
  local out url slug
  out="$(PROVISION_GEO_SELFTEST=1 GEO_ENV="$1" REGION_CONFIG=/nonexistent bash "${PROVISION}" 2>/dev/null)"
  url="$(printf '%s\n' "${out}" | sed -n 's/^REGION_URL=//p')"
  slug="${url##*/}"; slug="${slug%-latest.osm.pbf}"; slug="${slug%.osm.pbf}"
  [ "${slug}" = "us" ] && { printf 'US'; return 0; }
  ( . "${REGISTRY_SH}"; if state_resolve "${slug}" 2>/dev/null; then printf '%s' "${STATE_LABEL}"; else printf 'US'; fi )
}

@test "single-state geo.env: framed region == built region (Iowa)" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf\nGEO_REGION_LABEL=Iowa\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  assert_equal "$(framed_state "${BATS_TEST_TMPDIR}/geo.env")" "Iowa"
  assert_equal "$(built_state "${BATS_TEST_TMPDIR}/geo.env")" "Iowa"
}

@test "multi-word single-state geo.env: framed region == built region (New York)" {
  printf 'GEO_REGION_URL=https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf\nGEO_REGION_LABEL="New York"\n' \
    > "${BATS_TEST_TMPDIR}/geo.env"
  assert_equal "$(framed_state "${BATS_TEST_TMPDIR}/geo.env")" "$(built_state "${BATS_TEST_TMPDIR}/geo.env")"
  assert_equal "$(framed_state "${BATS_TEST_TMPDIR}/geo.env")" "New York"
}

@test "whole-country geo.env: both resolve to US" {
  printf 'GEO_COUNTRY=us\n' > "${BATS_TEST_TMPDIR}/geo.env"
  assert_equal "$(framed_state "${BATS_TEST_TMPDIR}/geo.env")" "US"
  assert_equal "$(built_state "${BATS_TEST_TMPDIR}/geo.env")" "US"
}

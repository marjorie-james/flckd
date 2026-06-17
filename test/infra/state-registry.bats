#!/usr/bin/env bats
# Behavioral tests for infra/scripts/state-registry.sh — the shared US state table
# (slug / FIPS / USPS / viewbox) and its state_resolve helper, used by both the dev
# wizard (setup.sh) and the single-state production deploy env (deploy-scope-env.sh).
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/state-registry.bats

bats_load_library bats-support
bats_load_library bats-assert

REGISTRY_SH="${BATS_TEST_DIRNAME}/../../infra/scripts/state-registry.sh"

@test "resolves a state by USPS code" {
  source "${REGISTRY_SH}"
  state_resolve IA
  assert_equal "${STATE_LABEL}" "Iowa"
  assert_equal "${STATE_SLUG}" "iowa"
  assert_equal "${STATE_FIPS}" "19"
  assert_equal "${STATE_VIEWBOX}" "-96.7,43.6,-90.0,40.3"
}

@test "resolves a state by 2-digit FIPS code" {
  source "${REGISTRY_SH}"
  state_resolve 06
  assert_equal "${STATE_LABEL}" "California"
  assert_equal "${STATE_VIEWBOX}" "-124.4,42.0,-114.1,32.5"
}

@test "resolves a state by Geofabrik slug (incl. multi-word)" {
  source "${REGISTRY_SH}"
  state_resolve new-york
  assert_equal "${STATE_LABEL}" "New York"
  assert_equal "${STATE_SLUG}" "new-york"
  assert_equal "${STATE_VIEWBOX}" "-79.8,45.0,-71.9,40.5"
}

@test "resolves a state by display label, case-insensitive and spaced" {
  source "${REGISTRY_SH}"
  state_resolve "new york"
  assert_equal "${STATE_LABEL}" "New York"
}

@test "is case-insensitive on the USPS code" {
  source "${REGISTRY_SH}"
  state_resolve ca
  assert_equal "${STATE_LABEL}" "California"
}

@test "fails fast on an unknown state token" {
  source "${REGISTRY_SH}"
  run state_resolve ZZ
  assert_failure
  assert_output --partial "unknown US state"
}

# Internal whitespace must NOT be collapsed: a garbled token like "I A" or "1 9"
# must error, not silently match Iowa (IA) / FIPS 19. Leading/trailing space is
# still trimmed, so " IA " resolves.
@test "internal whitespace does not collapse into a false USPS/FIPS match" {
  source "${REGISTRY_SH}"
  run state_resolve "I A"
  assert_failure
  run state_resolve "1 9"
  assert_failure
}

@test "leading/trailing whitespace is trimmed (\" IA \" resolves)" {
  source "${REGISTRY_SH}"
  state_resolve " IA "
  assert_equal "${STATE_LABEL}" "Iowa"
}

# The viewbox here is the SAME value the Ruby map-framing path parses
# (Geocoding::MapFraming reads GEOCODER_VIEWBOX). Iowa's bbox, once parsed into
# [[west,south],[east,north]], must match the value asserted in the Ruby specs —
# this guards against the two drifting.
@test "Iowa viewbox matches the bbox the Ruby map-framing spec asserts" {
  source "${REGISTRY_SH}"
  state_resolve IA
  # MapFraming spec: GEOCODER_VIEWBOX="-96.7,43.6,-90.0,40.3" -> [[-96.7,40.3],[-90.0,43.6]]
  assert_equal "${STATE_VIEWBOX}" "-96.7,43.6,-90.0,40.3"
  run grep -F -- "-96.7,43.6,-90.0,40.3" \
    "${BATS_TEST_DIRNAME}/../../backend/spec/services/geocoding/map_framing_spec.rb"
  assert_success
}

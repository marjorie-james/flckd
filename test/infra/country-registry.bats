#!/usr/bin/env bats
# Cross-checks the bash country registry (infra/scripts/country-registry.sh)
# against the Ruby source of truth (Geocoding::CountryRegistry). The two are
# hand-maintained mirrors; this fails CI if one is edited without the other.
# Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/country-registry.bats

bats_load_library bats-support
bats_load_library bats-assert

REGISTRY_SH="${BATS_TEST_DIRNAME}/../../infra/scripts/country-registry.sh"
REGISTRY_RB="${BATS_TEST_DIRNAME}/../../backend/app/services/geocoding/country_registry.rb"

@test "bash and ruby registries agree on the US record" {
  # shellcheck source=/dev/null
  source "${REGISTRY_SH}"
  country_resolve us

  # The bash extract URL, display name, and TIGER flag must all appear in the
  # Ruby registry — drift on either side fails here.
  run grep -F "${COUNTRY_EXTRACT_URL}" "${REGISTRY_RB}"
  assert_success
  run grep -F "${COUNTRY_NAME}" "${REGISTRY_RB}"
  assert_success
  assert_equal "${COUNTRY_TIGER}" "true"
  run grep -Eq "tiger:[[:space:]]*true" "${REGISTRY_RB}"
  assert_success
}

@test "bash registry fails fast on an unknown country (matches Ruby FR-009)" {
  source "${REGISTRY_SH}"
  run country_resolve zz
  assert_failure
  assert_output --partial "unknown or un-provisioned country"
}

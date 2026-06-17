#!/usr/bin/env bats
# Behavioral test for the geo-provisioning GATE in backend/bin/kamal-docker.
#
# Contract: provision-geo-host.sh (graph + tiles + geocoder import; minutes of
# work, plus an OSM extract download) must run on `setup` ONLY — never on a routine
# `deploy`, which is just the app image swap. Escape hatches: GEO_PROVISION=force
# also provisions on a deploy (used after a deploy-scope change); GEO_PROVISION=skip
# never provisions, even on setup. A failed app run (STATUS != 0) never provisions.
#
# Driving the whole script needs the Kamal Docker image, SSH, and real secrets, so
# this test mirrors the gate CONDITION exactly as kamal-docker evaluates it and
# asserts the decision across the matrix — plus a bash -n parse check and a guard
# that the script didn't silently revert to provisioning on `deploy`. Run via:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/kamal-docker-geo-gate.bats

bats_load_library bats-support
bats_load_library bats-assert

KAMAL_DOCKER="${BATS_TEST_DIRNAME}/../../backend/bin/kamal-docker"

# Mirror of the kamal-docker gate:
#   STATUS == 0 && GEO_PROVISION != skip && ( SUBCMD == setup || GEO_PROVISION == force )
_should_provision() {  # <status> <geo_provision> <subcmd>
  local status="$1" geo="$2" sub="$3"
  if [ "${status}" -eq 0 ] && [ "${geo}" != "skip" ] \
     && { [ "${sub}" = "setup" ] || [ "${geo}" = "force" ]; }; then
    echo "yes"
  else
    echo "no"
  fi
}

@test "setup → provisions" {
  assert_equal "$(_should_provision 0 "" setup)" "yes"
}

@test "deploy → does NOT provision (the fix)" {
  assert_equal "$(_should_provision 0 "" deploy)" "no"
}

@test "deploy + GEO_PROVISION=force → provisions" {
  assert_equal "$(_should_provision 0 force deploy)" "yes"
}

@test "setup + GEO_PROVISION=skip → does NOT provision" {
  assert_equal "$(_should_provision 0 skip setup)" "no"
}

@test "failed run (STATUS != 0) → does NOT provision, even on setup" {
  assert_equal "$(_should_provision 1 "" setup)" "no"
}

@test "other subcommand (config) → does NOT provision" {
  assert_equal "$(_should_provision 0 "" config)" "no"
}

@test "kamal-docker parses (bash -n)" {
  run bash -n "${KAMAL_DOCKER}"
  assert_success
}

# Guard against a silent revert to the old "setup OR deploy" gate: the deploy arm
# must only fire via GEO_PROVISION=force, never a bare SUBCMD = deploy.
@test "kamal-docker does not provision on a bare deploy" {
  run grep -F '[ "$SUBCMD" = "deploy" ]' "${KAMAL_DOCKER}"
  assert_failure
}

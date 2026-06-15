#!/usr/bin/env bash
#
# Bash mirror of the backend Geocoding::CountryRegistry (keep the two in sync).
# Resolves the configured country (COUNTRY, default `us`) to the provisioning
# inputs the infra scripts need: the whole-country OSM extract URL, whether the
# US Census TIGER house-number import applies, and a display name.
#
# Only `us` is populated and validated at launch (FR-002). An unknown or
# un-provisioned country code fails fast with an actionable error (FR-009) — it
# is never silently substituted. Adding a country = adding a case here AND
# provisioning its data, alongside the backend registry entry.
#
# Usage (source, don't execute):
#   . "$(dirname "$0")/country-registry.sh"
#   country_resolve "${COUNTRY:-us}" || exit 1
#   echo "$COUNTRY_EXTRACT_URL  tiger=$COUNTRY_TIGER  ($COUNTRY_NAME)"

# Resolve COUNTRY into COUNTRY_CODE / COUNTRY_NAME / COUNTRY_EXTRACT_URL /
# COUNTRY_TIGER (true|false). Returns non-zero (and prints to stderr) on an
# unknown / un-provisioned code.
country_resolve() {
  local code="${1:-us}"
  code="$(printf '%s' "${code}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [ -z "${code}" ] && code="us"

  case "${code}" in
    us)
      COUNTRY_CODE="us"
      COUNTRY_NAME="United States"
      COUNTRY_EXTRACT_URL="https://download.geofabrik.de/north-america/us-latest.osm.pbf"
      COUNTRY_TIGER="true"
      ;;
    *)
      echo "error: unknown or un-provisioned country '${1}'." >&2
      echo "  Only 'us' is supported and provisioned at launch (FR-009)." >&2
      echo "  Set COUNTRY in infra/.region to a supported, provisioned country —" >&2
      echo "  or leave it unset to default to the US." >&2
      return 1
      ;;
  esac
}

#!/usr/bin/env bash
#
# US state registry — the single source of truth for each state's provisioning
# inputs: the Geofabrik extract slug, the US Census FIPS + USPS codes, and the
# bounding box used BOTH for the bounded geocoder viewbox AND the initial map
# framing of a single-state deployment.
#
# Sourced (don't execute) by:
#   - infra/scripts/setup.sh            (the dev wizard's state picker)
#   - infra/scripts/deploy-scope-env.sh (derives the backend's single-state env
#                                        for a production single-state deploy)
#
# Keep STATES in sync with the Ruby map-framing expectations: a single-state
# deploy frames Geocoding::MapFraming.bounds, which is GEOCODER_VIEWBOX parsed
# from the value resolved here. The viewbox order is Nominatim's:
#   min_lng,max_lat,max_lng,min_lat  (left,top,right,bottom).
#
# Usage:
#   . "$(dirname "$0")/state-registry.sh"
#   state_resolve IA        # or 19 (FIPS), iowa (slug), "Iowa" (label)
#   echo "$STATE_LABEL $STATE_VIEWBOX"

# Format: "Display Label|geofabrik-slug|state-fips|usps-code|viewbox"
# FIPS codes are the 2-digit US Census state identifiers used by TIGER/Line
# downloads. USPS codes are the two-letter postal abbreviations.
STATES=(
  "Alabama|alabama|01|AL|-88.5,35.0,-84.9,30.2"
  "Alaska|alaska|02|AK|-170.0,71.5,-129.9,51.2"
  "Arizona|arizona|04|AZ|-114.8,37.0,-109.0,31.3"
  "Arkansas|arkansas|05|AR|-94.6,36.5,-89.6,33.0"
  "California|california|06|CA|-124.4,42.0,-114.1,32.5"
  "Colorado|colorado|08|CO|-109.06,41.0,-102.04,36.99"
  "Connecticut|connecticut|09|CT|-73.7,42.05,-71.8,40.98"
  "Delaware|delaware|10|DE|-75.8,39.84,-75.0,38.45"
  "District of Columbia|district-of-columbia|11|DC|-77.12,39.0,-76.91,38.79"
  "Florida|florida|12|FL|-87.6,31.0,-80.0,24.5"
  "Georgia|georgia|13|GA|-85.6,35.0,-80.8,30.4"
  "Hawaii|hawaii|15|HI|-160.3,22.3,-154.8,18.9"
  "Idaho|idaho|16|ID|-117.24,49.0,-111.04,42.0"
  "Illinois|illinois|17|IL|-91.5,42.5,-87.0,36.97"
  "Indiana|indiana|18|IN|-88.1,41.76,-84.8,37.77"
  "Iowa|iowa|19|IA|-96.7,43.6,-90.0,40.3"
  "Kansas|kansas|20|KS|-102.05,40.0,-94.6,36.99"
  "Kentucky|kentucky|21|KY|-89.6,39.15,-81.9,36.5"
  "Louisiana|louisiana|22|LA|-94.04,33.0,-88.8,28.9"
  "Maine|maine|23|ME|-71.1,47.5,-66.9,43.0"
  "Maryland|maryland|24|MD|-79.5,39.7,-75.0,37.9"
  "Massachusetts|massachusetts|25|MA|-73.5,42.9,-69.9,41.2"
  "Michigan|michigan|26|MI|-90.4,48.3,-82.4,41.7"
  "Minnesota|minnesota|27|MN|-97.24,49.4,-89.5,43.5"
  "Mississippi|mississippi|28|MS|-91.7,35.0,-88.1,30.2"
  "Missouri|missouri|29|MO|-95.8,40.6,-89.1,36.0"
  "Montana|montana|30|MT|-116.05,49.0,-104.04,44.36"
  "Nebraska|nebraska|31|NE|-104.05,43.0,-95.3,40.0"
  "Nevada|nevada|32|NV|-120.0,42.0,-114.04,35.0"
  "New Hampshire|new-hampshire|33|NH|-72.6,45.3,-70.6,42.7"
  "New Jersey|new-jersey|34|NJ|-75.6,41.4,-73.9,38.9"
  "New Mexico|new-mexico|35|NM|-109.05,37.0,-103.0,31.33"
  "New York|new-york|36|NY|-79.8,45.0,-71.9,40.5"
  "North Carolina|north-carolina|37|NC|-84.3,36.6,-75.5,33.8"
  "North Dakota|north-dakota|38|ND|-104.05,49.0,-96.55,45.94"
  "Ohio|ohio|39|OH|-84.82,42.0,-80.5,38.4"
  "Oklahoma|oklahoma|40|OK|-103.0,37.0,-94.43,33.6"
  "Oregon|oregon|41|OR|-124.6,46.3,-116.46,41.99"
  "Pennsylvania|pennsylvania|42|PA|-80.52,42.3,-74.7,39.7"
  "Rhode Island|rhode-island|44|RI|-71.9,42.02,-71.1,41.1"
  "South Carolina|south-carolina|45|SC|-83.4,35.2,-78.5,32.0"
  "South Dakota|south-dakota|46|SD|-104.06,45.95,-96.44,42.48"
  "Tennessee|tennessee|47|TN|-90.31,36.7,-81.65,35.0"
  "Texas|texas|48|TX|-106.65,36.5,-93.51,25.84"
  "Utah|utah|49|UT|-114.05,42.0,-109.04,37.0"
  "Vermont|vermont|50|VT|-73.44,45.02,-71.5,42.73"
  "Virginia|virginia|51|VA|-83.68,39.47,-75.24,36.54"
  "Washington|washington|53|WA|-124.85,49.0,-116.92,45.54"
  "West Virginia|west-virginia|54|WV|-82.65,40.64,-77.72,37.2"
  "Wisconsin|wisconsin|55|WI|-92.89,47.08,-86.8,42.49"
  "Wyoming|wyoming|56|WY|-111.06,45.01,-104.05,40.99"
)

# state_resolve TOKEN: match a state by USPS code (IA), 2-digit FIPS (19),
# Geofabrik slug (iowa / new-york), or display label (Iowa / "new york"),
# case-insensitive. On a match, sets STATE_LABEL / STATE_SLUG / STATE_FIPS /
# STATE_USPS / STATE_VIEWBOX and returns 0. Returns non-zero (and prints to
# stderr) on no match — never silently substituted.
state_resolve() {
  local raw="${1:-}"
  local upper lower slugform entry label slug fips usps viewbox
  # Trim only LEADING/TRAILING whitespace — never internal — so a garbled token
  # like "I A" stays "I A" and does NOT collapse to "IA" and falsely match Iowa.
  upper="$(printf '%s' "${raw}" | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  lower="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  # Slug form folds whitespace to hyphens so "new york" matches the "new-york" slug.
  slugform="$(printf '%s' "${lower}" | tr ' ' '-')"

  for entry in "${STATES[@]}"; do
    IFS='|' read -r label slug fips usps viewbox <<< "${entry}"
    if [ "${upper}" = "${usps}" ] || [ "${upper}" = "${fips}" ] \
       || [ "${slugform}" = "${slug}" ] \
       || [ "${lower}" = "$(printf '%s' "${label}" | tr '[:upper:]' '[:lower:]')" ]; then
      STATE_LABEL="${label}"
      STATE_SLUG="${slug}"
      STATE_FIPS="${fips}"
      STATE_USPS="${usps}"
      STATE_VIEWBOX="${viewbox}"
      return 0
    fi
  done

  echo "error: unknown US state '${raw}'." >&2
  echo "  Expected a USPS code (e.g. IA), a 2-digit FIPS code (e.g. 19), a" >&2
  echo "  Geofabrik slug (e.g. iowa, new-york), or a state name (e.g. Iowa)." >&2
  return 1
}

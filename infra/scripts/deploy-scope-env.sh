#!/usr/bin/env bash
#
# Derive the BACKEND's single-state environment (GEOCODER_REGION_STATE +
# GEOCODER_VIEWBOX) from the production deploy scope, so a single-state deploy
# frames the map on — and geocodes within — that one state instead of the whole
# country (FR-007). For a whole-country deploy both are exported empty, so the app
# frames the entire country (the default).
#
# SOURCE this (it exports vars); don't execute it:
#   . infra/scripts/deploy-scope-env.sh
#   echo "$GEOCODER_REGION_STATE / $GEOCODER_VIEWBOX"
#
# Scope precedence follows provision-geo-host.sh (so what the backend frames
# always matches what was actually built on the host); the bats cross-check in
# test/infra/deploy-scope-cross-check.bats fails CI if the two ever disagree:
#   1. per-invocation env: GEO_REGION_URL / GEO_REGION_LABEL or GEO_COUNTRY
#   2. the deploy-scope file backend/.kamal/geo.env (persistent choice)
#   3. infra/.region (local dev scope) — fallback only
#   4. nothing set → whole country (empty single-state env)
#
# The scope FILES are PARSED, never sourced/executed: a malformed or unquoted
# line (e.g. `GEO_REGION_LABEL=New York`) can't abort the deploy, and an embedded
# `$(...)` never runs. Only the per-invocation GEO_* overrides are read from the
# ambient environment; REGION / REGION_URL / REGION_LABEL / COUNTRY come ONLY from
# the scope files, so a stray exported REGION/COUNTRY can't change the scope.
#
# Resolution is best-effort: an unrecognized region (a custom/non-state extract)
# leaves the single-state env empty, so the app falls back to whole-country
# framing rather than failing the deploy.

# Read a `KEY=VALUE` assignment from a scope file WITHOUT executing the file.
# Strips one layer of matching single/double quotes. Always returns 0 (a missing
# file or key yields an empty value), so it is safe under the caller's `set -e`.
_scope_file_get() {  # <file> <key>
  [ -f "$1" ] || return 0
  local line val
  # tail makes the pipeline status 0 even when grep matches nothing.
  line="$(grep -E "^[[:space:]]*$2=" "$1" 2>/dev/null | tail -n1)"
  [ -n "${line}" ] || return 0
  val="${line#*=}"
  case "${val}" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  printf '%s' "${val}"
}

# Define the body in a function so a non-zero state lookup can't trip the caller's
# `set -e`, and so all the scope variables stay local (nothing leaks to the
# caller or to provision-geo-host.sh, which kamal-docker runs afterwards).
_derive_deploy_scope_env() {
  local here repo geo_env region_config url url_slug token
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # -> infra/scripts
  repo="$(cd "${here}/../.." && pwd)"

  # shellcheck source=/dev/null
  . "${here}/state-registry.sh"

  # Default to whole-country (no single-state env) unless we resolve a state below.
  GEOCODER_REGION_STATE=""
  GEOCODER_VIEWBOX=""

  # Per-invocation overrides come from the ambient env (GEO_*, exactly as
  # provision-geo-host.sh honors them). Everything else is FILE-ONLY: kept local
  # and empty so a stray ambient REGION/REGION_URL/REGION_LABEL/COUNTRY cannot
  # override the configured scope.
  local geo_region_url="${GEO_REGION_URL:-}"
  local geo_region_label="${GEO_REGION_LABEL:-}"
  local geo_country="${GEO_COUNTRY:-}"
  local region="" region_url="" region_label="" country=""

  # 1+2. geo.env (deploy scope) — unless a per-invocation GEO_* override already
  #      chose the scope (per-invocation wins).
  geo_env="${GEO_ENV:-${repo}/backend/.kamal/geo.env}"
  if [ -z "${geo_region_url}" ] && [ -z "${geo_country}" ] && [ -f "${geo_env}" ]; then
    geo_region_url="$(_scope_file_get "${geo_env}" GEO_REGION_URL)"
    geo_region_label="$(_scope_file_get "${geo_env}" GEO_REGION_LABEL)"
    geo_country="$(_scope_file_get "${geo_env}" GEO_COUNTRY)"
  fi

  # 3. infra/.region (local dev scope) — last resort, only if nothing above chose.
  if [ -z "${geo_region_url}" ] && [ -z "${geo_country}" ]; then
    region_config="${REGION_CONFIG:-${repo}/infra/.region}"
    region="$(_scope_file_get "${region_config}" REGION)"
    region_url="$(_scope_file_get "${region_config}" REGION_URL)"
    region_label="$(_scope_file_get "${region_config}" REGION_LABEL)"
    country="$(_scope_file_get "${region_config}" COUNTRY)"
  fi

  # An explicit whole-country scope (GEO_COUNTRY, or a country-mode .region that
  # set COUNTRY with no region extract): leave the single-state env empty (default
  # framing), silently — this is a normal, supported deploy.
  if [ -n "${geo_country}" ] || { [ -z "${geo_region_url}" ] && [ -z "${region_url}" ] && [ -z "${region}" ] && [ -n "${country}" ]; }; then
    export GEOCODER_REGION_STATE GEOCODER_VIEWBOX
    return 0
  fi

  # No scope configured at all (no geo.env, no .region): default to whole-country
  # framing, silently — nothing was specified, so there is nothing to warn about.
  if [ -z "${geo_region_url}" ] && [ -z "${region_url}" ] && [ -z "${region}" ] \
     && [ -z "${geo_region_label}" ] && [ -z "${region_label}" ]; then
    export GEOCODER_REGION_STATE GEOCODER_VIEWBOX
    return 0
  fi

  # A single-state scope. The extract URL is authoritative (GEO_REGION_URL wins
  # over REGION_URL, matching provision-geo-host.sh), so its Geofabrik slug is the
  # PRIMARY token — a bare region slug or label is only a fallback and can never
  # override the chosen URL's state. The canonical registry STATE_LABEL is the
  # backend's state name (parity with the dev wizard's GEOCODER_REGION_STATE),
  # never the operator's free-form label.
  url="${geo_region_url:-${region_url}}"
  url_slug=""
  if [ -n "${url}" ]; then
    url_slug="${url##*/}"            # basename
    url_slug="${url_slug%-latest.osm.pbf}"
    url_slug="${url_slug%.osm.pbf}"
  fi

  for token in "${url_slug}" "${region}" "${geo_region_label}" "${region_label}"; do
    [ -n "${token}" ] || continue
    if state_resolve "${token}" 2>/dev/null; then
      GEOCODER_REGION_STATE="${STATE_LABEL}"
      GEOCODER_VIEWBOX="${STATE_VIEWBOX}"
      export GEOCODER_REGION_STATE GEOCODER_VIEWBOX
      return 0
    fi
  done

  # Region set but unrecognized (e.g. a county or custom extract): warn and fall
  # back to whole-country framing rather than guessing a bbox.
  echo "deploy-scope-env: could not resolve a US state from the deploy scope" \
       "(url='${url}', label='${geo_region_label:-${region_label}}') —" \
       "the app will frame the whole country." >&2
  export GEOCODER_REGION_STATE GEOCODER_VIEWBOX
  return 0
}

_derive_deploy_scope_env
unset -f _derive_deploy_scope_env _scope_file_get

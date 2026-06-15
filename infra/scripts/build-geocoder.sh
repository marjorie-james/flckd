#!/usr/bin/env bash
#
# Download the US Census TIGER/Line address data — preprocessed for Nominatim —
# and import the configured state's counties into the running geocoder for
# house-number-level geocoding.
#
# Why the preprocessed bundle (not raw Census ADDR files)?
#   Nominatim's `add-data --tiger-data` consumes CSV files where each street
#   segment carries geometry + an address range + a street name. The raw Census
#   ADDR product is address-range tables only (no geometry, no street names), so
#   Nominatim publishes a preprocessed bundle that joins ADDR + EDGES +
#   FEATNAMES. The bundle is split one CSV per county, named by 5-digit FIPS
#   (SSCCC.csv) and sorted, so we extract only this state's counties to keep the
#   geocoder database small.
#
# Anonymity note: downloads only public US Census / Nominatim data. All geocoding
# continues to run on our own infrastructure — no user query is ever sent to a
# third party (FR-012a).
#
# Prerequisites:
#   1. Run infra/scripts/setup.sh to configure a state (writes infra/.region).
#   2. The geocoder container must be running and its initial OSM import
#      complete (first-run import takes ~20 min). Check health:
#        docker compose -f infra/docker-compose.yml ps geocoder
#      or watch: docker compose -f infra/docker-compose.yml logs -f geocoder
#
# Usage: infra/scripts/build-geocoder.sh
#
# Output: infra/data/tiger/<state_fips>/<fips>.csv  (cached; re-running is fast)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${DIR}/../docker-compose.yml"

# Load per-developer region config (written by infra/scripts/setup.sh).
# Provides: REGION, REGION_LABEL, REGION_URL, STATE_FIPS.
REGION_CONFIG="${DIR}/../.region"
STATE_FIPS="19"     # default: Iowa
REGION_LABEL="Iowa" # default label for messages
# shellcheck source=/dev/null
[ -f "${REGION_CONFIG}" ] && source "${REGION_CONFIG}"

YEAR="${YEAR:-2024}"

# Preprocessed-for-Nominatim TIGER bundle (one CSV per county, FIPS-named).
# Override TIGER_BUNDLE_URL in tests to point at a local fixture.
TIGER_BUNDLE_URL="${TIGER_BUNDLE_URL:-https://nominatim.org/data/tiger${YEAR}-nominatim-preprocessed.csv.tar.gz}"

# nominatim.org's CDN now rejects requests sending curl's default User-Agent
# (curl/<version>) with HTTP 403. Send an honest, descriptive UA instead so the
# download succeeds — we identify the tool and link the project rather than
# impersonating a browser.
TIGER_USER_AGENT="${TIGER_USER_AGENT:-flckd-setup (+https://github.com/marjorie-james/flckd)}"

# TIGER_HOST_DIR can be pre-exported to override the default (used in tests).
if [ -z "${TIGER_HOST_DIR:-}" ]; then
  TIGER_HOST_DIR="${DIR}/../data/tiger/${STATE_FIPS}"
fi
# infra/data/ is mounted at /nominatim/import/ inside the geocoder container
# (per docker-compose.yml). State-scoped subdirectory avoids cross-state collisions.
TIGER_CONTAINER_DIR="/nominatim/import/tiger/${STATE_FIPS}"

mkdir -p "${TIGER_HOST_DIR}"

echo "Building TIGER/Line address data for: ${REGION_LABEL} (FIPS ${STATE_FIPS})"

# ------------------------------------------------------------------
# Step 1: Fetch this state's county CSVs (cached — fast on re-run)
# ------------------------------------------------------------------
_count_state_csvs() {
  find "${TIGER_HOST_DIR}" -maxdepth 1 -name "${STATE_FIPS}*.csv" 2>/dev/null | wc -l | tr -d ' '
}

if [ "$(_count_state_csvs)" -gt 0 ]; then
  echo "==> [1/2] Using $(_count_state_csvs) cached county CSV(s) in ${TIGER_HOST_DIR}"
else
  echo "==> [1/2] Downloading preprocessed TIGER ${YEAR} bundle and extracting ${REGION_LABEL} counties…"
  echo "    The bundle is whole-US (~1.8 GB); only ${STATE_FIPS}*.csv is kept."
  echo "    Re-runs use the cached CSVs and skip this step."

  # Download to a temp file, then list-and-extract only this state's members by
  # their exact names. The bundle members are flat, FIPS-named (SSCCC.csv). We
  # avoid tar glob member-matching on purpose: GNU needs --wildcards, BSD globs
  # by default, and busybox (the CI bats image) does not glob members at all —
  # but all three extract a member given its exact name.
  BUNDLE_TMP="${TIGER_HOST_DIR}/.tiger-bundle.tar.gz"
  trap 'rm -f "${BUNDLE_TMP}"' EXIT
  curl -fsSL -A "${TIGER_USER_AGENT}" -o "${BUNDLE_TMP}" "${TIGER_BUNDLE_URL}"

  members="$(tar tzf "${BUNDLE_TMP}" | grep -E "^${STATE_FIPS}[0-9]{3}\.csv$" || true)"
  if [ -z "${members}" ]; then
    echo "error: bundle contains no county CSVs for state FIPS ${STATE_FIPS} (${REGION_LABEL})." >&2
    echo "  Check that infra/.region is configured correctly (infra/scripts/setup.sh)" >&2
    echo "  and retry: infra/scripts/build-geocoder.sh" >&2
    exit 1
  fi
  # Word-split the newline-separated member list into exact-name extract args.
  # shellcheck disable=SC2086
  tar xzf "${BUNDLE_TMP}" -C "${TIGER_HOST_DIR}" ${members}

  rm -f "${BUNDLE_TMP}"
  trap - EXIT
  echo "    Extracted $(_count_state_csvs) county CSV(s)."
fi

# ------------------------------------------------------------------
# Step 2: Import into the running Nominatim container
# ------------------------------------------------------------------
echo "==> [2/2] Importing TIGER data into Nominatim (requires a healthy container)…"

# Verify the geocoder is running and its OSM import has finished before
# attempting the TIGER import — nominatim add-data fails silently or hangs
# if the container hasn't completed its initial setup.
if ! curl -sf "http://localhost:8081/status.php" >/dev/null 2>&1; then
  echo "error: geocoder is not healthy (http://localhost:8081/status.php did not respond)" >&2
  echo "  Wait for the Nominatim OSM import to finish (~20 min first run), then retry:" >&2
  echo "    docker compose -f infra/docker-compose.yml logs -f geocoder" >&2
  echo "    infra/scripts/build-geocoder.sh" >&2
  exit 1
fi

# Run from the Nominatim project directory (.env + tokenizer/ live here). The
# image's WORKDIR is /app (root-owned, entrypoint scripts only); without -w the
# nominatim CLI defaults its project dir to /app and fails trying to create
# /app/tokenizer as the unprivileged nominatim user (PermissionError).
docker compose -f "${COMPOSE_FILE}" exec -u nominatim -w /nominatim geocoder \
  nominatim add-data --tiger-data "${TIGER_CONTAINER_DIR}"

# ------------------------------------------------------------------
# Step 3: Activate TIGER lookups in the search frontend AND the SQL functions
# ------------------------------------------------------------------
# `add-data --tiger-data` only loads the location_property_tiger table. Two
# pieces of Nominatim must additionally be regenerated WITH the flag set, and
# both are gated on NOMINATIM_USE_US_TIGER_DATA (default "no"):
#
#   --website   bakes CONST_Use_US_Tiger_Data into the PHP frontend, so SEARCH
#               consults the TIGER table. Without it, house numbers find nothing.
#   --functions emits the TIGER branch of the get_addressdata() SQL function, so
#               a found house number gets its address rolled up from the parent
#               street. Without it, search returns the right point but with an
#               EMPTY display_name (blank autocomplete suggestion).
#
# The mediagis image sets the flag at container init only when
# IMPORT_TIGER_ADDRESSES=true — which we deliberately do NOT use, because it
# would download the whole-US bundle at first boot instead of our state-scoped
# CSVs. So we set the flag ourselves, then regenerate both. All steps are
# idempotent, so re-running the script (or running it against an
# already-imported geocoder) safely repairs a database imported before they
# existed.
echo "==> Enabling TIGER house-number lookups (search frontend + SQL functions)…"
docker compose -f "${COMPOSE_FILE}" exec -u nominatim -w /nominatim geocoder bash -c '
  grep -q "^NOMINATIM_USE_US_TIGER_DATA=" .env \
    || echo "NOMINATIM_USE_US_TIGER_DATA=yes" >> .env
  nominatim refresh --website --functions
'

# ------------------------------------------------------------------
# Step 4: Free numeric house numbers from stray word tokens
# ------------------------------------------------------------------
# Nominatim only interprets a bare number in a query as a house number when that
# number is NOT already a known word token (see icu_tokenizer.php — the
# "Assume it is a house number" fallback fires only for tokens not found in the
# `word` table). OSM features tagged with a purely numeric name/ref — bus-stop
# `ref`s, route numbers — get indexed as ordinary word tokens (type W/w), which
# then SHADOWS every house number that happens to share those digits: the query
# parser treats e.g. "1007" as a name, never reaches the TIGER interpolation,
# and returns nothing. Purely numeric tokens are never useful as searchable
# place *names*, so we drop them post-import; the table is rebuilt from scratch
# on every import, so this is not destructive to source data. Housenumber (H)
# and postcode (P) tokens use different `type`s and are untouched.
echo "==> Clearing numeric word tokens that shadow house numbers…"
docker compose -f "${COMPOSE_FILE}" exec -u postgres geocoder \
  psql -d nominatim -v ON_ERROR_STOP=1 -c \
  "DELETE FROM word WHERE type IN ('W','w') AND word_token ~ '^[0-9]+\$';"

# ------------------------------------------------------------------
# Step 5: Import Wikipedia importance so place ranking is sane
# ------------------------------------------------------------------
# Without Wikipedia/Wikimedia importance data, Nominatim falls back to a
# rank-based importance where a broader admin area outranks the places inside it
# — e.g. "Des Moines" the COUNTY outranks Des Moines the CITY (Iowa's capital),
# pulling the wrong address (Burlington, in Des Moines County) to the top of
# autocomplete. Fresh containers load this during the OSM import (IMPORT_WIKIPEDIA
# in docker-compose.yml); this step repairs a geocoder imported before that, so
# re-running self-heals. `refresh --wiki-data` loads wikimedia-importance.sql.gz
# from the project dir; `--importance` then recomputes placex importances.
# Idempotent: skipped once the importance table is present.
WIKI_IMPORTANCE_URL="${WIKI_IMPORTANCE_URL:-https://nominatim.org/data/wikimedia-importance.sql.gz}"
_wiki_importance_loaded() {
  docker compose -f "${COMPOSE_FILE}" exec -T -u postgres geocoder \
    psql -d nominatim -tAc "SELECT to_regclass('public.wikipedia_article') IS NOT NULL" 2>/dev/null \
    | tr -d '[:space:]'
}
if [ "$(_wiki_importance_loaded)" = "t" ]; then
  echo "==> Wikipedia importance already present — skipping."
else
  echo "==> Importing Wikipedia importance (~0.3 GB download + recompute; one-time)…"
  # nominatim.org rejects curl's default UA (see TIGER_USER_AGENT above), so reuse it.
  docker compose -f "${COMPOSE_FILE}" exec -u nominatim -w /nominatim geocoder bash -c "
    curl -fsSL -A '${TIGER_USER_AGENT}' -o wikimedia-importance.sql.gz '${WIKI_IMPORTANCE_URL}'
    nominatim refresh --wiki-data
    nominatim refresh --importance
    rm -f wikimedia-importance.sql.gz
  "
fi

echo ""
echo "House-number geocoding is now active for ${REGION_LABEL}."
echo "County CSVs are cached in ${TIGER_HOST_DIR} — re-running this script is fast."

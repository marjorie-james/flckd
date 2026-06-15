# Feature Specification: House-Number Address Suggestions

**Feature Branch**: `fix/geocoder-housenumber-suggestions`

**Created**: 2026-06-10

**Status**: Implemented

**Input**: User report: "the app STILL does not provide suggestions for a specific street address,
one example is 1007 East Grand Avenue, Des Moines, IA, 50319"

## Summary

Typing a full street address into the route panel returned **no suggestions**, even though the TIGER
address data for that street was present in the geocoder database. Investigation found **three
independent defects**, each sufficient on its own to suppress a house-number match. The reported
address happened to trip all three at once.

## Root Causes

### RC1 — TIGER lookups were never switched on
`infra/scripts/build-geocoder.sh` imports the state's TIGER CSVs with `nominatim add-data
--tiger-data`, which populates the `location_property_tiger` table. But Nominatim's search code
consults that table **only when `NOMINATIM_USE_US_TIGER_DATA=yes`** (`SearchDescription.php:660`),
and that flag defaults to `no`. It was set nowhere — not in `docker-compose.yml`, not in the build
script. The mediagis image sets it at container init *only* when `IMPORT_TIGER_ADDRESSES=true`, which
we deliberately avoid (it downloads the whole-US bundle at first boot instead of our state-scoped
CSVs). Net effect: **every house number that exists only in TIGER returned nothing.**

### RC2 — the state token filtered out all house numbers
The Geofabrik single-state extract imports county (admin_level 6) and city (8) boundaries but **no
state/country boundary** (admin_level ≤ 4 is absent). House-number results therefore have no "Iowa"
in their address hierarchy, so a query containing `, IA` / `, Iowa` makes the state an unsatisfied
required term and Nominatim discards every house-number match. Proven: `1005 East Grand Avenue,
Des Moines, 50319` resolves, but adding `, IA` returns empty. The country (`, USA`) and ZIP still
resolve — only the state has no fallback.

### RC3 — purely numeric word tokens shadow house numbers
Nominatim only interprets a bare number in a query as a house number when that number is **not already
a known word token** (`icu_tokenizer.php` — the "Assume it is a house number" fallback only fires for
unmatched tokens). OSM features tagged with a purely numeric `name`/`ref` (bus-stop refs, route
numbers) get indexed as ordinary word tokens (type `W`/`w`). `1007` was such a token (an OSM bus-stop
node with `ref=1007`), so the parser treated "1007" as a name, never reached the TIGER interpolation,
and returned nothing. `1005`/`1009` have `H` (house-number) tokens from OSM nodes elsewhere, which is
why they worked. ~6,100 numeric word tokens existed in the Iowa import.

## Fixes

| RC | Fix | Location |
|----|-----|----------|
| RC1 | After `add-data`, set `NOMINATIM_USE_US_TIGER_DATA=yes` in the project `.env` (idempotent) and `nominatim refresh --website` to bake it into the PHP frontend. | `infra/scripts/build-geocoder.sh` |
| RC2 | Strip the state component (any USPS abbreviation or the configured region's state name) from typed queries before they reach Nominatim. The viewbox already bounds results to the region, so the state token is redundant; a single-state extract has no cross-state ambiguity. | `backend/app/services/geocoding/geocoder_client.rb` + `GEOCODER_REGION_STATE` env in compose/deploy |
| RC3 | After import, delete purely numeric `W`/`w` word tokens (`DELETE FROM word WHERE type IN ('W','w') AND word_token ~ '^[0-9]+$'`). They are never useful as searchable place *names* and the `word` table is rebuilt on every import. `H` (house number) and `P` (postcode) tokens use other types and are untouched. | `infra/scripts/build-geocoder.sh` |

## Verification

End-to-end through the real backend API with the **exact reported input**:

```
GET /api/v1/geocode/search?q=1007 East Grand Avenue, Des Moines, IA, 50319
→ { "label": "1007, East Grand Avenue, East Village, Des Moines, Polk County, 50319, United States",
    "lat": 41.591200, "lng": -93.603000, "type": "house" }
```

The same raw string against Nominatim *without* the fixes still returns empty, confirming each fix is
independently necessary.

## Tests

- `backend/spec/services/geocoding/geocoder_client_spec.rb` — state-token normalization (abbreviation,
  full name, case-insensitivity, first-component protection, city-shares-state-name, no-op cases).
- `test/infra/build-geocoder.bats` — the build script activates TIGER lookups (`refresh --website`) and
  clears numeric word tokens (`DELETE FROM word`), and both run *after* the import.

## Operational Note

Existing deployments imported before this change need the activation + cleanup applied once to their
running geocoder. Re-running `infra/scripts/build-geocoder.sh` does this (both new steps are
idempotent); a backend restart picks up `GEOCODER_REGION_STATE`.

## Confidence scoring (RC-adjacent)

TIGER-interpolated results carry a negative Nominatim `importance` (a Wikipedia-style prominence
signal), which `to_result` previously surfaced verbatim — so the exact house match for the reported
address reported `confidence: -0.62`, its *least*-confident value. Clamping to `[0, 1]` would have
flattened every interpolated result to `0.0`, mis-ranking the most precise matches if anything ever
sorted on the field.

Instead, `confidence_for` now derives confidence from Nominatim's `place_rank` (its
address-specificity scale: 30 = exact house number, ~26 a street, lower = broader areas), as
`place_rank / 30` clamped to `[0, 1]`. This is monotonic in precision and always non-negative, so an
exact address scores `1.0`. Falls back to a neutral `0.5` when Nominatim omits the rank. The reported
address now returns `confidence: 1.0`.

# Contract: Geocoding behavior (deltas)

The `/api/v1/geocode/*` request/response **shapes are unchanged**. What changes is
behavior at country scale — the single-state query workarounds are removed when the
index spans the whole country (research R3).

## GET /api/v1/geocode/search?q&limit

- **Multi-state results (FR-003)**: addresses anywhere in the configured country
  resolve, not just one sub-region.
- **Disambiguation (FR-004)**: a query that includes a state token (e.g.
  `"Springfield, IL"` vs `"Springfield, MO"`) is disambiguated by that token —
  the state is **no longer stripped** from the query. The previous single-state
  workaround (`normalize_query`) is disabled for a country-spanning index.
- **Label (FR-004)**: `humanized_label` uses the result's actual `addr["state"]`
  (present in whole-US data) rather than the configured fallback state.
- **Bounded search (perf, R7)**: search is viewbox-bounded to the country's bbox
  (from the country registry) to keep candidate sets small and avoid cross-border noise.
- Response item shape unchanged: `{ label, lat, lng, type, confidence }`.

## GET /api/v1/geocode/reverse

- Unchanged shape and validation; results span the whole country. Labels prefer the
  real `addr["state"]`.

## Single-country / dev fallback

- When a deployment is configured to a single sub-region (a dev build whose extract
  lacks the country's admin-level boundaries), the legacy single-region behavior remains
  available, gated behind the country/region configuration — so a state-only dev stack
  still geocodes correctly.

## Test contract (Principle II)

- Same-named cities in different states each resolve to the correct state.
- A state-qualified query is not nullified (regression guard against the old strip).
- Labels carry the result's real state, not the configured fallback.
- All driven by recorded Nominatim fixtures (no live geocoder).

# Phase 0 Research: Country-Wide Camera Mapping

All decisions below resolve the Technical Context unknowns and the spec's deferred
performance budgets. No open `NEEDS CLARIFICATION` remain.

## R1 — Whole-country OSM extract source

**Decision**: Drive the extract URL from a country registry. For US, use Geofabrik
`north-america/us-latest.osm.pbf` (whole-US, ~10+ GB). Keep the existing per-state
URLs available for dev/cheaper builds, but the default country build fetches the
country extract.

**Rationale**: `fetch-extract.sh` already supports `REGION_URL` override and a
URL-marker cache that re-downloads on change. Geofabrik publishes a single whole-US
PBF, so no merge step is needed for US (the README's `osmium merge` path stays as
the multi-state-subset escape hatch). One URL → one extract → existing
graph/tiles/geocoder/camera pipeline runs unchanged in shape, just bigger.

**Alternatives considered**: Merging all 50 state extracts with `osmium merge`
(slower, more moving parts, duplicate-boundary handling); a planet extract clipped
to US (unnecessary — Geofabrik already clips).

## R2 — Whole-US TIGER house-number import

**Decision**: When country = US, import **all** counties from the preprocessed
Nominatim TIGER bundle (the whole ~1.8 GB bundle) instead of extracting only
`STATE_FIPS*.csv`. Generalize `build-geocoder.sh` to skip the per-state member
filter for a country build (extract all `SSCCC.csv`), keeping the cache and the
post-import steps (numeric-token cleanup, `--website`/`--functions`, Wikipedia
importance) unchanged.

**Rationale**: The bundle is already whole-US; today's script downloads it and
throws away all but one state's CSVs. A country build simply keeps them all. The
import is the long pole (hours, large DB) — flagged as the dominant cost in the
runbook. TIGER is US-only (US Census product); the country registry marks
`tiger: true` only for US, so non-US countries skip this step and rely on OSM
house numbers (precision per-country, per Assumptions).

**Alternatives considered**: Per-state incremental TIGER imports (more orchestration,
no benefit for a whole-country target); skipping TIGER for US (regresses house-number
geocoding — rejected).

## R3 — Remove the single-state geocoder workarounds

**Decision**: Remove (condition off) `GeocoderClient#normalize_query`'s state-token
stripping and the `humanized_label` `@region_state` fallback **when the geocoder
index spans the whole country**. With whole-US OSM data, Nominatim has state-level
(admin_level 4) boundaries, so: (a) typed addresses no longer need the state token
stripped — the state now disambiguates rather than nullifies results, satisfying
FR-004; (b) `addr["state"]` is present, so the label uses the real state instead of
the configured fallback.

**Rationale**: The workaround exists *because* the single-state extract lacks the
state boundary (documented in `normalize_query`). At country scale that premise is
false and the workaround is actively harmful (it would strip the very token needed
to disambiguate same-named cities across states — the FR-004 edge case). The
single-state behavior is gated behind the country config so a single-state dev build
still works.

**Alternatives considered**: Keep stripping but only for the configured country's own
name (still wrong for intra-US state disambiguation); detect boundary presence at
runtime (fragile, extra query). Gating on the country config is simplest and testable.

## R4 — Country configuration representation

**Decision**: Introduce `Geocoding::CountryRegistry` (backend) — a small, static
registry keyed by ISO country code mapping to `{ name, extract_url, bbox/viewbox,
tiger: bool, sub_region_kind }`. Config selects the country via a single env var
`GEOCODER_COUNTRY` (default `us`), replacing `GEOCODER_REGION_STATE`. The geocoder
viewbox is derived from the registry's bbox (replacing the hand-set
`GEOCODER_VIEWBOX`). Infra scripts read the same country from `infra/.region`
(generalized to also carry `COUNTRY`).

**Rationale**: One source of truth for "what does country X need" (extract URL,
framing bbox, whether TIGER applies). Generic by construction (adding a country =
adding a registry row + provisioning its data), while US is the only fully populated
+ validated entry at launch (FR-009: an unknown/empty country code fails fast). Env
var keeps it deploy-time and account-less.

**Alternatives considered**: A DB `countries` table (overkill for static reference
data, adds a migration + seeding for something that never changes at runtime); free
-form env bbox only (loses the TIGER-applicability and extract-URL knowledge).

## R5 — Coverage as per-data-region presence + freshness

**Decision**: Separate the two roles currently conflated in `CoverageArea`:
1. **Country extent** (for map framing + "is this point in our country") — derived
   from the country registry bbox. `/coverage/bounds` returns the **country extent**
   so the map frames the whole country (FR-007), not the sparse camera footprint.
2. **Data-region** (for honest present/absent/stale signalling, FR-008/SC-005) —
   `CoverageArea` rows become *ingested data-regions* (e.g. per camera-data tile/state
   footprint) each carrying `data_freshness_at`. `/coverage` (point) reports whether
   the point falls in a data-region with camera data and how fresh it is.

`DataRefreshJob` sets `data_freshness_at` **per data-region as that region is
refreshed**, replacing the global `CoverageArea.update_all(...)` so freshness is
honest per region.

**Rationale**: The spec explicitly chose "per ingested data-region, including
freshness." Framing on the union of sparse footprints would violate FR-007 (frame
the whole country); using the country rectangle for present/absent would violate
FR-008 (false "camera-free"). Splitting the roles satisfies both. The refresh job is
already tiled, so per-region freshness is a natural fit.

**Alternatives considered**: Single `CoverageArea` = whole-US rectangle (fails the
honest-coverage requirement); a brand-new `data_regions` table (more schema churn —
reusing `CoverageArea` with clarified semantics + per-row freshness is lighter and
keeps `covers?`/`bounds` working). Revisit a dedicated table only if data-region
attributes grow.

## R6 — One-command country provisioning (FR-013)

**Decision**: `infra/scripts/build-geo.sh` is the single **canonical** one-command
country provisioning path (FR-013): country-aware (reads `COUNTRY`, default US), it
fetches the country extract, builds routing graph + tiles, runs whole-country TIGER,
seeds the country data-region, **imports camera data**, and writes the manifest.
`setup.sh` becomes the interactive wrapper that **delegates provisioning to
`build-geo.sh`** (adding the prompts, DB prepare, and progress panel), so default-US
setup and switch-country provisioning are identical in scope — both gather cameras and
seed coverage.

**Rationale**: The chain already exists (`fetch-extract → routing+tiles (parallel) →
manifest`, plus `build-geocoder.sh` and camera import). Generalizing the inputs to a
country and documenting the single command satisfies FR-013 without inventing new
infrastructure. The scheduled rebuild workflow (`.github/workflows/build-geo.yml`)
reuses it.

**Alternatives considered**: A brand-new orchestrator script (duplicates build-geo.sh);
leaving provisioning manual/out-of-band (rejected by clarification — provisioning is in scope).

## R7 — Performance budgets & resource envelope at country scale

**Decision**: Budgets as in plan Technical Context. The single new perf risk is
geocoder `/search` latency over the whole-US Nominatim index; mitigate with the
existing `IMPORT_STYLE=address` lean import, the registry-derived **viewbox + bounded
search** (constrains candidates to the country), and the numeric-token cleanup already
in `build-geocoder.sh`. Route planning, tiles, and coverage are not materially affected
by country scale (routing/tiles are pre-built; coverage is an indexed PostGIS
containment query). Document the country build's resource envelope (RAM/disk/time) in
`docs/runbooks/geo-stack.md`; country builds run on a larger/self-hosted runner, not CI.

**Rationale**: Principle IV requires measured budgets before implementation. Bounded
search keeps candidate sets small even on a whole-US index. The heavy costs are
build-time (provisioning), not request-time.

**Alternatives considered**: No viewbox / unbounded search (slower, risks cross-border
noise); sharding Nominatim (unjustified complexity for one-country-per-deployment).

## R8 — Test strategy (deterministic, Principle II)

**Decision**:
- **Geocoder**: replace single-state-strip specs with multi-state disambiguation specs
  (same-named cities across states resolve by state; label uses real `addr["state"]`),
  driven by recorded Nominatim fixtures — no live geocoder.
- **Country registry**: unit specs for lookup, default-to-US, and unknown-country failure (FR-009).
- **Coverage**: model + request specs for per-data-region presence and per-region
  `data_freshness_at`; `/coverage/bounds` returns the country extent; contract specs
  (`openapi_spec.rb`) updated for any response-shape deltas.
- **Infra**: bats coverage for `fetch-extract.sh` (country URL), `build-geocoder.sh`
  (all-county vs single-state extraction), and `setup.sh` country mode — using local
  fixture bundles/URLs (`TIGER_BUNDLE_URL`, `REGION_URL` overrides already exist).

**Rationale**: Keeps the suite deterministic and offline while covering every
behavioral change. Mirrors existing patterns (fixtures, override env vars, bats).

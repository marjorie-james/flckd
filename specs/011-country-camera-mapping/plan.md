# Implementation Plan: Country-Wide Camera Mapping

**Branch**: `011-country-camera-mapping` | **Date**: 2026-06-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/011-country-camera-mapping/spec.md`

## Summary

Lift a deployment's geographic scope from a single US **state** to an entire
**country**, defaulting to the **United States**. One operator-chosen country
drives every geographic facet — OSM extract, routing graph, vector tiles, geocoder
index + TIGER house numbers, camera-data gathering, map framing, and coverage
signalling. The configuration is country-generic, but the US is the sole validated
and supported target at launch; specifying an un-provisioned country fails setup
fast. Provisioning is in scope: the existing single-region data-prep scripts are
generalized to whole-country, with a documented one-command path.

The codebase is already substantially country-shaped — `CameraData::Sources::UsTiles::CONUS`
tiles the whole continental US, `DataRefreshJob` resumably refreshes "the whole
country" cell-by-cell, and `CoverageArea` framing/containment is generic. The
single-state assumptions are concentrated in: (1) the geocoder's single-state
query workarounds, (2) the extract/TIGER fetch defaults, (3) region env config,
and (4) seed/coverage data. This feature removes those assumptions and adds a
country registry + one-command provisioning.

## Technical Context

**Language/Version**: Ruby 3.4.x + Rails 8.1.x (API mode); TypeScript + React 19 (Vite, MapLibre GL JS); Bash (infra scripts)

**Primary Dependencies**: Self-hosted geo stack — Valhalla (segment-exclusion routing), Nominatim (`mediagis/nominatim`, geocoding + TIGER), Protomaps PMTiles via go-pmtiles (vector tiles), Planetiler (tile build), osmium (camera/extract filtering); PostgreSQL 17 + PostGIS; Solid Queue (Continuable jobs)

**Storage**: PostgreSQL 17 + PostGIS (`cameras`, `monitored_segments`, `coverage_areas`, `data_sources`); on-disk geo artifacts (`extract.osm.pbf`, Valhalla tiles, `tiles.pmtiles`, TIGER county CSVs); Nominatim's own Postgres volume

**Testing**: RSpec (backend, run in the backend container — host Ruby is broken), bats (infra shell scripts), Playwright + axe (frontend); geo services stubbed with recorded fixtures for determinism (Constitution Principle II)

**Target Platform**: Linux server (Kamal 2 + Thruster prod; docker-compose dev — same engines, no dev/prod drift)

**Project Type**: Web application (backend API + React frontend) plus an infra/ data-provisioning layer

**Performance Goals** (country scale; frozen as spec **SC-008** per Constitution Principle IV):
- Geocode `/search` p95 ≤ 600 ms over the whole-US index (autocomplete-usable); reverse p95 ≤ 400 ms.
- Route plan `/routes` p95 ≤ 2.5 s for an in-country trip (the existing camera-avoidance multi-route fan-out, unchanged in shape).
- `/coverage` point lookup p95 ≤ 150 ms; `/coverage/bounds` p95 ≤ 150 ms.
- Map first meaningful paint unchanged from today (tiles are pre-rendered; country scope only changes which `.pmtiles` is served).

**Constraints**:
- Strict anonymity (FR-011): no third party receives origin/destination/route; no accounts/PII/persistent IDs; logs retain no route coords or client IPs. Provisioning downloads only **public** data.
- Camera avoidance stays segment-exclusion (snap-to-road), not radius (FR-010).
- Same engines in dev and prod; tests deterministic via fixtures.
- Resource ceiling is real: a full-US OSM build is ~10+ GB and far exceeds a standard CI runner / laptop — country builds run on a larger/self-hosted runner.

**Scale/Scope**: US-wide — ~10+ GB OSM extract; whole-US TIGER bundle (~1.8 GB, all ~3,200 counties); CONUS camera grid (2° cells); 50 states + DC of address disambiguation. One country per deployment.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Code Quality** — PASS. Changes generalize existing, documented modules rather than adding parallel paths; the single-state geocoder workaround is *removed* (dead-workaround deletion) once whole-US admin boundaries exist, not layered over. Linter/formatter zero-warnings gate applies (rubocop in container, shellcheck for infra).
- **II. Testing Standards (NON-NEGOTIABLE)** — PASS (planned). Every behavioral change carries tests: geocoder multi-state disambiguation specs (replacing single-state-strip specs), country-registry validation specs, coverage per-data-region + freshness specs, contract specs for `/coverage` + `/coverage/bounds` deltas, and bats coverage for the generalized infra scripts. Geo services stay stubbed with fixtures.
- **III. UX Consistency** — PASS. Setup failure for an un-provisioned country is an actionable error (FR-009), matching the structured/localized error convention. Coverage signalling distinguishes present / absent / not-yet-gathered (no misleading "camera-free").
- **IV. Performance Requirements** — PASS. Budgets are defined in spec **SC-008** before implementation; T032 verifies them against representative country-scale data. Geocoder latency over the whole-US index is the one genuinely new perf risk — mitigated by bounded search and measured in research R7.

No violations requiring Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/011-country-camera-mapping/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions (extract source, TIGER, geocoder workaround removal, country registry, coverage model, perf)
├── data-model.md        # Phase 1 — Country registry, CoverageArea (reinterpreted as data-region + freshness)
├── quickstart.md        # Phase 1 — operator one-command US setup + switching country
├── contracts/           # Phase 1 — /coverage, /coverage/bounds, /geocode deltas; country-registry contract
│   ├── coverage.md
│   ├── geocoding.md
│   └── country-registry.md
└── checklists/
    └── requirements.md  # Spec quality checklist (already passing)
```

### Source Code (repository root)

```text
backend/
├── app/
│   ├── services/geocoding/geocoder_client.rb        # remove single-state strip; country-aware viewbox/label
│   ├── services/geocoding/country_registry.rb        # NEW — country → { extract_url, viewbox/bbox, tiger:, sub_region_terms }
│   ├── models/coverage_area.rb                        # reinterpret rows as ingested data-regions; per-region freshness
│   ├── controllers/api/v1/coverage_controller.rb      # /coverage returns presence + freshness; /bounds returns country extent
│   ├── jobs/data_refresh_job.rb                        # set freshness per data-region (not update_all)
│   └── services/camera_data/sources/us_tiles.rb        # already CONUS; confirm country-param path
├── config/
│   ├── deploy.yml                                      # GEOCODER_REGION_STATE → GEOCODER_COUNTRY (+ country viewbox)
│   └── locales/{en,es}.yml                             # any new error/coverage strings
├── db/seeds.rb                                         # seed the configured country's dev data-region (default US)
└── spec/                                               # specs for all of the above (Principle II)

infra/
├── scripts/
│   ├── setup.sh                                        # country mode (default US) alongside/over state prompt
│   ├── fetch-extract.sh                                # default whole-US extract; country registry-driven URL
│   ├── build-geocoder.sh                               # whole-US TIGER (all counties) when country=US
│   ├── build-geo.sh                                    # one-command country provisioning (FR-013)
│   └── *.sh                                            # bats-covered changes
├── docker-compose.yml                                  # geocoder viewbox/country env → country defaults
└── README.md / docs/runbooks/geo-stack.md              # country setup + resource guidance

frontend/
└── src/ (MapView)                                      # likely no change — framing already via /coverage/bounds
```

**Structure Decision**: Existing web-app + infra layout is retained. No new top-level
projects. The feature is a *generalization* concentrated in the geocoder service, the
coverage model/endpoints, the infra provisioning scripts, and region→country config —
plus one new backend module (`country_registry`) and the seed/data changes.

## Complexity Tracking

No constitution violations — section intentionally empty.

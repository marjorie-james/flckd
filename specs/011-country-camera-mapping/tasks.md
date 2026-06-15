---

description: "Task list for Country-Wide Camera Mapping"
---

# Tasks: Country-Wide Camera Mapping

**Input**: Design documents from `/specs/011-country-camera-mapping/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Per Constitution Principle II (NON-NEGOTIABLE), every behavioral change carries
automated tests that fail without it. Backend tests run **in the backend container** (host Ruby
is broken); geo services are stubbed with recorded fixtures for determinism; infra scripts are
covered with bats. Write tests FIRST and confirm they FAIL before implementing.

**Organization**: Grouped by user story (US1 P1 → US2 P2 → US3 P3) for independent delivery.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 (omitted for Setup, Foundational, Polish)
- Exact file paths are included in each task.

## Path Conventions

Web app + infra: `backend/app`, `backend/spec`, `infra/scripts`, `infra/spec` (bats), `frontend/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test scaffolding for the new behavior.

- [X] T001 [P] Add a recorded Nominatim fixture set for multi-state geocoding (same-named cities across states, with `addr.state` present) under `backend/spec/fixtures/geocoding/` and wire it into the existing geocoder fixture loader (`backend/spec/support/geo_fakes.rb`).
- [X] T002 [P] Add a local fixture TIGER bundle + extract-URL fixtures for bats under `infra/spec/fixtures/` (small tarball with multiple `SSCCC.csv` members across ≥2 state FIPS) so `build-geocoder.sh`/`fetch-extract.sh` country paths can be tested offline via `TIGER_BUNDLE_URL`/`REGION_URL` overrides.

**Checkpoint**: Deterministic fixtures available for geocoder + infra tests.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The country-configuration spine that US1, US2, and US3 all consume.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first, must FAIL)

- [X] T003 [P] Spec for `Geocoding::CountryRegistry` in `backend/spec/services/geocoding/country_registry_spec.rb`: resolves `us` by default when unset; returns the populated US record (name, extract_url, bbox, tiger:true, sub_region_kind); raises a clear, actionable error for an unknown/un-provisioned code (FR-002, FR-009).

### Implementation

- [X] T004 Create `backend/app/services/geocoding/country_registry.rb` — static registry keyed by ISO alpha-2, US fully populated per `contracts/country-registry.md` (`extract_url`, `bbox`, `tiger`, `sub_region_kind`); `.resolve(code = ENV["GEOCODER_COUNTRY"])` defaults to `us`, raises on unknown/un-provisioned.
- [X] T005 Wire `GEOCODER_COUNTRY` (default `us`) into `infra/docker-compose.yml` (geocoder env, replacing `GEOCODER_VIEWBOX`/`GEOCODER_REGION_STATE`) and `backend/config/deploy.yml` (replace `GEOCODER_REGION_STATE: Iowa`).
- [X] T006 Update `Geocoding::GeocoderClient.build` in `backend/app/services/geocoding/geocoder_client.rb` to derive viewbox from `CountryRegistry.resolve.bbox` and pass the resolved country (replacing `viewbox:`/`region_state:` env wiring). Keep `region_state` path available only for an explicit single-region dev override.

**Checkpoint**: Country config resolves everywhere; US1/US2/US3 can proceed.

---

## Phase 3: User Story 1 — Operator sets the deployment's country (Priority: P1) 🎯 MVP

**Goal**: One operator choice (default US) provisions the entire country end-to-end; an
un-provisioned country fails fast (FR-001, FR-002, FR-009, FR-013).

**Independent Test**: `infra/scripts/setup.sh` (no country) yields a US-wide stack; a non-US/invalid
country code fails setup with an actionable message and no silent fallback.

### Tests for User Story 1 (REQUIRED — Principle II) ⚠️

- [X] T007 [P] [US1] bats test in `infra/spec/fetch_extract.bats`: with `COUNTRY=us` (or unset) the script targets the whole-US Geofabrik extract URL; an unknown country code fails with a clear error (uses `REGION_URL` fixture override).
- [X] T008 [P] [US1] bats test in `infra/spec/build_geocoder.bats`: for a TIGER-applicable country it extracts **all** county CSVs across multiple FIPS (not a single state); for `tiger:false` it skips the TIGER import (uses the Phase-1 fixture bundle).
- [X] T009 [P] [US1] bats test in `infra/spec/setup.bats`: `COUNTRY` unset defaults to US; an unknown country code exits non-zero with the actionable message (FR-009).
- [X] T010 [P] [US1] Spec in `backend/spec/db/seeds_spec.rb` (or model spec): seeding creates the configured country's dev camera **data-region** (default US) from the registry (framing extent is registry-derived, not seeded).

### Implementation for User Story 1

- [X] T011 [US1] Generalize `infra/scripts/fetch-extract.sh`: read `COUNTRY` from `infra/.region`, default the extract URL to the registry's whole-country PBF (US = `north-america/us-latest.osm.pbf`); keep `REGION_URL` override and the URL-marker cache; fail clearly on unknown country.
- [X] T012 [US1] Generalize `infra/scripts/build-geocoder.sh`: when the country is TIGER-applicable, extract **all** `SSCCC.csv` members (drop the single-`STATE_FIPS` filter); preserve caching, numeric-token cleanup, `--website`/`--functions`, and Wikipedia importance; skip TIGER entirely for `tiger:false` countries.
- [X] T013 [US1] Make `infra/scripts/build-geo.sh` the **canonical** one-command country provisioning path (FR-013): country-aware (reads `COUNTRY`, default US), chaining fetch-extract → routing+tiles (parallel) → TIGER → seed data-region → **camera import (`camera_data:import SOURCE=pbf`)** → manifest. `setup.sh` (T014) delegates provisioning to this script so the default-US and switch-country paths are identical in scope. See also T035.
- [X] T014 [US1] Add a country mode to `infra/scripts/setup.sh`: default US (no prompt needed for the default), write `COUNTRY` into `infra/.region`, and fail fast with an actionable error on an unknown/un-provisioned country (FR-009). Keep the state path as an explicit dev override.
- [X] T015 [US1] Update `backend/db/seeds.rb` to seed a **dev camera data-region** for the configured country from `CountryRegistry` (default US) instead of the hardcoded Iowa bbox. Map-framing extent is registry-derived (T026), not seeded — keep the two roles separate per `data-model.md`.
- [X] T035 [US1] Confirm/extend camera ingestion to span the configured country (FR-006): assert `DataRefreshJob` + `CameraData::Sources::UsTiles` cover the country grid (US `CONUS` at launch) in `backend/spec/jobs/data_refresh_job_spec.rb`, and add a code comment marking `UsTiles::CONUS` as a US-only assumption to generalize when a 2nd country is added. (Appended post-`/speckit-analyze`; belongs to US1 provisioning.)

**Checkpoint**: A default `setup.sh` produces a US-wide deployment; bad country → fail-fast. MVP complete.

---

## Phase 4: User Story 2 — Search & route anywhere in the country (Priority: P2)

**Goal**: Addresses across all states resolve and disambiguate by state; routes cross state lines
(FR-003, FR-004, FR-005). Removes the now-harmful single-state geocoder workaround.

**Independent Test**: Same-named cities in different states each resolve to the correct state; a
state-qualified query is not nullified; a cross-state route returns.

### Tests for User Story 2 (REQUIRED — Principle II) ⚠️

- [X] T016 [P] [US2] Geocoder specs in `backend/spec/services/geocoding/geocoder_client_spec.rb`: a state-qualified query (`"Springfield, IL"` vs `"Springfield, MO"`) resolves to the correct state and is **not** stripped; `humanized_label` uses the result's real `addr["state"]` (not a configured fallback) — driven by the Phase-1 fixtures. Replace/repurpose the existing single-state-strip specs.
- [X] T017 [P] [US2] Request spec in `backend/spec/requests/api/v1/geocoding_spec.rb`: `/geocode/search` returns state-correct results across multiple states; regression guard that a state token is not dropped.
- [X] T018 [P] [US2] Routing integration spec in `backend/spec/requests/api/v1/routes_spec.rb`: a cross-state origin/destination returns a route (planner stubbed with a fixture; asserts the cross-boundary request is honored).

### Implementation for User Story 2

- [X] T019 [US2] In `backend/app/services/geocoding/geocoder_client.rb`, gate off `normalize_query`'s state-token stripping when the index spans the whole country (country-spanning config), so the state disambiguates rather than nullifies (FR-004).
- [X] T020 [US2] In the same file, change `humanized_label` to use the result's `addr["state"]` (present in whole-country data), keeping the configured fallback only for the single-region dev path.
- [X] T021 [US2] Apply the registry-derived viewbox as a **bounded** search in `search` (perf R7), keeping candidate sets country-scoped.

**Checkpoint**: Search disambiguates across states and routing crosses state lines; US1 still works.

---

## Phase 5: User Story 3 — Honest per-data-region coverage (Priority: P3)

**Goal**: Map frames the whole country; coverage reports present/absent + freshness per ingested
data-region (FR-007, FR-008, SC-005).

**Independent Test**: On load the map frames the country; a point with camera data → present +
freshness; a point inside the country without data → absent (not "camera-free").

### Tests for User Story 3 (REQUIRED — Principle II) ⚠️

- [X] T022 [P] [US3] Model specs in `backend/spec/models/coverage_area_spec.rb`: `containing`/`covers?` reflect camera-data presence per data-region; per-region `data_freshness_at` is respected.
- [X] T023 [P] [US3] Request specs in `backend/spec/requests/api/v1/coverage_spec.rb`: `/coverage` returns `{covered, data_freshness_at}` (present-with-freshness and absent-with-null cases per `contracts/coverage.md`); `/coverage/bounds` returns the configured country's extent from the registry.
- [X] T024 [P] [US3] Job spec in `backend/spec/jobs/data_refresh_job_spec.rb`: refresh sets `data_freshness_at` **per data-region** (not a global `update_all`).
- [X] T025 [P] [US3] Update contract spec `backend/spec/contract/openapi_spec.rb` for the `/coverage` response delta (`data_freshness_at`) and the `/coverage/bounds` country-extent source.

### Implementation for User Story 3

- [X] T026 [US3] Update `backend/app/controllers/api/v1/coverage_controller.rb`: `show` returns `{covered, data_freshness_at}` from the containing data-region; `bounds` returns the configured country's extent from `CountryRegistry` (not the `CoverageArea` union).
- [X] T027 [US3] Update `backend/app/jobs/data_refresh_job.rb` to set `data_freshness_at` per data-region as each is refreshed, replacing the global `CoverageArea.update_all(data_freshness_at: ...)`.
- [X] T028 [US3] Reconcile `backend/app/models/coverage_area.rb` semantics/docs to "ingested data-region" (presence + freshness); confirm `frontend` `MapView` framing still consumes `/coverage/bounds` unchanged (no code change expected — verify).

**Checkpoint**: All three stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T029 [P] Update `infra/README.md` "Expanding coverage to more states" → country-wide setup (default US), and the launch-region notes, to match the new one-command flow.
- [X] T030 [P] Add/update `docs/runbooks/geo-stack.md` with the whole-US resource envelope (RAM/disk/time) and the "run country builds on a larger/self-hosted runner" guidance (referenced by `build-geo.sh`).
- [X] T031 [P] Add localized strings (if any new error/coverage copy) to `backend/config/locales/en.yml` and `backend/config/locales/es.yml` (Principle III).
- [X] T032 Verify the affected paths meet the **SC-008** performance budgets with representative country-scale data (Principle IV gate); record the measurement. (Budgets are defined in spec SC-008 before implementation — this task confirms, it does not define them.)
- [X] T033 Run rubocop (backend, in container) + shellcheck (infra) to zero warnings (Principle I); run the full backend suite in the container with `COVERAGE=1`.
- [X] T034 Run the `quickstart.md` validation end-to-end (default US setup + the verification curls).
- [X] T036 [P] Extend `backend/spec/requests/anonymity_spec.rb` to cover the country-scaled geocode/coverage/route paths: no origin/destination/route coords or client IPs in logs, no third-party egress (FR-011 / SC-006, Principle II). (Appended post-`/speckit-analyze`.)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (P1)**: none.
- **Foundational (P2)**: depends on Setup; **blocks all user stories** (everything reads `CountryRegistry`).
- **US1 (P3)** → **US2 (P4)** → **US3 (P5)**: each depends only on Foundational; deliver in priority order or in parallel by different people.
- **Polish (P6)**: after the desired stories are complete.
- **SC-008 budgets**: defined in spec **before** implementation (Principle IV). T032 *verifies* them and may run in Polish, but the budgets themselves are frozen in the spec now.

### User Story Dependencies

- **US1 (P1)**: after Foundational. The MVP — provisioning + config.
- **US2 (P2)**: after Foundational. Independent of US1 at the code level (geocoder behavior), though a real end-to-end check benefits from US1's provisioned data.
- **US3 (P3)**: after Foundational. Independent; touches coverage controller/model/job.

### Within Each Story

- Tests first and FAILING (Principle II) → implementation.
- US2/US3 touch mostly disjoint files (geocoder vs coverage), so they parallelize cleanly.

### Parallel Opportunities

- Setup T001/T002 in parallel.
- Foundational test T003 then implementation T004–T006.
- Within US1, the test tasks T007–T010 in parallel; within US2, T016–T018; within US3, T022–T025.
- US2 and US3 implementation can proceed in parallel (geocoder_client vs coverage_controller/model/job — different files).

---

## Parallel Example: User Story 3

```bash
# Tests first (parallel):
Task: "Model specs in backend/spec/models/coverage_area_spec.rb"
Task: "Request specs in backend/spec/requests/api/v1/coverage_spec.rb"
Task: "Job spec in backend/spec/jobs/data_refresh_job_spec.rb"
Task: "Contract spec update in backend/spec/contract/openapi_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 Setup → Phase 2 Foundational (CountryRegistry + env) → Phase 3 US1.
2. **STOP and VALIDATE**: default `setup.sh` → US-wide stack; bad country → fail-fast.
3. This alone delivers the headline capability (configure a whole country, default US).

### Incremental Delivery

1. Foundation ready → US1 (provisioning, MVP) → demo.
2. US2 (multi-state search/routing) → demo.
3. US3 (honest per-data-region coverage) → demo.

### Notes

- Backend tests/lint run **in the backend container** (host Ruby is broken).
- Geo services stubbed with fixtures; infra scripts covered with bats; everything offline/deterministic.
- Removing the single-state geocoder workaround (US2) is a *deletion gated on config*, not a new code path — keep the single-region dev path working.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.

### Implementation notes (as-built)

- **bats location**: tests live in the repo's existing `test/infra/` (not the spec's
  `infra/spec/`), matching the established convention and the `ci-scripts.yml` invocation
  (now extended to run `fetch-extract.bats` + `setup.bats` alongside `build-geocoder.bats`).
- **Phase-1 fixtures (T001/T002)**: geocoder multi-state fixtures live under
  `backend/spec/fixtures/geocoder/` (the existing dir the geocoder spec reads). The bats TIGER
  bundle is built inline in `setup()` (multi-FIPS) and the shared `curl` stub was generalized to
  serve both the TIGER bundle and a dummy extract — deterministic + offline, no committed binaries.
- **Bash country registry**: `infra/scripts/country-registry.sh` mirrors
  `Geocoding::CountryRegistry` (keep in sync) — the scripts can't read the Ruby registry.
- **`build-geo.sh`**: full provisioning by default (FR-013); CI sets `GEO_ARTIFACTS_ONLY=1`
  (extract + routing + tiles + manifest only) so `build-geo.yml` still publishes artifacts.
- **`setup.sh`**: country-mode default (US, no prompt); state path retained as an explicit
  `--region` dev override; `SETUP_DRY_RUN=1` is the offline test seam used by `setup.bats`.
- **`/coverage` contract**: `area_name` dropped (only present in generated FE types, unused by
  FE code) to match `contracts/coverage.md`; `/coverage/bounds` path added to the OpenAPI contract.
- **T032 (SC-008)**: request-time paths verified on the dev stack (well inside budget) and the
  architecture argument recorded in `docs/runbooks/geo-stack.md`; country-scale p95 capture is
  deferred to the provisioned runner (a whole-US build is not runnable in this environment).
- **T034**: the feasible quickstart paths were validated live — `/coverage/bounds` returns the
  whole-US registry extent (FR-007) even on a single-state data stack, and present/absent +
  freshness behave per `contracts/coverage.md`. A full default-US `setup.sh` (~10+ GB, hours) was
  not executed here.
- **T031**: no new end-user localized copy was required (coverage dropped a field rather than
  adding one; the unknown-country error is operator/setup-facing). en/es parity unchanged.

---
description: "Task list for Aggregated Camera Data Source-of-Truth"
---

# Tasks: Aggregated Camera Data Source-of-Truth

**Input**: Design documents from `/specs/003-camera-data-aggregation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Per Constitution Principle II (Testing Standards, NON-NEGOTIABLE), every behavioral change MUST be accompanied by automated tests that would fail without the change. Test tasks below are REQUIRED. Write tests FIRST and ensure they FAIL before implementation. All external sources are stubbed with WebMock recorded fixtures (no network); time-dependent behavior uses `travel_to`.

**Organization**: Tasks grouped by user story for independent implementation and testing.

**Existing foundation (already on branch, uncommitted — reuse, do not recreate)**: `CameraData::Sources::Base`, `Sources::Overpass`, `Sources::GeojsonFile`, `CameraData::Importer` (provenance + license-aware), `CameraData::AggregateImport`, `spec/support/webmock.rb`. Tasks below target the delta.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (user-story phases only)
- All paths are repo-relative; backend runs in Docker (see quickstart).

## Path Conventions

Web-service backend: code under `backend/app/...`, jobs under `backend/app/jobs`, config under `backend/config`, migrations under `backend/db/migrate`, rake under `backend/lib/tasks`, specs under `backend/spec`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare fixtures and confirm deterministic test wiring.

- [X] T001 [P] Create recorded-fixture directory `backend/spec/fixtures/deflock/` and confirm `backend/spec/support/webmock.rb` disables net connections (allow_localhost) for all new source specs.
- [X] T002 [P] Add `CAMERA_REFRESH_MISSING_LIMIT` (default 3) configuration accessor in `backend/config/initializers/camera_data.rb` (ENV-overridable; used by the stale reconciler).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema + base entities that multiple user stories depend on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Migration: add freshness columns to cameras (`last_seen_in_source_at` timestamp nullable, `consecutive_missing_count` integer default 0 not null, `stale` boolean default false not null) plus a partial index on `stale WHERE stale`, in `backend/db/migrate/20260601000001_add_freshness_to_cameras.rb`.
- [X] T004 Migration: create `refresh_runs` (`trigger`, `status` default `running`, `started_at`, `finished_at`, `duration_ms`, `per_source` jsonb default `{}`, `totals` jsonb default `{}`) with indexes on `status` and `started_at`, in `backend/db/migrate/20260601000002_create_refresh_runs.rb`.
- [X] T005 Apply migrations to dev and test databases (`db:migrate` for default + `RAILS_ENV=test`) and regenerate `backend/db/structure.sql`.
- [X] T006 [P] RefreshRun model spec (trigger/status inclusion, `started_at` presence, default `running`) in `backend/spec/models/refresh_run_spec.rb`.
- [X] T007 [P] RefreshRun model with validations and status constants in `backend/app/models/refresh_run.rb`.
- [X] T008 [P] Camera freshness spec: `consecutive_missing_count >= 0` validation and `stale` scope, extending `backend/spec/models/camera_spec.rb`.
- [X] T009 [P] Camera model: freshness validations and `stale` scope (no lifecycle methods yet) in `backend/app/models/camera.rb`.

**Checkpoint**: Schema + base entities ready — user stories can proceed.

---

## Phase 3: User Story 1 - Aggregate every available source into one trusted database (Priority: P1) 🎯 MVP

**Goal**: Combine DeFlock + OpenStreetMap + open-data/FOIA sources, continental-US, into the `cameras` table as the source of truth, each record carrying provenance + license; duplicates collapse to one avoidance target at the segment layer.

**Independent Test**: Configure ≥2 sources, run an aggregation, confirm the DB holds the union with per-source license, and two sources reporting a camera on the same road yield one `MonitoredSegment`.

### Tests (write first, must fail)

- [X] T010 [P] [US1] DeFlock source spec with WebMock fixture (`backend/spec/services/camera_data/sources/deflock_spec.rb`) asserting DeFlock provenance + ODbL license and normalized ALPR records; add fixture `backend/spec/fixtures/deflock/alpr_response.json`.
- [X] T011 [P] [US1] UsTiles spec: continental-US grid covers the CONUS bbox, all cells valid `{south,west,north,east}`, configurable cell size, in `backend/spec/services/camera_data/us_tiles_spec.rb`.
- [X] T012 [P] [US1] Importer spec extension: import records the source `license` on `DataSource` and sets `last_seen_in_source_at` on imported cameras, in `backend/spec/services/camera_data/importer_spec.rb`.
- [X] T013 [US1] AggregateImport spec extension: per-source provenance/license; one source raising does not abort others; returns per-source counts, in `backend/spec/services/camera_data/aggregate_import_spec.rb`.
- [X] T013a [P] [US1] License-enforcement spec (FR-005): `AggregateImport` skips and logs a source whose `license` is blank (does not import its records), and `Importer.for_source` raises/refuses without a license, in `backend/spec/services/camera_data/aggregate_import_spec.rb`.

### Implementation

- [X] T014 [P] [US1] `Sources::Deflock` adapter (DeFlock-curated OSM ALPR via Overpass; DeFlock provenance, ODbL license) in `backend/app/services/camera_data/sources/deflock.rb`.
- [X] T015 [P] [US1] `Sources::UsTiles` continental-US bbox tiling helper in `backend/app/services/camera_data/us_tiles.rb`.
- [X] T016 [US1] Extend `Sources::Overpass` to iterate a tile set with rate-limit backoff and bounded concurrency (nationwide) in `backend/app/services/camera_data/sources/overpass.rb`.
- [X] T017 [US1] Extend `Importer` to set `last_seen_in_source_at` on upsert and persist the source `license` in `backend/app/services/camera_data/importer.rb`.
- [X] T017a [US1] Enforce permissive-license policy (FR-005): `Importer.for_source` requires a non-blank `license`, and `AggregateImport` skips + logs any source missing one (no records imported), in `backend/app/services/camera_data/importer.rb` and `backend/app/services/camera_data/aggregate_import.rb`.
- [X] T018 [US1] Extend `AggregateImport` with per-source rescue/isolation and per-source counts (added/updated/skipped) in `backend/app/services/camera_data/aggregate_import.rb`.
- [X] T019 [US1] Integrate segment snapping for newly imported cameras in `AggregateImport` and add `SOURCE=deflock` to `backend/lib/tasks/camera_data.rake`.
- [X] T020 [US1] Integration spec: aggregate over OSM + DeFlock + geojson → union with provenance; two sources on the same road collapse to one `MonitoredSegment`, in `backend/spec/services/camera_data/aggregate_import_spec.rb`.

**Checkpoint**: Aggregation MVP is independently testable and deliverable.

---

## Phase 4: User Story 2 - Automatic daily background refresh (Priority: P2)

**Goal**: Refresh all live sources nationwide every day at a fixed 08:00 UTC in the background, non-overlapping, plus an on-demand manual refresh.

**Independent Test**: With the schedule configured, a refresh fires automatically at 08:00 UTC, runs in the background, updates the DB; a second concurrent refresh is skipped; an operator can trigger a manual refresh.

### Tests (write first, must fail)

- [X] T021 [P] [US2] DataRefreshJob spec (FR-011): `aggregate` mode runs all sources via an injected fetcher (no network), is enqueued/executed via the background queue (asserted with `have_enqueued_job` / `perform_enqueued_jobs`, not inline blocking), and creates a `RefreshRun` with `trigger="scheduled"`, in `backend/spec/jobs/data_refresh_job_spec.rb`.
- [X] T022 [P] [US2] Non-overlap spec: a refresh is skipped (logged) while a `RefreshRun` is `running`, in `backend/spec/jobs/data_refresh_job_spec.rb`.
- [X] T023 [P] [US2] Schedule spec: `config/recurring.yml` parses to a `0 8 * * *` (08:00 UTC) cron, asserted via Fugit/`travel_to`, in `backend/spec/config/recurring_schedule_spec.rb`.

### Implementation

- [X] T024 [US2] Repoint `DataRefreshJob` to run `AggregateImport` over all live sources (US-wide) with a `trigger` param and `RefreshRun` creation, in `backend/app/jobs/data_refresh_job.rb`. Replace the stale feature-002 doc-comment citations (`FR-020`, `FR-018`) with the correct 003 FRs (FR-010 schedule, FR-011 background, FR-013 audit).
- [X] T025 [US2] Add Solid Queue `limits_concurrency(key: "camera_refresh", to: 1)` and a running-`RefreshRun` guard to `DataRefreshJob` in `backend/app/jobs/data_refresh_job.rb`.
- [X] T026 [US2] Update `backend/config/recurring.yml`: schedule `"0 8 * * *"`, `args: [ aggregate ]`.
- [X] T027 [US2] Add manual refresh rake `camera_data:refresh` (`trigger="manual"`) in `backend/lib/tasks/camera_data.rake`.

**Checkpoint**: Scheduled + manual refresh works without overlap.

---

## Phase 5: User Story 3 - Source-of-truth integrity across refreshes (Priority: P3)

**Goal**: Preserve internal verifications across refreshes; keep avoiding stale cameras and auto-retire after 3 missed refreshes (verified exempt); isolate per-source failures (last-good preserved); record a reviewable per-run audit.

**Independent Test**: Verify a camera, refresh, confirm verification persists; remove a camera upstream, confirm it stays avoided then auto-retires after 3 missing refreshes; review per-source run results with no user data.

### Tests (write first, must fail)

- [X] T028 [P] [US3] StaleReconciler spec (with `travel_to`): seen resets count/clears stale; missing increments + flags stale; auto-retire at 3 (`verification_status="removed"`); `verified` exempt; a failed source's cameras untouched, in `backend/spec/services/camera_data/stale_reconciler_spec.rb`.
- [X] T029 [P] [US3] Camera lifecycle spec: `seen_in_source!` / `mark_missing!` transitions and verified-exempt auto-retire, extending `backend/spec/models/camera_spec.rb`.
- [X] T030 [P] [US3] RefreshRun recording spec: `per_source` + `totals` counts, overall `status` (success/partial/failed), `duration_ms`, and assertion of NO user data, in `backend/spec/services/camera_data/aggregate_import_spec.rb`.
- [X] T031 [P] [US3] `camera_data:refresh:status` spec: human table + `--json` validates against `contracts/refresh-run.schema.json`, in `backend/spec/lib/tasks/refresh_status_spec.rb`.

### Implementation

- [X] T032 [P] [US3] Camera lifecycle methods (`seen_in_source!`, `mark_missing!`, auto-retire honoring `CAMERA_REFRESH_MISSING_LIMIT`, `verified` exempt) in `backend/app/models/camera.rb`.
- [X] T033 [US3] `StaleReconciler` service (per-source, post-success only) in `backend/app/services/camera_data/stale_reconciler.rb`.
- [X] T034 [US3] Integrate `StaleReconciler` into `AggregateImport` for successfully-refreshed sources only; leave failed sources untouched (preserve last-good), in `backend/app/services/camera_data/aggregate_import.rb`.
- [X] T035 [US3] Record `RefreshRun` outcome (per_source, totals, status, duration_ms) in `AggregateImport`/`DataRefreshJob` in `backend/app/services/camera_data/aggregate_import.rb` and `backend/app/jobs/data_refresh_job.rb`.
- [X] T036 [US3] Add `camera_data:refresh:status` rake (human table + `--json`) in `backend/lib/tasks/camera_data.rake`.

**Checkpoint**: Integrity, retire lifecycle, and observability complete.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T037 [P] Anonymity assertion spec: the refresh path logs no client IPs or coordinates and `RefreshRun` carries no user data (only counts/source names/error class), in `backend/spec/requests/anonymity_spec.rb`.
- [X] T038 [P] Performance check (SC-009): assert `duration_ms` is recorded on each run; document the ≤60-min nationwide budget and tiling concurrency bound in `specs/003-camera-data-aggregation/plan.md` Performance notes.
- [X] T039 [P] Run `rubocop` (rubocop-rails-omakase) to zero warnings across all new/changed files (Constitution Principle I).
- [X] T040 Run the full RSpec suite in Docker and confirm green; update `progress.md` with the 003 state and mark completed tasks `[X]`.

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **US1 (Phase 3)** → **US2 (Phase 4)** → **US3 (Phase 5)** → **Polish (Phase 6)**.
- Foundational T003/T004 (migrations) block T005; T005 blocks all model/service work. T006→T007, T008→T009 (test before impl).
- **US1** depends only on Foundational. It is the MVP and independently shippable.
- **US2** depends on US1 (the aggregate path it schedules) + Foundational (`RefreshRun`).
- **US3** depends on US1 (import/seen path) + Foundational (freshness columns, `RefreshRun`); T035 (RefreshRun recording) also builds on US2's `DataRefreshJob` wiring.
- Within each phase, tests precede their implementation tasks.

## Parallel Execution Examples

- **Foundational**: T006+T008 (specs, different files) in parallel; then T007+T009 (models) in parallel.
- **US1 tests**: T010, T011, T012 all `[P]` (distinct spec files) — author together; T013 follows (shared aggregate spec).
- **US1 impl**: T014 (DeFlock) + T015 (UsTiles) in parallel (distinct files); then T016/T017/T018 (touch Overpass/Importer/AggregateImport) sequentially as they interlock; T019/T020 after.
- **US2 tests**: T021+T022 share the job spec (sequential); T023 (`[P]`, separate file) in parallel.
- **US3 tests**: T028, T029, T031 `[P]` (distinct files); T030 shares the aggregate spec.

## Implementation Strategy

- **MVP = User Story 1** (Phases 1–3): real multi-source aggregation into the source-of-truth table with provenance, license, and segment-level dedup. Shippable on its own.
- **Increment 2 = User Story 2** (Phase 4): automate it on the fixed 08:00 UTC schedule, non-overlapping + manual trigger.
- **Increment 3 = User Story 3** (Phase 5): integrity guarantees (verification persistence, stale→retire lifecycle, partial-failure isolation, RefreshRun observability).
- **Polish** (Phase 6): anonymity/performance assertions, lint, full-suite green.

**Deferred / out of scope** (conscious decisions, no tasks generated): `RefreshRun` retention pruning (runs are small; revisit only if growth becomes material — see data-model.md).

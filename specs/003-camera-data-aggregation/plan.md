# Implementation Plan: Aggregated Camera Data Source-of-Truth

**Branch**: `003-camera-data-aggregation` | **Date**: 2026-06-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-camera-data-aggregation/spec.md`

## Summary

Aggregate ALPR/Flock camera locations from multiple permissively-licensed sources — DeFlock and
OpenStreetMap as live integrations, plus a generic open-data/FOIA file importer — into the existing
`cameras` table, which is the authoritative source of truth. Each record keeps its provenance and license;
the same physical camera reported by several sources collapses to a single avoidance target at the
monitored-segment layer (no camera-level merge). A background job refreshes the entire continental US daily
at a fixed **08:00 UTC**, isolating per-source failures, recording a per-run audit (`RefreshRun`), and never
running two refreshes concurrently. Cameras that vanish from a source stay avoided while flagged stale and
auto-retire after 3 consecutive missing daily refreshes (human-verified cameras are exempt). No user data is
ever sent to a source; refresh logs retain no IPs or coordinates.

This extends feature 002's data model and the `CameraData::Sources` / `AggregateImport` foundation already
present on this branch; it adds the DeFlock source, the `RefreshRun` entity, camera freshness/stale tracking,
and the fixed-UTC scheduled aggregate refresh.

## Technical Context

**Language/Version**: Ruby 3.4.9 (runs in Docker; host Ruby native exts are broken — see quickstart)

**Primary Dependencies**: Rails 8.1.3 (API mode), Solid Queue (recurring jobs + concurrency control),
Faraday (HTTP to Overpass/DeFlock), RGeo + activerecord-postgis-adapter (geometry), Oj (JSON). Test: RSpec,
WebMock (recorded fixtures, no network), FactoryBot.

**Storage**: PostgreSQL 16 + PostGIS (existing `cameras`, `data_sources`, `monitored_segments`,
`coverage_areas`; new `refresh_runs` table + new columns on `cameras`).

**Testing**: RSpec with WebMock-stubbed external sources backed by recorded fixtures; deterministic, no
network (Constitution Principle II). Runs in Docker only.

**Target Platform**: Linux server (Docker); Kamal 2 + Thruster deploy; Solid Queue worker (in-Puma or
standalone).

**Project Type**: Web service — Rails API backend. This feature is backend/data-pipeline only; no frontend
changes.

**Performance Goals**: The nationwide daily refresh runs entirely in the background and MUST NOT degrade
user-facing routing (routing p95 budget from feature 002 is unchanged). External-source fetching is tiled
and deliberately single-concurrency to respect public-source fair-use, so a nationwide run may take a few
hours against the public Overpass endpoint — acceptable for a once-daily job (a self-hosted endpoint brings
it well under an hour). Duration is recorded per run (SC-009).

**Constraints**: Strict anonymity (FR-016/FR-017) — no user origin/destination/route/IP transmitted to any
source; refresh/import logs retain no client IPs or route coordinates. Only sources whose terms permit reuse
may be ingested, with recorded license/attribution (FR-005). Deterministic tests (no live third-party calls).

**Scale/Scope**: Continental-US ALPR dataset — order tens of thousands of cameras, growing; one scheduled
refresh per day plus on-demand manual refresh; modest job volume well within Solid Queue's envelope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Code Quality**: PASS. `rubocop-rails-omakase` must pass with zero warnings. Each source is a single
  adapter with one responsibility (`fetch` → normalized records); aggregation, stale reconciliation, and
  run-recording are separate units (`AggregateImport`, a reconciler, `RefreshRun`). Adapters carry
  intent-documenting comments (provenance/license/legitimacy notes). No dead code.
- **II. Testing Standards (NON-NEGOTIABLE)**: PASS. Every behavioral change is test-first: DeFlock adapter
  (WebMock fixture), stale-retire reconciliation (model/service specs across simulated refreshes), partial-
  failure isolation (one source raises, others persist), RefreshRun recording, fixed-UTC schedule
  (config + schedule-parse assertion). Security/data-mutation paths (ingestion, auto-retire) get explicit
  coverage. All deterministic via recorded fixtures; suite green in CI before merge.
- **III. User Experience Consistency**: PASS. Operator surface is the `camera_data:*` rake namespace plus a
  manual-refresh entry point; output is human-readable with a structured per-source summary that mirrors the
  `RefreshRun` record. Source failures produce actionable messages (which source, why, that others
  continued). Terminology (`source`, `provenance`, `stale`, `retired`, `refresh run`) is used consistently
  across spec, data model, and code.
- **IV. Performance Requirements**: PASS. Explicit budget defined (≤60 min nationwide refresh; background,
  non-blocking). Overpass/DeFlock requests are tiled by region and concurrency-bounded so resource usage is
  bounded under sustained load; the refresh never runs concurrently with itself. Measurement approach noted
  in research (record per-run duration in `RefreshRun`).

No violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/003-camera-data-aggregation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (rake/CLI + RefreshRun summary contract)
│   ├── refresh-cli.md
│   └── refresh-run.schema.json
└── checklists/
    └── requirements.md  # from /speckit-specify
```

### Source Code (repository root)

```text
backend/
├── app/
│   ├── models/
│   │   ├── camera.rb                         # + freshness/stale fields, stale!/retire!/seen! transitions
│   │   ├── data_source.rb                    # (license already present; used for attribution)
│   │   └── refresh_run.rb                    # NEW — per-run audit (no user data)
│   ├── services/
│   │   └── camera_data/
│   │       ├── sources/
│   │       │   ├── base.rb                    # EXISTS (adapter contract)
│   │       │   ├── overpass.rb                # EXISTS (OSM ALPR; extend to nationwide tiling)
│   │       │   ├── geojson_file.rb            # EXISTS (open-data/FOIA importer)
│   │       │   └── deflock.rb                 # NEW — DeFlock live source
│   │       ├── importer.rb                    # EXISTS (provenance + license upsert; mark seen-in-source)
│   │       ├── aggregate_import.rb            # EXISTS — extend: per-source failure isolation + RefreshRun
│   │       ├── stale_reconciler.rb            # NEW — flag stale / auto-retire after N misses
│   │       └── us_tiles.rb                    # NEW — continental-US bbox tiling helper
│   └── jobs/
│       └── data_refresh_job.rb               # EXISTS — repoint to AggregateImport over all sources, US-wide
├── config/
│   └── recurring.yml                          # EXISTS — change schedule to fixed 08:00 UTC, aggregate args
├── db/migrate/
│   ├── *_add_freshness_to_cameras.rb          # NEW
│   └── *_create_refresh_runs.rb               # NEW
├── lib/tasks/
│   └── camera_data.rake                       # EXISTS — add manual aggregate refresh + refresh:status
└── spec/
    ├── fixtures/{overpass,deflock,camera_data}/  # recorded source responses
    ├── services/camera_data/                    # deflock_spec, stale_reconciler_spec, aggregate_import (extend)
    ├── models/{camera_spec,refresh_run_spec}.rb
    └── jobs/data_refresh_job_spec.rb
```

**Structure Decision**: Web-service backend (backend only). The feature lives entirely in the existing
`backend/` Rails app under `app/services/camera_data` (sources + orchestration), `app/jobs` (scheduled
refresh), `app/models` (Camera/DataSource/RefreshRun), and `config/recurring.yml` (schedule). No frontend
work. This reuses the structure and conventions established by feature 002.

## Complexity Tracking

> No constitution violations — section intentionally empty.

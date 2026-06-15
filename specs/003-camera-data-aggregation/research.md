# Phase 0 Research: Aggregated Camera Data Source-of-Truth

**Feature**: `003-camera-data-aggregation` · **Date**: 2026-06-01

All Technical Context unknowns are resolved below. Each item: Decision / Rationale / Alternatives.

## R1. DeFlock data access and license (legitimacy gate)

**Decision**: Treat DeFlock's authoritative ALPR dataset as **OpenStreetMap data under ODbL**, ingested via
the existing Overpass adapter — not via scraping DeFlock's website. DeFlock's own backend API
(`FoggedLens/deflock`) exposes only `/geocode`, `/sponsors/github`, and `/healthcheck`; it has **no public
camera-read endpoint**. DeFlock is "powered by OpenStreetMap": contributors submit ALPR locations that are
stored in OSM (`man_made=surveillance` + `surveillance:type=ALPR`), which is ODbL-licensed and freely
exportable. The dedicated `Sources::Deflock` adapter is therefore a thin, attributed configuration over the
OSM/Overpass pipeline (optionally narrowing to DeFlock-curated nodes), recording DeFlock as the community
provenance and ODbL as the license. If DeFlock later publishes a permissively-licensed bulk export, it can
be onboarded through the generic `Sources::GeojsonFile` importer with no redesign.

**Rationale**: Honors FR-005 (ingest only where terms permit; record license) and the project's
legitimate-sourcing stance — OSM/ODbL explicitly permits reuse with attribution, whereas scraping the
DeFlock SPA has no such grant and is brittle. It also means "DeFlock" and "OpenStreetMap" draw from the same
licensed substrate, so duplicates between them collapse naturally at the segment layer (FR-006).

**Alternatives considered**: Scraping `maps.deflock.org` markers — rejected (no license grant, brittle,
against the legitimate-path stance). Inventing a DeFlock REST endpoint — rejected (confirmed not to exist).
Skipping DeFlock as redundant with OSM — rejected: keeping it as a named source preserves explicit
provenance/attribution and lets a future DeFlock export slot in.

## R2. Continental-US extent and request tiling

**Decision**: Tile the continental-US bounding box into a grid of smaller bbox cells (`Sources::UsTiles`)
and iterate Overpass/DeFlock per cell with rate-limit backoff and bounded concurrency. A single nationwide
Overpass query is not viable (server timeout/memory caps). Tile size is configurable; cells are processed
sequentially or at low concurrency to stay within the public endpoint's fair-use limits, and the endpoint is
configurable so a self-hosted Overpass instance can lift those limits.

**Rationale**: Satisfies FR-019 (nationwide each refresh) within the ≤60-min performance budget while
respecting source fair-use (the legitimate-path requirement). Tiling also bounds memory (Principle IV) and
lets a failed tile be retried without restarting the whole run.

**Alternatives considered**: One giant bbox query (rejected — exceeds Overpass limits). Per-state queries
(viable; a coarser special case of tiling — tiling generalizes it). Daily OSM planet/Geofabrik extract
diffing (heavier ops; deferred — revisit if tiled Overpass proves too slow at scale).

## R3. Fixed 08:00 UTC daily schedule (Solid Queue)

**Decision**: Schedule the refresh in `config/recurring.yml` with an explicit **UTC cron**: `schedule: "0 8
* * *"` (08:00 UTC daily), replacing the earlier TZ-ambiguous `every day at 4am`. The app runs with
`Time.zone`/`config.time_zone` at UTC, and Solid Queue recurring schedules are parsed by Fugit; an explicit
numeric cron avoids any local-time interpretation. A regression test asserts the parsed schedule fires at
08:00 UTC.

**Rationale**: Implements the clarified decision (fixed 08:00 UTC = 2am CST / 3am CDT, no DST adjustment,
SC-006). A numeric UTC cron is unambiguous and DST-immune by construction.

**Alternatives considered**: `every day at 4am` natural-language schedule (rejected — interpreted in the
process time zone; ambiguous and fragile). A `America/Chicago` cron (rejected — the clarification chose a
fixed UTC instant, not DST-aware local). External cron/systemd timer (rejected — adds ops surface; Solid
Queue recurring is in-box).

## R4. Preventing overlapping refreshes

**Decision**: Guard the refresh two ways: (1) Solid Queue `limits_concurrency(key: "camera_refresh", to: 1)`
on `DataRefreshJob` so a second enqueue cannot run while one is active; (2) a defensive check that no
`RefreshRun` is in the `running` state before starting, short-circuiting with a logged skip if one is. The
`RefreshRun` is marked `running` at start and `success`/`partial`/`failed` at finish (with `finished_at`).

**Rationale**: FR-014 (no concurrent duplicate runs). Belt-and-suspenders: the concurrency key handles the
queue layer; the RefreshRun guard handles manual + scheduled overlap and survives a worker restart.

**Alternatives considered**: PostgreSQL advisory lock (works, but a persisted RefreshRun also gives the
observability FR-013 needs, so it does double duty). Relying on a single worker (rejected — fragile
assumption).

## R5. Stale-camera lifecycle and reconciliation

**Decision**: Add freshness tracking to `cameras`: `last_seen_in_source_at`, `consecutive_missing_count`
(default 0), and a `stale` boolean (derived/explicit). The `StaleReconciler` runs **per source after that
source's fetch succeeds**: cameras of that source seen this run reset `consecutive_missing_count` to 0,
clear `stale`, and set `last_seen_in_source_at`; cameras not seen increment `consecutive_missing_count` and
set `stale=true`. When `consecutive_missing_count >= 3` (configurable) the camera is **auto-retired**
(`verification_status: "removed"`, which the existing `active`/`routable` scopes already exclude from
routing) — **unless** `verification_status == "verified"`, which is exempt and never auto-retired. A
re-appearing camera resets the counter and clears stale. Stale-but-not-retired cameras remain routable.

**Rationale**: Implements FR-008/FR-009 and the clarified 3-miss grace window. Reusing the existing
`verification_status` enum (`removed` already excluded from routing) avoids a parallel state machine and
keeps "verified is sticky" trivially true. Per-source, post-success reconciliation is what makes
partial-failure isolation correct (a failed source must not retire its cameras — see R6).

**Alternatives considered**: Time-based staleness (e.g. "missing > 3 days") — rejected: count-of-missed-runs
is deterministic and testable without wall-clock coupling. A separate `lifecycle_state` column — rejected:
overlaps `verification_status`; would create contradictory states.

## R6. Partial-failure isolation and the RefreshRun audit

**Decision**: `AggregateImport` wraps **each source** in its own rescue: a source that raises is recorded as
`failed` for that source (error class only) and the run continues with the others; its cameras are **not**
reconciled or retired (last-good data preserved). A new `RefreshRun` row records, per source, counts of
added/updated/skipped and failure status, plus overall `status` (`success` if all sources succeeded,
`partial` if some failed, `failed` if all did), `started_at`, `finished_at`, and trigger (`scheduled` or
`manual`). `RefreshRun` contains **no user data** — only reference-data counts and source names.

**Rationale**: FR-012 (partial-failure isolation; preserve last good) and FR-013 (per-run observability
without user data). Recording only the error **class** (not arbitrary message bodies) keeps logs clean and
anonymity-safe (FR-017), and there is no user data in this pipeline to leak.

**Alternatives considered**: Abort the whole run on any source failure (rejected — violates FR-012). Logging
to stdout only without a persisted run (rejected — fails FR-013's reviewability and the R4 overlap guard).

## R7. Test determinism (no network, no wall-clock coupling)

**Decision**: All external sources are stubbed with **WebMock** against recorded fixtures (already wired in
`spec/support/webmock.rb`, net connections disabled). Stale-count progression and the 08:00 UTC schedule are
tested with `ActiveSupport::Testing::TimeHelpers` (`travel_to`) so multi-day refresh sequences and the cron
fire time are deterministic. No test performs a live third-party call.

**Rationale**: Constitution Principle II (deterministic suite; behavior over implementation). Fixtures make
adapter normalization and partial-failure paths reproducible; time travel makes the 3-miss auto-retire and
the fixed-UTC schedule assertable without flakiness.

**Alternatives considered**: VCR (heavier; WebMock fixtures suffice for these small JSON payloads). Live
smoke tests in CI (rejected — non-deterministic, leaks the legitimate-path concern of hammering a source).

## Resolved unknowns summary

| Unknown (Technical Context) | Resolution |
|---|---|
| How to ingest "DeFlock" legitimately | OSM/ODbL via Overpass; no scraping, no nonexistent API (R1) |
| Nationwide extent without exceeding source limits | Tiled US bbox grid + backoff + bounded concurrency (R2) |
| Fixed 08:00 UTC schedule mechanism | Explicit UTC cron in recurring.yml (R3) |
| Prevent overlapping refreshes | Solid Queue concurrency key + RefreshRun running-guard (R4) |
| Stale → retire lifecycle | Freshness columns + per-source post-success reconciler, retire at 3, verified exempt (R5) |
| Partial-failure isolation + observability | Per-source rescue + RefreshRun audit, no user data (R6) |
| Deterministic tests | WebMock fixtures + time travel (R7) |

**Sources** (R1):
[deflock.org](https://deflock.org/) ·
[maps.deflock.org](https://maps.deflock.org/) ·
[FoggedLens/deflock API](https://github.com/FoggedLens/deflock/tree/master/api) ·
[OSM Tag:surveillance:type=ALPR](https://wiki.openstreetmap.org/wiki/Tag:surveillance:type=ALPR)

# ADR 0001 — Scaling the nationwide camera refresh

Status: **Accepted / complete.** All items landed: write-batching, DeFlock
demotion, per-tile isolation + tile-aware reconcile, continuation
checkpoint/resume, OSM-substrate staleness detection, the OSM rebuild
build+publish pipeline, the geo-deploy workflow, and the `external_ref` NOT NULL +
plain-unique-index cleanup. Parallel-cell concurrency was evaluated and
deliberately not built (Overpass fair-use + coordination risk — see below). The
only thing outside the repo is the actual run of the deploy workflow against real
geo hosts (needs host/SSH config).

> **Superseded in part by [ADR 0002](0002-pbf-derived-camera-source.md):** the
> tiled-Overpass *mechanism* described below is no longer the default substrate —
> cameras are derived from the OSM PBF extract instead. The tiling machinery
> (UsTiles, per-tile isolation, checkpoint/resume, tile-aware reconcile) is
> **retained** but only exercised by the `CAMERA_OSM_SOURCE=overpass` escape
> hatch. The batched-importer, DeFlock-demotion, and provenance decisions here
> still stand.

## Context

The daily `DataRefreshJob` (08:00 UTC) aggregates every live source into the
`cameras` source-of-truth table. At nationwide scale this has three cost/▲risk
centers:

1. **Per-record writes.** `Importer` did a `find_by` + `save!` per camera — two
   round-trips each. Across tens of thousands of cameras × 2 sources that
   dominated the run and held write locks far longer than necessary.
2. **One long sequential job.** `Sources::UsTiles` yields ~390 2°×2° cells;
   each is fetched sequentially, per source, inside a single `perform`. With
   `limits_concurrency(to: 1)` the run can't be sharded, has no checkpoint, and
   a late failure wastes the whole pass.
3. **DeFlock duplicates Overpass.** `Sources::Deflock < Overpass` issues the
   same query against the same endpoint, so every OSM ALPR node is fetched
   twice and stored twice (collapsing only at the segment layer). ~2× import
   and storage cost for a provenance-only difference.

## Decisions

### Landed now (this change)
- **Batched importer writes.** `Importer#import` processes records in slices of
  1,000; each slice does one `WHERE external_ref IN (…)` existence lookup and one
  transaction — eliminating the N `find_by` queries and per-row commit overhead
  while bounding both transaction size and in-memory rows. If a slice hits an
  unexpected DB error (validations already filter the known-bad records), it
  rolls back and replays record-by-record so one bad row is skipped rather than
  dropping the slice. Exact added/updated/skipped counts (which the `RefreshRun`
  audit depends on) are preserved.
- **Not multi-row `upsert_all`.** The uniqueness index is *partial*
  (`UNIQUE (data_source_id, external_ref) WHERE external_ref IS NOT NULL`,
  because `external_ref` is nullable), so `ON CONFLICT` can't target it without
  the predicate, which `upsert_all` won't emit. Going further means a migration
  (see below).

### Follow-ups
- **Demote DeFlock to an attribution tag.** ✅ **Done** (migration
  `20260601000003`). DeFlock fetched the identical OSM substrate as Overpass, so
  it's no longer a separate pass — OpenStreetMap covers its contributions and
  the duplicate rows were removed. Halved nationwide Overpass load and writes.
- **Per-tile isolation + tile-aware reconciliation.** ✅ **Done.**
  `CameraData::TiledRefresh` fetches + imports each `UsTiles` cell independently,
  so one unreachable tile no longer aborts the whole pass — the old
  `Overpass#fetch` looped every cell and a single failure lost the entire source.
  `DataRefreshJob` now drives it (injectable `tiles:` + `source_factory:`), and a
  run reports `success` / `partial` / `failed` with `tiles_ok` / `tiles_failed`.
  - **Correctness constraint handled (non-obvious):** `StaleReconciler` gained a
    `bboxes:` scope and reconciles **only within successfully-fetched tiles**. A
    failed tile's cameras are left untouched — otherwise they'd look "missing"
    and auto-retire after 3 such failures (FR-008/009), silently dropping real
    cameras. Covered by a dedicated spec.
- **Checkpoint / resume across interruption (continuations).** ✅ **Done.**
  `DataRefreshJob` is now an `ActiveJob::Continuable`. The tile loop runs in one
  `step` whose cursor is the whole progress state (tile index + running tallies +
  the successful-bbox list) as a JSON-safe Hash; `step.set!(state)` checkpoints
  after every cell. On a graceful interrupt (deploy) the job re-enqueues and
  resumes from the last cell instead of re-fetching the country, re-adopting the
  in-flight `RefreshRun` rather than starting a second (`continuation.started?`).
  Keeping the full state on the cursor (not the `RefreshRun`) means a resumed
  execution carries accurate counts + the successful-bbox set for tile-aware
  reconcile for free; finalize is guarded by run status + wrapped in a
  transaction so a crash-retry can't double-run the reconciler. `resume_errors_
  after_advancing = false`, so only graceful interrupts resume — real errors fail
  the run. (Note: a Proc `source_factory` isn't serializable, so production uses
  the default factory, which survives resume; injected lambdas are test-only and
  run straight-through.)
- **Parallel-cell concurrency.** ❌ **Deliberately not built.** Running cells in
  parallel would speed the nightly job, but: (1) the public Overpass usage policy
  asks for serial queries — the code fetches at concurrency 1 *by design* for
  fair-use — so parallel fetches against the default endpoint are off the table;
  and (2) coordinating "all cells done → run the tile-aware reconcile" across
  parallel child jobs is exactly the completion-coordination Solid Queue lacks
  natively, and getting it wrong re-introduces the false-retirement bug. The job
  already resumes after interruption, and a nightly run has time to be serial, so
  the cost/risk isn't worth it. Conditional path if ever needed: only against a
  self-hosted Overpass (`OVERPASS_URL`), with a barrier before reconcile.
- **Make `external_ref` NOT NULL + a non-partial unique index.** ✅ **Done**
  (migration `20260601000004` + a model presence validation). Backfilled any
  legacy NULLs, set the column NOT NULL, and swapped the partial unique index for
  a plain one — removing the blank-`external_ref` non-idempotency footgun (the
  importer now skips ref-less records instead of creating anonymous rows). The
  multi-row `upsert_all` this unblocks was **not** adopted: with per-tile imports
  each batch is small, so the chunked per-row insert is already cheap and the
  round-trip win is marginal — not worth the PostGIS-geometry serialization
  fiddliness or losing the exact added/updated counts the audit needs.

## OSM substrate automation (related)

Camera data refreshes daily, but the **routing graph / vector tiles / Nominatim
index** are rebuilt only by the manual `infra/scripts/*` (see
[geo-stack runbook](../runbooks/geo-stack.md)). Stale OSM silently degrades route
quality and camera-segment snapping.

- **Staleness detection.** ✅ **Done.** `GeoStalenessJob` (weekly) reads
  Valhalla's `tileset_last_modified` via `/status` and alerts through the
  `Telemetry` seam when the graph exceeds `GEO_SUBSTRATE_STALE_DAYS` (default 30)
  — the same way degraded refresh runs are alerted.
- **Rebuild build + publish.** ✅ **Done.** `infra/scripts/build-geo.sh` chains
  fetch → routing graph → tiles → `geo-manifest.sh`, and
  `.github/workflows/build-geo.yml` runs it (on demand only — `workflow_dispatch`) on a CI runner,
  publishing a versioned GitHub Release with the artifacts + `manifest.json` /
  `manifest.sha256` (region, source extract, build time, per-artifact sha256).
  Fits the Iowa launch region on a hosted runner; full-US needs a larger/self-
  hosted runner (documented).
- **Deploy the build onto the hosts.** *Manual ops step (needs host access).*
  Pull the release, `geo-manifest.sh verify`, drop the artifacts into the Kamal
  accessory volumes, restart. Procedure in the
  [geo-stack runbook](../runbooks/geo-stack.md#rebuild-automation).

## Consequences

- The batched importer is a pure win with no behavior change (guarded by the
  existing importer specs + a query-count regression test).
- The follow-ups are larger and sequenced for when coverage expands beyond the
  Iowa launch region; each can land independently.

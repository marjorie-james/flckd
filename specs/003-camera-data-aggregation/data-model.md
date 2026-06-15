# Phase 1 Data Model: Aggregated Camera Data Source-of-Truth

**Feature**: `003-camera-data-aggregation` · **Date**: 2026-06-01

This is the **delta** over feature 002's data model. Existing entities (`Camera`, `DataSource`,
`MonitoredSegment`, `CoverageArea`) are reused; only the changes below are introduced.

## DataSource (existing — no schema change)

The `license` column already exists and is now actively populated per source (FR-004/FR-005). No migration
needed. Sources seeded for v1:

| name | kind | license | url |
|------|------|---------|-----|
| OpenStreetMap (Overpass) | community | ODbL-1.0 | https://www.openstreetmap.org/ |
| DeFlock | community | ODbL-1.0 | https://deflock.org/ |
| (open-data / FOIA imports) | community / official | per-file (recorded) | per-file |

`last_imported_at` continues to mark the most recent successful import for the source.

## Camera (existing — additive columns)

New freshness/lifecycle fields (migration `add_freshness_to_cameras`). All additive, nullable or defaulted,
so existing rows and feature-002 behavior are unaffected.

| field | type | notes |
|-------|------|-------|
| last_seen_in_source_at | timestamp, nullable | set when the camera's source reports it in a successful refresh |
| consecutive_missing_count | integer, default 0, not null | increments each successful refresh the camera is absent from its source; reset to 0 on reappearance |
| stale | boolean (stored column), default false, not null | true while present-but-missing (count ≥ 1 and not yet retired); set by the reconciler, not computed at read time |

**Reused field**: `verification_status` enum (`unverified`, `verified`, `disputed`, `removed`). Auto-retire
sets `removed` (already excluded from routing by the `active`/`routable` scopes). No new lifecycle column.

**Terminology**: "retire"/"retired" in this spec means setting `verification_status = "removed"`. The
`RefreshRun.per_source`/`totals` `retired` counter counts cameras moved to `removed` during that run.

**Coverage-area scope note (reconciles FR-019 with feature 002)**: Because each refresh ingests the entire
continental US (FR-019), cameras MAY be stored outside the coverage area(s) routing currently serves. Import
MUST NOT gate on "within a CoverageArea" — that constraint from feature 002's data-model does not apply to
003 ingestion (and is not enforced by the current `Camera` model). Routing continues to use only cameras in
served areas via existing scopes; out-of-area cameras simply wait until their area is served.

**Lifecycle rules** (FR-008/FR-009, clarified 3-miss window):

- **Seen this refresh** → `last_seen_in_source_at = now`, `consecutive_missing_count = 0`, `stale = false`.
- **Missing this refresh** (its source succeeded) → `consecutive_missing_count += 1`, `stale = true`.
- **Auto-retire** when `consecutive_missing_count >= 3` (configurable) **and** `verification_status != "verified"`
  → set `verification_status = "removed"`. Verified cameras are exempt (removed only by a human).
- **Reappears** → counter resets to 0, `stale = false`; if previously auto-retired (not human-removed) it may
  return to `unverified`.
- A camera whose source **failed** this refresh is left untouched (no increment, no retire) — last-good
  preserved (FR-012).

**Validations** (new): `consecutive_missing_count >= 0`. Existing validations unchanged.

**Indexes**: index on `verification_status` already exists; add a partial index on `stale` (where `stale`)
to make stale review queries cheap.

## MonitoredSegment (existing — no change)

Unchanged. Remains the unit of avoidance and the point where cross-source duplicates collapse: cameras from
different sources snapped to the same `osm_way_id` produce a single avoidance target (FR-006). No camera-level
canonical merge is introduced.

## RefreshRun (NEW)

Per-refresh audit record for observability (FR-013) and the overlap guard (FR-014). Contains **no user
data** — only reference-data counts and source names.

| field | type | notes |
|-------|------|-------|
| id | bigint PK | |
| trigger | string, not null | `scheduled` \| `manual` |
| status | string, not null, default `running` | `running` \| `success` \| `partial` \| `failed` |
| started_at | timestamp, not null | set at run start |
| finished_at | timestamp, nullable | set at completion |
| duration_ms | integer, nullable | derived; for the performance budget (Principle IV) |
| per_source | jsonb, not null, default `{}` | map of source name → `{added, updated, skipped, retired, status, error_class?}` |
| totals | jsonb, not null, default `{}` | `{added, updated, skipped, retired}` aggregated across sources |

**State transitions**: `running → success` (all sources ok) \| `running → partial` (≥1 source failed,
≥1 succeeded) \| `running → failed` (all sources failed). A run is only ever `running` for one record at a
time (enforced by R4 concurrency guard).

**Validations**: `trigger` ∈ {scheduled, manual}; `status` ∈ {running, success, partial, failed};
`started_at` present. `per_source`/`totals` carry only integer counts, source names, and an error **class**
string (never a message body or any coordinate/IP).

**Indexes**: index on `status` (to find an in-flight `running` run fast); index on `started_at` (recent-runs
review).

**Retention**: runs are reference-only and small; keep a rolling window (e.g., last 90 days). Pruning is an
operational concern, not a correctness one, and is **explicitly deferred** (out of scope for this feature —
no pruning task is generated). Revisit if `refresh_runs` growth ever becomes material.

## Entity relationships (delta)

```text
DataSource 1───* Camera 1───* MonitoredSegment
RefreshRun  (standalone audit; references source names by string, no FK to user data)
```

## Configuration (not persisted entities, but design inputs)

- `CAMERA_REFRESH_MISSING_LIMIT` (default 3) — auto-retire threshold.
- `OVERPASS_URL` / `OVERPASS_USER_AGENT` — source endpoint + honest identification (existing).
- US tiling grid parameters (cell size, concurrency) — `Sources::UsTiles` constants, overridable via ENV.
- Schedule: `config/recurring.yml` cron `0 8 * * *` (UTC).

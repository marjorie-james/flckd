# Contract: Camera-Data Refresh CLI & Schedule

**Feature**: `003-camera-data-aggregation`

This feature exposes **no new HTTP endpoints**. Its interfaces are the operator-facing rake/CLI surface, the
background schedule, and the structured `RefreshRun` summary. All commands run in Docker (see quickstart).

## Rake / CLI commands (`camera_data` namespace)

### `camera_data:import` (existing — extended)

Single-source import (used in dev and for targeted backfills). Extended source set:

| `SOURCE` | Required env | Behavior |
|----------|--------------|----------|
| `fixture` | — | Local dev seed from `db/fixtures/cameras.json`. |
| `overpass` | `BBOX="south,west,north,east"` | OSM ALPR nodes for one bbox. |
| `deflock` | `BBOX` (optional; defaults to US tiles) | DeFlock-curated OSM ALPR data (ODbL), via Overpass. |
| `geojson` | `GEOJSON_PATH`, `NAME` (opt: `URL`, `LICENSE`, `KIND`) | Open-data / FOIA export. |
| `aggregate` | optional `BBOX`, `GEOJSON_PATH`+`NAME` | All configured sources at once. |

### `camera_data:refresh` (NEW — manual full refresh, FR-018)

Runs the same aggregate refresh the scheduler runs (all live sources, continental US), synchronously or by
enqueuing the job. Creates a `RefreshRun` with `trigger=manual`.

```
SOURCE-agnostic:  bin/rails camera_data:refresh
```

**Output (human-readable, Principle III)** — one line per source plus totals, e.g.:

```
Refresh (manual) started at 2026-06-01T10:00:00Z
  OpenStreetMap (Overpass)  added=120 updated=4300 skipped=12 retired=8  [success]
  DeFlock                   added=15  updated=900  skipped=0  retired=1  [success]
  open-data:Denver          —                                            [failed: Faraday::TimeoutError]
Status: partial  duration=742s  (other sources preserved last-good)
```

**Exit codes**: `0` success or partial (run recorded); non-zero only on total failure or invalid args.

### `camera_data:refresh:status` (NEW — review, FR-013)

Prints the most recent `RefreshRun`(s). Supports `--json` for machine consumption (mirrors the schema in
`refresh-run.schema.json`); default output is the human table above.

## Background schedule (FR-010)

`config/recurring.yml` (Solid Queue, production):

```yaml
production:
  camera_data_refresh:
    class: DataRefreshJob
    queue: default
    args: [ aggregate ]
    schedule: "0 8 * * *"   # 08:00 UTC daily (= 2am CST / 3am CDT); fixed, no DST adjustment
```

**Contract guarantees**:
- Fires once daily at **08:00 UTC** (SC-006: begins within 15 min of 08:00 UTC).
- Runs in background; never blocks user-facing routing (FR-011).
- Never overlaps a still-running refresh (FR-014): a second fire is skipped while a `RefreshRun` is `running`
  (and Solid Queue `limits_concurrency key: "camera_refresh", to: 1`).
- On any source failure, other sources still import and the run is recorded `partial` (FR-012).
- Transmits no user data to any source; logs no IPs/coordinates (FR-016/FR-017).

## DataRefreshJob contract

```
DataRefreshJob.perform_later(mode = "aggregate", trigger: "scheduled")
```

- `mode="aggregate"` → runs `CameraData::AggregateImport` over all live sources across US tiles, then
  `StaleReconciler` per successfully-refreshed source, then records a `RefreshRun`.
- Idempotent: re-running imports updates rather than duplicates (FR-007).
- Injectable source list / fetcher for deterministic tests (no network).

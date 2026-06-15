# Runbook: Camera-data refresh operations

The `cameras` source-of-truth table is rebuilt daily from the OpenStreetMap
ALPR substrate (default: PBF local extract via `build-cameras.sh`; escape hatch:
live Overpass — see [geo-stack.md](geo-stack.md)), snapping new cameras to their
monitored road segments and recording a `RefreshRun` audit. No user data is ever
involved — this operates on reference data only, never by any user location.

All backend commands run in Docker — host Ruby native extensions are broken.
Prefix everything with:

```bash
docker compose -f infra/docker-compose.yml run --rm backend <cmd>
```

In production use `kamal app exec <cmd>` instead.

## The daily job

`DataRefreshJob` (`app/jobs/data_refresh_job.rb`) runs via Solid Queue recurring
at a **fixed 08:00 UTC** (= 2am CST / 3am CDT), no DST adjustment
(`config/recurring.yml`):

```yaml
production:
  camera_data_refresh:
    class: DataRefreshJob
    queue: default
    args: [ aggregate ]
    schedule: "0 8 * * *"
```

It runs in the background (non-blocking), with per-source failure isolation, and
records a `RefreshRun` for every run. A Solid Queue worker must be running for
the schedule to fire (`SOLID_QUEUE_IN_PUMA=true` in the web process, or a
standalone `bin/jobs`).

## Trigger a manual refresh

```bash
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:refresh
```

This runs the full aggregate with trigger `manual` and prints per-source
`added/updated/retired`. The source is controlled by `CAMERA_OSM_SOURCE`
(default: `pbf` — reads the local GeoJSON built by `build-cameras.sh`; set to
`overpass` for the live-API escape hatch). A targeted backfill of one source or
bbox uses `camera_data:import` instead — see
[specs/003-camera-data-aggregation/quickstart.md](../../specs/003-camera-data-aggregation/quickstart.md).

## Check status

```bash
# Human table of the last few runs:
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:refresh:status

# Machine-readable:
docker compose -f infra/docker-compose.yml run --rm backend bin/rails camera_data:refresh:status -- --json
```

Backed by `CameraData::RefreshStatus`, which reads the `RefreshRun` audit
(most-recent first). Each row shows trigger, status, duration, and per-source
`added/updated/retired` (or the source's failure status + `error_class`).

## What the statuses mean (`RefreshRun.status`)

- **`running`** — a run is in progress. Also the non-overlap guard (below).
- **`success`** — every source imported cleanly.
- **`partial`** — at least one source failed but others succeeded. The failed
  source keeps its last-good data (it is **not** reconciled, so its cameras are
  never wrongly retired — `StaleReconciler` runs only for sources that fetched
  successfully).
- **`failed`** — the run could not produce usable results.

## Telemetry alerts

When a run finishes with status other than `success`, `DataRefreshJob` calls
`Telemetry.alert("camera_data refresh finished status=…", run_id:, status:,
per_source:)` (`app/services/telemetry.rb`). The payload carries only
statuses/counts/`error_class` — **no coordinates, addresses, or IPs**.

Until an error tracker is wired up, alerts go to the Rails log as
`[telemetry] …`. To plug in Sentry/Honeybadger later, set `Telemetry.handler` in
an initializer (one place) — the default handler also auto-detects a loaded
`Sentry` SDK. A silently-broken source is otherwise visible only in the
`RefreshRun` audit, so this seam is the early-warning path.

## Non-overlap guard

Two layers prevent overlapping refreshes (FR-014):

1. **Queue layer** — `limits_concurrency(to: 1, key: "camera_data_refresh")`.
2. **Run guard** — `DataRefreshJob` returns `:skipped` (logs
   `[camera_data] refresh skipped — another run is already in progress`) if
   `RefreshRun.running?` is true (any run still in `running` status).

If a refresh is wedged in `running` (e.g. the process was killed mid-run),
manual and scheduled runs will keep skipping. Confirm nothing is actually
running, then clear the stuck record:

```bash
docker compose -f infra/docker-compose.yml run --rm backend \
  bin/rails runner 'RefreshRun.where(status:"running").update_all(status:"failed", finished_at: Time.current)'
```

## Stale → auto-retire

After a source's import succeeds, `CameraData::StaleReconciler` reconciles that
source's cameras:

- Cameras the source reported this run are marked fresh.
- Cameras it no longer reports get `consecutive_missing_count += 1`.
- After **3 consecutive misses** (`CAMERA_REFRESH_MISSING_LIMIT`, default 3) a
  camera is **auto-retired**: the recoverable `auto_retired` flag is set (NOT the
  terminal `verification_status = "removed"`, which is reserved for human removal)
  and it is excluded from routing. If the source reports it again in a later
  refresh it is **revived** (`auto_retired` cleared, `consecutive_missing_count`
  reset) and re-enters avoidance.
- **Human-verified cameras (`verification_status = "verified"`) are exempt** —
  they are never auto-retired.

Reconciliation runs **only for sources that fetched successfully**, so a failing
source never retires its own cameras.

## When a source fails

1. Check which source and why:
   `camera_data:refresh:status` → look for the `failed` row and its
   `error_class`.
2. The run will be `partial`; the failed source's data is preserved (last-good).
   No emergency action is required — the next successful run reconciles it.
3. If a source is failing repeatedly (rate limits, upstream outage,
   schema change), backfill it on its own once the cause clears, e.g.:
   ```bash
   docker compose -f infra/docker-compose.yml run --rm \
     -e SOURCE=overpass backend bin/rails camera_data:import
   ```
4. The Overpass client identifies the app honestly and backs off on rate
   limits — do not work around source rate limiting or terms.

## Solid Queue worker

The scheduled refresh and all camera jobs run on the `job` host via `bin/jobs`
(`SOLID_QUEUE_IN_PUMA: false` in `deploy.yml`). If the worker process dies,
scheduled jobs silently stop running.

```bash
# Check if the worker is running:
kamal app exec --roles=job 'pgrep -f bin/jobs || echo "NOT RUNNING"'

# Restart the job container:
kamal app boot --roles=job

# Tail job logs:
kamal app logs --roles=job -f
```

In `docker-compose` dev the worker isn't separate — Solid Queue runs embedded in
Puma (`SOLID_QUEUE_IN_PUMA=true` is set in the dev env or start it manually:
`bin/rails solid_queue:start`).

See also: [backups.md](backups.md) (the `cameras` table is the one piece of
state worth protecting) and [incident-response.md](incident-response.md).

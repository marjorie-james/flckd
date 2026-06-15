# Runbook: Incident response (fast triage)

Fast checklist, not prose. Backend commands run in Docker
(`docker compose -f infra/docker-compose.yml run --rm backend <cmd>`) locally, or
`kamal app exec <cmd>` in production. Strict anonymity: **never log user route
coordinates or client IPs** while debugging.

Data recovery (the `cameras` table) → [backups.md](backups.md).

---

## DB down — health endpoint 503

- **Symptom:** `/api/v1/health` returns 503 with `{"status":"degraded","checks":{"database":"error"}}`; Kamal proxy pulls the app out of rotation.
- **Confirm:** `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/api/v1/health` → 503. Health gates **only** on the DB.
- **First remediation:** check Postgres is up — `docker compose -f infra/docker-compose.yml ps postgres`; restart `docker compose -f infra/docker-compose.yml up -d postgres`. Check disk, connection pool, credentials (`DATABASE_*`).
- **Recover data:** restore the latest dump → [backups.md](backups.md).

## API 5xx spike

- **Symptom:** elevated 5xx across endpoints.
- **Confirm:** check `/api/v1/health` first (rules DB in/out). Tail logs for the failing endpoint / exception class. Check `[telemetry]` lines.
- **First remediation:** if DB-related → see "DB down". If a single accessory (routing/geocoder/tiles) → those fail soft and should **not** 5xx the whole app; investigate that service (below). Restart the web process if memory/threads exhausted.

## Routing returns no route / Valhalla down

- **Symptom:** `/api/v1/routes` returns a localized 503 or no route.
- **Confirm:** `curl -s http://localhost:8002/status`. No response → Valhalla down. Status OK but no route → check the graph covers the coordinates (region built?).
- **First remediation:** `docker compose -f infra/docker-compose.yml up -d routing`. If the graph is missing/corrupt, rebuild → [geo-stack.md](geo-stack.md) (`build-routing-graph.sh`). Geo services fail soft — health stays `ok`; the app still serves other endpoints.

## Geocoder (Nominatim) down

- **Symptom:** address search (`/api/v1/geocode/*`) fails; routing by explicit coordinates still works.
- **Confirm:** `curl -s http://localhost:8081/status` (host port 8081 → container 8080).
- **First remediation:** `docker compose -f infra/docker-compose.yml up -d geocoder`. If the import is incomplete/corrupt, re-import → [geo-stack.md](geo-stack.md). Degrades gracefully — not an outage on its own.

## Tiles missing / basemap blank

- **Symptom:** map renders blank; tile requests 404/5xx.
- **Confirm:** `curl -s http://localhost:8080/tiles/metadata` and a sample tile `curl -s -o /dev/null -w '%{http_code} %{content_type}\n' http://localhost:8080/tiles/10/247/380.mvt`.
- **First remediation:** `docker compose -f infra/docker-compose.yml up -d tileserver`; if `tiles.pmtiles` is missing, rebuild → [geo-stack.md](geo-stack.md) (`build-tiles.sh`).

## Refresh job stuck / failed

- **Symptom:** stale camera data; `[telemetry] camera_data refresh finished status=…` alert; runs keep skipping.
- **Confirm:** `bin/rails camera_data:refresh:status` — look for `partial`/`failed`, a lingering `running` row, or a source `error_class`.
- **First remediation:**
  - One source failed → run is `partial`, last-good data preserved; backfill that source once the cause clears (`SOURCE=… camera_data:import`).
  - Wedged in `running` (overlap guard keeps skipping) → confirm nothing is actually running, then clear it:
    ```bash
    bin/rails runner 'RefreshRun.where(status:"running").update_all(status:"failed", finished_at: Time.current)'
    ```
  - Trigger a fresh run: `bin/rails camera_data:refresh`.
- **Full detail:** [refresh-ops.md](refresh-ops.md).

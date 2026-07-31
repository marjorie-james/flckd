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

## Deploy fails health check — app aborts at boot on host authorization

- **Symptom:** deploy aborts with `Error: target failed to become healthy within configured timeout (30s)`; the container log shows `bin/rails aborted!` and `APP_HOSTS or API_DOMAIN must be set in production`.
- **Cause:** host authorization **fails closed**. When the allow-list resolves empty, `config/environments/production.rb` raises at boot rather than silently running with Host checking disabled.
- **Confirm:** read the boot log of the container the deploy just started:
  ```bash
  docker ps -aq --filter label=service=flckd-backend --filter label=role=web \
    | head -1 | xargs -r docker logs --tail 50
  ```
- **First remediation:** set the allow-list for the deployment (`APP_HOSTS`, comma-separated) and redeploy. For an environment that genuinely has no domain (CI/staging), set `RAILS_ENV_SKIP_HOST_CHECK=1` instead — never as a production workaround, it disables Host checking entirely.
- **Not the same as** the 403 case below: here the process never boots. If the app is *up* and still serving nothing, read the next entry.

## API 403 on every request — Host not in the allow-list

- **Symptom:** the app looks **completely healthy** (process up, deploy reported success, `/api/v1/health` returns 200) but the site loads with no data. Every API request returns 403 with an HTML body.
- **Cause:** the request's `Host` header is not in the allow-list, so `ActionDispatch::HostAuthorization` rejects it before the controller runs. Health checks are exempt (`/up` and `/api/v1/health` are excluded), which is exactly why this is invisible from the outside and why the deploy passes.
- **Confirm:** the blocked host is only visible in the app log. Grep for it:
  ```bash
  docker ps -q --filter label=service=flckd-backend --filter label=role=web \
    | head -1 | xargs -r docker logs --tail 200 2>&1 | grep HostAuthorization
  # or, via Kamal:  kamal app logs --roles=web | grep HostAuthorization
  ```
  A match looks like `[ActionDispatch::HostAuthorization::DefaultResponseApp] Blocked hosts: flckd.example`. The named host is the one missing from the allow-list.
- **First remediation:** add **every** hostname that reaches Rails to `APP_HOSTS`, comma-separated, and redeploy — e.g. `APP_HOSTS=api.flckd.example,flckd.example`. Typically hit when the allow-list holds only the API subdomain but the frontend is served from the apex and proxies through, so requests arrive with the apex `Host`.
- **Gotcha:** `APP_HOSTS` **replaces** `API_DOMAIN`, it does not merge with it (`EdgeConfig.allowed_hosts` falls back to `API_DOMAIN` only when `APP_HOSTS` is unset). Setting `APP_HOSTS` alone silently drops whatever `API_DOMAIN` held, so list the API domain in `APP_HOSTS` too.

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
- **Confirm:** `curl -s http://localhost:8081/status.php` (host port 8081 → container 8080).
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

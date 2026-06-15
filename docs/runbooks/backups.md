# Runbook: Database backup & restore

The `cameras` source-of-truth table is rebuilt daily from the OSM PBF extract
(fast, minutes) — but a rebuild still loses any human-verified camera records.
Treat the PostGIS database as the one piece of state worth protecting —
everything else (routing graph, tiles, Nominatim index) is rebuildable from
public OSM extracts.

## Taking a backup

```bash
# In the backend (or `kamal app exec`):
BACKUP_DIR=/var/backups/flckd bin/rails db:backup
```

Writes a timestamped `pg_dump` custom-format file:
`flckd-flckd_production-YYYYMMDDTHHMMSSZ.dump`. Custom format (`-Fc`) supports
selective, parallel restore and is compressed.

`BACKUP_DIR` defaults to `storage/backups/` if unset.

### Scheduling

Run it daily, after the 08:00 UTC camera refresh has settled. Either:

- **Solid Queue recurring** — add a recurring entry that invokes a small job
  wrapping `Rake::Task["db:backup"]`, or
- **host cron / platform scheduler** on the job host:
  `0 9 * * * cd /app && BACKUP_DIR=/var/backups/flckd bin/rails db:backup`

> **Offsite is required.** A dump sitting on the same disk as the database is not
> a backup. Sync `BACKUP_DIR` to object storage (S3/B2/etc.) with lifecycle
> retention (e.g. 7 daily + 4 weekly). This step is environment-specific and
> intentionally not in the repo.

## Restoring

```bash
# Recreate an empty database if needed, then restore (PostGIS must be installed):
createdb -h "$DB_HOST" -U flckd flckd_production
pg_restore --no-owner --no-privileges -h "$DB_HOST" -U flckd \
  -d flckd_production flckd-flckd_production-YYYYMMDDTHHMMSSZ.dump
```

Notes:
- The `postgis` extension is created by the schema; restore into a database
  whose template has PostGIS, or run `CREATE EXTENSION postgis;` first.
- `--no-owner --no-privileges` keeps the restore portable across roles.
- After a restore, verify: `SELECT count(*) FROM cameras;` and run a sample
  route to confirm segment exclusion still works.

## Verifying a backup is good

A backup you haven't restored is a guess. Periodically restore the latest dump
into a throwaway database and run the smoke check above.

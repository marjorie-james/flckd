# Quickstart: Parallel TIGER/Line Data Download

## Running the script

```bash
# Full first-time setup (downloads all county files for your configured state)
infra/scripts/build-geocoder.sh

# Re-run (skips cached files, re-unpacks any missing, imports into Nominatim)
infra/scripts/build-geocoder.sh
```

The script reads `infra/.region` (written by `setup.sh`). If that file is absent it defaults to Iowa (`STATE_FIPS=19`).

Expected output for a fresh Iowa run:
```
Building TIGER/Line address data for: Iowa (FIPS 19)
==> [1/3] Discovering county files from Census Bureau (TIGER 2024)…
  Found 99 county file(s)
==> [2/3] Downloading and unpacking county files (up to 5 in parallel)…
  fetch   tl_2024_19001_addr.zip
  fetch   tl_2024_19003_addr.zip
  ...
==> [3/3] Importing TIGER data into Nominatim …
House-number geocoding is now active for Iowa.
```

Expected output for a fully-cached re-run (< 5 seconds):
```
Building TIGER/Line address data for: Iowa (FIPS 19)
==> [1/3] Discovering county files from Census Bureau (TIGER 2024)…
  Found 99 county file(s)
==> [2/3] Downloading and unpacking county files (up to 5 in parallel)…
  cached  tl_2024_19001_addr.zip
  cached  tl_2024_19003_addr.zip
  ...
==> [3/3] Importing TIGER data into Nominatim …
House-number geocoding is now active for Iowa.
```

## Tuning the concurrency cap

The cap is a single constant at the top of `build-geocoder.sh`:

```bash
MAX_PARALLEL_DOWNLOADS=5
```

Lower this if you see HTTP 429 responses in the output. Raise it (carefully) if Census Bureau bandwidth allows. A value of 1 reproduces the original sequential behavior for debugging.

## Running the bats tests

```bash
# No local bats install needed — runs in Docker
docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/build-geocoder.bats
```

Test output:
```
1..7
ok 1 successful_download_invokes_unzip
ok 2 failed_download_exits_nonzero_names_file
ok 3 rate_limit_429_triggers_backoff_retry
ok 4 concurrency_cap_limits_parallel_connections
ok 5 cached_dbf_skips_download_and_unzip
ok 6 nominatim_import_runs_after_successful_downloads
ok 7 nominatim_import_skipped_when_download_fails
```

Note: tests that exercise 429/500 retry backoff (T002, T007) sleep through real backoff delays (~35–45s each). The full suite takes ~90s. The cached-path-only test (T005) completes in well under 5 seconds.

## Troubleshooting

**Some files failed to download:**
```
error: 3 county file(s) failed to download:
  tl_2024_19021_addr.zip
  tl_2024_19045_addr.zip
  tl_2024_19099_addr.zip
  Re-run infra/scripts/build-geocoder.sh to retry.
```
Re-running the script is safe — it skips already-unpacked files and only retries the failures.

**Persistent HTTP 429 errors:**
Lower `MAX_PARALLEL_DOWNLOADS` in `build-geocoder.sh` (e.g., try 2 or 3) and re-run.

**Script passes but house-number search still fails:**
Verify the Nominatim container is healthy before the import step runs:
```bash
curl -sf http://localhost:8081/status.php
docker compose -f infra/docker-compose.yml logs -f geocoder
```

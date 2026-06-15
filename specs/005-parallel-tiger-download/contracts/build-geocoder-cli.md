# CLI Contract: build-geocoder.sh

## Invocation

```
infra/scripts/build-geocoder.sh
```

No positional arguments. No flags. Configuration is read from `infra/.region`.

## Inputs

| Source | Variable | Required | Default | Description |
|--------|----------|----------|---------|-------------|
| `infra/.region` | `STATE_FIPS` | No | `19` | FIPS code for the state to import |
| `infra/.region` | `REGION_LABEL` | No | `Iowa` | Human-readable state name for messages |
| Environment | `TIGER_HOST_DIR` | No | `infra/data/tiger/${STATE_FIPS}` | Override cache directory (useful in tests) |

`infra/.region` is written by `setup.sh` and sourced at the top of the script. If the file does not exist, Iowa defaults apply.

## Outputs

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | All county files downloaded, unpacked, and imported into Nominatim successfully |
| 1 | One or more county files failed to download after all retries; OR geocoder is not healthy; OR `nominatim add-data` failed |

### Standard output (informational, non-machine-readable)

```
Building TIGER/Line address data for: <REGION_LABEL> (FIPS <STATE_FIPS>)
==> [1/3] Discovering county files from Census Bureau (TIGER <YEAR>)…
  Found <N> county file(s)
==> [2/3] Downloading and unpacking county files (up to <N> in parallel)…
  cached  <filename>     # file already unpacked; skipped
  fetch   <filename>     # download started
  retry N/4 (<http_code>) <filename>   # transient failure; retrying
==> [3/3] Importing TIGER data into Nominatim …
House-number geocoding is now active for <REGION_LABEL>.
```

### Standard error

Errors only. Examples:
```
error: no TIGER ADDR files found for state FIPS <fips> (<label>)
error: geocoder is not healthy (http://localhost:8081/status.php did not respond)
error: <N> county file(s) failed to download:
  tl_2024_19001_addr.zip
  ...
error: download failed for <filename> (HTTP <code>)
```

## Side effects

| Path | Effect |
|------|--------|
| `infra/data/tiger/<STATE_FIPS>/tl_*.zip` | Created (downloaded ZIPs, kept as cache) |
| `infra/data/tiger/<STATE_FIPS>/tl_*.dbf` | Created (unpacked shapefiles) |
| `infra/data/tiger/<STATE_FIPS>/tl_*.shp` | Created (unpacked shapefiles) |
| Nominatim database | Mutated: address-range data imported via `nominatim add-data` |

## Invariants

- The Nominatim import step (`nominatim add-data`) is NOT called if any county file fails to download (FR-005).
- At most `MAX_PARALLEL_DOWNLOADS` (default: 5) simultaneous outbound connections to `www2.census.gov` at any moment (FR-002).
- Already-unpacked files (`.dbf` present) are never re-downloaded or re-unpacked (FR-004).
- A ZIP file that was downloaded in a previous interrupted run but not yet unpacked will be unpacked (not re-downloaded) on re-run.

## Idempotency

The script is safe to run multiple times. Each invocation:
- Skips files already unpacked
- Retries any files not yet fully processed
- Re-runs the Nominatim import (idempotent per Nominatim's `add-data` semantics)

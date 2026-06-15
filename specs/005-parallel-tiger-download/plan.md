# Implementation Plan: Parallel TIGER/Line Data Download

**Branch**: `005-parallel-tiger-download` | **Date**: 2026-06-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-parallel-tiger-download/spec.md`

## Summary

Replace the sequential `while` loop in `infra/scripts/build-geocoder.sh` (Step 2) with a background-job parallel download pattern capped at 5 concurrent connections. Add HTTP 429 backoff, per-file error collection via a temp directory, and a `.dbf` existence check to skip already-unpacked files. Add bats-core behavioral tests for the new parallel behavior and extend CI to run them alongside the existing shellcheck job.

## Technical Context

**Language/Version**: Bash, compatible with Bash 3.2.57+ (macOS default) and Bash 5.x (Linux / CI ubuntu-latest)

**Primary Dependencies**:
- `curl` ≥ 7.x — already required by `setup.sh`; no version bump needed
- `unzip` — already required by `build-geocoder.sh`
- `docker` — existing Nominatim import step, unchanged
- `bats-core` (new, test-only) — `bats-core/bats-action@4.0.0` in CI; `brew install bats-core` locally

**Storage**: `infra/data/tiger/<state_fips>/` — local filesystem cache directory (structure unchanged)

**Testing**: bats-core (new) + shellcheck (existing)

**Target Platform**: macOS (Bash 3.2, developer workstations) + Linux (Bash 5.x, CI `ubuntu-latest`)

**Project Type**: Infrastructure CLI script

**Performance Goals**:
- All 99 Iowa county files download + unpack in < 10 minutes on broadband (FR-007, SC-001)
- < 5 seconds when fully cached (SC-003)

**Constraints**:
- ≤ 5 simultaneous connections to the Census Bureau at any moment (FR-002)
- No `wait -n` (Bash 4.3+), no associative arrays (Bash 4.0+), no `mapfile`/`readarray` (Bash 4.0+)
- Script must remain shellcheck-clean under the existing excludes (SC1091, SC2034)
- Worker subshells must survive individual failures without aborting the whole batch

**Scale/Scope**: ~40 lines replaced in one script; 4 new bats tests; 1 CI job addition

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Tests required for every behavioral change (Principle II) | ✓ PASS | bats-core tests cover all behavioral changes: parallel dispatch, cache-skip (download + unzip), failure collection with correct exit code, unzip-after-download |
| No third-party routing/geocoding (anonymity non-negotiable) | ✓ PASS | Downloads only public Census Bureau static files. No user origin/destination/route data involved at any point |
| Camera avoidance = segment exclusion | N/A | Feature does not touch routing |
| Geo services stubbed in tests (deterministic CI) | ✓ PASS | `curl` is PATH-stubbed in bats; no live Census Bureau requests in CI |

## Project Structure

### Documentation (this feature)

```text
specs/005-parallel-tiger-download/
├── plan.md                      # This file
├── research.md                  # Phase 0 output
├── quickstart.md                # Phase 1 output
├── contracts/
│   └── build-geocoder-cli.md   # CLI interface contract
└── tasks.md                     # Phase 2 output (/speckit-tasks — not yet created)
```

### Source Code (repository root)

```text
infra/
└── scripts/
    └── build-geocoder.sh        # Modified: replace sequential loop (lines 67-79) with parallel pattern

test/
└── infra/
    ├── build-geocoder.bats      # New: bats behavioral tests (4 test cases)
    └── stubs/
        ├── curl                 # New: curl stub — records args, returns configurable HTTP codes
        └── unzip                # New: unzip stub — records args, no-ops by default

.github/workflows/
└── ci-scripts.yml               # Modified: add bats test job alongside existing shellcheck job
```

**Structure Decision**: Single-project layout. The only runtime change is in `infra/scripts/build-geocoder.sh`. Tests live in `test/infra/` (new directory) to keep infra tests separate from the backend RSpec suite without introducing a new top-level concept. No new service layers, no new packages.

## Implementation Design

### The Parallel Download Loop (replaces build-geocoder.sh lines 67–79)

```bash
# Maximum simultaneous connections to Census Bureau — lower if throttled (FR-002, FR-009)
MAX_PARALLEL_DOWNLOADS=5

echo "==> [2/3] Downloading and unpacking county files (up to ${MAX_PARALLEL_DOWNLOADS} in parallel)…"

# Per-failure marker directory: each worker touches ${FAIL_DIR}/${filename} on error
FAIL_DIR=$(mktemp -d)
trap 'rm -rf "${FAIL_DIR}"' EXIT

_dl_worker() {
  local filename="$1"
  local dest="${TIGER_HOST_DIR}/${filename}"
  local url="https://www2.census.gov/geo/tiger/TIGER${YEAR}/ADDR/${filename}"
  local dbf="${TIGER_HOST_DIR}/${filename%.zip}.dbf"

  # Fast path: already downloaded and unpacked
  if [ -f "${dbf}" ]; then
    printf "  cached  %s\n" "${filename}"
    return 0
  fi

  # Slow path: download needed (or zip exists but was never unpacked)
  if [ ! -f "${dest}" ]; then
    printf "  fetch   %s\n" "${filename}"
    local delay=5 http_code attempt
    for attempt in 1 2 3 4; do
      http_code=$(curl -sL --write-out "%{http_code}" -o "${dest}" "${url}" 2>/dev/null) || true
      case "${http_code}" in
        2??) break ;;
        429|500|502|503|504)
          rm -f "${dest}"
          printf "  retry %d/4 (%s) %s\n" "${attempt}" "${http_code}" "${filename}"
          [ "${attempt}" -lt 4 ] && sleep $((delay + (RANDOM % 5)))
          delay=$((delay * 2))
          ;;
        *) rm -f "${dest}"; break ;;
      esac
    done
    if [ "${http_code}" != "200" ] 2>/dev/null; then
      printf "error: download failed for %s (HTTP %s)\n" "${filename}" "${http_code:-?}" >&2
      touch "${FAIL_DIR}/${filename}"
      return 1
    fi
  fi

  unzip -oq "${dest}" -d "${TIGER_HOST_DIR}"
}

# Background jobs with PID array — Bash 3.2 compatible (no wait -n)
pids=()
running=0
while IFS= read -r filename; do
  [ -z "${filename}" ] && continue
  if [ "${running}" -ge "${MAX_PARALLEL_DOWNLOADS}" ]; then
    wait "${pids[0]}" 2>/dev/null || true
    pids=("${pids[@]:1}")
    running=$((running - 1))
  fi
  _dl_worker "${filename}" &
  pids+=($!)
  running=$((running + 1))
done < <(printf '%s\n' "${FILE_LIST}")

if [ "${#pids[@]}" -gt 0 ]; then
  for pid in "${pids[@]}"; do
    wait "${pid}" 2>/dev/null || true
  done
fi

failed_count=$(find "${FAIL_DIR}" -maxdepth 1 -type f | wc -l | tr -d ' ')
if [ "${failed_count}" -gt 0 ]; then
  echo "error: ${failed_count} county file(s) failed to download:" >&2
  find "${FAIL_DIR}" -maxdepth 1 -type f -exec basename {} \; | sort >&2
  echo "  Re-run infra/scripts/build-geocoder.sh to retry." >&2
  exit 1
fi
```

### Key design decisions (see research.md for full rationale)

| Decision | Choice | Why |
|----------|--------|-----|
| Parallelism | Background jobs + PID array | Only portable Bash 3.2 approach; no external deps |
| Error collection | Per-file marker in `FAIL_DIR` | No write-race risk; subshell-safe |
| HTTP 429 handling | Explicit `--write-out` + backoff loop | Portable; no version-specific curl flags |
| Unpack caching | Check `.dbf` existence | Needed to satisfy SC-003 (< 5s for cached run) |
| Tests | bats-core + PATH stubs | Bash 3.2 compatible; CI via `bats-action` |

### bats Test Plan

Seven tests in `test/infra/build-geocoder.bats`, each using `test/infra/stubs/` prepended to `PATH` and `TIGER_HOST_DIR=$BATS_TEST_TMPDIR`:

1. **`successful_download_invokes_unzip`** (US1/T006) — Stub curl HTTP 200; assert unzip stub is called
2. **`failed_download_exits_nonzero_names_file`** (US1/T007) — Stub curl HTTP 500; assert exit 1 and filename in stderr
3. **`rate_limit_429_triggers_backoff_retry`** (US2/T009) — Stub returns 429 then 200; assert success and "retry" in output
4. **`concurrency_cap_limits_parallel_connections`** (US2/T011) — 10 files, `CURL_STUB_SLEEP=0.1`; assert `max_concurrent ≤ 5` from slot counter
5. **`cached_dbf_skips_download_and_unzip`** (US3/T012) — Pre-create `.dbf`; stub curl to fail; assert success and curl not called
6. **`nominatim_import_runs_after_successful_downloads`** (US4/T014) — Assert docker stub called with `nominatim add-data`
7. **`nominatim_import_skipped_when_download_fails`** (US4/T015) — Stub curl HTTP 500; assert docker stub NOT called

The curl stub also implements a slot counter (enter/peak/exit pattern) to support test 4. `FILE_LIST` is pre-exported in each test's `setup()` — the `build-geocoder.sh` Step 1 discovery is skipped via the `[ -z "${FILE_LIST:-}" ]` guard.

## Complexity Tracking

No constitution violations. This is a 40-line in-place replacement within an existing script with no new service layers, no new runtime dependencies, and no schema changes.

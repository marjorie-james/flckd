# Research: Parallel TIGER/Line Data Download

**Feature**: `005-parallel-tiger-download`
**Date**: 2026-06-10

## Decision 1 — Parallelism mechanism

**Decision**: Background jobs with PID array tracking (native Bash)

The sequential `while ... do curl; unzip; done` loop is replaced with:
1. Spawn each file download as a background subshell (`_dl_worker "${filename}" &`)
2. Track PIDs in an indexed array
3. Throttle to `MAX_PARALLEL_DOWNLOADS` by calling `wait "${pids[0]}"` (FIFO) when at capacity
4. After the loop drains, wait for all remaining PIDs

This satisfies the Bash 3.2 constraint: indexed arrays, `$!`, `wait PID`, and the `pids[@]:1` slice are all available in Bash 3.2.57.

**Rationale**: The only portable approach that works identically on macOS Bash 3.2 and Linux Bash 5.x without additional dependencies. Workers run in subshells that inherit all parent-shell variables, so `TIGER_HOST_DIR`, `YEAR`, `FAIL_DIR`, and `BASE_URL` are accessible without `export`.

**Alternatives considered**:
- `xargs -P N` with `export -f`: Appealing for simplicity, but reliability of `export -f` across `xargs` subshells on Bash 3.2 is environment-specific. The function-in-environment encoding changed between Bash versions; using the PID approach avoids this risk entirely.
- GNU `parallel`: External dependency, not on stock macOS. Rejected on portability grounds.
- FIFO/named-pipe semaphore: Works in Bash 3.2 but adds ~30 lines of boilerplate (reader/writer setup, cleanup traps) with no benefit over PID tracking for this use case.

**Bash 3.2 compatibility notes**:
- `pids=()` — indexed array declaration: ✓ Bash 3.2
- `pids+=($!)` — array append: ✓ Bash 3.2
- `"${pids[@]:1}"` — array slice from index 1: ✓ Bash 3.2
- `wait "${pids[0]}"` — wait for specific PID: ✓ Bash 3.2
- `${#pids[@]}` — array length: ✓ Bash 3.2
- `wait -n` — wait for *any* child: ✗ Bash 4.3+ only — NOT used

## Decision 2 — Error collection across parallel workers

**Decision**: Per-failure marker files in a temp directory (`FAIL_DIR`)

Each worker touches `${FAIL_DIR}/${filename}` on failure. After all workers finish, the parent counts files in `FAIL_DIR` to determine whether any downloads failed and which ones.

```bash
FAIL_DIR=$(mktemp -d)
trap 'rm -rf "${FAIL_DIR}"' EXIT
```

**Rationale**: Workers run in subshells and cannot write to parent-shell variables. A shared file with `>>` appends is safe on macOS APFS/HFS+ for short single-line writes (kernel O_APPEND is atomic), but it is not POSIX-guaranteed for concurrent writers. Using one file per failure (no concurrent writes to the same file) eliminates the race entirely.

**Alternatives considered**:
- Shared append log (`echo "${filename}" >> "$FAIL_LOG"`): Safe in practice on macOS/Linux but not POSIX-guaranteed for concurrent writes. Per-file markers are strictly safer.
- Exit code collection via `wait PID`: Returns an exit code but cannot identify *which file* failed without a separate mapping structure, which is more complex in Bash 3.2 (no associative arrays).

## Decision 3 — HTTP rate-limit / retry handling

**Decision**: `curl --write-out "%{http_code}"` without `-f`, with a 4-attempt exponential backoff loop

Worker inner retry loop:
```bash
for attempt in 1 2 3 4; do
  http_code=$(curl -sL --write-out "%{http_code}" -o "${dest}" "${url}" 2>/dev/null) || true
  case "${http_code}" in
    2??)  unzip -oq ...; return 0 ;;
    429|503|500|502|504)
      rm -f "${dest}"
      sleep $((delay + (RANDOM % 5)))  # jitter avoids thundering herd
      delay=$((delay * 2))             # 5s → 10s → 20s → 40s
      ;;
    *)  rm -f "${dest}"; break ;;      # 4xx non-429: fatal, don't retry
  esac
done
```

**Rationale**:
- `curl --retry 3` already handles HTTP 429 internally (429 is in curl's built-in transient-error list since ≈7.52). However, the outer loop gives us explicit visibility (logging the HTTP code) and control over jitter.
- Removing `-f` allows capturing the HTTP code even on 4xx/5xx responses. With `-f`, curl exits immediately without writing `--write-out` output on errors in some versions.
- `--retry-all-errors` (curl 7.71.0+) is not used: not available on stock macOS system curl on older releases. The explicit loop is fully portable.
- Jitter (`RANDOM % 5`) prevents all 5 concurrent workers from waking at the same second after a shared 429 response.
- 429 and 5xx are retried; 4xx (other than 429) are treated as fatal — a 403 or 404 won't succeed on retry.

Initial delay: 5s; multiplier: 2×; max effective wait: 5+10+20+40 = 75s before giving up.

## Decision 4 — Unpack caching (skip unzip for already-unpacked files)

**Decision**: Check for the presence of `${TIGER_HOST_DIR}/${filename%.zip}.dbf` before downloading or unpacking

TIGER addr ZIPs follow a predictable naming convention: `tl_2024_19001_addr.zip` always contains `tl_2024_19001_addr.dbf` (plus `.shp`, `.shx`, `.prj`, `.cpg`). Checking for `.dbf` is a reliable "already unpacked" marker.

Worker fast-path:
```bash
if [ -f "${TIGER_HOST_DIR}/${filename%.zip}.dbf" ]; then
  printf "  cached  %s\n" "${filename}"
  return 0
fi
```

This path skips both download and unzip, satisfying SC-003 (< 5 seconds when fully cached).

**Rationale**: Unzipping 99 files takes 10–50 seconds on typical hardware; without this check, a fully-cached re-run would still take longer than SC-003 allows.

**Alternatives considered**:
- Always unzip cached ZIPs: Simple but violates SC-003.
- Separate `.unpacked` marker file: Extra complexity; `.dbf` is the natural artifact indicating successful unpack.

## Decision 5 — Test framework

**Decision**: bats-core with PATH-prepend stubs; CI via `bats-core/bats-action@4.0.0`

Tests live in `test/infra/build-geocoder.bats`. Stubs for `curl` and `unzip` are tiny shell scripts placed in `test/infra/stubs/` and prepended to `PATH` in `setup()`. Each stub records its invocations and returns configurable exit codes.

**Rationale**:
- bats-core explicitly supports Bash 3.2 (macOS), is the de-facto standard for bash testing, and has a GitHub Action that needs no Dockerfile changes.
- PATH-prepend stubs are idiomatic bats practice: the full script is invoked as written, only the external commands are intercepted.
- `bats-assert` (installed by `bats-action`) provides clean `assert_output`, `assert_success`, `assert_failure` helpers.

**Alternatives considered**:
- shunit2: Simpler but no argument-capture support and no GitHub Action.
- Inline function overrides (`function curl() {}`): Can't intercept subshells spawned by the script when run via `run bash script.sh`; PATH-prepend works at the OS level.

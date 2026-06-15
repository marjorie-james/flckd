---
description: "Task list for Parallel TIGER/Line Data Download"
---

# Tasks: Parallel TIGER/Line Data Download

**Input**: Design documents from `specs/005-parallel-tiger-download/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, contracts/build-geocoder-cli.md ✓, quickstart.md ✓

**Tests**: Required per Constitution Principle II. Each behavioral change has a corresponding bats test that must fail before the implementation task runs.

**Organization**: Grouped by user story. US1 (P1) is the MVP — ship it alone if needed.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other tasks in the same phase (different files, no shared dependencies)
- **[Story]**: Which user story this task maps to (US1–US4)

---

## Phase 1: Setup

**Purpose**: Create test infrastructure (stubs + bats skeleton) that all story phases depend on.

- [X] T001 Create directories `test/infra/` and `test/infra/stubs/` (mkdir -p; these must exist before any stub is written)
- [X] T002 [P] Create `test/infra/stubs/curl` — executable bash stub that: (a) records the full invocation to `$BATS_TEST_TMPDIR/curl_calls` (one line per call), (b) reads `CURL_STUB_HTTP_CODE` (default 200), (c) if `-o` arg is present writes an empty file there, (d) implements a concurrency slot counter: on entry `touch "$BATS_TEST_TMPDIR/slots/$$"`, count files in `$BATS_TEST_TMPDIR/slots/`, write peak to `$BATS_TEST_TMPDIR/max_concurrent` if higher, then if `CURL_STUB_SLEEP` is set sleep that many seconds, then `rm -f "$BATS_TEST_TMPDIR/slots/$$"`, (e) exits 0; make it executable with `chmod +x`; ensure `$BATS_TEST_TMPDIR/slots/` is created in the stub itself (`mkdir -p`).
- [X] T003 [P] Create `test/infra/stubs/unzip` — executable bash stub that: (a) records invocation to `$BATS_TEST_TMPDIR/unzip_calls`, (b) no-ops (no extraction), (c) exits 0; make it executable with `chmod +x`
- [X] T004 [P] Create `test/infra/stubs/docker` — executable bash stub that: (a) records invocation to `$BATS_TEST_TMPDIR/docker_calls`, (b) exits 0 for all args; make it executable with `chmod +x`

---

## Phase 2: Foundational

**Purpose**: Create the bats test harness skeleton that all story-phase tests will be added to. Depends on Phase 1.

**⚠️ CRITICAL**: No story-phase tests can be written until this skeleton exists.

- [X] T005 Create `test/infra/build-geocoder.bats` with: (a) `load` for `bats-support` and `bats-assert` using `$BATS_LIB_PATH` when set, otherwise skip gracefully; (b) `setup()` that exports `PATH="$BATS_TEST_DIRNAME/stubs:$PATH"`, sets `TIGER_HOST_DIR="$BATS_TEST_TMPDIR"`, exports `STATE_FIPS=19 YEAR=2024 REGION_LABEL="TestState"`, creates `$BATS_TEST_TMPDIR`; (c) `teardown()` that removes `$BATS_TEST_TMPDIR`; (d) define helper `SCRIPT` pointing to `infra/scripts/build-geocoder.sh` (use `$BATS_TEST_DIRNAME/../../infra/scripts/build-geocoder.sh`)

**Checkpoint**: `bats test/infra/build-geocoder.bats` runs without error (0 tests, 0 failures).

---

## Phase 3: User Story 1 — Fast First-Time Setup (Priority: P1) 🎯 MVP

**Goal**: All county files download in parallel and unzip after each download completes. A failed download exits non-zero and names the offending file.

**Independent Test**: Run `bats test/infra/build-geocoder.bats` — tests T006 and T007 pass.

### Tests for User Story 1

- [X] T006 [US1] Add bats test `successful_download_invokes_unzip` to `test/infra/build-geocoder.bats`: export `FILE_LIST="tl_2024_19001_addr.zip"` and `CURL_STUB_HTTP_CODE=200`; the curl stub will write an empty file to the `-o` destination automatically — do not pre-create the ZIP; run `bash "$SCRIPT"`; assert success and assert `$BATS_TEST_TMPDIR/unzip_calls` exists (unzip was invoked). **Verify this test FAILS before T008 is implemented.**
- [X] T007 [US1] Add bats test `failed_download_exits_nonzero_names_file` to `test/infra/build-geocoder.bats`: export `CURL_STUB_HTTP_CODE=500`, export `FILE_LIST="tl_2024_19001_addr.zip"`; run `bash "$SCRIPT"`; assert failure (exit 1); assert output contains `tl_2024_19001_addr.zip` (failure named in stderr). **Verify this test FAILS before T008 is implemented.**

### Implementation for User Story 1

- [X] T008 [US1] Implement parallel download loop in `infra/scripts/build-geocoder.sh` — replace lines 67–79 (the sequential `while IFS= read -r filename; do ... done` block) with: (a) add `MAX_PARALLEL_DOWNLOADS=5` constant with a comment referencing FR-002 and FR-009; (b) declare `FAIL_DIR=$(mktemp -d)` and `trap 'rm -rf "${FAIL_DIR}"' EXIT`; (c) define `_dl_worker()` function that takes `filename` arg, calls `curl -sL --write-out "%{http_code}" -o "${dest}" "${url}"`, checks for a `2??` HTTP response (use `case "${http_code}" in 2??)` — not just exact 200), runs `unzip -oq "${dest}" -d "${TIGER_HOST_DIR}"` on success, touches `"${FAIL_DIR}/${filename}"` on non-2xx failure; (d) background dispatch loop with `&`, PID array (`pids=()`, `pids+=($!)`), FIFO throttle: when `running >= MAX_PARALLEL_DOWNLOADS` call `wait "${pids[0]}" 2>/dev/null || true`, shift `pids=("${pids[@]:1}")`, decrement `running`; (e) drain loop and post-loop `failed_count` check with exit 1 on non-zero. The 429/5xx retry backoff is added in T010.

**Checkpoint**: `bats test/infra/build-geocoder.bats` — T006 and T007 pass. `shellcheck infra/scripts/build-geocoder.sh` passes.

---

## Phase 4: User Story 2 — Rate-Limit-Aware Concurrency (Priority: P2)

**Goal**: At most 5 concurrent connections to the Census Bureau. HTTP 429 triggers backoff and retry rather than immediate failure.

**Independent Test**: Run `bats test/infra/build-geocoder.bats` — tests T009 and T011 pass alongside T006 and T007.

### Tests for User Story 2

- [X] T009 [US2] Add bats test `rate_limit_429_triggers_backoff_retry` to `test/infra/build-geocoder.bats`: use a call-count file (`$BATS_TEST_TMPDIR/curl_count`) so the stub returns 429 on the first call per filename and 200 on subsequent calls; export `FILE_LIST="tl_2024_19001_addr.zip"`; run `bash "$SCRIPT"`; assert success; assert output contains `retry` (the retry message was printed). **Verify this test FAILS before T010 is implemented.**
- [X] T011 [US2] Add bats test `concurrency_cap_limits_parallel_connections` to `test/infra/build-geocoder.bats`: export `FILE_LIST` with 10 filenames (`tl_2024_19001_addr.zip` through `tl_2024_19019_addr.zip`), set `CURL_STUB_SLEEP=0.1` and `CURL_STUB_HTTP_CODE=200`; run `bash "$SCRIPT"`; assert success; assert `$(cat "$BATS_TEST_TMPDIR/max_concurrent" 2>/dev/null || echo 0)` is ≤ 5 (relies on the slot counter in the T002 curl stub). **Verify this test FAILS if `MAX_PARALLEL_DOWNLOADS` is removed from the script.**

### Implementation for User Story 2

- [X] T010 [US2] Add 429/5xx backoff to `_dl_worker` in `infra/scripts/build-geocoder.sh`: replace the single `curl` call with a `for attempt in 1 2 3 4; do` retry loop; use `case "${http_code}" in 2??) break ;; 429|500|502|503|504) rm -f "${dest}"; printf "  retry %d/4 (%s) %s\n" "${attempt}" "${http_code}" "${filename}"; sleep $((delay + (RANDOM % 5))); delay=$((delay * 2)) ;; *) rm -f "${dest}"; break ;; esac`; initial `delay=5`; if the loop exits without a `2??` match, touch `"${FAIL_DIR}/${filename}"` and return 1

**Checkpoint**: `bats test/infra/build-geocoder.bats` — T006, T007, T009, T011 all pass.

---

## Phase 5: User Story 3 — Resilient Partial Re-Runs (Priority: P3)

**Goal**: Files with a `.dbf` marker already present are skipped entirely (no download, no unzip). Fully-cached runs complete in < 5 seconds.

**Independent Test**: Run `bats test/infra/build-geocoder.bats` — test T012 passes alongside all prior tests.

### Test for User Story 3

- [X] T012 [US3] Add bats test `cached_dbf_skips_download_and_unzip` to `test/infra/build-geocoder.bats`: pre-create `$BATS_TEST_TMPDIR/tl_2024_19001_addr.dbf` (the unpacked marker); export `FILE_LIST="tl_2024_19001_addr.zip"`; use a curl stub that exits 1 if called (proving download was not attempted); run `bash "$SCRIPT"`; assert success; assert `$BATS_TEST_TMPDIR/curl_calls` does not exist or is empty for download URLs. **Verify this test FAILS before T013 is implemented.**

### Implementation for User Story 3

- [X] T013 [US3] Add `.dbf` existence fast-path as the first check inside `_dl_worker` in `infra/scripts/build-geocoder.sh`: `if [ -f "${TIGER_HOST_DIR}/${filename%.zip}.dbf" ]; then printf "  cached  %s\n" "${filename}"; return 0; fi` — this must precede all download logic so already-unpacked files are skipped entirely.

**Checkpoint**: `bats test/infra/build-geocoder.bats` — all 5 tests (T006, T007, T009, T011, T012) pass.

---

## Phase 6: User Story 4 — Setup Wizard Integration (Priority: P4)

**Goal**: The setup wizard's animated dashboard (step 5) continues to work correctly. The script's exit-code contract with `setup.sh` is unchanged.

**Independent Test**: Run `bats test/infra/build-geocoder.bats` — tests T014 and T015 pass.

### Tests for User Story 4

- [X] T014 [US4] Add bats test `nominatim_import_runs_after_successful_downloads` to `test/infra/build-geocoder.bats`: export `FILE_LIST="tl_2024_19001_addr.zip"`, set `CURL_STUB_HTTP_CODE=200`, pre-create `.dbf` marker (to skip real download); run `bash "$SCRIPT"`; assert success; assert `$BATS_TEST_TMPDIR/docker_calls` contains `nominatim add-data` (import was invoked). **Verify this test FAILS before T015 is implemented** (docker stub doesn't exist yet in the path by default — confirm the stub from T004 is wired).
- [X] T015 [US4] Add bats test `nominatim_import_skipped_when_download_fails` to `test/infra/build-geocoder.bats`: set `CURL_STUB_HTTP_CODE=500`, export `FILE_LIST="tl_2024_19001_addr.zip"`; run `bash "$SCRIPT"`; assert failure (exit 1); assert `$BATS_TEST_TMPDIR/docker_calls` does not contain `nominatim add-data` (import was NOT called).

### Verification for User Story 4

- [X] T016 [US4] Read `infra/scripts/setup.sh` and verify step 5 (the `build-geocoder.sh` invocation) correctly propagates exit codes to the dashboard's pass/fail indicator — confirm `_run_step` captures the exit code and that no code change is needed; if a change is needed, make it. Document outcome as a comment in `specs/005-parallel-tiger-download/plan.md` under the US4 section.

**Checkpoint**: `bats test/infra/build-geocoder.bats` — all 7 tests pass (T006, T007, T009, T011, T012, T014, T015).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: CI integration, lint validation, and final verification.

- [X] T017 Update `.github/workflows/ci-scripts.yml` — add a `bats` job after the existing `shellcheck` job: use `bats-core/bats-action@4.0.0` to install bats + bats-assert + bats-support; add step `run: bats test/infra/`; add `paths` trigger entry `test/infra/**` alongside existing `infra/scripts/**`
- [X] T018 Run `shellcheck --severity=warning --exclude=SC1091,SC2034 infra/scripts/build-geocoder.sh` locally and fix any new warnings introduced by the parallel loop changes (common issues: SC2034 unused vars, SC2064 trap quoting, SC2206 word-splitting in array assignment)
- [X] T019 Validate against `specs/005-parallel-tiger-download/quickstart.md` — (a) run `bats test/infra/` and confirm output matches expected format; update quickstart.md if actual output differs from documented examples; (b) SC-003 timing: `time bats test/infra/build-geocoder.bats` on the cached-file test should complete in well under 5 seconds — record the wall-clock result in a PR comment as evidence for SC-003; (c) SC-001 timing: on the first real Iowa run (requires live Census Bureau access outside CI), record the actual wall-clock time in `specs/005-parallel-tiger-download/BENCHMARKS.md` with connection speed and date as evidence for the < 10 min budget (SC-001)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (stubs must exist before skeleton is written)
- **Phases 3–6 (User Stories)**: All depend on Phase 2 completion; stories are sequential (each builds on the same script)
- **Phase 7 (Polish)**: Depends on all story phases complete

### User Story Dependencies

- **US1 (P1)**: No dependencies — can start after Phase 2
- **US2 (P2)**: Depends on US1 (throttling wraps the loop implemented in US1)
- **US3 (P3)**: Depends on US1 (fast-path is added to `_dl_worker` from US1)
- **US4 (P4)**: Depends on US1 (tests rely on the worker + import step being wired together)

### Within Each Phase

- Tests (T006/T007, T009/T011, T012, T014/T015) must be written and confirmed to **fail** before their paired implementation tasks run
- `_dl_worker` modifications in phases 3–5 all touch the same function in `infra/scripts/build-geocoder.sh` — these are sequential
- All polish tasks (T017–T019) are independent and can run in parallel

### Parallel Opportunities

- T002, T003, T004 (Phase 1 stubs) — different files, no dependencies
- T006, T007 (Phase 3 test tasks) — same file, write sequentially unless splitting across devs
- T014, T015 (Phase 6 test tasks) — same file, write sequentially
- T017, T018, T019 (Phase 7 polish) — different files, can run in parallel

---

## Parallel Example: Phase 1 Stubs

```bash
# All three stubs can be written simultaneously (different files):
Task: "Create test/infra/stubs/curl"        # T002
Task: "Create test/infra/stubs/unzip"       # T003
Task: "Create test/infra/stubs/docker"      # T004
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (stubs)
2. Complete Phase 2: Foundational (bats skeleton)
3. Write tests T006, T007 → confirm they fail
4. Complete Phase 3: US1 (parallel loop)
5. **STOP and VALIDATE**: `bats test/infra/build-geocoder.bats` — 2 tests pass
6. Ship US1 alone if needed; US2–US4 are additive

### Incremental Delivery

1. Setup + Foundational → test infrastructure ready
2. US1 → parallel downloads working, tests green → MVP
3. US2 → rate-limit-safe (cap + backoff), tests green
4. US3 → fast re-runs, tests green
5. US4 → setup wizard integration confirmed, all 6 tests green
6. Polish → CI updated, shellcheck clean

---

## Notes

- [P] = different files or no unresolved dependencies in the same phase
- All `_dl_worker` tasks (T008, T011, T013) touch `infra/scripts/build-geocoder.sh` — run sequentially
- All bats test tasks (T006, T007, T009, T012, T014, T015) touch `test/infra/build-geocoder.bats` — run sequentially
- `TIGER_HOST_DIR` env override (documented in CLI contract) is the key to testability — all tests set it to `$BATS_TEST_TMPDIR`
- `FILE_LIST` is set as an env var export in tests to bypass the Census Bureau discovery step (Step 1 of the script runs curl for the index — stub it or pre-export FILE_LIST)
- Commit after each checkpoint (Phase 3 complete, Phase 4 complete, etc.)

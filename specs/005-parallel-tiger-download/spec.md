# Feature Specification: Parallel TIGER/Line Data Download

> **⚠️ Superseded (2026-06-10).** This spec assumed TIGER address data is sourced as raw per-county
> Census ADDR files, which a faster parallel download would speed up. That premise is invalid:
> Nominatim 4.4's `add-data --tiger-data` requires *preprocessed CSV* (street geometry + address
> range + name), whereas Census ADDR files are address-range tables only (no geometry, no street
> names). `infra/scripts/build-geocoder.sh` now downloads Nominatim's official preprocessed bundle
> (`tiger<YEAR>-nominatim-preprocessed.csv.tar.gz`) — a single, county-split file — and extracts only
> the configured state's counties. There is no longer a multi-file download to parallelize, so the
> user-facing goal (a fast first-run TIGER import) is met by a different mechanism. The sections below
> are retained for historical context only.

**Feature Branch**: `005-parallel-tiger-download`

**Created**: 2026-06-10

**Status**: Superseded

**Input**: User description: "the app downloads TIGER data from Census Bureau in parallel"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fast First-Time Setup (Priority: P1)

A developer runs the setup wizard for the first time. The TIGER/Line address data step currently downloads 99 county files one at a time from the US Census Bureau, which takes over an hour on a typical connection. With parallel downloads, the same step completes in a few minutes, making the full setup wizard practical to run on a first-time local environment.

**Why this priority**: The setup wizard is blocked on this step. At current sequential speeds (~2 min/file × 99 counties), the TIGER import is prohibitively slow for any developer setting up the project. Parallel downloads are the only practical path to a usable first-run experience.

**Independent Test**: Run `infra/scripts/build-geocoder.sh` against a clean cache on an Iowa region and verify all 99 county files are downloaded and successfully imported in under 10 minutes.

**Acceptance Scenarios**:

1. **Given** no county files are cached, **When** `build-geocoder.sh` runs, **Then** all county files download concurrently (up to the rate-limit-safe concurrency cap) and complete in under 10 minutes for Iowa (99 counties).
2. **Given** some county files are already cached, **When** `build-geocoder.sh` runs, **Then** only missing files are fetched (cached files are skipped), and the script completes faster than a full download.
3. **Given** a download fails for one county after retries, **When** the script finishes, **Then** the failure is reported clearly, the import does not run with partial data, and the user is told which file(s) failed.

---

### User Story 2 - Rate-Limit-Aware Concurrency (Priority: P2)

The parallel downloads stay within the Census Bureau's acceptable use limits. The concurrency level is chosen conservatively enough that requests succeed without triggering throttling or HTTP 429 responses. If the server does return a rate-limit response, the script backs off and retries rather than failing immediately.

**Why this priority**: Blasting 99 simultaneous connections to a government server risks being blocked or rate-limited, breaking the tool for all users. Responsible concurrency is a prerequisite for reliable parallel operation.

**Independent Test**: Run `build-geocoder.sh` with the full Iowa county list and verify no HTTP 429 or connection-refused errors appear in the output; all files complete without manual intervention.

**Acceptance Scenarios**:

1. **Given** a fresh cache, **When** the script runs, **Then** no more than the configured maximum concurrent connections are open to the Census Bureau at any moment.
2. **Given** the Census Bureau returns an HTTP 429 for a file, **When** the retry logic runs, **Then** the download waits before retrying and ultimately succeeds or reports a clear failure after exhausting retries.
3. **Given** the concurrency cap is set to a value, **When** 99 files need downloading, **Then** files are dispatched in batches of that size until all are complete.

---

### User Story 3 - Resilient Partial Re-Runs (Priority: P3)

A developer's download was interrupted mid-run. When they re-run the script, only the missing county files are fetched — already-downloaded files are not re-downloaded.

**Why this priority**: With 99 files, interruptions are likely. A re-run that repeats all downloads negates much of the speed gain from parallelism.

**Independent Test**: Download a partial set of county files, then run `build-geocoder.sh` and confirm only the absent files are fetched while present files are skipped.

**Acceptance Scenarios**:

1. **Given** 50 of 99 county files exist in the cache, **When** the script runs, **Then** exactly 49 files are fetched and 50 are skipped.
2. **Given** all county files exist in the cache, **When** the script runs, **Then** zero files are fetched and the import step runs immediately.

---

### User Story 4 - Setup Wizard Integration (Priority: P4)

The setup wizard's animated dashboard (step 5: "TIGER address data") continues to work correctly when the underlying script runs downloads in parallel — showing a spinner and elapsed time throughout, and marking ✓ or ✗ on completion.

**Why this priority**: The dashboard drives the developer's first-run experience. It must reflect reality regardless of whether the underlying work is sequential or parallel.

**Independent Test**: Run the full `setup.sh` wizard through step 5 and verify the dashboard spinner animates throughout the download and correctly reflects success or failure.

**Acceptance Scenarios**:

1. **Given** the setup wizard reaches step 5, **When** parallel downloads are running, **Then** the dashboard spinner animates and the elapsed time increments normally.
2. **Given** the parallel download completes successfully, **When** step 5 finishes, **Then** the dashboard shows ✓ with the elapsed time.
3. **Given** one or more county downloads fail, **When** step 5 finishes, **Then** the dashboard shows ✗ and the failure detail is printed below the panel.

---

### Edge Cases

- What happens when the Census Bureau rate-limits requests? (affected downloads should back off and retry rather than failing immediately)
- What is the safe maximum concurrency that avoids triggering throttling on the Census Bureau's servers?
- How does the system handle a complete network outage mid-download? (partial cache is preserved; re-run fetches only missing files)
- What happens if the geocoder container is not healthy when the import step runs after downloads complete? (existing pre-flight health check must still run before `nominatim add-data`)
- Does macOS's older Bash (3.2, which lacks `wait -n`) need to be supported, or can the implementation require a newer Bash?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST download all county TIGER/Line ZIP files concurrently rather than sequentially.
- **FR-002**: The system MUST cap concurrent connections to the Census Bureau at a fixed maximum (default: 5) to stay within responsible-use limits and avoid triggering rate limiting.
- **FR-003**: If the Census Bureau returns an HTTP 429 (rate limit) or a transient connection error, the system MUST wait before retrying that file rather than failing immediately.
- **FR-004**: The system MUST skip any county file that already exists in the local cache directory, so partial and complete re-runs do not re-fetch already-downloaded files.
- **FR-005**: The system MUST report a clear error and exit with a non-zero status if any county file fails to download after all retries, without running the Nominatim import against partial data.
- **FR-006**: Each downloaded ZIP file MUST be unpacked after its own download completes rather than waiting for all downloads to finish, so unpacking work overlaps with remaining downloads.
- **FR-007**: The total time for downloading and unpacking all Iowa county files (99 files) on a typical broadband connection MUST be under 10 minutes.
- **FR-008**: All existing post-download behavior MUST be preserved: geocoder health check, `nominatim add-data` invocation, and final success/failure messaging.
- **FR-009**: The concurrency cap MUST be a single, easily-changed constant in the script so it can be tuned if the Census Bureau's policies change.

### Key Entities

- **County file**: A ZIP archive from the Census Bureau containing address-range shapefiles for one county, identified by state FIPS + county FIPS code (e.g., `tl_2024_19001_addr.zip`).
- **Cache directory**: The local directory (`infra/data/tiger/<fips>/`) where downloaded ZIPs are stored; files present here are treated as already-downloaded.
- **Concurrency cap**: The maximum number of simultaneous outbound connections to the Census Bureau server; the primary knob for respecting rate limits.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 99 Iowa county files download and unpack in under 10 minutes on a standard broadband connection (down from 3+ hours sequential).
- **SC-002**: At no point during the download phase are more than 5 simultaneous connections open to the Census Bureau.
- **SC-003**: Re-running the script when all files are cached completes the download phase in under 5 seconds.
- **SC-004**: A run where one county file exhausts all retries exits with a non-zero status, names the failed file, and does not invoke the Nominatim import.
- **SC-005**: The setup wizard's step-5 dashboard behaves identically to the current sequential implementation: spinner animates throughout, ✓/✗ reflects the final outcome.

## Assumptions

- The Census Bureau's public TIGER download endpoint does not require authentication.
- A concurrency cap of 5 simultaneous connections is conservative enough to avoid rate limiting on Census Bureau servers; this can be lowered if throttling is observed in practice.
- The developer's environment has `curl` available (already a prerequisite checked by `setup.sh`).
- macOS ships Bash 3.2 which lacks `wait -n`; the implementation must use a portable approach (background jobs with PID tracking, or `xargs -P`) that works on both macOS and Linux without requiring a Bash upgrade.
- The existing per-file retry logic (`curl --retry 3`) handles transient failures; the concurrency cap handles rate-limit pressure.
- Parallel downloads apply to all configured states, not just Iowa.

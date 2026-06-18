# Feature Specification: Aggregated Camera Data Source-of-Truth

**Feature Branch**: `003-camera-data-aggregation`

**Created**: 2026-06-01

**Status**: Completed

**Input**: User description: "use all the Flock camera location sources, including DeFlock and others, and aggregate the data so our database is the source of truth. refresh our data periodically in the background at whatever 4am central time is in UTC"

## Clarifications

### Session 2026-06-01

- Q: Should the daily refresh run at a fixed UTC time or always at 4am local Central (DST-aware)? → A: Fixed 08:00 UTC (= 2am CST / 3am CDT); constant year-round, not adjusted for daylight saving.
- Q: How are duplicate cameras reported by multiple sources judged to be the same physical camera? → A: No camera-level merge; each source's record is kept with its own provenance, and duplicates collapse at the monitored-segment layer (cameras on the same road segment share one avoidance target).
- Q: What is the lifecycle of a camera that disappears from its source? → A: Keep avoiding it while stale, then auto-retire (exclude from avoidance) after 3 consecutive missing daily refreshes; internally-verified cameras are exempt from auto-retire and require human removal.
- Q: Which concrete sources are in scope for v1? → A: DeFlock + OpenStreetMap as live integrations, plus a generic importer for any permissively-licensed open-data/records (FOIA) export; additional "other" sources are added through that importer or new adapters without redesign.
- Q: What geographic extent does each refresh cover? → A: The entire continental US on every refresh, regardless of where routing is offered (not limited to configured coverage areas).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Aggregate every available camera source into one trusted database (Priority: P1)

The system gathers ALPR/Flock camera locations from all available external sources — community-maintained
datasets (e.g., DeFlock), OpenStreetMap surveillance/ALPR data, and official or public open-data / records
exports — and combines them into a single internal database that the route planner treats as the
authoritative source of truth. Each camera carries the record of where it came from.

**Why this priority**: Coverage and accuracy of avoidance depend entirely on how complete and trustworthy
the camera dataset is. No single public source is comprehensive; aggregating them is the core value of this
feature and the foundation everything else builds on.

**Independent Test**: Configure two or more sources, run an aggregation, and confirm the database contains
the union of their cameras, each tagged with its originating source and license, with duplicate physical
cameras represented once for avoidance.

**Acceptance Scenarios**:

1. **Given** multiple configured sources each listing distinct cameras, **When** an aggregation runs,
   **Then** the database contains cameras from every source, each with a recorded source and license.
2. **Given** two sources that both report the same physical camera, **When** an aggregation runs,
   **Then** that camera is represented as a single avoidance target (not double-counted), while each
   source observation remains attributable.
3. **Given** an aggregation has already run, **When** the same source data is imported again,
   **Then** no duplicate records are created and no existing records are lost (idempotent).

---

### User Story 2 - Automatic daily background refresh (Priority: P2)

Camera data is refreshed automatically once per day in the background, at 2am Central time, without anyone
having to trigger it. New cameras appear, and changes from the upstream sources are pulled in, so the
planner's data stays current on its own.

**Why this priority**: Surveillance camera deployments change continuously. Stale data degrades avoidance
quality. Automation removes the operational burden and guarantees freshness, but it depends on the
aggregation pipeline (P1) already existing.

**Independent Test**: With the schedule configured, confirm a refresh is triggered automatically at the
scheduled time (2am Central), runs to completion in the background, and updates the database — and that an
operator can also trigger a refresh on demand.

**Acceptance Scenarios**:

1. **Given** the daily schedule is active, **When** the clock reaches 2am Central, **Then** a refresh
   starts automatically in the background without blocking user-facing routing.
2. **Given** a refresh is already running, **When** the next scheduled time arrives, **Then** a second
   overlapping refresh does not start.
3. **Given** an operator wants fresh data immediately, **When** they trigger a manual refresh,
   **Then** the same aggregation runs on demand.

---

### User Story 3 - Source-of-truth integrity across refreshes (Priority: P3)

The internal database remains the authoritative record even as upstream sources change. Human-made
verifications and corrections are preserved across refreshes, and cameras that disappear upstream are
handled conservatively rather than vanishing silently.

**Why this priority**: Aggregation and refresh are only trustworthy if repeated refreshes don't erase
curated knowledge or cause avoidance targets to flip-flop. This protects long-term data quality but is a
refinement on top of P1/P2.

**Independent Test**: Verify/correct a camera, run a refresh, and confirm the verification persists; remove
a camera from a source, run a refresh, and confirm it is flagged stale rather than immediately dropped from
avoidance.

**Acceptance Scenarios**:

1. **Given** a camera has been internally verified or corrected, **When** a refresh pulls updated upstream
   data, **Then** the internal verification/correction is preserved and not silently overwritten.
2. **Given** a camera that existed in a prior import is no longer present in its source, **When** a refresh
   runs, **Then** that camera is flagged as stale/unverified rather than immediately removed from avoidance.
3. **Given** a refresh completes, **When** an operator reviews the outcome, **Then** per-source results
   (counts added/updated, failures, timestamp) are available without exposing any user data.

---

### Edge Cases

- **Source unavailable / times out**: the refresh continues with the remaining sources and preserves the
  last good data for the failing source; the failure is recorded.
- **Source returns malformed or partial data**: invalid records are skipped without aborting the whole
  refresh; the count of skipped records is recorded.
- **Conflicting attributes for the same camera across sources**: each observation is retained with its
  provenance; duplicates collapse to a single avoidance target; corroboration by multiple sources raises
  confidence.
- **Camera removed upstream**: flagged stale rather than hard-deleted (see User Story 3).
- **Source license/terms do not permit reuse**: that source is not ingested; only permissively-licensed
  sources are aggregated, and attribution is recorded.
- **Overlapping refreshes**: a new refresh does not start while one is already running.
- **Daylight-saving transition**: the schedule is a fixed UTC instant (08:00 UTC) and does not adjust for
  DST; it is 2am Central in winter (CST) and 3am Central in summer (CDT).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST aggregate ALPR/Flock camera locations from multiple external sources into a single
  internal database that serves as the authoritative source of truth for route avoidance.
- **FR-002**: System MUST include, for v1, two live source integrations — DeFlock and OpenStreetMap
  surveillance/ALPR data — plus a generic importer for any permissively-licensed open-data or public-records
  (FOIA) export. Additional "other" sources are onboarded via that importer or new adapters (see FR-003).
- **FR-003**: System MUST be extensible to add additional sources without redesigning the pipeline.
- **FR-004**: Every camera record MUST retain its provenance (originating source) and the license /
  attribution applicable to that source.
- **FR-005**: System MUST ingest only from sources whose terms permit reuse, and MUST record the applicable
  license and attribution for each.
- **FR-006**: System MUST ensure the same physical camera reported by more than one source becomes a single
  avoidance target rather than being double-counted. This is achieved at the monitored-segment layer (each
  source's camera record is retained with its own provenance; cameras on the same road segment share one
  avoidance target) — there is no camera-level merge into a canonical record.
- **FR-007**: Imports MUST be idempotent — re-importing the same source data MUST NOT create duplicates or
  lose existing records.
- **FR-008**: System MUST preserve internal verification/correction state across refreshes; upstream changes
  MUST NOT silently overwrite human-verified data.
- **FR-009**: When a previously imported camera is no longer present in its source, the system MUST flag it
  as stale while continuing to use it for avoidance, and MUST auto-retire it (exclude it from avoidance)
  only after 3 consecutive missing daily refreshes (configurable grace window). Internally-verified cameras
  are exempt from auto-retire and are removed only by a human.
- **FR-010**: System MUST refresh the data automatically on a recurring daily schedule at a fixed 08:00 UTC
  (= 2am CST / 3am CDT), not adjusted for daylight saving.
- **FR-011**: Refresh MUST run in the background, without manual intervention and without blocking or
  degrading user-facing routing.
- **FR-012**: If a source is unavailable or errors during a refresh, the system MUST continue with the
  remaining sources and preserve the last good data for the failing source (partial-failure isolation).
- **FR-013**: System MUST record the outcome of each refresh per source (records added/updated/skipped,
  failures, and timestamp) for observability, without retaining any user data.
- **FR-014**: System MUST prevent overlapping refreshes of the same data (no concurrent duplicate runs).
- **FR-015**: System MUST associate newly imported/updated cameras with the specific monitored road
  segment(s) they cover, consistent with the existing segment-based avoidance model.
- **FR-016**: Data acquisition MUST NOT transmit any user's origin, destination, route, or other user data
  to any external source; sources are queried only for reference data over a broad geographic extent (the
  continental US), never by any individual user's location.
- **FR-019**: Each refresh MUST cover the entire continental US, independent of which coverage areas routing
  is currently offered in.
- **FR-017**: Refresh/import logs MUST NOT retain client IPs or route coordinates, consistent with the
  project's anonymity rules.
- **FR-018**: System MUST allow an operator-triggered manual refresh in addition to the automatic schedule.

### Key Entities *(include if feature involves data)*

- **Camera (reference data)**: a known ALPR/Flock camera — location, type, facing direction (if known),
  confidence, verification status, provenance, and freshness tracking (last seen in source, count of
  consecutive missing refreshes, stale/retired flag). Reference data only; never user data.
- **Data Source**: a provider of camera data — name, kind (community / official / internal), reference URL,
  license/attribution, and the timestamp it was last refreshed.
- **Monitored Segment**: the specific road segment(s) a camera covers; the unit of avoidance.
- **Refresh Run**: the record of a scheduled or manual refresh — per-source counts (added/updated/skipped),
  failures, status, and timestamp. Contains no user data.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After any refresh, 100% of camera records carry an identifiable source and license/attribution.
- **SC-002**: Under normal operation, camera data is automatically refreshed every day and is never more than
  24 hours stale.
- **SC-003**: When one source is unavailable, coverage from healthy sources is unaffected — zero records from
  healthy sources are lost during a partial failure.
- **SC-004**: A physical camera reported by multiple sources is represented as exactly one avoidance target
  (no double-counting in route avoidance).
- **SC-005**: Internal verifications/corrections are retained across consecutive refreshes with 100%
  persistence (no silent loss).
- **SC-006**: The scheduled refresh begins within 15 minutes of 08:00 UTC each day.
- **SC-007**: No user data (origin, destination, route, IP) is transmitted to any external source during data
  acquisition, verifiable by audit/test.
- **SC-008**: Aggregating from all configured sources increases the count of distinct avoidance targets
  versus any single source alone.
- **SC-009**: A full nationwide refresh completes within its daily window and records its duration per run.
  Fetching is deliberately single-concurrency to respect public-source fair-use, so a nationwide run may take
  on the order of a few hours against the public Overpass endpoint; this is acceptable for a once-daily
  background job. (A self-hosted endpoint would bring it well under an hour, but is not required.)

## Assumptions

- This feature extends the existing camera/segment/provenance data model and the segment-based avoidance
  approach (feature 002); it broadens the set of sources and adds scheduled background refresh rather than
  redesigning the model.
- The daily refresh runs at a fixed 08:00 UTC (per clarification) — equivalent to 2am Central Standard Time
  and 3am Central Daylight Time. It is not adjusted for daylight saving. The scheduled time is configurable.
- "All sources" means all sources that are publicly available under terms that permit reuse at build time;
  the source set is extensible over time. Sources whose terms forbid reuse are excluded.
- Conflicts between sources are resolved by retaining all observations with provenance and collapsing
  duplicates at the monitored-segment layer (cameras on the same road segment share one avoidance target);
  corroboration across sources raises confidence.
- Cameras missing from a source on refresh are marked stale rather than hard-deleted, preserving internal
  verification and avoiding abrupt loss of avoidance targets.
- Background job scheduling and the recurring-job mechanism from the existing stack are used for the daily
  refresh; the schedule is configurable.
- Data acquisition queries sources over a broad geographic extent — the continental US — never by any
  individual user's location, preserving the project's strict-anonymity non-negotiable. Nationwide pulls may
  require chunking/tiling the request to stay within external-source limits; the chunking strategy is an
  implementation concern for the planning phase.

# Security and Reliability Audit Report

## Executive summary

The audit confirmed one high-severity privacy issue, one high-severity refresh correctness issue, and several medium-severity availability, scalability, and correctness risks. The highest-risk items are the unrestricted runtime API endpoint and refresh continuation state. The API endpoint can redirect route and geocoder data to an arbitrary host if runtime configuration is modified. A resumed refresh can use a different delta anchor than the initial run and produce an inconsistent camera set.

No confirmed evidence was found for the alleged CSP contradiction, production route-response drift, or a cross-host failover claim. Those items should not be tracked as defects without additional deployment evidence.

## Prioritized findings

### P0 / High

#### F-01: Runtime `apiBase` accepts arbitrary endpoints

**Evidence:** `frontend/src/config.ts:40-48`; `frontend/src/services/apiClient.ts:46-58`

`config.json` is accepted without origin or path validation, and route and geocoder requests are sent to the resulting value. A modified or compromised runtime configuration can send origin, destination, and route data to an attacker-controlled service, violating the anonymity invariant.

**Recommendation:** Remove runtime endpoint override where possible and derive the API origin from the serving origin. If an override is required, require an explicit allowlist of HTTPS origins, reject credentials and unexpected paths, validate before rendering, and add tests for malicious absolute URLs, non-HTTPS URLs, and unapproved origins. Consider serving configuration with a restrictive integrity/deployment control.

#### F-02: Refresh delta anchor is not persisted in continuation state

**Evidence:** `TiledRefresh#delta_since`; refresh continuation cursor/state

The delta timestamp is held on the job instance while the continuation cursor stores no anchor. After resumption, earlier tiles may have updated `DataSource.last_imported_at`, causing later tiles to calculate deltas from a different timestamp. The same refresh can therefore reconcile against mixed source snapshots.

**Recommendation:** Capture the delta anchor once before the first tile and serialize it in continuation state. Every resumed segment must use that exact timestamp. Add a failure/resume test that mutates `last_imported_at` between segments and verifies identical selection behavior.

### P1 / High to Medium

#### F-03: Route deadline does not cover route planning

**Evidence:** `RoutePlanner#plan`

The deadline is initialized only after candidate lookup, fastest routing, and detection begin. Each Valhalla request can consume five seconds, and avoidance can issue many sequential requests. The configured deadline therefore does not bound the actual request duration.

**Recommendation:** Create the monotonic deadline at the beginning of `plan`, pass remaining time into every collaborator, stop before starting a request that cannot fit, and enforce request-level timeouts against the remaining budget. Return the documented fallback result when the budget expires. Add deterministic tests covering timeout during candidate lookup, fastest routing, and avoidance.

#### F-04: No bound on route candidate distance or count

**Evidence:** `SegmentExclusionBuilder#segments_in_bbox` uses `.to_a`; route inputs have coordinate validation only

A large bounding box or otherwise valid but distant endpoints can fully materialize an unbounded candidate set. This creates database, memory, and route-planning work proportional to attacker-controlled input.

**Recommendation:** Enforce maximum endpoint separation and maximum bounding-box area at the request boundary. Add a database-side candidate cap with deterministic ordering and return a bounded, explicit error when exceeded. Keep processing lazy or batched rather than calling `.to_a` on an unbounded relation. Add request and service tests for maximum and over-limit inputs.

#### F-05: Camera refresh snapping materializes all rows and writes per row

**Evidence:** `SegmentSnapper#snap_all`; `create_segments`

The refresh loads the complete camera relation into an array, then performs per-camera queries and inserts. Memory and database round trips grow linearly with the full source size.

**Recommendation:** Process cameras in bounded batches using keyset pagination, bulk-load candidate road data where practical, and use bulk insert/upsert for derived segments. Add batch-size metrics and failure-safe retry behavior. Test that large refreshes do not materialize the complete relation.

#### F-06: GeoJSON ingestion reads and parses the entire file

**Evidence:** `GeojsonFile#fetch`

`File.read` followed by `JSON.parse` makes source parsing memory proportional to the entire file. Import batching starts only after parsing and does not protect the ingestion boundary.

**Recommendation:** Enforce a maximum source size before reading, stream or incrementally parse GeoJSON, and reject malformed or oversized inputs with an actionable error. Measure peak memory in an import fixture representative of production data.

#### F-07: Refresh reconciliation holds one large transaction and performs per-row writes

**Evidence:** `StaleReconciler#reconcile`; `mark_missing!`

One transaction spans the complete source, while missing cameras are updated with multiple statements per row. Long locks and transaction growth can contend with reads and other refresh work.

**Recommendation:** Reconcile in bounded, restartable batches. Prefer set-based updates or bulk operations, keep transactions scoped to a batch, and record progress for retry. Validate lock duration and statement counts under a production-sized fixture.

#### F-08: Telemetry forwards arbitrary context

**Evidence:** `Telemetry.notify` and `Telemetry.alert`

Unrestricted hashes are forwarded to logs or Sentry. The privacy rule is documented but not enforced, so route coordinates, client data, or future sensitive fields can leak through observability paths.

**Recommendation:** Define an allowlisted telemetry schema, sanitize recursively, redact coordinate-like and identifier-like values, cap field sizes, and reject or drop unknown keys. Add tests proving origin, destination, route geometry, client IP, and arbitrary nested values are excluded.

#### F-09: Geo dependency failures are reported as invalid routes

**Evidence:** `RoutesController`

Every `Geo::HttpClient::ServiceError` is converted to HTTP 422. A Valhalla or other dependency outage is therefore presented as a client input error and prevents correct retry/alert behavior.

**Recommendation:** Map dependency timeouts and service failures to HTTP 503 with a stable error code and `Retry-After` where appropriate. Keep malformed or semantically invalid user input at 422. Add request specs for both classes of failure.

#### F-10: Viewport camera results are unordered before `limit(5_000)`

**Evidence:** `CamerasController#index`

Without `ORDER BY`, a dense viewport returns an unstable and arbitrary subset. Users can see different cameras for the same request, and important records may be omitted.

**Recommendation:** Define deterministic ordering, preferably by stable primary key or spatial priority. Return truncation metadata (`truncated`, total/estimated count, or a continuation mechanism) so clients know the result is incomplete. Add a dense-result request spec.

### P2 / Medium

#### F-11: Frontend camera rendering scales poorly at the 5,000-camera limit

**Evidence:** camera GeoJSON generation, MapLibre source/layer updates, and hidden list rendering

A response can create point and segment GeoJSON, trigger large MapLibre updates, and render 5,000 hidden DOM list items. The implementation has a confirmed code-level scaling cost, but user-visible jank and memory impact require browser profiling.

**Recommendation:** Profile at 1,000, 5,000, and worst-case realistic payloads. Virtualize the camera list, avoid duplicate representations where possible, and use server-side tiling or viewport-level aggregation for dense areas. Set a measured payload and frame-time budget.

#### F-12: `/config.json` can block initial rendering indefinitely

**Evidence:** `frontend/src/main.tsx`; `loadConfig()`

The application renders only after configuration loading resolves, and the fetch has no timeout. A stalled request leaves the initial page unavailable indefinitely.

**Recommendation:** Add an abort timeout and an explicit error/loading state. Provide a safe same-origin fallback when deployment permits. Test timeout, malformed configuration, and recovery behavior.

#### F-13: Fixed MapLibre shared asset name defeats immutable caching

**Evidence:** `frontend/vite.config.ts`; Caddy one-year cache for `/assets/*`

`assets/maplibre-gl-shared.mjs` has a stable filename while the server advertises immutable long-lived caching. Updated content can remain stale in clients until cache expiry.

**Recommendation:** Emit a content-hashed filename, or remove immutable caching from the fixed path and version it explicitly. Add a build/deployment check that confirms changed asset content receives a changed cache key.

#### F-14: Geocoder requests use default TanStack retries

**Evidence:** `useGeocodeSearch`

Default retries can multiply requests during an outage or slow dependency period. This increases load on the geocoder and delays visible failure.

**Recommendation:** Disable retries for non-transient geocoder errors and use a small bounded retry policy only for explicitly transient failures, with backoff and cancellation. Add tests for retry count and error classification.

#### F-15: Detector work scales with distinct route candidates

**Evidence:** route detector cache and candidate geometry handling

The detector cache avoids many repeated exact calls, so the claim that every invocation repeats work is overstated. Distinct candidate geometries still cause additional PostGIS work, and total cost scales with the candidate set.

**Recommendation:** Keep the cache, normalize equivalent geometries before lookup, cap candidates, and measure query count and latency against candidate count. Treat this as part of F-04 rather than a separate unconditional duplicate-query bug.

#### F-16: Coverage warning performs limited redundant work

At most two coverage queries occur, and Ruby short-circuiting often reduces this to one. This is a low-severity optimization, not a significant performance finding.

**Recommendation:** Defer unless profiling identifies it as material; combine or cache the query only if doing so simplifies rather than complicates the code.

## Operational items requiring validation

The following conditions are plausible concerns but are not rated as confirmed high-impact findings without deployment and workload evidence:

- PostgreSQL connection-pool sizing and whether configured capacity is excessive.
- Single-host failure domain.
- Missing resource limits, incomplete health checks, and backup coverage.
- Queue/database contention under concurrent refresh and web load.
- Rate-limit identifiers as a privacy exception. Solid Cache entries expire and are not persistent identities in the usual sense; document the retention and threat model before changing architecture.
- Fixed sleeps and missing Playwright artifact upload. These are test-maintenance issues unrelated to runtime architecture.

Validate these with deployment configuration, PostgreSQL limits, concurrency tests, backup-restore drills, and incident/runbook review.

## Incorrect or unsupported claims rejected

- **Separate-origin failover contradicts CSP:** not established. The inspected Caddy configuration does not emit the Rails CSP. Cross-origin behavior still depends on CORS and deployment configuration.
- **Frontend API failover silently fails because of CSP:** not established for the same reason; CORS or network policy may still cause failure.
- **Refreshes run outside the web process as a complete mitigation:** jobs use a separate process, but web, jobs, and PostgreSQL share a host in Kamal. This reduces process interference, not host or database contention.
- **Missing `fastest_comparison.geometry` proves production API drift:** false. Route request specs include the field. The fixture omission is a weak test-quality issue only.

## Remediation order

1. Constrain or remove runtime `apiBase` overrides.
2. Persist the refresh delta anchor in continuation state.
3. Enforce one end-to-end route deadline.
4. Add a real route-planner performance test with deterministic geo collaborators.
5. Bound route candidate distance/count and refresh source memory.
6. Add telemetry context sanitization and privacy tests.
7. Return 503 for geo-service failures.
8. Add deterministic camera ordering and truncation metadata.
9. Batch snapping/reconciliation and profile frontend rendering.
10. Fix config fetch timeout, asset hashing, and geocoder retry policy.

## Verification plan

- Add regression tests for each P0/P1 item before implementation.
- Run backend and frontend checks through `infra/docker-compose.yml` only.
- Exercise route and refresh workloads with production-sized deterministic fixtures.
- Browser-profile dense camera responses and record memory, frame time, and request counts.
- Recheck telemetry output and deployment cache headers after remediation.

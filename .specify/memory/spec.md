# flckd — Main Specification

> Consolidated, cross-feature specification. Each archived feature has its own subsection that
> preserves that feature's **local** requirement IDs (FR-xxx / SC-xxx) verbatim; uniqueness across
> features comes from the `[Source: specs/###-feature]` heading, not a global renumbering.
> Where a later feature changed or removed an earlier requirement, see **§ Superseded / Evolved
> Requirements** at the end — that section is authoritative for the *current implemented state*.
>
> Features are listed in chronological (implementation) order. Bootstrapped 2026-06-18 by archiving
> the full `specs/` directory (002–013).

---

## 002 — Camera-Avoiding Route Planner  [Source: specs/002-flock-route-avoidance]

The founding feature: plan a drivable route that avoids known ALPR/Flock cameras by excluding the
specific monitored road segment(s), shown on an interactive map with localized turn-by-turn
directions, fully anonymous and account-less.

**User Stories**: (P1) plan a camera-avoiding route; (P2) use anonymously, no account/PII;
(P3) use in own language (auto-detect + runtime switch); (P3) understand/control how cameras are
avoided (counts, graceful "no clean route").

**Functional Requirements** (verbatim):
- **FR-001**: Let a user specify an origin and destination (place/address search, map selection, and/or device location when permitted).
- **FR-002**: Generate a drivable route between origin and destination.
- **FR-003**: Avoid known cameras by excluding the specific road segment(s) each camera monitors (camera snapped to nearest road/intersection, small tolerance), producing a route that traverses zero monitored segments whenever one exists. A route MUST NOT be penalized merely for passing near a camera on a road it doesn't monitor.
- **FR-004**: When no fully camera-free route exists, return the fewest-camera route and clearly indicate complete avoidance wasn't possible.
- **FR-005**: Display the route on an interactive map with human-readable step-by-step directions.
- **FR-006**: Show the trade-off between the camera-avoiding route and the fastest route (added distance + estimated added time). *(Elaborated/implemented by 009.)*
- **FR-007**: Let the user choose an avoidance preference (avoid vs. fastest) and recalculate. *(REMOVED by 004 — see § Superseded.)*
- **FR-008**: Indicate the number of cameras avoided and any unavoidable cameras remaining.
- **FR-009**: Be fully usable on mobile, small touch screens primary (no horizontal scroll / pinch-zoom for core flow).
- **FR-010**: Allow full use without account creation, login, or PII.
- **FR-011**: Not persist origins/destinations/routes in a form linkable to an individual beyond the request lifetime.
- **FR-012**: Not track users across sessions with persistent identifiers for advertising/profiling.
- **FR-012a**: Perform all geocoding, routing, and tile serving on own infrastructure — no external third party ever receives the user's origin/destination/route in normal use.
- **FR-012b**: Allow opening the finished route in an external maps app (Apple/Google) only as an explicit user action, with a prior warning that it shares the locations. *(REMOVED post-009 — replaced by client-side GPX export. See § Superseded.)*
- **FR-013**: Present the interface in multiple languages, selectable any time.
- **FR-014**: Auto-detect preferred language from device/browser, fall back to default. *(Reworked by 012.)*
- **FR-015**: Localize all user-facing text, including directions and error messages.
- **FR-016**: Handle ambiguous/unrecognized location input by prompting to clarify or choose among matches.
- **FR-017**: Support manual origin entry when the user declines device location.
- **FR-018**: Communicate when camera data is incomplete/unavailable for an area while still providing a route.
- **FR-019**: Let the user adjust an existing route (endpoints/preference) and recalculate without restarting.
- **FR-020**: Keep camera data reasonably current via periodic updates; convey recency/coverage limits. *(Mechanism delivered by 003.)*
- **FR-021**: Build camera data by importing open/community datasets + an internal verification/correction layer; record each camera's source/provenance and verification status. *(Delivered by 003.)*

**Key Entities**: Route Request (ephemeral O/D + preference); Route (geometry, distance, time, directions, cameras-avoided, remaining); Camera Location (position, monitored segment(s), type, facing, last-verified, confidence, provenance, verification status); Avoidance Preference *(removed by 004)*; Locale. Data-model also defines `is_fully_clean`, `coverage_warning` codes (`outside_coverage`/`stale_data`), `snap_distance_m`, and a Camera `verification_status` state machine (`unverified`/`verified`/`disputed`/`removed`).

**Success Criteria** (verbatim, with current-state notes):
- **SC-001**: When a camera-free route exists, return zero-camera route in ≥95% of cases.
- **SC-002**: New user → displayed route in <60 s and ≤4 interactions.
- **SC-003**: Complete the flow on a phone-sized screen with no horizontal scroll/zoom.
- **SC-004**: Planned route within 5 s for ≥95% of typical metro requests.
- **SC-005**: 100% of features usable with zero required PII fields and no account.
- **SC-006**: Interface available in ≥5 languages at launch, 100% strings localized. *(Implemented set is en+es; see § Superseded.)*
- **SC-007**: Present avoiding-route time alongside fastest-route time whenever an alternative exists.
- **SC-008**: After a request, retain zero records linking an origin/destination to an identifiable user.
- **SC-009**: Zero third-party requests with origin/destination/route during normal planning; external maps handoff only after explicit warned action. *(Handoff later removed.)*

---

## 003 — Aggregated Camera Data Source-of-Truth  [Source: specs/003-camera-data-aggregation]

Aggregate ALPR/Flock locations from all permissive sources into one authoritative DB (each record
provenance-tagged), refreshed daily in the background at a fixed UTC instant, preserving human
verifications and conservatively retiring upstream-disappeared cameras.

**User Stories**: (P1) aggregate every source into one trusted DB; (P2) automatic daily 08:00 UTC refresh + manual trigger; (P3) source-of-truth integrity across refreshes.

**Functional Requirements** (verbatim):
- **FR-001**: Aggregate ALPR/Flock locations from multiple external sources into one internal DB that is the authoritative source of truth for avoidance.
- **FR-002**: v1 includes two live integrations — DeFlock and OSM surveillance/ALPR data — plus a generic importer for permissively-licensed open-data / FOIA exports.
- **FR-003**: Be extensible to add sources without redesigning the pipeline.
- **FR-004**: Every camera record retains its provenance and the applicable license/attribution.
- **FR-005**: Ingest only from sources whose terms permit reuse; record license + attribution.
- **FR-006**: The same physical camera reported by multiple sources becomes a single avoidance target (no double-count) — handled at the monitored-segment layer; each source record kept with its own provenance (no camera-level canonical merge).
- **FR-007**: Imports MUST be idempotent — re-importing creates no duplicates and loses no records.
- **FR-008**: Preserve internal verification/correction state across refreshes; upstream changes never silently overwrite human-verified data.
- **FR-009**: When a camera is no longer in its source, flag it stale (still used for avoidance) and auto-retire only after 3 consecutive missing daily refreshes (configurable). Internally-verified cameras are exempt; removed only by a human.
- **FR-010**: Refresh automatically on a fixed daily schedule at 08:00 UTC (2am CST / 3am CDT), not DST-adjusted.
- **FR-011**: Refresh runs in the background without blocking/degrading routing.
- **FR-012**: On a source error, continue with remaining sources and preserve last-good data for the failing source (partial-failure isolation).
- **FR-013**: Record each refresh's per-source outcome (added/updated/skipped, failures, timestamp) for observability, retaining no user data.
- **FR-014**: Prevent overlapping refreshes of the same data.
- **FR-015**: Associate imported/updated cameras with their specific monitored segment(s).
- **FR-016**: Data acquisition transmits no user data to any source; sources are queried only for reference data over a broad extent (CONUS), never by a user's location.
- **FR-017**: Refresh/import logs retain no client IPs or route coordinates.
- **FR-018**: Allow an operator-triggered manual refresh in addition to the schedule.
- **FR-019**: Each refresh covers the entire continental US, independent of where routing is offered.

**Key Entities**: Camera (reference data + freshness: `last_seen_in_source_at`, `consecutive_missing_count`, stale flag); Data Source (name, kind, URL, license/attribution, last-refreshed); Monitored Segment (avoidance unit where cross-source duplicates collapse); Refresh Run (per-source counts, failures, status, timestamps, duration_ms — no user data).

**Success Criteria** (verbatim): SC-001 100% of records carry source + license/attribution; SC-002 data never >24 h stale; SC-003 zero healthy-source records lost during partial failure; SC-004 multi-source physical camera = exactly one avoidance target; SC-005 100% persistence of human verifications across refreshes; SC-006 scheduled refresh begins within 15 min of 08:00 UTC; SC-007 no user data transmitted to any source (audit/test-verifiable); SC-008 aggregating all sources increases distinct avoidance targets vs. any single source; SC-009 nationwide refresh completes within its daily window, duration recorded per run (single-concurrency fair-use → a few hours on public Overpass is acceptable).

---

## 004 — Automatic Camera-Priority Routing  [Source: specs/004-auto-route-priority]

Remove the avoidance-preference choice entirely: always try a zero-camera route first, else fall
back to the fewest-camera route, and communicate which kind was returned. Net removal of UI.

**User Stories**: (P1) zero-camera route found automatically; (P1) fewest-camera fallback communicated clearly; (P2) no preference UI anywhere.

**Functional Requirements** (verbatim):
- **FR-001**: Attempt a zero-camera route first, before any alternative.
- **FR-002**: If none exists, return the fewest-camera route.
- **FR-003**: Clearly distinguish a zero-camera route from a minimum-camera fallback.
- **FR-004**: Never present an avoidance-preference selection at any point in the flow.
- **FR-005**: Display the count of cameras the route passes (zero or more).
- **FR-006**: Handle "no route found" with a meaningful error.

**Key Entities**: Route (camera-avoided count, remaining count, fully-camera-free flag); Routing Strategy (internal "zero-first, fewest-fallback", no user-facing parameter).

**Success Criteria** (verbatim): SC-001 100% of results use zero-first/fewest-fallback with no input beyond O/D; SC-002 fewer steps (preference step eliminated); SC-003 zero-camera route returned 100% when one exists; SC-004 minimum-camera route 100% when no zero exists; SC-005 result always communicates zero-camera vs minimum-camera.

> **Note**: This feature deletes 002's preference UI/params (`PreferenceRadios`, `AvoidanceControl`, `avoidance_preference`). `RoutePlanner#plan` drops the `preference:` kwarg.

---

## 005 — Parallel TIGER/Line Data Download  [Source: specs/005-parallel-tiger-download]  ⚠️ SUPERSEDED

> **Status: Superseded (2026-06-10), never implemented.** The premise was invalid — Nominatim 4.4
> needs a preprocessed CSV, not raw per-county ADDR files, so there is no multi-file download to
> parallelize. Geo provisioning was instead reworked at country scale by **011**. Retained for
> historical context only; its requirements are **not** in effect.

Intended: download county TIGER ZIPs concurrently (cap 5), 429-backoff, skip cached files, unpack
per-file, fail-fast before Nominatim import, <10 min for Iowa's 99 counties. FRs FR-001…FR-009 and
SCs SC-001…SC-005 as specified in the feature spec. Test harness (bats-core) was designed but the
feature was abandoned.

---

## 006 — House-Number Address Suggestions (geocoder fix)  [Source: specs/006-geocoder-housenumber-fix]

> Bug-fix spec (unnumbered, `Status: Implemented`). Fixed three independent defects that each
> suppressed house-number geocoding (reported: "1007 East Grand Avenue, Des Moines, IA, 50319").
> Detailed root causes are in **§ Known Issues & Gotchas** of plan.md.

**Fixes**:
- **RC1** — Set `NOMINATIM_USE_US_TIGER_DATA=yes` after `add-data` + `nominatim refresh --website` (activates TIGER lookups). (`infra/scripts/build-geocoder.sh`)
- **RC2** — Strip the state component (USPS abbrev or configured state name) from queries before Nominatim; the viewbox already bounds results, and a single-state extract has no cross-state ambiguity. (`geocoder_client.rb` + `GEOCODER_REGION_STATE`) *(Later gated off at country scale by 011 — the state token is needed for cross-region disambiguation.)*
- **RC3** — After import, delete purely numeric `W`/`w` word tokens (`DELETE FROM word WHERE type IN ('W','w') AND word_token ~ '^[0-9]+$'`); `H`/`P` tokens untouched.
- **Confidence** — `confidence_for` = `place_rank/30` clamped `[0,1]` (falls back to `0.5`), replacing surfacing Nominatim's negative `importance` verbatim (exact reported address now `1.0`, was `-0.62`).

**Acceptance**: live `GET /api/v1/geocode/search?q=1007 East Grand Avenue, Des Moines, IA, 50319` returns the correct house result (lat 41.5912, lng -93.6030, type "house", confidence 1.0); the same raw string against unfixed Nominatim returns empty (each fix independently necessary).

---

## 007 — Zoom to Starting Address  [Source: specs/007-zoom-to-origin]

When a starting address is confirmed, recenter/zoom the map to a consistent street-level framing
and drop a single marker — smooth by default, instant under reduced-motion, no third-party leak.

**User Stories**: (P1) see my starting point on the map; (P2) comfortable, non-disorienting move (reduced-motion aware); (P3) responsible, predictable framing.

**Functional Requirements** (verbatim):
- **FR-001**: On confirmed starting address, recenter the map on that location.
- **FR-002**: Zoom to a consistent street/address-level framing (immediate block + surrounding streets), uniform regardless of density; never max/rooftop zoom.
- **FR-003**: Repositioning is a smooth animation bounded to a short duration.
- **FR-004**: Under a reduced-motion preference, reposition instantly without animation.
- **FR-005**: Recenter ONLY on a confirmed selection; never move on intermediate keystrokes/unselected suggestions.
- **FR-006**: If a newer address is confirmed before a prior move completes, end on the most recently confirmed location.
- **FR-007**: If the confirmed address has no usable coordinate, leave the view unchanged.
- **FR-008**: After repositioning, the user retains full manual pan/zoom control.
- **FR-009**: Recentering transmits the coordinate to no third party; all new-view content from the app's own map service.
- **FR-010**: Framing is consistent however the start is established (typed address or "use my location").
- **FR-011**: Display a visible marker at the confirmed address's exact location.
- **FR-012**: Show at most one starting marker; confirming a new address moves it rather than leaving the old one.
- **FR-013**: When the start is unset (field cleared), remove the marker; with no usable coordinate, show no marker.

**Key Entities**: Starting location/origin (`lat`/`lng`, optional label; lifted to `PlanRoutePage` as `origin: Coordinate | null`); Map viewport (`center`, fixed `zoom: 16`); Starting marker (single GeoJSON Point, updated via `setData`).

**Success Criteria** (verbatim): SC-001 centered within 1.5 s; SC-002 ≥95% show street + immediate surroundings (not city-wide, not single rooftop); SC-003 ≥90% confirm correct without further pan/zoom; SC-004 zero unintended recenters while typing; SC-005 reduced-motion → no animation 100%; SC-006 zero coordinate requests to third parties during recentering; SC-007 exactly one marker, never stale/duplicate.

---

## 008 — Render Camera Locations in the Current Viewport  [Source: specs/008-viewport-cameras]

Show known cameras in the visible map area as individual markers (sparse) or count clusters
(dense), updating debounced on pan/zoom, with detail popups and disputed-camera distinction —
independent of route planning.

**User Stories**: (P1) see cameras where I'm looking; (P2) cameras follow the map / clusters expand; (P3) inspect a camera, spot disputed ones.

**Functional Requirements** (verbatim):
- **FR-001**: Display known cameras whose location falls within the current visible area, as individual markers where spread out.
- **FR-002**: On pan/zoom, update displayed cameras/clusters to the new visible area.
- **FR-003**: Debounce updates so continuous pan/zoom reflects only the settled (latest) viewport.
- **FR-004**: When cameras overlap at the current zoom, aggregate into a cluster marker showing the count.
- **FR-005**: Tapping a cluster zooms in so it breaks into smaller clusters / individual markers.
- **FR-006**: Tapping an individual camera shows its details (type, confidence, verification status).
- **FR-007**: Display all routable cameras in the area — confirmed and disputed above the confidence floor — not only confirmed.
- **FR-008**: Visually distinguish disputed/low-confidence cameras from confirmed.
- **FR-009**: Camera markers/clusters visually distinct from the route line and starting marker; must not obscure the route.
- **FR-010**: When the area has no cameras, show nothing and present no error.
- **FR-011**: Bound the per-viewport request by a display cap (server's 500); when exceeded, use the capped set (clustered) and surface reaching the cap (log/telemetry), never silently truncate.
- **FR-012**: Camera display functions independently of route planning.
- **FR-013**: Fetching sends only viewport bounds to the app's own backend (never a third party); bounds not retained in logs with any client identifier.
- **FR-014**: Cameras and details are reference data only — never user-specific data.
- **FR-015**: The details popup is dismissible including via keyboard (Esc), with open/closed state conveyed accessibly (popup is the accessible surface; canvas marker a11y limits accepted).

**Key Entities**: Camera (reference point: id, location, camera_type, confidence 0–1, verification_status); Cluster (point_count, cluster_id, centroid); Visible area/viewport (`bbox` "minLng,minLat,maxLng,maxLat").

**Success Criteria** (verbatim): SC-001 markers/clusters within 1 s of view settling; SC-002 update to new area within 1 s of settling; SC-003 bounded small number of debounced refreshes during continuous pan; SC-004 overlapping cameras aggregated (no unreadable pile-up); SC-005 tapping a cluster zooms + separates; SC-006 tapping a camera shows details; SC-007 disputed/low-confidence distinguishable 100%, and distinct from route/start marker; SC-008 no perceptible map jank; SC-009 zero third-party requests with viewport bounds; SC-010 popup dismissible via keyboard (Esc), not pointer alone.

---

## 009 — Comparison Route (Fastest-Route Baseline)  [Source: specs/009-comparison-route]

Alongside the recommended avoiding route, compute and show the fastest non-avoiding route as a
distinct secondary line and surface the avoidance cost (added time headline, added distance, what
the fastest route would expose) — only when avoidance actually costs time.

**User Stories**: (P1) see the cost of avoidance on the map; (P2) no needless comparison when avoidance is free; (P3) understand what the fastest route would have exposed.

**Functional Requirements** (verbatim):
- **FR-001**: When planning, also determine the fastest ordinary (non-avoiding) route for the same O/D.
- **FR-002**: Show the avoiding route as visually primary and the fastest as a distinct secondary ("comparison") route whenever added time > 0.
- **FR-002a**: Show the comparison automatically by default; the user can hide/dismiss it; the recommended route + its time remain visible when dismissed.
- **FR-003**: Display the recommended route's estimated travel time (fastest route's time conveyed via the added-time delta; its absolute time MAY also be shown).
- **FR-004**: Display the additional travel time of the avoiding route vs. the fastest (positive difference — the headline metric).
- **FR-004a**: Also display the additional distance vs. the fastest, as a secondary detail.
- **FR-005**: Make clear which route is recommended and that the comparison is informational, not selectable to navigate.
- **FR-006**: When added time = 0 (fastest already avoids all cameras or same path), draw no separate comparison line and present no positive added-time figure.
- **FR-007**: Indicate the fastest non-avoiding route is not camera-free when it passes ≥1 camera (e.g., a count).
- **FR-008**: Keep the recommended route distinguishable from the comparison even where they overlap.
- **FR-009**: Update the comparison consistently on each new plan (no stale comparison left on the map).
- **FR-010**: Honor anonymity — O/D and routes to no third party (own routing only); no route coords or client identifiers in logs.

**Key Entities**: Recommended route (avoiding: time, geometry, remaining exposure); Comparison route (fastest non-avoiding: time, geometry, cameras-it-would-pass; informational only); Avoidance cost (added time headline, added distance, cameras fastest would pass).

**Success Criteria** (verbatim): SC-001 identify both routes + extra time within 5 s, no interaction; SC-002 100% no comparison line when fastest already clean; SC-003 100% added time = recommended − fastest (never negative); SC-004 ≥90% correctly identify recommended route (manual usability test); SC-005 0% O/D/geometry to any third party from the comparison; SC-006 comparison doesn't push request→result beyond the latency budget.

---

## 010 — Responsive, Full-Width Layout  [Source: specs/010-responsive-layout]

Presentation-only: full-width, map-dominant two-pane layout on desktop; full-width stacked
map→controls→results on mobile; graceful reflow at all widths; preserves features, styling,
accessibility, anonymity, and performance.

**User Stories**: (P1) desktop full-width map-prominent layout; (P2) adapts across smaller desktop/tablet; (P3) mobile full-width stacked flow.

**Functional Requirements** (verbatim):
- **FR-001**: Use the full usable viewport width, eliminating large fixed left/right margins.
- **FR-002**: Remain usable across four size ranges (large desktop, smaller desktop, tablet, mobile) — two-pane on desktop (ultra-wide sidebar cap), full-width stack on tablet/mobile.
- **FR-003**: On wide screens, the map is dominant with controls/results alongside (not a narrow column).
- **FR-004**: On narrow screens, full-width vertical flow map → controls → results.
- **FR-005**: No horizontal scrolling at any width from smallest phone to large desktop.
- **FR-006**: No content clipped/truncated/hidden-unreachable; all controls reachable and operable.
- **FR-007**: Reflow cleanly on resize/rotation, no broken/overlapping intermediate state.
- **FR-008**: On ultra-wide displays, stay visually balanced (no unbounded text stretch, no centered strip with empty margins).
- **FR-009**: Map area resizes with the layout, keeping controls and route/camera overlays positioned and usable.
- **FR-010**: Preserve all existing functionality and content (presentation change only).
- **FR-011**: Preserve accessibility affordances (keyboard reachability, labelled map region, live route/error region) across breakpoints.
- **NFR-001**: Preserve visual styling identity (dark theme, colors, typography).
- **NFR-002**: Anonymity unaffected — no new third-party requests/identifiers/transmission.
- **NFR-003**: No perceived-performance regression (CLS negligible, no jank, e2e perf budget passes).

**Key Entities**: None (presentation-only). Layout regions: Shell `.plan-page`, Header `.app-header`, Map pane `.map-container`, Content/sidebar pane.

**Success Criteria** (verbatim): SC-001 ≤5% combined empty margin at 1440px; SC-002 no horizontal scroll 320–2560px; SC-003 map ≥55% of content area at ≥1024px; SC-004 100% controls reachable + no clipping at 375/768/1024/1440px; SC-005 never visibly broken across the resize range; SC-006 no functional regressions; SC-007 first-paint CLS <0.1 and perf e2e passes unchanged.

---

## 011 — Country-Wide Camera Mapping  [Source: specs/011-country-camera-mapping]

Lift a deployment's scope from a single US state to an entire **country (default US)**: search,
routing, tiles, geocoder + whole-US TIGER, camera gathering, map framing, and per-data-region
coverage all span the country, via a `CountryRegistry` and a one-command provisioning path.

**User Stories**: (P1) operator sets the deployment's country; (P2) end user searches/routes anywhere in-country (cross-sub-region); (P3) coverage communicated honestly at country scale.

**Functional Requirements** (verbatim):
- **FR-001**: An operator can set the single country a deployment covers via one setup-time config choice.
- **FR-002**: When no country is specified, default to the United States.
- **FR-003**: Address search resolves across the entire configured country, all sub-regions.
- **FR-004**: Search disambiguates identically named places by sub-region (replacing any single-sub-region assumption).
- **FR-005**: Routing can produce routes whose origin/destination lie in different sub-regions, including crossing internal administrative boundaries.
- **FR-006**: Camera data is gathered for the whole configured country from its available sources.
- **FR-007**: On first load, the map frames the configured country's geographic extent.
- **FR-008**: Expose coverage info reflecting the configured country, distinguishing where camera data is present vs. absent — determined per ingested data-region (bbox) and including each region's freshness.
- **FR-009**: Config is country-generic, but the US is the sole validated/supported country at launch; specifying any non-provisioned or invalid country MUST fail setup with a clear, actionable error and MUST NOT silently substitute another country.
- **FR-010**: Camera avoidance continues via excluding the specific monitored segment(s) (snap-to-road), unchanged at country scale.
- **FR-011**: All anonymity guarantees hold unchanged at country scale.
- **FR-012**: Changing the configured country re-scopes every geographic facet (search/route/framing/coverage) with no residual single-sub-region or previous-country assumptions.
- **FR-013**: Provide a documented one-command path to provision the country's full map/routing/geocoding/camera data.

**Key Entities**: Deployment Coverage Configuration (single country, default US); Country (registry: `code`, `name`, `extract_url`, `bbox`, `tiger`, `sub_region_kind`); Camera (now country-wide); Coverage Area / Data-Region (`name`, `region` PostGIS geom, `data_freshness_at`; present/absent/not-yet-gathered).

**Success Criteria** (verbatim): SC-001 sampled addresses across ≥10 US states each resolve correctly; SC-002 cross-sub-region route returns valid avoiding route (or documented fallback) 100% when reachable; SC-003 first load frames the whole country (no hardcoded sub-region); SC-004 re-scoping needs only the one country value + one-command provisioning, no code changes; SC-005 coverage reports presence/absence per data-region with freshness, no false "camera-free" where data merely absent; SC-006 zero user O/D/route to third parties across country-wide ops; SC-007 unsupported country at setup → actionable error 100%, no silent substitution; SC-008 country-scale p95 budgets — geocode `/search` ≤600 ms, `/reverse` ≤400 ms, `/routes` ≤2.5 s, `/coverage` & `/coverage/bounds` ≤150 ms; map first paint unchanged.

---

## 012 — Preferred Language Detection  [Source: specs/012-preferred-language-detection]

Derive the UI language from the visitor's full ordered environment signals (q-weighted) matched
against offered locales (en, es) with base-language regional fallback, resolved synchronously
before first paint; an explicit choice wins and persists on-device; the effective locale is sent to
the backend; map labels follow the selected language.

**User Stories**: (P1) interface opens in best-available language automatically (no flash); (P2) explicit choice overrides + is remembered, clearable; (P3) map labels match the interface language.

**Functional Requirements** (verbatim):
- **FR-001**: Derive the initial language automatically from environment-advertised preferences, no manual step on first visit.
- **FR-001a**: Fully resolve the language before initial render — no flash of the default before the derived language applies.
- **FR-002**: Consider the visitor's full ordered preference list and relative strengths (not only the first entry).
- **FR-003**: Match advertised preferences against offered languages, selecting the offered language that best satisfies them.
- **FR-004**: When a preference is a regional variant of an offered language, fall back to the base offered language rather than the default.
- **FR-005**: When nothing matches, use the default (English) and render a complete interface.
- **FR-006**: Allow explicit override any time, effective immediately, without discarding already-entered text.
- **FR-007**: Remember an explicit choice across reloads/return visits on the same device, preferred over the derived guess.
- **FR-008**: Provide a way to clear the remembered choice and return to automatic derivation.
- **FR-008a**: When on-device storage is unavailable/blocked, degrade gracefully — explicit choice applies for the session but isn't remembered; no block/error.
- **FR-009**: Apply the selected language to all controlled visitor-facing text (labels, buttons, results, status, errors, camera popup).
- **FR-010**: Render map labels in the selected language where data provides it, falling back to a local/default name — never a blank label.
- **FR-011**: Server-produced text for a visit resolves to the same selected language (mechanism FR-016).
- **FR-012**: Ignore missing/empty/wildcard/malformed preference entries, continuing to evaluate the rest.
- **FR-013**: Derivation is deterministic for identical inputs, with a stable tie-break.
- **FR-014**: For missing individual strings, fall back to the default language (no blanks/identifier placeholders).
- **FR-015**: Require no account/login/PII to derive/apply/remember; transmit no persistent identifier or route data to any third party; remembered preference lives only on-device.
- **FR-016**: Communicate the **effective selected language** (resolved, override included) to the server on each request; the server honors it rather than re-deriving from the raw environment signal.

**Key Entities**: Supported Languages ({en, es}; FE `SUPPORTED_LOCALES`, BE `I18n.available_locales`); Advertised Preference (transient ordered list: `tag`, `region?`, `quality`); Selected Language (`code`, `source` remembered|environment|default; precedence remembered→environment→default); Remembered Choice (`localStorage["flckd.locale"]`, on-device only, no identity/timestamp).

**Success Criteria** (verbatim): SC-001 ≥99% first-frame correct language, no flash; SC-002 no-match → complete default interface, zero blanks; SC-003 100% regional variant → base offered language; SC-004 100% remembered choice on reload/return until cleared; SC-005 entire interface (incl. server text + map labels where data exists) in the selected language, no mixed-language; SC-006 deterministic across repeated trials; SC-007 no accounts/PII/persistent identifier leave the device.

---

## 013 — Printable Driving Directions  [Source: specs/013-printable-directions]

An icon-only print control atop the on-screen directions opens the browser's native print dialog
showing a dedicated, print-only view (heading, origin/destination, totals, full ordered steps,
privacy notice) — large, high-contrast, paginated; map/chrome/controls and camera notices excluded;
fully client-side, zero transmission. Localized en + es.

**User Stories**: (P1, MVP) print a clean copy of the directions; (P2) readable while driving; (P3) trip context + route-on-paper awareness.

**Functional Requirements** (verbatim):
- **FR-001**: Display an icon-only print control (accessible label for AT) at the top of the directions whenever a planned route's directions are shown.
- **FR-002**: Do not display the control when no route/directions are present.
- **FR-003**: Activating the control opens the device's standard print dialog.
- **FR-004**: Printed output includes the complete, ordered turn-by-turn steps exactly as on screen for the current route.
- **FR-005**: Printed output excludes the interactive map, page nav/header, form inputs, and on-screen-only controls (including the print control itself).
- **FR-006**: Steps in a simplified, high-legibility layout: large type (≥~14pt), clear per-step numbering, generous spacing, black-on-white.
- **FR-007**: Paginate long routes so steps continue across pages and individual steps aren't split across a page break where avoidable.
- **FR-008**: Include a heading, the origin and destination labels, and total travel time and distance.
- **FR-009**: Include a brief notice that the printed page contains the user's route (consistent with the export warning).
- **FR-010**: Exclude camera/coverage notices — only driving steps and trip context.
- **FR-011**: The control's accessible label and all printed text honor the user's active language (en + es).
- **FR-012**: Always reflect the currently displayed directions; after a re-plan, print the new route (labels captured at plan time so editing inputs can't desync).
- **FR-013**: Producing the printout is fully client-side and transmits nothing (route/directions/origin/destination) to servers or third parties — only the user's own print/PDF target.

**Key Entities**: PrintableDirectionsView (derived, in-memory only): `originLabel`/`destinationLabel` (lifted from `RoutePanel` → `PlanRoutePage`, captured at plan time), `totalDurationMin` (`Route.duration_s`), `totalDistanceKm` (`Route.distance_m`), `steps` (`Route.maneuvers`, in order), `privacyNotice` (i18n). No persisted data; camera/coverage excluded.

**Success Criteria** (verbatim): SC-001 open print dialog in a single action; SC-002 100% of on-screen steps in order; SC-003 zero excluded elements (map/chrome/controls); SC-004 step text ≥14pt, readable at arm's length across languages; SC-005 multi-page route paginates with no step clipped/split 100%; SC-006 zero network requests carrying route/location data; SC-007 dialog opens with no perceptible delay (<100 ms), synchronous client-side, no network.

---

## § Superseded / Evolved Requirements (authoritative for current state)

- **Avoidance preference removed** — 002 FR-007 and the *Avoidance Preference* entity (avoid/balanced/fastest) were **removed by 004**. There is no preference UI or `avoidance_preference` parameter. The planner always prefers a fully-clean route and auto-falls back to fewest-cameras.
- **External maps handoff removed** — 002 FR-012b / its SC-009 clause (open in Apple/Google Maps with a warning) was **removed post-009**. The only way a route leaves the app is the user-initiated, fully client-side **GPX export** (built in the browser, saved to the user's device, with a warning that the file holds the route). 013 print is similarly local-only.
- **Offered languages = {en, es}** — 002 SC-006 ("≥5 languages at launch") did not hold; the implemented offered set is **English + Spanish**, with the 012 detection mechanism being locale-agnostic (catalog can grow without code change).
- **Single-state → country (US) scope** — 002/006 assumed a single US state. **011** generalized search/routing/tiles/geocoder/camera-gathering/framing/coverage to the whole configured country (default US). 006's RC2 state-token stripping is **gated off** at country scale (the state token is needed for FR-004 disambiguation).
- **005 never shipped** — superseded; geo provisioning is the 011 country-scale one-command path.
- **Camera avoidance hardened beyond on-segment exclusion** — post-009 the planner adds a soft camera-**proximity** objective (`ProximityScorer`), iterative-exclusion and "quiet" surface-street candidates, an `is_fully_clean` flag, and a `RouteNotice` banner when a route still passes within view of cameras; camera lifecycle uses a recoverable `auto_retired` flag distinct from terminal human `removed`. (Captured in CLAUDE.md "Recent work (post-009)".)
- **Stack evolved** — 002's React 18 / PostgreSQL 16 are now **React 19 / PostgreSQL 17**; backend Ruby 3.4.x + Rails 8.1.x. See plan.md.

---

## Revision Log

- **2026-06-18** — Bootstrapped from first archival: merged `013-printable-directions`.
- **2026-06-18** — Archived the full `specs/` directory (002–012): added per-feature subsections,
  reordered chronologically, and added the Superseded/Evolved section reflecting the implemented
  state. 005 recorded as superseded; 006 as an implemented geocoder bugfix.

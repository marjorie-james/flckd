# Feature Specification: Country-Wide Camera Mapping

**Feature Branch**: `011-country-camera-mapping`

**Created**: 2026-06-15

**Status**: Draft

**Input**: User description: "user can set up mapping for entire specified country with flock cameras, defaulting to US"

## Clarifications

### Session 2026-06-15

- Q: At launch, which countries must actually work (search/route/map/cameras), not just be configurable? → A: US only — the configuration is country-generic, but the United States is the sole validated and supported country at launch; other countries are future config + data work.
- Q: Does this feature include provisioning the country-scale map/routing/geocoding/camera data, or only the scoping logic? → A: Both — generalize the existing single-region data-preparation pipelines to whole-country scope and provide a documented one-command full-country provisioning path for operators.
- Q: How is camera-data "present vs absent" determined for honest coverage signalling? → A: Per ingested data-region — presence is reported per ingested data area / bounding box, including data freshness.

## User Scenarios & Testing *(mandatory)*

The operator who stands up a flckd deployment chooses **one country** for that
deployment to cover. Today a deployment is scoped to a single sub-region (one US
state): its address search, map framing, routing graph, and camera coverage all
assume that single region. This feature lifts that scope to an **entire country**,
with the **United States as the default** when no country is specified. The same
self-hosted, account-less, anonymity-preserving experience must hold at country
scale.

The two audiences are distinct:

- The **operator** configures *which* country a deployment covers (a one-time
  setup choice that defaults to the US).
- The **end user** searches, views the map, and plans camera-avoiding routes —
  now anywhere within the whole configured country rather than one state.

### User Story 1 - Operator sets the deployment's country (Priority: P1)

An operator standing up (or reconfiguring) a deployment specifies the single
country it should cover. If they specify nothing, the deployment covers the
United States. From that one choice, every geographic facet of the deployment —
the searchable area, the area routes can be planned across, the area the map
frames, and the area camera data is gathered for — spans that entire country.

**Why this priority**: This is the feature. Without a single country-scoping
control that defaults to the US, none of the downstream country-wide behavior is
reachable, and the deployment stays stuck at single-region scope.

**Independent Test**: Stand up a deployment with no country specified and confirm
it operates over the entire United States; stand up another with an explicitly
specified country and confirm it operates over that country instead. Both reach
full country coverage through the documented setup process without code changes.

**Acceptance Scenarios**:

1. **Given** a fresh deployment with no country specified, **When** it is brought
   online, **Then** its searchable, routable, mapped, and camera-covered area is
   the entire United States.
2. **Given** an operator who explicitly specifies the United States (the sole
   country provisioned at launch), **When** the deployment is brought online,
   **Then** every geographic facet spans the entire US — exercising the
   country-generic configuration on its launch target.
3. **Given** an operator who specifies any country whose data has not been
   provisioned (any non-US country at launch) or an invalid country, **When** they
   attempt to bring the deployment online, **Then** setup fails with a clear,
   actionable message and the deployment does not silently fall back to a
   different country.

---

### User Story 2 - End user searches and routes anywhere in the country (Priority: P2)

An end user enters an origin and destination anywhere within the configured
country — including addresses in different sub-regions — i.e. states, the US
sub-region kind — and gets correct geocoding results and a camera-avoiding route that
may cross internal administrative boundaries.

**Why this priority**: A country-scoped deployment is only useful if search and
routing actually work across the whole country. The current single-region
assumptions (e.g., stripping a single known state from typed addresses, framing
on one region) actively break once more than one sub-region is in scope, so this
must be corrected for the feature to deliver value.

**Independent Test**: Search representative addresses in several different
sub-regions of the configured country and confirm each resolves to the correct
place; plan a route whose origin and destination are in different sub-regions and
confirm a route is returned.

**Acceptance Scenarios**:

1. **Given** a US-scoped deployment, **When** a user searches an address in any US
   state, **Then** the correct location is returned.
2. **Given** two cities that share a name in different sub-regions, **When** a user
   searches with the sub-region included, **Then** the result is disambiguated to
   the correct sub-region.
3. **Given** an origin and destination in different sub-regions of the country,
   **When** the user requests a route, **Then** a camera-avoiding route spanning
   the boundary is returned (or the documented fallback when no fully clean route
   exists).
4. **Given** any search or route within the configured country, **When** it is
   processed, **Then** no origin, destination, or route coordinate is sent to any
   third party.

---

### User Story 3 - Coverage is communicated honestly at country scale (Priority: P3)

An end user can tell what the deployment covers: the map opens framed on the whole
configured country, and the app indicates where within that country camera data
actually exists versus where it does not yet — so users are not misled into
thinking the entire country has camera coverage when data is sparse.

**Why this priority**: Country-wide map/search/routing can ship and deliver value
before camera data is dense everywhere. Honest coverage signalling prevents users
from trusting "no cameras here" in an area that simply has no data yet. It is
valuable but not blocking for the core capability.

**Independent Test**: On first load, confirm the map frames the configured
country. Query coverage at a point known to have camera data and at a point known
to have none, and confirm the app reports presence and absence correctly.

**Acceptance Scenarios**:

1. **Given** a configured country, **When** the app first loads, **Then** the map
   frames that country's geographic extent.
2. **Given** a location inside the country with camera data, **When** coverage is
   checked there, **Then** the app reports that camera data is present.
3. **Given** a location inside the country without camera data, **When** coverage
   is checked there, **Then** the app reports that camera data is absent rather
   than implying the area is camera-free.

---

### Edge Cases

- **Same-named places across sub-regions**: With multiple sub-regions in scope,
  identically named cities/streets must be disambiguated by sub-region instead of
  assuming a single region.
- **Country with no camera-data sources**: Map, search, and routing still work;
  coverage honestly reports that no camera data exists.
- **Sparse camera data within a large country**: Coverage signalling must
  distinguish "no cameras present" from "no data gathered here yet."
- **Unsupported / misspelled country at setup**: Fail fast with an actionable
  error; never silently substitute a different country. (The US default applies
  only when the country is *unspecified*, not when it is specified-but-invalid.)
- **Non-US country lacking the same address-precision data the US has**: Search
  still functions using whatever address data is available for that country, at
  whatever precision that data supports.
- **Country-scale data volume**: A country (especially the US) is far larger than
  a single region; setup and data refresh must complete via the documented process
  without manual per-sub-region steps.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: An operator MUST be able to set the single country a deployment
  covers through one configuration choice made at setup time.
- **FR-002**: When no country is specified, the system MUST default to the United
  States.
- **FR-003**: Address search MUST resolve locations across the entire configured
  country, including all of its sub-regions, not a single sub-region.
- **FR-004**: Address search MUST disambiguate identically named places by
  sub-region, replacing any single-sub-region assumption in how typed addresses
  are interpreted.
- **FR-005**: Route planning MUST be able to produce routes whose origin and
  destination lie in different sub-regions of the configured country, including
  routes that cross internal administrative boundaries.
- **FR-006**: Camera data MUST be gathered for the configured country from its
  available sources, across the whole country rather than a single sub-region.
- **FR-007**: On first load, the map MUST frame the configured country's
  geographic extent.
- **FR-008**: The system MUST expose coverage information that reflects the
  configured country and distinguishes locations where camera data is present from
  those where it is absent, determined per **ingested data-region** (data area /
  bounding box) and including each region's data freshness.
- **FR-009**: The configuration MUST be country-generic, but the United States is
  the sole validated and supported country at launch; specifying any country whose
  data has not been provisioned (any non-US country at launch) or an invalid
  country MUST fail setup with a clear, actionable error and MUST NOT silently
  substitute another country.
- **FR-010**: Camera avoidance MUST continue to work by excluding the specific
  monitored road segment(s) (snap-to-road), unchanged at country scale.
- **FR-011**: All existing anonymity guarantees MUST hold unchanged at country
  scale — no third party ever receives a user's origin, destination, or route; no
  accounts, PII, or persistent identifiers; logs retain no route coordinates or
  client IPs.
- **FR-012**: Changing the configured country MUST consistently re-scope every
  geographic facet (search area, routable area, map framing, camera coverage) with
  no residual single-sub-region or previous-country assumptions.
- **FR-013**: The system MUST provide a documented one-command path for an operator
  to provision the configured country's full map, routing, geocoding, and camera
  data, generalizing the existing single-region data-preparation pipelines to
  whole-country scope.

### Key Entities *(include if feature involves data)*

- **Deployment Coverage Configuration**: The single chosen country a deployment
  covers. Defaults to the United States. Drives the searchable area, routable
  area, map framing, and the scope of camera-data gathering.
- **Country**: A supported nation that a deployment can be scoped to, with a known
  geographic extent and internal sub-regions (e.g., states/provinces). The US is
  the default and reference-supported country.
- **Camera** *(existing)*: A known monitored location within the configured
  country; its coverage now spans the whole country rather than one sub-region.
- **Coverage Area / Data-Region**: An ingested data area (bounding box) within the
  configured country, recording whether camera data is present and how fresh that
  data is — used to communicate honest, per-region coverage to users (present vs
  absent vs not-yet-gathered).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With default configuration, address searches for locations sampled
  across at least 10 different US states each return the correct location.
- **SC-002**: A route requested between an origin and destination in two different
  sub-regions of the configured country returns a valid camera-avoiding route (or
  the documented fallback) 100% of the time when one is reachable.
- **SC-003**: On first load, the map frames the entire configured country's extent
  with no hardcoded single-sub-region framing.
- **SC-004**: Re-scoping a deployment to a different country requires changing only
  the single country configuration value and running the documented one-command
  provisioning step — no code changes — to reach full country coverage.
- **SC-005**: At points sampled inside the configured country, coverage information
  correctly reports camera-data presence/absence per ingested data-region — with no
  false "camera-free" signal in areas that merely lack gathered data — and reflects
  each region's data freshness.
- **SC-006**: Zero user origin/destination/route data is transmitted to any third
  party across all country-wide search and routing operations.
- **SC-007**: Specifying an unsupported country at setup produces an actionable
  error 100% of the time, with no silent substitution.
- **SC-008**: At country scale, user-perceivable paths meet these budgets (Principle IV):
  geocode `/search` p95 ≤ 600 ms and `/reverse` p95 ≤ 400 ms over the whole-country
  index; route `/routes` p95 ≤ 2.5 s for an in-country trip; `/coverage` and
  `/coverage/bounds` p95 ≤ 150 ms. Map first paint is unchanged (tiles pre-rendered).

## Assumptions

- **"User" = operator at setup time**: Because flckd is account-less and
  self-hosted, "set up mapping for a country" is a deployment/operator
  configuration choice, not an end-user runtime country switcher. End users
  consume whatever country the deployment was configured for.
- **One country per deployment**: "Entire specified country" is singular; each
  deployment covers exactly one country. Multi-country or runtime country
  switching by end users is out of scope for this feature.
- **US is the only supported country at launch**: The configuration is
  country-generic so future countries are additive (config + provisioned data), but
  the United States is the sole validated and supported target at launch and the
  source of the highest-precision address data. Validating any additional country
  is out of scope for this feature.
- **Self-hosted stack is reused**: The existing self-hosted geocoding, routing,
  vector tiles, and camera-aggregation pipelines are extended to country scope;
  no third-party geo services are introduced (anonymity non-negotiable).
- **Camera coverage follows available sources**: Country-wide scope means camera
  data is gathered wherever sources exist within the country; it does not promise
  dense camera coverage in every part of the country at launch.
- **Country-scale data provisioning is in scope**: This feature generalizes the
  existing single-region data-preparation pipelines to whole-country scope and adds
  a documented one-command full-country provisioning path for operators (rather than
  assuming country-scale data is provisioned out-of-band).

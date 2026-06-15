# Phase 1 Data Model: Country-Wide Camera Mapping

Two roles that are conflated today are separated: the **configured country** (static
reference, for framing + in-country checks) and the **ingested data-region** (where
camera data actually exists, with freshness). Plus the existing camera entities,
unchanged in shape.

## Country (registry entry — static reference data, not a DB table)

The single country a deployment covers. Selected by `GEOCODER_COUNTRY` (default `us`)
and surfaced via `Geocoding::CountryRegistry`.

| Field | Type | Notes |
|-------|------|-------|
| `code` | string (ISO 3166-1 alpha-2) | Key, e.g. `us`. Default when unspecified. |
| `name` | string | Display name, e.g. "United States". |
| `extract_url` | string (URL) | Whole-country OSM PBF (Geofabrik `us-latest.osm.pbf` for US). |
| `bbox` | [west, south, east, north] | Country extent → geocoder viewbox + map framing. |
| `tiger` | boolean | Whether the US Census TIGER house-number import applies (true only for US). |
| `sub_region_kind` | string | Label for internal admin divisions ("state"); used in disambiguation/UX copy. |

**Validation / rules**:
- An unspecified country resolves to `us` (FR-002).
- A code not present (or not fully populated/provisioned) in the registry **fails
  setup** with an actionable error; never silently substituted (FR-009).
- At launch only `us` is populated and validated; the structure is generic for future
  additions (config + provisioned data).

**Lifecycle**: Static. Changing the configured country is a config change plus the
one-command provisioning run (FR-012, FR-013), not a runtime mutation.

## CoverageArea (existing table — semantics clarified)

Reinterpreted from "the served region" to **an ingested camera-data region** within
the configured country, carrying its own freshness. Drives honest present / absent /
not-yet-gathered signalling. (No column changes required; `data_freshness_at` already
exists.)

| Field | Type | Notes |
|-------|------|-------|
| `name` | string (required) | Data-region label (e.g. a state or tile footprint). |
| `region` | PostGIS geometry (required) | Footprint where camera data is present. |
| `data_freshness_at` | timestamp | When *this region's* data was last refreshed (set per-region by `DataRefreshJob`). |

**Behavior changes**:
- `DataRefreshJob` sets `data_freshness_at` **per data-region** as each is refreshed,
  replacing the global `CoverageArea.update_all(data_freshness_at: ...)`.
- `covers?(lon, lat)` / `containing` now answer "is there camera data here?" (presence),
  not "is this in our country?".
- `bounds` is **no longer** the framing source for the map (see below).

**Relationships**: Conceptually scoped to the configured Country (the union of data-
regions lies within the country extent). Cameras/monitored segments are unchanged and
relate to data-regions only spatially.

## Map-framing extent (derived, not stored)

`/coverage/bounds` returns the **configured country's extent** (from the country
registry bbox), so the client frames the whole country (FR-007) regardless of how
sparse the camera footprint is. This replaces deriving framing bounds from the union
of `CoverageArea` rows.

## Camera / MonitoredSegment (existing — unchanged)

Shapes are unchanged; only their geographic spread grows to country scale. Camera
avoidance remains segment-exclusion / snap-to-road (FR-010). Camera ingestion already
tiles the whole CONUS grid (`CameraData::Sources::UsTiles`), resumable via
`DataRefreshJob`.

## State transitions

| Entity | From → To | Trigger |
|--------|-----------|---------|
| Deployment country | unset → `us` (default) | No `GEOCODER_COUNTRY` set |
| Deployment country | country A → country B | Config change + one-command provisioning (FR-012/013) |
| Data-region freshness | stale → fresh | Per-region refresh completes in `DataRefreshJob` |
| Setup | configuring → failed | Unsupported/un-provisioned country code (FR-009) |

# Phase 1 Data Model: Camera-Avoiding Route Planner

Two categories of data:

1. **Persisted** (PostgreSQL + PostGIS) — reference data about cameras and coverage. Contains **no user
   data**.
2. **Ephemeral** (request/response value objects) — route requests and results. **Never persisted in a
   form linkable to a user** (FR-011); modeled here for the API contract only.

---

## Persisted entities

### DataSource
Provenance for camera records (supports the hybrid pipeline, FR-021).

| Field | Type | Notes |
|-------|------|-------|
| id | bigint PK | |
| name | string | e.g., "DeFlock", "OpenStreetMap", "Internal" |
| kind | enum(`community`, `internal`) | |
| url | string, nullable | source/reference URL |
| license | string, nullable | data license |
| last_imported_at | timestamp, nullable | |

- 1 DataSource → many Cameras.

### Camera
A known ALPR/Flock camera (FR-003, FR-021, Key Entity "Camera Location").

| Field | Type | Notes |
|-------|------|-------|
| id | bigint PK | |
| data_source_id | bigint FK → DataSource | provenance |
| external_ref | string, nullable | id within the source dataset (dedupe key) |
| location | geometry(Point, 4326) | PostGIS; spatial index (GiST) |
| facing_direction | integer, nullable | degrees 0–359, if known (R8/precision) |
| camera_type | string, nullable | e.g., "Flock", generic ALPR |
| confidence | float, default 0.5 | 0–1 |
| verification_status | enum(`unverified`,`verified`,`disputed`,`removed`) default `unverified` | |
| first_seen_at | timestamp | |
| last_verified_at | timestamp, nullable | |
| timestamps | | created_at/updated_at |

**Validation**: `location` required and within a CoverageArea; `confidence` ∈ [0,1];
`facing_direction` ∈ [0,359] when present; `(data_source_id, external_ref)` unique when `external_ref`
present.

**State transitions** (`verification_status`):
`unverified → verified` | `unverified → disputed` | `verified → disputed` | any `→ removed` (soft
delete; excluded from routing). `last_verified_at` set on entry to `verified`.

- 1 Camera → many MonitoredSegments.

### MonitoredSegment
The road segment(s) a camera reads — the unit of avoidance (spec clarification Q2, FR-003).

| Field | Type | Notes |
|-------|------|-------|
| id | bigint PK | |
| camera_id | bigint FK → Camera | |
| osm_way_id | bigint | matches the routing graph's OSM way id |
| geometry | geometry(LineString, 4326) | snapped segment; GiST index |
| direction | enum(`both`,`forward`,`backward`) default `both` | from facing_direction when known |
| snap_distance_m | float | camera→segment distance at snap time (quality signal) |
| timestamps | | |

**Validation**: `camera_id`, `osm_way_id`, `geometry` required; `snap_distance_m` ≥ 0. A removed/
disputed-below-threshold camera's segments are not emitted to the routing exclusion set.

### CoverageArea
Where camera data exists / avoidance is meaningful (FR-018, edge case "outside coverage").

| Field | Type | Notes |
|-------|------|-------|
| id | bigint PK | |
| name | string | e.g., "United States" or a metro |
| region | geometry(MultiPolygon, 4326) | GiST index |
| data_freshness_at | timestamp, nullable | last successful refresh for this area |

**Validation**: `region` required. Used to decide whether to advertise avoidance for a given
origin/destination and to surface freshness/coverage warnings.

---

## Ephemeral value objects (API only — not persisted with user linkage)

### RouteRequest
| Field | Type | Notes |
|-------|------|-------|
| origin | {lat, lng} | required (FR-001) |
| destination | {lat, lng} | required |
| avoidance_preference | enum(`avoid`,`balanced`,`fastest`) default `avoid` | FR-007 |
| locale | BCP-47 string | for localized maneuvers (FR-015) |

**Validation**: origin & destination required and routable; preference in enum. Coordinates are
processed in-memory and excluded from logs (R6).

### Route (response)
| Field | Type | Notes |
|-------|------|-------|
| geometry | encoded polyline | for map display (FR-005) |
| distance_m | integer | |
| duration_s | integer | |
| maneuvers | array of {type, localized_text, distance_m, location} | localized turn-by-turn (FR-005/015) |
| cameras_avoided_count | integer | FR-008 |
| remaining_cameras | array of {location, osm_way_id} | unavoidable cameras on route (FR-004/008) |
| is_fully_clean | boolean | false ⇒ minimum-exposure route (FR-004, R2) |
| fastest_comparison | {distance_m, duration_s, added_distance_m, added_duration_s} | trade-off (FR-006) |
| coverage_warning | string code, nullable | e.g., `outside_coverage`, `stale_data` (FR-018) |

### GeocodeResult (autocomplete/disambiguation)
| Field | Type | Notes |
|-------|------|-------|
| label | string | display name |
| coordinates | {lat, lng} | |
| type | string | place/address/poi |
| confidence | float | for ranking matches (FR-016) |

---

## Relationships (summary)

```
DataSource 1───* Camera 1───* MonitoredSegment
CoverageArea (spatial containment) ⊇ Camera.location
RouteRequest ──(in-memory)──▶ RoutePlanner ──▶ Route   (no persistence of user coordinates)
```

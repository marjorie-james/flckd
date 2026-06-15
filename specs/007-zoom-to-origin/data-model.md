# Phase 1 Data Model: Zoom to Starting Address

This feature has **no persistent data** and **no backend entities** — everything is ephemeral
client-side UI state (anonymity: nothing is stored or transmitted). The "entities" below are the
in-memory shapes the feature reads and writes.

## Entity: Starting location (origin)

The user's confirmed start point.

| Field | Type | Notes |
|-------|------|-------|
| `lat` | number | Latitude; finite, −90…90 |
| `lng` | number | Longitude; finite, −180…180 |
| (label) | string | Optional human-readable address; not required by this feature |

- **Source of truth**: lifted to `PlanRoutePage` state as `origin: Coordinate | null`.
- **Reuses** the existing `Coordinate` type (`frontend/src/types/api.ts`).
- **Lifecycle / state transitions**:
  - `null → set`: user picks a suggestion or "use my location" resolves → `onOriginChange(coord)`.
  - `set → set'`: user picks a different address → value replaced (latest wins).
  - `set → null`: user edits/clears the starting-address field → `onOriginChange(null)`.
- **Validation**: a coordinate is "usable" only if `lat`/`lng` are finite numbers in range. An
  unusable/absent coordinate produces no recenter and no marker (FR-007, FR-013).

## Entity: Map viewport

The visible area the feature drives. Owned by the MapLibre `map` instance (not React state).

| Field | Type | Notes |
|-------|------|-------|
| `center` | [lng, lat] | Set to the starting location on confirm |
| `zoom` | number | Set to the fixed address-level constant (**16**, see research D1) |

- **Transitions**: on a usable origin, `center → origin` and `zoom → 16`, applied via `flyTo`
  (animated) or `jumpTo` (reduced motion). After the move, the user may freely change center/zoom
  (FR-008); a later origin change re-applies.

## Entity: Starting marker

A single visual indicator at the starting location.

| Field | Type | Notes |
|-------|------|-------|
| feature | GeoJSON Point | `coordinates: [lng, lat]` of the current origin |
| presence | derived | Exactly one when origin is set & usable; none otherwise |

- **Representation**: one GeoJSON source updated via `setData`; a single circle/symbol layer renders
  it (research D3).
- **Invariants** (SC-007, FR-011/012/013):
  - At most one starting marker exists at any time.
  - On origin change → marker moves to the new point (no stale/duplicate).
  - On origin `null` / unusable coordinate → source set to an empty `FeatureCollection` (marker gone).
- **Scope**: starting location only; destination markers and route-line rendering are out of scope.

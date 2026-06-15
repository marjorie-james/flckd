# Phase 1 UI Contract: Zoom to Starting Address

This is a frontend-only feature — there is **no new or changed backend API contract**. The "contract"
is the component interface (props/callbacks) between the parent page and its children. Existing prop
shapes are preserved; only additive changes are listed.

## `RoutePanel` — new outbound callback

```ts
interface RoutePanelProps {
  onPlan: (origin: Coordinate, destination: Coordinate) => void;  // existing
  planning: boolean;                                              // existing
  onOriginChange?: (origin: Coordinate | null) => void;           // NEW (additive, optional)
}
```

**`onOriginChange` contract**:
- Called with a `Coordinate` when the starting point becomes set/confirmed — via selecting a geocode
  suggestion (`pickOrigin`) **or** "use my location" resolving (FR-001, FR-010).
- Called with `null` when the starting point is unset — the user edits/clears the field (the same
  moment the component already does `setOrigin(null)`) (FR-013).
- MUST NOT be called on intermediate keystrokes or unselected suggestions (FR-005).
- Backward compatible: optional; omitting it preserves today's behavior.

## `MapView` — new inbound prop

```ts
interface MapViewProps {
  route: RoutePlan | null;          // existing
  origin?: Coordinate | null;       // NEW (additive, optional)
}
```

**`origin` prop contract**:
- When it changes to a usable coordinate and the map is ready: recenter (`flyTo` zoom 16, or `jumpTo`
  under reduced motion) and place/move the single starting marker there (FR-001/002/003/004/011/012).
- When it changes to `null` (or an unusable coordinate): remove the starting marker; do **not** move
  the map (FR-007/013).
- Rapid changes resolve to the latest value (FR-006).
- Recentering issues no third-party requests; tiles come only from the self-hosted style (FR-009).

## `PlanRoutePage` — wiring (no new external contract)

- Holds `origin: Coordinate | null` state.
- Passes `origin` down to `<MapView origin={origin} />`.
- Passes `onOriginChange={setOrigin}` (or a thin wrapper) to `<RoutePanel />`.
- Continues to derive `endpoints`/`plan` exactly as today on submit.

## Utility contract (new)

```ts
// frontend/src/utils/reducedMotion.ts
export function prefersReducedMotion(): boolean;
```

- Returns `true` when `window.matchMedia("(prefers-reduced-motion: reduce)").matches`, else `false`.
- Safe when `matchMedia` is unavailable (returns `false`).

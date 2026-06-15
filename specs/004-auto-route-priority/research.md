# Research: Automatic Camera-Priority Routing

## Routing Engine Constraint: Hard Exclusion Only

**Decision**: Accept that Valhalla supports only hard polygon exclusion (`exclude_polygons`), not soft per-segment penalty routing.

**Rationale**: The `RoutingEngineClient` sends camera segment buffers as `exclude_polygons` to Valhalla. When exclusions make routing geometrically impossible, Valhalla raises a `ServiceError`. There is no native "fewest cameras" soft-penalty mode in the current integration. The existing "avoid" fallback (retry without exclusions → return fastest route) is the best approximation available without a significant engine-layer change.

**Implication for feature**: "Zero-camera first; fewest-camera fallback" is implemented as:
1. Attempt strict exclusion of all camera polygons → if Valhalla succeeds, `is_fully_clean = true`
2. If Valhalla raises `ServiceError` (route geometrically impossible without cameras) → fall back to fastest route, `is_fully_clean = false`

The fallback is the fastest route, which is the engine's best answer when strict avoidance is impossible. In the sparse-camera environment where this app operates, nearly all routes will succeed on the first pass; the fallback is a rare edge case. A true minimum-camera algorithm would require either iterative exclusion refinement (O(N) engine calls) or a penalty-graph approach — both deferred as future work.

**Alternatives considered**:
- Iterative exclusion (exclude N cameras, try N-1, ...): O(N) Valhalla calls, unacceptable latency.
- Penalty multiplier on camera segments: Valhalla does support costing options but the current client architecture doesn't expose per-segment cost overrides. Deferred.

---

## "Balanced" and "Fastest" Mode Removal

**Decision**: Remove "balanced" and "fastest" preference modes entirely.

**Rationale**: Both modes exist only to give users control over the avoidance tradeoff. With the automatic priority strategy, this control is no longer exposed. "Balanced" mode (confidence ≥ 0.8 subset) and "fastest" mode (no avoidance) become dead code after this feature. Removing them reduces `RoutePlanner` complexity and eliminates the `BALANCED_MIN_CONFIDENCE` constant, `PREFERENCES` constant, and `balanced_route` private method.

**Alternatives considered**:
- Keep modes as internal implementation details (hidden from UI but accessible via API): rejected. With no UI and no documented use case, maintaining untested code paths violates Constitution Principle I.

---

## API Contract: Deprecation vs. Removal of `avoidance_preference`

**Decision**: Remove `avoidance_preference` from the `RouteRequest` schema and permitted params.

**Rationale**: The app has no external API consumers. There is no backward-compatibility obligation. Removing the field immediately is cleaner than soft-deprecating it.

**Alternatives considered**:
- Accept but ignore the field: Would silently swallow client bugs; rejected under Constitution Principle III (errors must be actionable).
- Soft-deprecate with a warning header: No external consumers, unnecessary overhead.

---

## Frontend State Ownership

**Decision**: Remove `preference` state from `PlanRoutePage` entirely. Remove `PreferenceRadios` and `AvoidanceControl` components. Simplify `RoutePanel` to remove the preference fieldset.

**Rationale**: With a single automatic strategy, there is nothing for the user to choose and no state to manage. Removing the components eliminates the shared-state coordination between pre-plan (`RoutePanel`) and post-plan (`AvoidanceControl`) controls, simplifying the page to a pure input→route→result flow.

**Alternatives considered**:
- Hide preference controls via CSS: Leaves dead code in the component tree; rejected under Constitution Principle I.

---

## i18n Cleanup

**Decision**: Remove `preference.avoid`, `preference.balanced`, `preference.fastest`, and the `form.preference` label key from all locale files.

**Rationale**: Unused translation keys are dead code. The `result.minimumExposure` key is kept — it describes the fallback state to the user, which is still relevant.

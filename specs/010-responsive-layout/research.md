# Phase 0 Research: Responsive, Full-Width Layout

All items below were open questions in the Technical Context. Each is resolved with a decision, rationale, and the alternatives considered. No `NEEDS CLARIFICATION` markers remain.

## 1. Breakpoint thresholds

**Decision**: Three thresholds.
- **Mobile / stacked**: `< 900px` — single full-width vertical column (map → controls → results), the current flow but edge-to-edge.
- **Desktop / two-pane**: `≥ 900px` — map pane + sidebar pane side by side.
- **Ultra-wide guard**: `≥ 1600px` — sidebar holds a fixed max width; the map absorbs the extra width.

**Rationale**: 900px is the point at which a ~360–420px control sidebar plus a usable map (>480px) both fit comfortably; below it the sidebar would crush the map or the controls. A single desktop switch (rather than separate tablet/desktop layouts) keeps the CSS simple and matches the spec's "various sizes" intent without bespoke per-device code. The spec's four named ranges (large desktop / smaller desktop / tablet / mobile) are all covered: tablet landscape (≥900) gets the two-pane layout, tablet portrait and phones (<900) get the stack.

**Alternatives considered**: A separate tablet breakpoint (e.g. 640–1024 stacked-but-wide) — rejected as added complexity with no clear UX win; tablet landscape benefits from the two-pane map-app layout. Container queries keyed on the page element — deferred; media queries on viewport width are sufficient here and have broader, simpler tooling support.

## 2. Desktop two-pane mechanism — CSS Grid vs Flexbox

**Decision**: **CSS Grid** for the top-level two-pane split (`grid-template-columns: 1fr min(420px, 38%)` on desktop, single column on mobile); **Flexbox** inside each pane (already how the components lay out internally).

**Rationale**: Grid expresses "map takes remaining space, sidebar takes a bounded share" declaratively in one rule and flips to a single column with a single media query, avoiding the flex-basis/min-width juggling that a flex row needs to stop the map collapsing. It keeps the map as the `1fr` dominant element (satisfies FR-003 / SC-003). The user said "flexbox or something" — Grid for the shell, Flex within is the idiomatic modern combination and honors the intent (responsive outcome, not a mandated mechanism).

**Alternatives considered**: Pure flexbox row — workable but needs `min-width: 0` guards and explicit basis to keep the map from collapsing; more fragile. Absolute positioning / JS-measured layout — rejected (violates the "no JS-driven layout" performance constraint and adds resize listeners).

## 3. Map sizing strategy per breakpoint

**Decision**:
- **Desktop (two-pane)**: map pane fills the full height of the viewport row (`height: 100svh` on the shell; map pane `height: 100%`). The sidebar pane scrolls internally (`overflow-y: auto`).
- **Mobile (stacked)**: map keeps a viewport-relative height (retain ~`46svh`, `min-height` floor) so controls remain visible below it; the page scrolls as a whole.

**Rationale**: On desktop a map-app expects a full-height map with a scrolling control rail beside it — long turn-by-turn lists must not push the map around (addresses the "long content" edge case). On mobile the established `svh`-based height already works and avoids the iOS dynamic-toolbar `vh` jump. Using `svh` (small viewport height) over `vh` prevents the mobile-browser chrome from causing overflow.

**Alternatives considered**: Fixed pixel map heights — rejected (not responsive). Letting the desktop sidebar grow the page height (no internal scroll) — rejected because the map would scroll out of view, defeating its prominence.

## 4. Ultra-wide handling

**Decision**: At `≥ 1600px`, cap the sidebar column at a fixed width (≈420px) and let the map consume all remaining width. Do **not** cap the overall page width.

**Rationale**: Satisfies FR-008 / the ultra-wide edge case: the control column never stretches into awkwardly long lines, and the page never reverts to a narrow centered strip with empty margins (the original problem). The map simply gets larger, which is the desirable outcome for a map tool.

**Alternatives considered**: Capping total content width and centering — rejected; that reintroduces the exact empty-margin problem the user complained about. Letting the sidebar grow proportionally on ultra-wide — rejected; long text columns and oversized form controls read poorly.

## 5. Tablet portrait vs landscape

**Decision**: Behavior follows width alone (the thresholds in §1), not orientation. Tablet landscape (≥900px) → two-pane; tablet portrait (<900px) → stacked.

**Rationale**: Width is the property that determines whether two panes fit; orientation is a proxy that breaks on large phones and small tablets. Width-based rules are simpler and more predictable, and they reflow correctly on rotation (addresses the orientation-change edge case) with no extra code.

**Alternatives considered**: Orientation media queries — rejected as redundant and less predictable than width thresholds.

## 6. Responsive test strategy

**Decision**: Add `frontend/tests/e2e/responsive-layout.spec.ts` (Playwright), parameterized over a viewport list `[320, 375, 768, 900, 1024, 1440, 2560] × height`. Per viewport assert: (a) no horizontal scroll (`document.scrollWidth <= clientWidth`); (b) key controls visible and clickable (origin/destination inputs, plan button; after planning, results reachable); (c) at ≥900px the two-pane arrangement is present and the map's measured width is the dominant share (≥55% of content area, SC-003); (d) at <900px the stacked order holds and content is full-width (no large side margin, SC-001). Add an axe pass at one mobile and one desktop width. Reuse `tests/e2e/helpers.ts` (`mockApi`, `planRoute`). Keep the single chromium Playwright project; set viewport per test via `page.setViewportSize`.

**Rationale**: Layout/measurement assertions require a real layout engine; jsdom (Vitest) cannot measure element geometry or detect overflow. Playwright already runs in CI with axe, so this fits the existing gate with no new tooling. Parameterization over a viewport list gives deterministic, named cases per breakpoint that fail on today's 520px layout and pass after the change (satisfies Constitution II).

**Alternatives considered**: jsdom component tests asserting class names only — rejected; they wouldn't actually verify "no horizontal scroll" or map prominence, so they wouldn't fail on the current layout. Visual screenshot diffing — useful but flaky across environments; left to the existing `screenshot-redesign.spec.ts` style if desired, not the primary gate.

## Resolved constraints summary

| Question | Resolution |
|----------|-----------|
| Breakpoints | `<900` stacked, `≥900` two-pane, `≥1600` sidebar width-capped |
| Shell mechanism | CSS Grid shell + Flexbox within panes |
| Map height | desktop full-height pane + scrolling sidebar; mobile `~46svh` |
| Ultra-wide | cap sidebar width, map grows; never cap/center the page |
| Tablet | width-driven (no orientation queries) |
| Tests | Playwright viewport-parameterized + axe; reuse e2e helpers |

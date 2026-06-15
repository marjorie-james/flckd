# UI Contract: Responsive, Full-Width Layout

This app's external "contract" is its rendered UI. The table below is the testable contract per breakpoint — each row maps to one or more Playwright assertions in `frontend/tests/e2e/responsive-layout.spec.ts`. Widths are viewport widths in CSS px.

## Per-breakpoint behavior

| Viewport | Arrangement | Map | Side margins | Horizontal scroll |
|----------|-------------|-----|--------------|-------------------|
| 320px | Stacked, full-width | ~46svh, full width | none (edge-to-edge) | none |
| 375px | Stacked, full-width | ~46svh, full width | none | none |
| 768px | Stacked, full-width | ~46svh, full width | none | none |
| 900px | **Two-pane** (map ∣ sidebar) | full pane height, ≥55% of width | n/a | none |
| 1024px | Two-pane | full height, ≥55% of width | n/a | none |
| 1440px | Two-pane | full height, ≥55% of width | combined L+R empty ≤5% | none |
| 2560px | Two-pane, sidebar capped (≤~420px) | full height, absorbs extra width | content fills width; no centered strip | none |

## Hard invariants (asserted at every viewport above)

- **INV-1 — No horizontal scroll**: `document.documentElement.scrollWidth ≤ clientWidth` (FR-005, SC-002).
- **INV-2 — Controls reachable**: origin input, destination input, and the plan button are visible and clickable; after planning, the route notice / camera summary / results are reachable (FR-006, SC-004).
- **INV-3 — No clipping/overlap**: no asserted element has zero size or is covered such that a click misses it (FR-006, SC-005).
- **INV-4 — Order preserved**: DOM/reading order is header → origin → destination → plan → results (FR-004, FR-011).
- **INV-5 — Accessibility preserved**: the map region exposes its `aria-label`; the results section keeps `aria-live="polite"`; axe reports no serious/critical violations at one mobile and one desktop width (FR-011, Constitution III).
- **INV-6 — Full width / no big margins**: at <900px content is edge-to-edge; at ≥1440px combined empty side margin ≤5% of viewport width (FR-001, SC-001).
- **INV-7 — Map prominence on desktop**: at ≥900px the map's measured width is ≥55% of the content area (FR-003, SC-003).
- **INV-8 — Clean reflow**: stepping viewport across the 900px boundary in both directions leaves no overlapping/off-screen content (FR-007, SC-005).

## Non-goals (explicitly out of contract)

- No change to colors, typography, iconography, copy, or component-internal styling beyond fitting the layout.
- No new controls, screens, or behaviors; no API/network changes (anonymity guarantees unaffected).

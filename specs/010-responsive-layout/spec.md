# Feature Specification: Responsive, Full-Width Layout

**Feature Branch**: `010-responsive-layout`

**Created**: 2026-06-12

**Status**: Completed

**Input**: User description: "modernize the UI. Use flexbox or something to make the screen fit various sizes (desktop, smaller desktop, tablet, mobile) and git rid of this huge left and right margin we have set up"

## User Scenarios & Testing *(mandatory)*

Today the entire experience is locked to a narrow centered column. On any screen wider than that column the app shows large empty side margins, and the map — the primary surface for understanding a route — is squeezed into a small area while space goes unused. This feature makes the layout fill the available screen and adapt sensibly from large desktop down to a phone, with the map given the prominence it deserves on larger screens.

### User Story 1 - Desktop user sees a full-width, map-prominent layout (Priority: P1)

A person planning a route on a laptop or desktop monitor opens the app. Instead of a thin centered strip with wide empty margins on either side, the interface uses the available width: the map fills the majority of the screen and the route controls/results sit alongside it in a panel. Nothing important is cut off, and there is no wasted dead space on the left and right.

**Why this priority**: This is the explicit problem the user raised ("get rid of this huge left and right margin") and the most common viewing context. It delivers the visible payoff on its own.

**Independent Test**: Load the app on a typical desktop width (e.g., 1440px) and confirm the content spans the usable width with no large empty side margins, the map occupies the majority of the area, and the planning controls and results remain fully visible and usable.

**Acceptance Scenarios**:

1. **Given** the app open on a 1440px-wide window, **When** the page renders, **Then** content fills the usable width with no large empty left/right margin and the map is the dominant element.
2. **Given** the app open on a desktop window, **When** a route is planned, **Then** the route controls, notice, camera summary, and turn-by-turn results are all reachable and readable without horizontal scrolling.
3. **Given** the app open on a very wide monitor (e.g., 2560px), **When** the page renders, **Then** the layout remains visually balanced (content does not stretch into awkwardly long lines or leave the prior narrow strip surrounded by emptiness).

---

### User Story 2 - Layout adapts across smaller desktop and tablet sizes (Priority: P2)

A person resizes their browser, uses a smaller laptop, or views the app on a tablet (portrait or landscape). As the available width shrinks, the layout reflows gracefully — the map and the controls rearrange so both stay usable — rather than overflowing, clipping content, or forcing horizontal scrolling.

**Why this priority**: Smooth adaptation between the desktop and mobile extremes is what makes the layout genuinely "responsive" rather than two hard-coded states. It builds directly on P1.

**Independent Test**: Resize the window continuously from desktop down to tablet widths and confirm there is no horizontal scrollbar, no clipped or overlapping content, and the map plus all controls remain usable at every width.

**Acceptance Scenarios**:

1. **Given** the app at a tablet width (e.g., 768px), **When** the page renders, **Then** all content fits the viewport width with no horizontal scrolling and every interactive control is reachable.
2. **Given** the window is resized smoothly from 1440px down to 600px, **When** it crosses the point where the side-by-side arrangement no longer fits, **Then** the layout reflows (e.g., to a stacked arrangement) without content being clipped, hidden behind other elements, or overflowing the screen.

---

### User Story 3 - Mobile user keeps a usable full-width stacked flow (Priority: P3)

A person on a phone opens the app. The existing top-to-bottom flow (map, then planning controls, then results) is preserved and uses the full device width edge to edge, with tap targets and text remaining comfortably usable on a small screen.

**Why this priority**: Mobile already roughly works as a single column; the requirement is to ensure the modernized layout does not regress the small-screen experience and that it too uses the full width.

**Independent Test**: Load the app at a phone width (e.g., 375px) and confirm the content uses the full width with no side margins, the flow is map → controls → results, and all controls are tappable without horizontal scrolling.

**Acceptance Scenarios**:

1. **Given** the app at a 375px-wide viewport, **When** the page renders, **Then** content uses the full width with no large side margins and no horizontal scrolling.
2. **Given** the app on a small phone (e.g., 320px wide), **When** a route is planned, **Then** the map, controls, and results are all reachable and readable in a vertical flow.

---

### Edge Cases

- **Very wide displays**: On ultra-wide monitors the content stays balanced rather than either stretching text into unreadably long lines or reverting to a tiny centered strip surrounded by empty space.
- **Very narrow / smallest supported phones (~320px)**: All controls and text remain usable with no horizontal scrolling.
- **Short viewports (landscape phone)**: The map and at least the primary planning controls remain reachable (via the page's normal scrolling) without the map consuming the entire visible area.
- **Long content**: A route with many turn-by-turn steps or a long address scrolls within the layout without breaking it or introducing horizontal scroll.
- **Resize / orientation change**: Rotating a device or resizing the window re-flows the layout cleanly without leaving the interface in a broken intermediate state.
- **Map controls and overlays**: Interactive map controls and the camera/route overlays continue to display correctly as the map area changes size.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The interface MUST use the full usable width of the viewport, eliminating the large fixed empty left/right margins present today.
- **FR-002**: The layout MUST remain usable across the four named size ranges — large desktop, smaller desktop, tablet, and mobile. Large and smaller desktop share the two-pane layout (distinguished by the ultra-wide sidebar cap), and tablet portrait/mobile share the full-width stack; "usable at each" is the requirement, not a distinct layout per range.
- **FR-003**: On wide screens (desktop), the map MUST be the dominant element, with the route planning controls and results presented alongside it rather than stacked in a narrow column.
- **FR-004**: On narrow screens (mobile), the layout MUST present a full-width vertical flow in the order map → planning controls → results.
- **FR-005**: At every supported width from the smallest supported phone to a large desktop, the interface MUST NOT produce horizontal scrolling.
- **FR-006**: At every supported width, no content may be clipped, truncated, or hidden behind another element such that it becomes unreachable; all interactive controls MUST remain reachable and operable.
- **FR-007**: The layout MUST reflow cleanly when the window is resized or the device is rotated, without entering a broken or overlapping intermediate state.
- **FR-008**: On ultra-wide displays the content MUST remain visually balanced (no unbounded stretching of text columns and no reversion to a small centered strip surrounded by empty margins).
- **FR-009**: The map area MUST resize with the layout while keeping its interactive controls and route/camera overlays correctly positioned and usable.
- **FR-010**: The change MUST preserve all existing functionality and content (route planning, route notice, camera summary, turn-by-turn results, language switcher) — this is a layout/presentation change only, not a change to features or behavior.
- **FR-011**: The interface MUST preserve existing accessibility affordances (keyboard reachability of controls, the labelled map region, and the live region announcing route/error updates) across all breakpoints.

### Non-Functional Requirements

- **NFR-001**: Visual styling identity (existing dark theme, colors, typography, and component styling) MUST be preserved; this feature changes layout and sizing, not the visual brand.
- **NFR-002**: The strict-anonymity guarantees are unaffected — this is a presentational change and MUST NOT introduce any new third-party requests, identifiers, or transmission of route/origin/destination data.
- **NFR-003**: The layout MUST NOT regress perceived performance: first-paint layout shift (CLS) stays negligible, the layout reflows without visible jank on resize/rotation, and the existing performance budget (the e2e performance suite) continues to pass.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a 1440px-wide desktop window, the combined empty left + right margin is no more than 5% of the viewport width (today it is the large majority of the width).
- **SC-002**: The interface is usable with no horizontal scrolling at every width from 320px to 2560px.
- **SC-003**: On desktop widths (≥1024px), the map occupies at least 55% of the visible content area.
- **SC-004**: At each representative breakpoint (≈375px, ≈768px, ≈1024px, ≈1440px), 100% of interactive controls are reachable and operable, and no content is clipped or overlapping.
- **SC-005**: Resizing the window across the full supported range never leaves the layout in a visibly broken state (no overlapping elements, no content pushed off-screen).
- **SC-006**: All route-planning functionality that works today continues to work identically after the change (no functional regressions).
- **SC-007**: First-paint cumulative layout shift attributable to the layout stays below 0.1, and the existing performance e2e budget passes unchanged.

## Assumptions

- **Wide-screen arrangement**: On desktop and large tablets the modernized layout places the map as the dominant surface with the planning controls and results in an adjacent panel (a map-app convention), and collapses to the existing full-width vertical stack on narrow screens. This is the informed default for the "various sizes" request; an alternative full-width-but-still-stacked desktop layout was considered and rejected as not "modern" for a map-centric tool.
- **Breakpoints**: The four named ranges (mobile, tablet, smaller desktop, large desktop) are conceptual; the exact pixel thresholds are finalized in the plan as a single two-pane switch at **900px** and an ultra-wide sidebar cap at **1600px** (see research.md §1). Tablet portrait and phones fall below 900px (stacked); tablet landscape and up are two-pane.
- **Smallest supported width**: ~320px is treated as the smallest supported phone width.
- **Scope is presentational**: Only layout, sizing, and responsiveness change. No new screens, no changes to route-planning logic, the API, copy, or the visual theme.
- **Existing components are reused**: The current header, map, route panel, route notice, camera summary, and results components are rearranged, not rebuilt or replaced.
- **"Flexbox or something"** in the request is read as a hint toward modern responsive layout techniques, not a hard constraint on a specific mechanism; the requirement is the responsive outcome, not the technique.

## Out of Scope

- Redesigning the visual theme, colors, typography, iconography, or individual component styling beyond what is needed to make them fit the responsive layout.
- Adding new features, screens, or controls.
- Changing route-planning behavior, the camera-avoidance logic, or any backend/API contract.

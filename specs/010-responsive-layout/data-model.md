# Phase 1 Data Model: Responsive, Full-Width Layout

This is a presentation-only feature. There are **no persisted data entities, no schema changes, and no API changes**. What follows models the *structural* shape the layout implements — the regions and the breakpoint states — so the contract and tests have a shared vocabulary.

## Layout regions

| Region | Element (current) | Contents | Role |
|--------|-------------------|----------|------|
| **Shell** | `.plan-page` | everything | Top-level responsive container. Stops being a 520px centered column; becomes full-width, height `100svh` on desktop. |
| **Header** | `.app-header` | app title, `LanguageSwitcher` | Stays at the top in both layouts. |
| **Map pane** | `.map-container` (wrapping `MapView`) | the map | Dominant element on desktop; top element on mobile. |
| **Content pane (sidebar)** | new wrapper around `RoutePanel` + `.result-section` | planning form, `RouteNotice`, `CameraSummary`, `RouteResult` | Beside the map on desktop (internally scrollable); below the map on mobile. |

The content pane groups today's `RoutePanel` and `result-section` so they can sit beside the map as one scrollable column on desktop. On mobile they read in the same order as today.

## Breakpoint states (state machine on viewport width)

```
        width < 900px            900px ≤ width < 1600px         width ≥ 1600px
   ┌──────────────────┐       ┌──────────────────────┐     ┌──────────────────────┐
   │   STACKED        │       │   TWO-PANE            │     │   TWO-PANE (capped)   │
   │  (full width)    │  ───► │  map | sidebar        │ ──► │  map | sidebar≤420px  │
   │  header          │       │  header spans top     │     │  map absorbs extra w  │
   │  map (~46svh)    │       │  map = 1fr (≥55%)     │     │                       │
   │  controls        │       │  sidebar scrolls      │     │                       │
   │  results         │       │  full viewport height │     │                       │
   └──────────────────┘       └──────────────────────┘     └──────────────────────┘
```

Transitions are driven purely by viewport width (CSS media queries); resize/rotation moves between states with no JS and no intermediate broken state.

## Invariants (hold in every state)

- No horizontal scrolling (content width ≤ viewport width) from 320px to 2560px.
- Every interactive control is visible/reachable and operable; nothing clipped or overlapped.
- Reading/tab order stays: header → origin → destination → plan → results.
- Accessibility affordances preserved: `.map-container` remains a labelled `region`; the results live region keeps `aria-live="polite"`.
- Visual theme (colors, typography, component styling) unchanged.

## Out of model

No new types, props, or state are required by the design (the JSX change is a wrapper element, not new data flow). If a wrapper component is introduced for the content pane, it is a pure presentational container with no props beyond `children`.

# UI Contract: Printable Directions

This is a frontend-only feature; the contract is the React component interface, the rendered
print structure, and the new i18n keys. No HTTP/API contract changes (the backend `Route` response
is unchanged).

## Component: `PrintableDirections`

```ts
interface PrintableDirectionsProps {
  route: Route;            // existing type from src/types/api.ts
  originLabel: string;     // confirmed origin address (or "lat, lng" for device location)
  destinationLabel: string;// confirmed destination address
}
```

### Behavior contract

1. Renders an **icon-only** trigger `<button>` at the top of the directions section. The SVG is
   `aria-hidden="true"`; the button carries `aria-label` and `title` = `t("print.action")`.
2. Activating the trigger calls `window.print()` exactly once per activation.
3. Renders a print-only region (`class="printable-directions"`) that is `display:none` on screen
   and visible only under `@media print`.
4. The print region, in order, contains:
   - a heading — `t("print.heading")`
   - origin and destination labels (`originLabel`, `destinationLabel`) with localized field labels
     (`t("print.from")`, `t("print.to")`)
   - total travel time and distance (reusing `result.travelTime` / `result.distance` formatting)
   - an ordered list of every `route.maneuvers[i].localized_text`, in order
   - a privacy notice — `t("print.privacyNotice")`
5. The print region MUST NOT contain the map, the interactive controls, the trigger button itself,
   or any camera/coverage notice text.
6. No network request is issued at any point in the flow.

### Rendering structure (print region)

```html
<div class="printable-directions" aria-hidden="true">
  <h2>{print.heading}</h2>
  <p class="print-trip">
    <span class="print-from">{print.from}: {originLabel}</span>
    <span class="print-to">{print.to}: {destinationLabel}</span>
  </p>
  <p class="print-totals">{result.travelTime} · {result.distance}</p>
  <ol class="print-steps">
    <li>{maneuver.localized_text}</li>
    ...
  </ol>
  <p class="print-notice">{print.privacyNotice}</p>
</div>
```

> The on-screen `RouteResult` keeps its existing `<ol class="directions">`; the print region is a
> separate, print-only copy so screen and print can be styled independently.

## Mount point change: `RouteResult`

The print trigger appears at the top of the directions block:

```tsx
<div class="directions-header">
  <h3>{t("result.directions")}</h3>
  <PrintableDirections route={route} originLabel={...} destinationLabel={...} />
</div>
```

`RouteResult` gains `originLabel` / `destinationLabel` props (threaded from `PlanRoutePage`).

## Prop-lift change: `RoutePanel` → `PlanRoutePage`

`onPlan` is extended so the page receives the confirmed labels at plan time:

```ts
onPlan: (origin: Coordinate, destination: Coordinate, labels: { origin: string; destination: string }) => void;
```

`PlanRoutePage` stores `{ originLabel, destLabel }` alongside `endpoints` and passes them to
`RouteResult`. (A separate callback is an acceptable alternative; the constraint is that labels are
captured at plan time so they can't desync — FR-012.)

## i18n keys (new `print.*` namespace)

Add to `en.json` and `es.json` (parity required, FR-011):

| Key | English (reference) |
|-----|---------------------|
| `print.action` | "Print directions" |
| `print.heading` | "Driving directions" |
| `print.from` | "From" |
| `print.to` | "To" |
| `print.privacyNotice` | A brief reminder that the printed page contains the user's full route (start, destination, and turns) and should be protected once printed — same intent/tone as `gpx.warning`, shortened for paper. |

> Exact final copy is set during implementation; Spanish translations must be added in the same
> change. No `result.*` keys are removed; the print view reuses `result.travelTime` /
> `result.distance` for the totals line.

## Print stylesheet contract (`App.css`)

- `@media screen`: `.printable-directions { display: none; }`
- `@media print`:
  - hide app chrome (`.app-header`, `.app-footer`, `.map-container`, `.route-panel`,
    `.comparison-toggle`, `.export-gpx-btn`, the print trigger, `RouteNotice`, `CameraSummary`,
    on-screen `.directions`/`.stats`/status pills) — only `.printable-directions` shows;
  - `.printable-directions { display: block; }`, black text on white, no backgrounds/shadows;
  - large, readable step type (≥14pt) with clear numbering and generous spacing;
  - `.print-steps li { break-inside: avoid; }` so a step never splits across a page break;
  - no fixed `@page size` (adapt to the user's Letter/A4 setting).

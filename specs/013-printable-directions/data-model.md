# Data Model: Printable Driving Directions

No persisted entities and no backend schema changes. This feature renders data already present on
the client. The "model" here is the in-memory view data the print region consumes and where each
field comes from.

## Entity: PrintableDirectionsView (derived, in-memory only)

The exact content the print region renders for the currently displayed route.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `originLabel` | string | Lifted from `RoutePanel` (`originText`) → `PlanRoutePage` | Human address the user picked, or a `lat, lng` string for "use my location". Captured at plan time. |
| `destinationLabel` | string | Lifted from `RoutePanel` (`destText`) → `PlanRoutePage` | As above for the destination. |
| `totalDurationMin` | number | `Route.duration_s` (÷60, rounded) | Same rounding as `RouteResult` (`result.travelTime`). |
| `totalDistanceKm` | string | `Route.distance_m` (÷1000, 1 dp) | Same formatting as `RouteResult` (`result.distance`). |
| `steps` | `Maneuver[]` | `Route.maneuvers` | Rendered in order via `localized_text`, matching the on-screen `<ol class="directions">`. |
| `privacyNotice` | string (i18n) | `print.privacyNotice` key | Brief "this page holds your route" reminder (FR-009). |

### Validation / rules

- **Visibility**: The print control and view exist only when a route is displayed
  (`route && endpoints`), i.e. the same condition that renders `RouteResult` (FR-002).
- **Currency**: `originLabel` / `destinationLabel` are stored together with the planned trip at
  plan time, so editing the input fields afterward cannot desync the printed sheet (FR-012).
- **Exclusions**: No camera/coverage fields are part of this view (FR-010). No map, controls, or
  page chrome (FR-005).
- **Locale**: All static text (`heading`, control label, `privacyNotice`) resolves through
  react-i18next under the active language; `steps` use the server-localized `localized_text`
  (FR-011).
- **Empty/degenerate**: A route with `maneuvers.length <= 1` still renders a valid sheet (header +
  whatever steps exist); never a blank page (Edge Cases).

## State changes (frontend wiring)

```text
RoutePanel: on plan submit
  onPlan(origin, destination, { originLabel, destLabel })   # extended signature
        │
        ▼
PlanRoutePage: store { endpoints, originLabel, destLabel } together
        │  (passed as props)
        ▼
RouteResult(route, originLabel, destLabel)
        │
        ▼
PrintableDirections(route, originLabel, destLabel)
   ├─ on-screen: icon button (aria-label) → window.print()
   └─ print-only region (@media print): heading, origin→destination,
      totals, ordered steps, privacy notice
```

No other component's data flow changes; `Route` and the API contract are untouched.

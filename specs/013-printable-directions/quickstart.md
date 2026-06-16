# Quickstart: Printable Driving Directions

Frontend-only feature. All work is under `frontend/`. Run commands from the repo root.

## Prerequisites

- Frontend dev tooling as usual (Vite + Vitest). Backend not required for this feature; you can
  develop against a planned route fixture or a running stack.

## Files to touch

| File | Change |
|------|--------|
| `frontend/src/components/PrintableDirections.tsx` | NEW — icon trigger + print-only region |
| `frontend/src/components/RouteResult.tsx` | Mount the print control atop the directions header; accept `originLabel`/`destinationLabel` props |
| `frontend/src/components/RoutePanel.tsx` | Surface confirmed origin/dest labels via `onPlan` |
| `frontend/src/pages/PlanRoutePage.tsx` | Store the labels with `endpoints`; pass to `RouteResult` |
| `frontend/src/i18n/locales/en.json` | Add `print.*` keys |
| `frontend/src/i18n/locales/es.json` | Spanish parity for `print.*` |
| `frontend/src/App.css` | `@media print` block + control styles |
| `frontend/tests/printable-directions.test.tsx` | NEW — control + print-view tests |
| `frontend/tests/route-result.test.tsx` | Assert print control mounts atop directions |

## Implementation order

1. **Lift the labels** (`RoutePanel` → `PlanRoutePage`): extend `onPlan` to include
   `{ origin, destination }` labels; store them in page state with `endpoints`; thread to
   `RouteResult`. Verify existing route-panel/page tests still pass.
2. **Build `PrintableDirections`**: icon-only button (`aria-label`/`title` = `t("print.action")`,
   `aria-hidden` SVG) that calls `window.print()`, plus the print-only region per
   `contracts/print-view.md`.
3. **Mount it** in `RouteResult`'s directions header.
4. **Add i18n keys** to `en.json` and `es.json` (parity).
5. **Add print CSS** to `App.css`: hide app chrome under `@media print`, show
   `.printable-directions`, large black-on-white type, `break-inside: avoid` on steps, no fixed
   page size.
6. **Tests** (Principle II — write alongside, must fail without the change).

## Running tests

```bash
# from frontend/ (or via the project's frontend test script)
pnpm test           # full Vitest suite
pnpm test printable-directions
pnpm lint && pnpm typecheck   # Principle I gates
```

> Per project policy, run JS/TS tooling the way the repo is set up; do not run Ruby/host toolchains
> for this frontend-only feature.

## Manual verification (acceptance)

1. Plan any route; confirm a **printer icon** appears at the top of the directions (and is absent
   before any route is planned).
2. Click it → the browser print dialog opens.
3. In the print preview, confirm: heading; **From/To** origin + destination; total time + distance;
   **every** turn-by-turn step in order; a privacy notice; and **no** map, chrome, controls, or
   camera/coverage text.
4. Steps are large, numbered, well-spaced, black-on-white; a multi-page route paginates with no
   step split across a page break.
5. Switch language → control label and printed static text follow the active language.
6. Save as PDF from the dialog → same readable layout.
7. (Privacy) Observe the network panel during print → zero requests carrying route/location data.

## Done checklist

- [ ] Print control visible only when a route is shown; icon-only with accessible label.
- [ ] `window.print()` invoked on activation (no network).
- [ ] Print view: heading, origin/destination, totals, all ordered steps, privacy notice.
- [ ] No map/chrome/controls/camera notices in print output.
- [ ] Large, legible, paginated print layout (`break-inside: avoid`).
- [ ] en + es parity for `print.*`.
- [ ] Tests added and green; lint + typecheck clean.

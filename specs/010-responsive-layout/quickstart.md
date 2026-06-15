# Quickstart: Responsive, Full-Width Layout

All commands run from `frontend/` (package manager: `pnpm`).

## Run the app locally

```bash
cd frontend
pnpm install        # if deps not yet installed
pnpm dev            # Vite dev server (http://localhost:5173)
```

## Manually verify the layout

1. Open the app and the browser devtools device toolbar.
2. Step through widths and confirm the [contract](./contracts/responsive-layout.md):
   - **320 / 375 / 768px** — full-width vertical stack (map → controls → results), no empty side margins, no horizontal scroll.
   - **900 / 1024 / 1440px** — map sits beside a controls/results sidebar; map dominates (≥~55% width); sidebar scrolls on its own when results are long.
   - **2560px** — sidebar stays a sensible width, the map grows to fill the rest; the page never collapses back to a narrow centered strip.
3. Resize smoothly across ~900px and rotate a simulated device — the layout reflows with no overlap, clipping, or horizontal scrollbar.
4. Plan a route at each width and confirm the route notice, camera summary, and turn-by-turn steps are all reachable.

## Run the automated gates

```bash
cd frontend
pnpm lint                                   # zero warnings (Constitution I)
pnpm test                                    # Vitest component/unit suite (no regressions)

# e2e (Playwright) — build + preview is wired via playwright.config baseURL :4173
pnpm build
pnpm e2e tests/e2e/responsive-layout.spec.ts # NEW responsive + axe assertions
pnpm e2e                                     # full e2e incl. a11y, anonymity, perf — must stay green
```

## What "done" looks like

- `responsive-layout.spec.ts` passes at every viewport in the contract and **fails against the pre-change 520px layout** (proves the test has teeth — Constitution II).
- `a11y.spec.ts`, `anonymity.spec.ts`, `perf.spec.ts`, and the Vitest suite remain green.
- `pnpm lint` is clean; no dead/duplicated CSS rules left behind.
- The dark theme and all existing functionality are visually and behaviorally unchanged — only the layout differs.

# Merged Features Log

### Printable Driving Directions — 2026-06-18
**Branch:** `013-printable-directions`
**Spec:** specs/013-printable-directions

**What was added:**
- US-013-1 (P1, MVP): an icon-only print control at the top of the on-screen driving directions
  that opens the browser's native print dialog showing a dedicated, print-only view — the full
  ordered turn-by-turn steps in a large, uncluttered layout; map, page chrome, and all controls
  excluded; hidden when no route is planned.
- US-013-2 (P2): print-only stylesheet making the sheet glanceable while driving — large
  black-on-white type, clear step numbering, generous spacing, and `break-inside: avoid` pagination
  so steps don't split across a page break; no fixed `@page` size (adapts to Letter/A4).
- US-013-3 (P3): trip header on the printout — heading, origin + destination labels, total travel
  time and distance, and a brief "this page holds your route" privacy notice mirroring the GPX
  export warning. Camera/coverage notices deliberately omitted.
- Fully client-side (`window.print()` + `@media print`), zero network transmission — anonymity
  model intact (FR-013, SC-006). Localized en + es.

**New Components:**
- `frontend/src/components/PrintableDirections.tsx` — icon trigger + print-only view.
- Print stylesheet block in `frontend/src/App.css` (`@media print` / `@media screen`).
- `print.*` i18n namespace in `en.json` / `es.json`.
- Wiring: origin/destination labels lifted `RoutePanel → PlanRoutePage → RouteResult →
  PrintableDirections` (captured at plan time so they can't desync — FR-012). No backend/API change.

**Tasks Completed:** 18/19 tasks (T019 — manual quickstart verification incl. network-panel privacy
check, print dialog latency, and print-to-PDF pass — left unchecked as a manual acceptance step).

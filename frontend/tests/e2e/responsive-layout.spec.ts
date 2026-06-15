import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import {
  mockApi,
  planRoute,
  viewport,
  expectNoHorizontalScroll,
  sideMarginFraction,
  mapWidthFraction,
} from "./helpers";

// Feature 010 — Responsive, full-width layout. These assertions encode the UI
// contract (contracts/responsive-layout.md) and FAIL against the pre-change
// 520px centered column (there is no .content-pane, so the side-by-side/stacked
// checks throw).

test.beforeEach(async ({ page }) => {
  await mockApi(page);
});

// Returns the map and content-pane bounding boxes (both required to exist).
async function panes(page: import("@playwright/test").Page) {
  const map = await page.locator(".map-container").boundingBox();
  const content = await page.locator(".content-pane").boundingBox();
  expect(map, "map pane present").not.toBeNull();
  expect(content, "content pane present").not.toBeNull();
  return { map: map!, content: content! };
}

// ─── User Story 1: desktop full-width, map-prominent two-pane (T005) ───
for (const name of ["desktop-900", "desktop-1024", "desktop-1440"] as const) {
  test(`US1 ${name}: map-dominant two-pane, controls + results reachable`, async ({ page }) => {
    const v = viewport(name);
    await page.setViewportSize({ width: v.width, height: v.height });
    await page.goto("/");

    // Side-by-side: content pane begins at/after the map's right edge.
    const { map, content } = await panes(page);
    expect(content.x + 1).toBeGreaterThanOrEqual(map.x + map.width - 1);

    // Map dominates the content area (≥55%, SC-003).
    expect(await mapWidthFraction(page)).toBeGreaterThanOrEqual(0.55);
    await expectNoHorizontalScroll(page);

    // Controls reachable.
    await expect(page.locator('.route-panel input[inputmode="search"]').first()).toBeVisible();
    await expect(page.locator('.route-panel button[type="submit"]')).toBeVisible();

    // After planning, results reachable with no overflow (INV-2).
    await planRoute(page);
    await expect(page.locator(".route-result")).toBeVisible();
    await expectNoHorizontalScroll(page);
  });
}

test("US1 desktop-1440: combined empty side margin ≤5% (SC-001)", async ({ page }) => {
  const v = viewport("desktop-1440");
  await page.setViewportSize({ width: v.width, height: v.height });
  await page.goto("/");
  expect(await sideMarginFraction(page)).toBeLessThanOrEqual(0.05);
});

// ─── User Story 2: reflow, tablet, ultra-wide (T008) ───
test("US2 tablet-768: stacked, full-width, controls reachable (SC-004)", async ({ page }) => {
  const v = viewport("tablet-768");
  await page.setViewportSize({ width: v.width, height: v.height });
  await page.goto("/");

  // Stacked: content pane sits below the map.
  const { map, content } = await panes(page);
  expect(content.y).toBeGreaterThanOrEqual(map.y + map.height - 1);
  expect(await sideMarginFraction(page)).toBeLessThanOrEqual(0.02);
  await expectNoHorizontalScroll(page);

  await expect(page.locator('.route-panel input[inputmode="search"]').first()).toBeVisible();
  await expect(page.locator('.route-panel button[type="submit"]')).toBeVisible();
  await planRoute(page);
  await expect(page.locator(".route-result")).toBeVisible();
});

test("US2 transition across 900px is clean (INV-8)", async ({ page }) => {
  // Two-pane at exactly 900.
  await page.setViewportSize({ width: 900, height: 900 });
  await page.goto("/");
  let p = await panes(page);
  expect(p.content.x + 1).toBeGreaterThanOrEqual(p.map.x + p.map.width - 1);
  await expectNoHorizontalScroll(page);

  // Stacked just below 900.
  await page.setViewportSize({ width: 899, height: 900 });
  p = await panes(page);
  expect(p.content.y).toBeGreaterThanOrEqual(p.map.y + p.map.height - 1);
  await expectNoHorizontalScroll(page);
});

test("US2 ultra-wide 2560: sidebar bounded, map absorbs width, no centered strip (FR-008)", async ({
  page,
}) => {
  const v = viewport("ultrawide-2560");
  await page.setViewportSize({ width: v.width, height: v.height });
  await page.goto("/");

  expect(await sideMarginFraction(page)).toBeLessThanOrEqual(0.02); // fills width, no strip
  const { content } = await panes(page);
  expect(content.width).toBeLessThanOrEqual(440); // ~420 cap + tolerance
  expect(await mapWidthFraction(page)).toBeGreaterThanOrEqual(0.7);
  await expectNoHorizontalScroll(page);
});

// ─── User Story 3: mobile + short-height landscape (T011) ───
for (const name of ["mobile-320", "mobile-375", "landscape-phone"] as const) {
  test(`US3 ${name}: edge-to-edge stacked flow, no horizontal scroll`, async ({ page }) => {
    const v = viewport(name);
    await page.setViewportSize({ width: v.width, height: v.height });
    await page.goto("/");

    expect(await sideMarginFraction(page)).toBeLessThanOrEqual(0.02);
    await expectNoHorizontalScroll(page);

    // Stacked order: map above content (INV-4).
    const { map, content } = await panes(page);
    expect(content.y).toBeGreaterThanOrEqual(map.y + map.height - 1);

    await expect(page.locator('.route-panel input[inputmode="search"]').first()).toBeVisible();
    await expect(page.locator('.route-panel button[type="submit"]')).toBeVisible();
  });
}

test("US3 landscape-phone: map does not consume the entire viewport height", async ({ page }) => {
  const v = viewport("landscape-phone");
  await page.setViewportSize({ width: v.width, height: v.height });
  await page.goto("/");
  const { map } = await panes(page);
  expect(map.height).toBeLessThan(v.height); // controls have room below the map
});

// ─── Accessibility at mobile + desktop (T013, INV-5) ───
const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];
for (const name of ["mobile-375", "desktop-1440"] as const) {
  test(`a11y ${name}: no serious/critical violations`, async ({ page }) => {
    const v = viewport(name);
    await page.setViewportSize({ width: v.width, height: v.height });
    await page.goto("/");
    // MapLibre's canvas/controls are library-managed (matches a11y.spec.ts).
    const results = await new AxeBuilder({ page }).withTags(WCAG).exclude(".map-view").analyze();
    const serious = results.violations.filter(
      (x) => x.impact === "serious" || x.impact === "critical"
    );
    expect(serious, JSON.stringify(serious.map((x) => x.id), null, 2)).toEqual([]);
  });
}

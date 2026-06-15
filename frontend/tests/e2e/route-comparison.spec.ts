import { test, expect } from "@playwright/test";
import { mockApi, planRoute, routeFor } from "./helpers";

// Feature 009: the fastest non-avoiding route is drawn as a comparison line and
// the trade-off is surfaced; it is dismissible and never lingers across plans.
test.beforeEach(async ({ page }) => {
  // Opt in to exposing the in-page map so the test can inspect its layers/sources.
  await page.addInitScript(() => {
    (window as unknown as { __E2E__: boolean }).__E2E__ = true;
  });
  await mockApi(page);
  await page.goto("/");
});

// Number of coordinates currently in the comparison line's GeoJSON source.
// -1 means the source/layer was never created (no comparison ever drawn).
async function comparisonCoordCount(page: import("@playwright/test").Page): Promise<number> {
  return page.evaluate(async () => {
    const src = (
      window as unknown as {
        __flckdMap?: { getSource(id: string): { getData?: () => Promise<unknown> } | undefined };
      }
    ).__flckdMap?.getSource("comparison");
    if (!src || !src.getData) return -1;
    const data = (await src.getData()) as
      | { type: "Feature"; geometry?: { coordinates?: unknown[] } }
      | { type: "FeatureCollection"; features: { geometry?: { coordinates?: unknown[] } }[] };
    const feature = data.type === "FeatureCollection" ? data.features[0] : data;
    return feature?.geometry?.coordinates?.length ?? 0;
  });
}

// Wait until the plan has rendered (the trade-off toggle only appears once a
// penalty route's result is on screen), so map-layer assertions don't race the
// route-drawing effect.
async function waitForPenaltyPlan(page: import("@playwright/test").Page): Promise<void> {
  await expect(page.locator(".route-result")).toBeVisible();
  await expect(
    page.getByRole("button", { name: /hide fastest route|show fastest route/i }),
  ).toBeVisible();
  // Generous ceiling: the map's draw effect only runs after the style loads,
  // which can lag under parallel-worker contention on the single preview server.
  await expect.poll(() => comparisonCoordCount(page), { timeout: 30000 }).toBeGreaterThan(0);
}

const hasLayer = (page: import("@playwright/test").Page, id: string) =>
  page.evaluate(
    (layerId) =>
      !!(window as unknown as { __flckdMap?: { getLayer(id: string): unknown } }).__flckdMap?.getLayer(
        layerId,
      ),
    id,
  );

test("draws the fastest route as a comparison line and surfaces the trade-off (US1)", async ({ page }) => {
  await planRoute(page);
  await waitForPenaltyPlan(page);

  const result = page.locator(".route-result");
  // Added time (headline) + added distance (secondary) + fastest-route exposure.
  await expect(result.locator(".stats")).toContainText("+3 min vs fastest");
  await expect(result.locator(".stats")).toContainText("+1.2 km vs fastest");
  await expect(result.locator(".fastest-exposes")).toContainText("3 cameras");

  // Both lines are on the map; the comparison has real geometry.
  expect(await hasLayer(page, "route-line")).toBe(true);
  expect(await hasLayer(page, "comparison-line")).toBe(true);
});

test("hides the comparison line on dismiss while keeping the recommended route", async ({ page }) => {
  await planRoute(page);
  await waitForPenaltyPlan(page);

  await page.locator(".route-result").getByRole("button", { name: /hide fastest route/i }).click();

  await expect.poll(() => comparisonCoordCount(page)).toBe(0); // comparison cleared
  expect(await hasLayer(page, "route-line")).toBe(true); // recommended route remains
});

test("clears the comparison and shows no trade-off when a new plan is penalty-free (FR-009)", async ({
  page,
}) => {
  await planRoute(page);
  await waitForPenaltyPlan(page);

  // Re-plan, this time returning a route whose fastest path is already the chosen
  // route (no added time). Last-registered handler wins.
  await page.route("**/api/v1/routes", async (route) => {
    const r = routeFor("en");
    r.fastest_comparison.added_duration_s = 0;
    r.fastest_comparison.added_distance_m = 0;
    await route.fulfill({ json: r });
  });
  await page.locator('.route-panel button[type="submit"]').click();

  await expect(page.locator(".route-result")).toBeVisible();
  await expect(page.locator(".route-result .stats")).not.toContainText("vs fastest");
  await expect.poll(() => comparisonCoordCount(page)).toBe(0);
});

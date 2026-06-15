import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { mockApi, planRoute } from "./helpers";

// T074: WCAG 2.1 AA audit (axe) on the core flow — both the initial input
// screen and the planned-route result.
const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];

test("input screen has no serious/critical accessibility violations", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");

  // Exclude MapLibre's own canvas/controls (e.g. its attribution link) — that
  // DOM is library-managed, not our UI surface.
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).exclude(".map-view").analyze();
  const serious = results.violations.filter(
    (v) => v.impact === "serious" || v.impact === "critical"
  );
  expect(serious, JSON.stringify(serious.map((v) => v.id), null, 2)).toEqual([]);
});

test("planned-route screen has no serious/critical accessibility violations", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);
  await expect(page.locator(".route-result")).toBeVisible();

  const results = await new AxeBuilder({ page })
    .withTags(WCAG_TAGS)
    // MapLibre's canvas region is exempt from text-based WCAG rules.
    .exclude(".map-view")
    .analyze();
  const serious = results.violations.filter(
    (v) => v.impact === "serious" || v.impact === "critical"
  );
  expect(serious, JSON.stringify(serious.map((v) => v.id), null, 2)).toEqual([]);
});

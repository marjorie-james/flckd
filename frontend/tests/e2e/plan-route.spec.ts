import { test, expect } from "@playwright/test";
import { mockApi, planRoute } from "./helpers";

// T027 (US1): enter origin/destination → an avoiding route with directions renders.
test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
});

test("plans a camera-avoiding route and shows localized directions", async ({ page }) => {
  await planRoute(page);

  // Fully-clean status (the "avoid" preference returns a clean route).
  const result = page.locator(".route-result");
  await expect(result.locator(".status.clean")).toContainText("avoids all known cameras");

  // Avoided-count and distance stats are present.
  await expect(page.locator(".camera-summary")).toContainText("3 cameras avoided");
  await expect(result.locator(".stats")).toContainText("8.2 km");
  await expect(result.locator(".stats")).toContainText("+3 min vs fastest");

  // Directions list renders each maneuver.
  const steps = result.locator("ol.directions li");
  await expect(steps).toHaveCount(3);
  await expect(steps.first()).toHaveText("Head north on Main St");
  await expect(steps.last()).toHaveText("Arrive at your destination");
});

test("renders the map container for the planned route", async ({ page }) => {
  await planRoute(page);
  await expect(page.locator(".map-view")).toBeVisible();
});

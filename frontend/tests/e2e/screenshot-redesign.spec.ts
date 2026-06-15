import { test } from "@playwright/test";
import { mockApi, planRoute } from "./helpers";

test("screenshot: empty state", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await page.waitForTimeout(800);
  await page.screenshot({ path: "/tmp/redesign-empty.png", fullPage: true });
});

test("screenshot: after route planned", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);
  await page.locator(".route-result").waitFor({ state: "visible" });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: "/tmp/redesign-planned.png", fullPage: true });
});

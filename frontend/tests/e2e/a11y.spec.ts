import { test, expect } from "@playwright/test";
import { mockApi, planRoute, routeFor, expectNoAxeViolations } from "./helpers";

// ── Helpers for triggering specific UI states ──

// Return a route with remaining cameras so RouteNotice renders its alert.
function notCleanRoute() {
  const base = routeFor("en");
  return {
    ...base,
    is_fully_clean: false,
    remaining_cameras: [{ osm_way_id: 12345 }, { osm_way_id: 67890 }],
  };
}

// ── Core flow ──

test("input screen has no accessibility violations", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");

  await expectNoAxeViolations(page);
});

test("planned-route screen has no accessibility violations", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);
  await expect(page.getByRole("heading", { level: 3 })).toBeVisible();

  await expectNoAxeViolations(page);
});

// ── Autocomplete states ──

test("autocomplete no-matches state has no violations", async ({ page }) => {
  await mockApi(page);
  // Override geocode to return empty results.
  await page.route("**/api/v1/geocode/search**", async (route) => {
    await route.fulfill({ json: { results: [] } });
  });
  await page.goto("/");

  await page.getByLabel("Start").fill("xyznotfound");
  // The status text appears both in the visible <div> and a visually-hidden
  // <span role="status">, so getByText matches two elements. Target the visible
  // div by tag+class (it has no ARIA role to select on).
  await expect(page.locator("div.suggestion-status")).toBeVisible();

  await expectNoAxeViolations(page);
});

test("autocomplete error state has no violations", async ({ page }) => {
  await mockApi(page);
  // Override geocode to fail.
  await page.route("**/api/v1/geocode/search**", async (route) => {
    await route.fulfill({ status: 500, body: "Internal Server Error" });
  });
  await page.goto("/");

  await page.getByLabel("Start").fill("test address");
  // TanStack Query retries 3 times with exponential backoff (~7s) before
  // surfacing the error. The error div has no ARIA role (the sibling
  // visually-hidden <span role="status"> carries the same text, so getByText
  // would match two elements). Target the visible div by class.
  await expect(page.locator(".suggestion-status.error")).toBeVisible({ timeout: 15_000 });

  await expectNoAxeViolations(page);
});

test("autocomplete loading state has no violations", async ({ page }) => {
  await mockApi(page);
  // Override geocode to hang so the loading indicator stays up.
  await page.route("**/api/v1/geocode/search**", async (route) => {
    await new Promise((r) => setTimeout(r, 30_000));
    await route.fulfill({ json: { results: [] } });
  });
  await page.goto("/");

  await page.getByLabel("Start").fill("test address");
  await expect(page.locator(".suggestion-status")).toBeVisible();

  await expectNoAxeViolations(page);
});

// ── GPX export dialog ──

test("GPX export dialog has no violations", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);
  await expect(page.getByRole("heading", { level: 3 })).toBeVisible();

  await page.getByRole("button", { name: "Export route (GPX)" }).click();
  await expect(page.getByRole("alertdialog")).toBeVisible();

  await expectNoAxeViolations(page);
});

// ── Error banner ──

test("error banner has no violations", async ({ page }) => {
  await mockApi(page);
  // Override route API to return an error after the geocode succeeds.
  await page.route("**/api/v1/routes", async (route) => {
    await route.fulfill({
      status: 422,
      contentType: "application/json",
      body: JSON.stringify({ code: "no_route", message: "No drivable route found" }),
    });
  });
  await page.goto("/");
  await planRoute(page);

  // The error banner uses role="alert".
  await expect(page.getByRole("alert")).toBeVisible();

  await expectNoAxeViolations(page);
});

// ── Route with remaining cameras (RouteNotice visible) ──

test("not-fully-clean route notice has no violations", async ({ page }) => {
  await mockApi(page);
  // Override route API to return a route with remaining cameras.
  await page.route("**/api/v1/routes", async (route) => {
    await route.fulfill({ json: notCleanRoute() });
  });
  await page.goto("/");
  await planRoute(page);

  // RouteNotice renders an alert for routes that aren't camera-free.
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page.getByRole("heading", { level: 3 })).toBeVisible();

  await expectNoAxeViolations(page);
});

// ── Print media ──

test("print media view has no violations", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);
  await expect(page.getByRole("heading", { level: 3 })).toBeVisible();

  // Switch to print media so @media print rules take effect: the directions
  // sheet becomes visible and the map/panel/controls hide.
  await page.emulateMedia({ media: "print" });

  // emulateMedia activates @media print CSS but does NOT fire the beforeprint
  // event. The print sheet toggles aria-hidden off in its beforeprint handler,
  // so we dispatch the event manually to match what a real print flow does.
  await page.evaluate(() => window.dispatchEvent(new Event("beforeprint")));

  // The print sheet now provides an <h1> (with aria-hidden toggled off), so
  // the print view has a top-level heading and page-has-heading-one passes.
  await expectNoAxeViolations(page);
});

// ── Spanish locale ──

test("Spanish locale has no violations", async ({ page }) => {
  await mockApi(page);
  // Set the browser to Spanish so the locale resolver picks it up.
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "languages", { get: () => ["es"] });
    Object.defineProperty(navigator, "language", { get: () => "es" });
  });
  await page.goto("/");

  await expectNoAxeViolations(page);
});

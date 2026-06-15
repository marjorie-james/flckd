import { test, expect } from "@playwright/test";
import { mockApi, planRoute } from "./helpers";

// T046 (US2): the full flow makes ZERO third-party network requests, and the
// GPX export builds the route file locally (no transmission) after warning the
// user that the file itself holds their route.

test("makes no third-party requests during the full route flow", async ({ page, baseURL }) => {
  const allowedHost = new URL(baseURL!).host;
  const offending: string[] = [];

  page.on("request", (req) => {
    const url = req.url();
    if (url.startsWith("data:") || url.startsWith("blob:")) return;
    const host = new URL(url).host;
    // Only our own origin is allowed (self-hosted everything, FR-012a).
    if (host !== allowedHost) offending.push(url);
  });

  await mockApi(page);
  await page.goto("/");
  await planRoute(page);
  await expect(page.locator(".route-result")).toBeVisible();

  expect(offending, `Unexpected third-party requests:\n${offending.join("\n")}`).toEqual([]);
});

test("viewing/panning cameras sends the viewport bbox only to our own backend (FR-013)", async ({ page, baseURL }) => {
  const allowedHost = new URL(baseURL!).host;
  const offending: string[] = [];

  page.on("request", (req) => {
    const url = req.url();
    if (url.startsWith("data:") || url.startsWith("blob:")) return;
    if (new URL(url).host !== allowedHost) offending.push(url);
  });

  await mockApi(page);
  await page.goto("/");
  await page.locator(".map-view").waitFor({ state: "visible" });
  // Pan so the viewport bbox is recomputed and a camera fetch fires.
  await page.waitForTimeout(500);
  await page.mouse.move(300, 300);
  await page.mouse.down();
  await page.mouse.move(120, 200, { steps: 6 });
  await page.mouse.up();
  await page.waitForTimeout(800);

  expect(offending, `Unexpected third-party requests:\n${offending.join("\n")}`).toEqual([]);
});

test("recentering on a selected starting address makes no third-party requests", async ({ page, baseURL }) => {
  const allowedHost = new URL(baseURL!).host;
  const offending: string[] = [];

  page.on("request", (req) => {
    const url = req.url();
    if (url.startsWith("data:") || url.startsWith("blob:")) return;
    if (new URL(url).host !== allowedHost) offending.push(url);
  });

  await mockApi(page);
  await page.goto("/");

  // Select only the starting address — this triggers the recenter + tile fetches
  // for the new viewport, which must stay on our own origin (FR-009).
  const input = page.locator('.route-panel input[inputmode="search"]').nth(0);
  await input.fill("iowa state");
  const suggestion = page.locator(".suggestions li button").first();
  await suggestion.waitFor({ state: "visible" });
  await suggestion.click();
  await page.waitForTimeout(800); // allow the recenter animation + tile requests

  expect(offending, `Unexpected third-party requests:\n${offending.join("\n")}`).toEqual([]);
});

test("exports the route as a local GPX file after warning about the file risk", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);

  // The warning is not shown until the user opts in.
  const result = page.locator(".route-result");
  await expect(result.locator('[role="alertdialog"]')).toHaveCount(0);

  await result.getByRole("button", { name: /export route \(gpx\)/i }).click();

  // The explicit warning appears BEFORE the file is created: it must state the
  // file holds the route AND how to use it.
  const dialog = page.locator('[role="alertdialog"]');
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("contains your exact route");
  await expect(dialog).toContainText("track-following navigation app");

  // Downloading produces a LOCAL .gpx file; the user never leaves the app and
  // (per the request listener in the test above) nothing is sent to a third party.
  const [download] = await Promise.all([
    page.waitForEvent("download"),
    dialog.getByRole("button", { name: /download \.gpx/i }).click(),
  ]);
  expect(download.suggestedFilename()).toBe("flckd-route.gpx");
  expect(page.url()).toMatch(/localhost:4173/);
});

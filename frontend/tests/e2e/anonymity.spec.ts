import { test, expect } from "@playwright/test";
import { mockApi, planRoute } from "./helpers";

// T046 (US2): the full flow makes ZERO third-party network requests, and the
// open-in-maps handoff warns the user before any external navigation.

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

test("warns before handing off to an external maps provider", async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
  await planRoute(page);

  // The warning is not shown until the user opts in.
  const handoff = page.locator(".route-result");
  await expect(handoff.locator('[role="alertdialog"]')).toHaveCount(0);

  await handoff.getByRole("button", { name: /open in maps/i }).click();

  // Now the explicit pre-handoff warning appears BEFORE any external link.
  const dialog = page.locator('[role="alertdialog"]');
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("shares this route's locations");

  // External links exist but target a new tab — the user has not left the app.
  await expect(dialog.getByRole("link", { name: "Apple Maps" })).toHaveAttribute("target", "_blank");
  await expect(dialog.getByRole("link", { name: "Google Maps" })).toHaveAttribute(
    "href",
    /google\.com\/maps/
  );
  expect(page.url()).toMatch(/localhost:4173/);
});

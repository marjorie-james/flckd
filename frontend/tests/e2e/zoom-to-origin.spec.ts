import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import { mockApi, ORIGIN, DEST } from "./helpers";

// Feature 007: selecting a starting address recenters the map on it at street
// level and drops a single marker. Reads the in-page map via the opt-in
// window.__flckdMap hook (set only when window.__E2E__ is true).
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    (window as unknown as { __E2E__: boolean }).__E2E__ = true;
  });
  await mockApi(page);
  await page.goto("/");
});

const originInput = (page: Page) => page.locator('.route-panel input[inputmode="search"]').nth(0);

// Clicks the suggestion matching expectedLabel (not just the first button):
// useGeocodeSearch keeps previous data, so the list briefly shows the prior
// query's result before the new one loads — matching by text avoids a stale click.
async function selectOrigin(page: Page, query: string, expectedLabel: string) {
  await originInput(page).fill(query);
  const option = page.locator(".suggestions li button", { hasText: expectedLabel }).first();
  await option.waitFor({ state: "visible" });
  await option.click();
}

const mapZoom = (page: Page) =>
  page.evaluate(() => Math.round((window as unknown as { __flckdMap: { getZoom(): number } }).__flckdMap.getZoom()));

const mapCenter = (page: Page) =>
  page.evaluate(() => {
    const c = (window as unknown as { __flckdMap: { getCenter(): { lng: number; lat: number } } }).__flckdMap.getCenter();
    return { lng: c.lng, lat: c.lat };
  });

// Count markers via the source's official async getData(), which reflects the
// latest setData. (querySourceFeatures duplicates across tiles; serialize() and
// _options.data return the source's creation-time data — both unreliable here.)
const originMarkerCount = (page: Page) =>
  page.evaluate(async () => {
    const map = (window as unknown as {
      __flckdMap: { getSource(id: string): { getData?: () => Promise<{ features?: unknown[] }> } | undefined };
    }).__flckdMap;
    const src = map.getSource("origin");
    if (!src?.getData) return 0;
    const data = await src.getData();
    return data && Array.isArray(data.features) ? data.features.length : 0;
  });

// Poll until the map has settled centered near the target (flyTo animates, and
// zoom may already be 16 from a prior selection, so we wait on the center).
async function expectCenteredNear(page: Page, target: { lng: number; lat: number }, timeout = 5000) {
  await expect
    .poll(
      async () => {
        const c = await mapCenter(page);
        return Math.abs(c.lng - target.lng) < 0.02 && Math.abs(c.lat - target.lat) < 0.02;
      },
      { timeout },
    )
    .toBe(true);
}

test("recenters on the selected starting address at street level with one marker", async ({ page }) => {
  await selectOrigin(page, "iowa state", ORIGIN.label);

  // Centered on the address within 1.5 s of selection (SC-001).
  await expectCenteredNear(page, ORIGIN, 1500);
  await expect.poll(() => mapZoom(page)).toBe(16);
  await expect.poll(() => originMarkerCount(page)).toBe(1);
});

test("keeps one marker at a consistent zoom when a different address is selected", async ({ page }) => {
  await selectOrigin(page, "iowa state", ORIGIN.label);
  await expectCenteredNear(page, ORIGIN);

  await selectOrigin(page, "blank park", DEST.label);
  await expectCenteredNear(page, DEST); // moved to the new address...
  await expect.poll(() => mapZoom(page)).toBe(16); // ...settling at the same street-level zoom
  await expect.poll(() => originMarkerCount(page)).toBe(1); // still exactly one
});

test("keeps manual map control after recentering (FR-008)", async ({ page }) => {
  await selectOrigin(page, "iowa state", ORIGIN.label);
  await expectCenteredNear(page, ORIGIN, 1500);
  const before = await mapCenter(page);

  // A real user drag must still pan the map — recentering does not lock it.
  const box = (await page.locator(".map-view").boundingBox())!;
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  await page.mouse.move(cx, cy);
  await page.mouse.down();
  await page.mouse.move(cx - 160, cy, { steps: 8 });
  await page.mouse.up();

  await expect
    .poll(async () => Math.abs((await mapCenter(page)).lng - before.lng) > 0.0005)
    .toBe(true);
});

test("removes the marker when the starting address is cleared", async ({ page }) => {
  await selectOrigin(page, "iowa state", ORIGIN.label);
  await expect.poll(() => originMarkerCount(page)).toBe(1);

  await originInput(page).fill(""); // clear the field → origin unset
  await expect(originInput(page)).toHaveValue(""); // onChange fired
  await expect.poll(() => originMarkerCount(page)).toBe(0);
});

test("does not move the map while typing without selecting (FR-005)", async ({ page }) => {
  // The map frames on the covered region on load (async, when /coverage/bounds
  // resolves), zooming in from the neutral default. Wait for that one allowed move
  // to settle before snapshotting, so we measure stillness during typing — not the
  // initial framing.
  await expect.poll(() => mapZoom(page)).toBeGreaterThan(2);

  const before = { zoom: await mapZoom(page), center: await mapCenter(page) };

  await originInput(page).fill("iowa"); // suggestions appear; do not click one
  await page.locator(".suggestions li button").first().waitFor({ state: "visible" });

  expect(await mapZoom(page)).toBe(before.zoom);
  expect(await mapCenter(page)).toEqual(before.center);
});

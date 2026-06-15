import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import { mockApi } from "./helpers";

// Feature 008: known cameras in the viewport render (clustered) on the real map.
// A dense group near the dev default view + one disputed camera.
const CLUSTER_CENTER = { lng: -93.6, lat: 41.6 };
function cameraFixtures() {
  const cams = Array.from({ length: 8 }, (_, i) => ({
    id: i + 1,
    location: { lat: 41.6 + (i % 4) * 0.0006, lng: -93.6 + Math.floor(i / 4) * 0.0006 },
    camera_type: "flock",
    confidence: 0.9,
    verification_status: "verified",
  }));
  cams.push({
    id: 99, location: { lat: 41.605, lng: -93.61 },
    camera_type: "flock", confidence: 0.3, verification_status: "disputed",
  });
  return cams;
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => { (window as unknown as { __E2E__: boolean }).__E2E__ = true; });
  await mockApi(page);
  // Override the empty /cameras stub from mockApi (last route wins).
  await page.route("**/api/v1/cameras**", (route) => route.fulfill({ json: { cameras: cameraFixtures() } }));
  await page.goto("/");
  await page.locator(".map-view").waitFor({ state: "visible" });
});

const sourceCount = (page: Page) =>
  page.evaluate(async () => {
    const src = (window as unknown as {
      __flckdMap: { getSource(id: string): { getData?: () => Promise<{ features?: unknown[] }> } | undefined };
    }).__flckdMap.getSource("cameras");
    if (!src?.getData) return 0;
    const d = await src.getData();
    return d?.features?.length ?? 0;
  });

// Click the map canvas at the projected pixel of a lng/lat.
async function clickAt(page: Page, lng: number, lat: number) {
  const canvas = page.locator(".maplibregl-canvas");
  const box = (await canvas.boundingBox())!;
  const px = await page.evaluate(([lng, lat]) => {
    const p = (window as unknown as { __flckdMap: { project(c: [number, number]): { x: number; y: number } } }).__flckdMap.project([lng, lat]);
    return [p.x, p.y];
  }, [lng, lat] as [number, number]);
  await page.mouse.click(box.x + px[0], box.y + px[1]);
}

test("renders the viewport's cameras on the map within 1s (SC-001)", async ({ page }) => {
  await expect.poll(() => sourceCount(page), { timeout: 1500 }).toBe(9);
});

test("re-fetches cameras when the map is panned (FR-002)", async ({ page }) => {
  let requests = 0;
  page.on("request", (r) => { if (r.url().includes("/api/v1/cameras")) requests++; });
  await expect.poll(() => sourceCount(page)).toBe(9); // initial load
  const before = requests;
  await page.evaluate(() => (window as unknown as { __flckdMap: { panBy(o: [number, number]): void } }).__flckdMap.panBy([300, 300]));
  await expect.poll(() => requests).toBeGreaterThan(before);
});

test("opens a details popup on camera click and dismisses it via Esc (FR-006/SC-010)", async ({ page }) => {
  await expect.poll(() => sourceCount(page)).toBe(9);
  // Center on the disputed camera and zoom in so it's an unclustered point, then click it.
  const disputed = { lng: -93.61, lat: 41.605 };
  await page.evaluate((c) => (window as unknown as { __flckdMap: { jumpTo(o: unknown): void } }).__flckdMap.jumpTo({ center: [c.lng, c.lat], zoom: 18 }), disputed);
  await page.waitForTimeout(400);
  await clickAt(page, disputed.lng, disputed.lat);

  const popup = page.locator(".maplibregl-popup");
  await expect(popup).toBeVisible();
  await expect(popup).toContainText("Status: disputed");

  await page.keyboard.press("Escape");
  await expect(popup).toHaveCount(0);
});

test("expands a cluster on tap (FR-005)", async ({ page }) => {
  await expect.poll(() => sourceCount(page)).toBe(9);
  const zoom = () => page.evaluate(() => Math.round((window as unknown as { __flckdMap: { getZoom(): number } }).__flckdMap.getZoom()));
  // Default view (zoom 7) clusters the group; clicking it zooms in.
  await clickAt(page, CLUSTER_CENTER.lng, CLUSTER_CENTER.lat);
  await expect.poll(zoom).toBeGreaterThan(7);
});

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

const renderedFeatureCount = (page: Page, lng: number, lat: number, layers: string[]) =>
  page.evaluate(({ lng, lat, layers }) => {
    const map = (window as unknown as {
      __flckdMap: {
        project(c: [number, number]): { x: number; y: number };
        queryRenderedFeatures(p: [number, number], o: { layers: string[] }): unknown[];
      };
    }).__flckdMap;
    const p = map.project([lng, lat]);
    return map.queryRenderedFeatures([p.x, p.y], { layers }).length;
  }, { lng, lat, layers });

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
  await expect.poll(() => renderedFeatureCount(page, disputed.lng, disputed.lat, ["camera-points", "camera-cones"])).toBeGreaterThan(0);
  await clickAt(page, disputed.lng, disputed.lat);

  const popup = page.locator(".maplibregl-popup");
  await expect(popup).toBeVisible();
  // Assert on the structured label/value markup, not concatenated textContent
  // (the row() helper renders separate spans with no colon separator).
  // Labels come from the en locale file; this test runs in the default English locale.
  const statusRow = popup.locator('.camera-popup__row', {
    has: page.locator('.camera-popup__k', { hasText: /^Status$/ }),
  });
  await expect(statusRow.locator('.camera-popup__v')).toHaveText('disputed');

  await page.keyboard.press("Escape");
  await expect(popup).toHaveCount(0);
});

test("expands a cluster on tap (FR-005)", async ({ page }) => {
  await expect.poll(() => sourceCount(page)).toBe(9);
  const zoom = () => page.evaluate(() => Math.round((window as unknown as { __flckdMap: { getZoom(): number } }).__flckdMap.getZoom()));
  const initialZoom = await zoom();
  await expect.poll(() => renderedFeatureCount(page, CLUSTER_CENTER.lng, CLUSTER_CENTER.lat, ["camera-clusters"])).toBeGreaterThan(0);
  await clickAt(page, CLUSTER_CENTER.lng, CLUSTER_CENTER.lat);
  await expect.poll(zoom).toBeGreaterThan(initialZoom);
});

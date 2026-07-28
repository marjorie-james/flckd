import { test, expect } from "@playwright/test";
import { mockApi } from "./helpers";
import { readdirSync, readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// T073: mobile first-contentful-paint budget + JS bundle budget.

// Emulate a mid-tier mobile viewport for the FCP measurement.
test.use({ viewport: { width: 393, height: 851 } });

test("mobile first-contentful-paint is under 2.5 s", async ({ page }) => {
  await mockApi(page);
  await page.goto("/", { waitUntil: "load" });

  // The paint-timing entry is buffered asynchronously after the first
  // contentful paint. A single synchronous read right after `load` can
  // miss it in headless Chromium. Use a PerformanceObserver with
  // `buffered: true` to pick up already-recorded entries and wait for
  // late ones, with a 5 s ceiling so the test fails cleanly if FCP
  // genuinely never fires.
  const fcp = await page.evaluate(() =>
    new Promise<number | null>((resolve) => {
      const existing = performance.getEntriesByName("first-contentful-paint")[0];
      if (existing) return resolve(existing.startTime);
      const observer = new PerformanceObserver((list) => {
        const e = list.getEntriesByName("first-contentful-paint")[0];
        if (e) { observer.disconnect(); resolve(e.startTime); }
      });
      observer.observe({ type: "paint", buffered: true });
      setTimeout(() => { observer.disconnect(); resolve(null); }, 5_000);
    })
  );

  expect(fcp, "first-contentful-paint entry should be recorded").not.toBeNull();
  expect(fcp!).toBeLessThan(2500);
});

test("shipped JS bundle stays within the gzip budget", async () => {
  // Budget: 500 KB gzipped across all emitted JS chunks.
  const BUDGET_BYTES = 500 * 1024;
  const distAssets = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "dist", "assets");

  const jsFiles = readdirSync(distAssets).filter((f) => f.endsWith(".js"));
  expect(jsFiles.length, "expected a built bundle in dist/assets (run pnpm build)").toBeGreaterThan(0);

  const totalGzip = jsFiles.reduce(
    (sum, f) => sum + gzipSync(readFileSync(join(distAssets, f))).length,
    0
  );

  expect(
    totalGzip,
    `JS bundle is ${(totalGzip / 1024).toFixed(0)} KB gzipped (budget ${BUDGET_BYTES / 1024} KB)`
  ).toBeLessThan(BUDGET_BYTES);
});

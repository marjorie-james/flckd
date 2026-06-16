import { test, expect } from "@playwright/test";
import { mockApi, planRoute } from "./helpers";

// T055 (US3): switching language updates all UI — including directions — and
// preserves in-progress route input.
test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await page.goto("/");
});

test("switches language at runtime, localizing UI and directions, preserving input", async ({
  page,
}) => {
  await planRoute(page);

  // English baseline.
  await expect(page.locator(".route-result h3")).toHaveText("Directions");
  await expect(page.locator("ol.directions li").first()).toHaveText("Head north on Main St");

  // Capture the in-progress origin input before switching.
  const originInput = page.locator('.route-panel input[inputmode="search"]').nth(0);
  const originBefore = await originInput.inputValue();
  expect(originBefore).toContain("Iowa State Capitol");

  // Switch to Spanish.
  await page.locator(".language-switcher select").selectOption("es");

  // UI chrome localizes immediately.
  await expect(page.locator("h1")).toHaveText("Planificador de rutas que evita cámaras");
  await expect(page.locator(".route-panel button[type=submit]")).toHaveText("Planificar ruta");
  await expect(page.locator(".route-result h3")).toHaveText("Indicaciones");

  // In-progress input is preserved across the switch (state, not URL).
  await expect(originInput).toHaveValue(originBefore);

  // Re-planning returns server-localized directions in the new language.
  await page.locator('.route-panel button[type="submit"]').click();
  await expect(page.locator("ol.directions li").first()).toHaveText("Dirígete al norte por Main St");
});

// US1 (FR-001/001a, SC-001): with a Spanish-first browser, the interface renders
// in Spanish from the first load — no manual step, no flash of English. Because
// the language is resolved synchronously before the first render, the first
// queryable state is already Spanish and <html lang> is "es".
test.describe("first paint follows the environment", () => {
  test.use({ locale: "es-ES" });

  test("renders Spanish on first load with no manual selection", async ({ page }) => {
    await expect(page.locator("h1")).toHaveText("Planificador de rutas que evita cámaras");
    await expect(page.locator("html")).toHaveAttribute("lang", "es");
  });
});

// US2 (FR-007/008, SC-004): an explicit choice is remembered on-device across a
// reload and overrides the (English) environment guess; choosing "Automatic"
// clears it and reverts to the environment-derived language.
test("remembers an explicit choice across reload and reverts on Automatic", async ({ page }) => {
  await expect(page.locator("h1")).toHaveText("Camera-Avoiding Route Planner");

  await page.locator(".language-switcher select").selectOption("es");
  await expect(page.locator("h1")).toHaveText("Planificador de rutas que evita cámaras");

  // Persisted: a reload keeps Spanish even though the browser advertises English.
  await page.reload();
  await expect(page.locator("h1")).toHaveText("Planificador de rutas que evita cámaras");

  // Automatic: forget the choice, re-derive from the environment (English).
  await page.locator(".language-switcher select").selectOption("auto");
  await expect(page.locator("h1")).toHaveText("Camera-Avoiding Route Planner");
  await page.reload();
  await expect(page.locator("h1")).toHaveText("Camera-Avoiding Route Planner");
});

// US3 (FR-010, AS3; Constitution IV): map labels follow the selected language and
// update in place at runtime — a single setLayoutProperty per label layer, no
// page reload and no network — so the switch is well within the performance
// budget. We assert the label expression's selected-language field flips en → es.
test("map labels follow the selected language at runtime without reload", async ({ page }) => {
  await page.addInitScript(() => {
    (window as unknown as { __E2E__?: boolean }).__E2E__ = true;
  });
  await page.reload(); // re-create the map with the E2E map hook exposed

  const roadLabelField = () =>
    page.evaluate(() => {
      const map = (window as unknown as { __flckdMap?: { getLayoutProperty(id: string, p: string): unknown } })
        .__flckdMap;
      if (!map) return null;
      try {
        return JSON.stringify(map.getLayoutProperty("road-labels", "text-field"));
      } catch {
        return null;
      }
    });

  await expect.poll(roadLabelField).toContain("name:en");

  await page.locator(".language-switcher select").selectOption("es");
  await expect.poll(roadLabelField, { timeout: 2000 }).toContain("name:es");
});

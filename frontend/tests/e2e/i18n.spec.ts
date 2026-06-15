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

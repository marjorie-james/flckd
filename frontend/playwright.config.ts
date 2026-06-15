import { defineConfig, devices } from "@playwright/test";

// E2E config for the Camera-Avoiding Route Planner SPA.
//
// Determinism (Constitution Principle II): every test stubs the backend API and
// the self-hosted tiles via `page.route` (see tests/e2e/helpers.ts), so the
// suite needs no live geo stack and makes ZERO third-party requests. The tests
// run against the production build served by `vite preview`.
export default defineConfig({
  testDir: "./tests/e2e",
  testMatch: "**/*.spec.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"]],
  use: {
    baseURL: "http://localhost:4173",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    // `pnpm build` runs before the suite (see the e2e Docker image / CI step);
    // preview serves the static dist with no backend.
    command: "pnpm preview --port 4173 --strictPort --host",
    url: "http://localhost:4173",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});

import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/e2e",
  testMatch: "admin_editorial_ui.spec.ts",
  outputDir: "../../output/admin-catalog-20261028/editorial/test-results",
  workers: 1,
  timeout: 45000,
  use: {
    baseURL: "http://127.0.0.1:5187",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "npm run dev -- --port 5187 --strictPort",
    url: "http://127.0.0.1:5187",
    reuseExistingServer: false,
  },
});

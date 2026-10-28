import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/e2e",
  testMatch: "card_duplicate_warning.spec.ts",
  outputDir: "../../output/admin-duplicate-warning-20261028/browser",
  workers: 1,
  timeout: 45000,
  use: {
    baseURL: "http://127.0.0.1:5193",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "npm run dev -- --port 5193 --strictPort",
    url: "http://127.0.0.1:5193",
    reuseExistingServer: false,
  },
});

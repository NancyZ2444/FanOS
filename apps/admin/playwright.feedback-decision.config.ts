import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/e2e",
  testMatch: "feedback-decision-ui.spec.ts",
  outputDir: "../../output/admin-feedback-decision-20261028/test-results",
  workers: 1,
  timeout: 45000,
  use: {
    baseURL: "http://127.0.0.1:5191",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "npm run dev -- --port 5191 --strictPort",
    url: "http://127.0.0.1:5191",
    reuseExistingServer: false,
  },
});

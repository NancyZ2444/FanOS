import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "tests/e2e",
  testMatch: "admin_scan_selection.spec.ts",
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:5185",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "npm run dev -- --port 5185 --strictPort",
    url: "http://127.0.0.1:5185",
    reuseExistingServer: false,
  },
});

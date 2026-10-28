import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/e2e",
  testMatch: "auth_v15_ui.spec.ts",
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:5176",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "npm run dev -- --port 5176",
    url: "http://127.0.0.1:5176",
    reuseExistingServer: false,
  },
});

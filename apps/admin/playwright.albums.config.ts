import { defineConfig } from "@playwright/test";

// Use the disposable album API, never the user's development database on port 8000.
export default defineConfig({
  testDir: "./tests/e2e",
  testMatch: "digital_albums.spec.ts",
  workers: 1,
  use: {
    channel: 'chrome',
    baseURL: "http://127.0.0.1:5181",
    headless: true,
    viewport: { width: 1440, height: 1000 },
  },
  webServer: {
    command:
      "API_PROXY_TARGET=http://127.0.0.1:18001 npm run dev -- --port 5181 --strictPort",
    url: "http://127.0.0.1:5181",
    reuseExistingServer: false,
  },
});

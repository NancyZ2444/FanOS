import { defineConfig } from "@playwright/test";
import { mkdirSync, mkdtempSync } from "node:fs";
import { resolve } from "node:path";
mkdirSync(resolve(".test-data"), { recursive: true });
const testRoot = mkdtempSync(resolve(".test-data/run-"));
const python = process.env.API_PYTHON || "../api/.venv/bin/python";
export default defineConfig({
  testDir: "tests/e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 45000,
  use: {
    baseURL: "http://127.0.0.1:5174",
    viewport: { width: 1440, height: 1000 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    launchOptions: process.env.PLAYWRIGHT_EXECUTABLE_PATH
      ? { executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH }
      : {},
  },
  webServer: [
    {
      command: `${python} -m uvicorn app.main:app --app-dir ../api --host 127.0.0.1 --port 8011`,
      url: "http://127.0.0.1:8011/health",
      reuseExistingServer: false,
      env: {
        DATABASE_URL: `sqlite:///${testRoot}/admin-e2e.db`,
        LOCAL_MEDIA_ROOT: `${testRoot}/uploads`,
        PUBLIC_MEDIA_BASE_URL: "http://127.0.0.1:8011/media",
        CARD_MATCHER_INDEX_PATH: `${testRoot}/index.json`,
        AUTO_SEED: "true",
      },
    },
    {
      command: "npm run dev -- --port 5174",
      url: "http://127.0.0.1:5174",
      reuseExistingServer: false,
      env: { API_PROXY_TARGET: "http://127.0.0.1:8011" },
    },
  ],
});

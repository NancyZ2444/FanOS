import { defineConfig } from "@playwright/test";
import { mkdirSync, mkdtempSync } from "node:fs";
import { resolve } from "node:path";

mkdirSync(resolve(".test-data"), { recursive: true });
const testRoot = mkdtempSync(resolve(".test-data/albums-p0-"));
export default defineConfig({
  testDir: "./tests/e2e",
  testMatch: ["digital_albums_p0_acceptance.spec.ts", "digital_albums.spec.ts"],
  workers: 1,
  timeout: 90000,
  use: {
    channel: "chrome",
    baseURL: "http://127.0.0.1:5183",
    headless: true,
    viewport: { width: 1440, height: 1000 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  webServer: [
    {
      command:
        "../api/.venv/bin/python -m uvicorn app.main:app --app-dir ../api --host 127.0.0.1 --port 18102",
      url: "http://127.0.0.1:18102/health",
      reuseExistingServer: false,
      env: {
        DATABASE_URL: `sqlite:///${testRoot}/albums-p0.db`,
        LOCAL_MEDIA_ROOT: `${testRoot}/uploads`,
        PUBLIC_MEDIA_BASE_URL: "http://127.0.0.1:18102/media",
        CARD_MATCHER_INDEX_PATH: `${testRoot}/index.json`,
        AUTO_SEED: "true",
        DEV_PHONE_CODE: "123456",
      },
    },
    {
      command: "npm run dev -- --port 5183 --strictPort",
      url: "http://127.0.0.1:5183",
      reuseExistingServer: false,
      env: { API_PROXY_TARGET: "http://127.0.0.1:18102" },
    },
  ],
});

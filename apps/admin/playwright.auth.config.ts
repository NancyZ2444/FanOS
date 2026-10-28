import { defineConfig } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { mkdirSync, mkdtempSync } from "node:fs";
import { resolve } from "node:path";
mkdirSync(resolve(".test-data"), { recursive: true });
const root = mkdtempSync(resolve(".test-data/auth-"));
process.env.AUTH_E2E_PASSWORD ||= `Test-${randomUUID()}`;
export default defineConfig({
  testDir: "tests/e2e",
  testMatch: "auth_v15_live.spec.ts",
  workers: 1,
  timeout: 60000,
  use: {
    baseURL: "http://127.0.0.1:5177",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    trace: "off",
  },
  webServer: [
    {
      command: "../api/.venv/bin/python tests/e2e/start-auth-api.py",
      url: "http://127.0.0.1:8016/health",
      reuseExistingServer: false,
      env: {
        DATABASE_URL: `sqlite:///${root}/auth.db`,
        AUTH_E2E_PASSWORD: process.env.AUTH_E2E_PASSWORD!,
        AUTO_SEED: "true",
        ENVIRONMENT: "test",
        LOCAL_MEDIA_ROOT: `${root}/media`,
        CARD_MATCHER_INDEX_PATH: `${root}/index.json`,
      },
    },
    {
      command: "npm run dev -- --port 5177",
      url: "http://127.0.0.1:5177",
      reuseExistingServer: false,
      env: { API_PROXY_TARGET: "http://127.0.0.1:8016" },
    },
  ],
});

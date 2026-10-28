import { defineConfig } from "@playwright/test";
import base from "./playwright.config";

export default defineConfig({
  ...base,
  testMatch: [
    "feedback-closure.spec.ts",
    "feedback-interactions.spec.ts",
    "feedback-ui.spec.ts",
  ],
  timeout: 90000,
  use: { ...base.use, channel: "chrome" },
  webServer: (base.webServer as Array<{ command: string }>).map(
    (server, index) =>
      index === 0
        ? {
            ...server,
            command: `${process.env.API_PYTHON || "../api/.venv/bin/python"} tests/e2e/start-feedback-api.py`,
          }
        : server,
  ),
});

import { defineConfig } from "@playwright/test";
import auth from "./playwright.auth.config";

// Reuse the isolated auth acceptance server; never target the developer database.
export default defineConfig({
  ...auth,
  testMatch: "missing-catalog.spec.ts",
  webServer: Array.isArray(auth.webServer) ? auth.webServer.map((server, index) => index === 0
    ? { ...server, env: { ...server.env, PUBLIC_MEDIA_BASE_URL: "http://127.0.0.1:8016/media" } }
    : server) : auth.webServer,
});

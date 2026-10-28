import { defineConfig } from "@playwright/test";
import base from "./playwright.auth.config";
export default defineConfig({
  ...base,
  testMatch: "company_permissions_live.spec.ts",
  outputDir: "test-results/company-permissions",
});

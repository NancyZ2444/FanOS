import { defineConfig } from "@playwright/test";
import base from "./playwright.albums-p0.config";

export default defineConfig({
  ...base,
  testMatch: ["digital_albums_v11.spec.ts"],
});

import { test, expect } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
const stage = process.env.UI_AUDIT_STAGE || "after";
const routes = [
  "dashboard",
  "catalog/cards",
  "catalog/groups",
  "catalog/idols",
  "catalog/albums",
  "catalog/events",
  "catalog/others",
  "catalog/companies",
  "catalog/tags",
  "catalog/workbench",
  "catalog/review",
  "catalog/scan",
  "catalog/import",
  "reviews/sources",
  "operations/social",
  "operations/accounts",
  "operations/comments",
  "operations/daily",
  "operations/draws",
  "operations/notifications",
  "operations/announcements",
  "operations/users",
  "operations/reports",
  "digital-albums",
  "system/admins",
  "system/roles",
  "system/logs",
  "catalog/groups/group-lumina/detail",
  "catalog/cards/new",
];
for (const width of [1280, 1440, 1920])
  test(`all pages at ${width}`, async ({ page }) => {
    test.setTimeout(180000);
    const dest = resolve(
      "../../output/admin-ui-20261013",
      stage,
      String(width),
    );
    mkdirSync(dest, { recursive: true });
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/catalog/cards");
    await page.getByRole("button", { name: "填入账号" }).click();
    await page.getByRole("button", { name: "进入工作台" }).click();
    await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    for (const route of routes) {
      await page.goto("/" + route);
      await expect(page.locator("main h1, main h2").first()).toBeVisible();
      await expect(page.locator(".ant-skeleton")).toHaveCount(0);
      await expect(page.locator(".ant-spin-spinning")).toHaveCount(0);
      await page.waitForLoadState("networkidle");
      if (stage === "after") {
        expect(
          await page.locator(".toolbar-actions").evaluateAll((groups) =>
            groups.flatMap((group) => {
              const controls = [...group.querySelectorAll("button")].filter(
                (el) =>
                  el.getBoundingClientRect().width > 0 &&
                  getComputedStyle(el).visibility !== "hidden",
              );
              return controls.flatMap((el, i) =>
                controls
                  .slice(i + 1)
                  .filter((other) => {
                    const a = el.getBoundingClientRect(),
                      b = other.getBoundingClientRect();
                    return (
                      Math.min(a.right, b.right) - Math.max(a.left, b.left) >
                        1 &&
                      Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1
                    );
                  })
                  .map((other) => `${el.textContent} / ${other.textContent}`),
              );
            }),
          ),
          route + " 工具栏按钮重叠",
        ).toEqual([]);
        expect(
          await page
            .locator(".toolbar-actions .ant-btn")
            .evaluateAll((buttons) =>
              buttons
                .filter((el) => el.getBoundingClientRect().width > 0)
                .map((el) => parseFloat(getComputedStyle(el).height))
                .filter((h) => ![28, 36].includes(h)),
            ),
          route + " 按钮高度",
        ).toEqual([]);
      }
      await page.screenshot({
        animations: "disabled",
        path: resolve(dest, route.replaceAll("/", "-") + ".png"),
        fullPage: true,
      });
      if (stage === "after")
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth,
          ),
          route,
        ).toBeTruthy();
    }
    await page.goto("/catalog/groups?create=true");
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(page.locator(".ant-spin-spinning")).toHaveCount(0);
    await page.screenshot({
      animations: "disabled",
      path: resolve(dest, "group-form.png"),
      fullPage: true,
    });
    if (stage === "after") expect(errors).toEqual([]);
  });

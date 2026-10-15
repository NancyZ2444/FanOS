import { test, expect, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { setupFeedback } from "./feedback-fixtures";
const stage = process.env.FEEDBACK_UI_STAGE || "after";
const output = resolve("../../output/feedback-ui-20261014", stage);
async function checkLayout(page: Page) {
  if (stage === "before") return;
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - innerWidth,
    ),
  ).toBeLessThanOrEqual(1);
  expect(
    await page.locator("main .ant-btn").evaluateAll((buttons) =>
      buttons
        .filter((el) => el.getBoundingClientRect().width > 0)
        .map((el) => getComputedStyle(el).height)
        .filter((height) => !["28px", "36px"].includes(height)),
    ),
  ).toEqual([]);
  for (const group of await page
    .locator(".feedback-footer, .toolbar-actions, .page-heading-actions")
    .all()) {
    expect(await group.locator(".ant-btn-primary").count()).toBeLessThanOrEqual(
      1,
    );
    const boxes = await group.locator(".ant-btn").evaluateAll((buttons) =>
      buttons.map((el) => {
        const r = el.getBoundingClientRect();
        return { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
      }),
    );
    for (let i = 0; i < boxes.length; i++)
      for (let j = i + 1; j < boxes.length; j++) {
        const a = boxes[i],
          b = boxes[j];
        expect(
          Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
            Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1,
        ).toBe(false);
      }
  }
}

test("feedback lists and review details at three widths", async ({
  page,
  request,
}) => {
  test.setTimeout(180000);
  const setup = await setupFeedback(request, page);
  const missing = await setup.createMissing();
  const correction = await setup.createCorrection();
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  for (const width of [1280, 1440, 1920]) {
    mkdirSync(resolve(output, String(width)), { recursive: true });
    await page.setViewportSize({ width, height: 1000 });
    for (const [route, row] of [
      ["missing-cards", missing],
      ["corrections", correction],
    ] as const) {
      await page.goto("/catalog/" + route);
      const record = page
        .locator(".ant-table-tbody tr")
        .filter({ hasText: row.id });
      await expect(record).toBeVisible();
      await checkLayout(page);
      await page.screenshot({
        path: resolve(output, String(width), route + "-list.png"),
        fullPage: true,
        animations: "disabled",
      });
      await record.getByRole("button", { name: row.name, exact: true }).click();
      if (stage === "before")
        await expect(page.getByRole("dialog")).toBeVisible();
      else {
        await expect(page).toHaveURL(new RegExp("/" + row.id));
        await expect(
          page.getByRole("heading", { name: "基本信息", exact: true }),
        ).toBeVisible();
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth - innerWidth,
          ),
        ).toBeLessThanOrEqual(1);
      }
      await checkLayout(page);
      await page.screenshot({
        path: resolve(output, String(width), route + "-detail.png"),
        fullPage: true,
        animations: "disabled",
      });
      if (stage !== "before") {
        await page.getByRole("button", { name: "编辑", exact: true }).click();
        await checkLayout(page);
        await page.screenshot({
          path: resolve(output, String(width), route + "-edit.png"),
          fullPage: true,
          animations: "disabled",
        });
      }
    }
  }
  expect(errors).toEqual([]);
});

import { expect, test, type APIResponse } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const root = "http://127.0.0.1:8016/api/v1";
const output = resolve("../../output/admin-company-permissions-20261028");
async function data(response: APIResponse) {
  expect(
    response.ok(),
    `API returned ${response.status()}: ${await response.text()}`,
  ).toBeTruthy();
  return (await response.json()).data;
}
test.beforeEach(async ({ page, request }) => {
  const session = await data(
    await request.post(root + "/admin/auth/login", {
      data: {
        account: "auth-e2e-admin",
        password: process.env.AUTH_E2E_PASSWORD,
      },
    }),
  );
  await page.addInitScript(
    (value) =>
      sessionStorage.setItem("fanos-admin-session", JSON.stringify(value)),
    session,
  );
  mkdirSync(output, { recursive: true });
});

test("role checkboxes save and persist with superadmin recovery access", async ({
  page,
}) => {
  await page.goto("/system/roles");
  const edit = page.getByRole("checkbox", {
    name: "内容运营：图鉴新增、编辑与导入",
    exact: true,
  });
  await expect(edit).toBeChecked();
  await expect(
    page.getByRole("checkbox", {
      name: "超级管理员：角色权限管理",
      exact: true,
    }),
  ).toBeDisabled();
  await edit.uncheck();
  await page.getByRole("button", { name: "保存", exact: true }).click();
  await expect(
    page.getByText("角色权限已保存，相关账号下次操作即生效", { exact: true }),
  ).toBeVisible();
  await page.reload();
  await expect(edit).not.toBeChecked();
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBeTruthy();
    await page.screenshot({
      path: resolve(output, `roles-${width}.png`),
      fullPage: false,
      animations: "disabled",
    });
  }
  await edit.check();
  const saved = page.waitForResponse((response) =>
    response.url().endsWith("/admin/console/roles") && response.request().method() === "PUT");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  expect((await saved).ok()).toBeTruthy();
  await page.reload();
  await expect(edit).toBeChecked();
});

test("company switch persists and controls available group companies", async ({
  page,
}) => {
  const name = "UI 开启公司验收";
  await page.goto("/catalog/companies");
  await page.getByRole("button", { name: "新增公司", exact: true }).first().click();
  const modal = page.getByRole("dialog");
  await modal.getByLabel("名称", { exact: true }).fill(name);
  await expect(
    modal.getByRole("switch", { name: "开启公司", exact: true }),
  ).toBeChecked();
  await modal.getByRole("button", { name: "保存", exact: true }).click();
  await expect(modal).toHaveCount(0);
  const row = page.getByRole("row").filter({ hasText: name });
  await expect(row.getByText("已开启", { exact: true })).toBeVisible();
  await page.goto("/catalog/groups");
  await page.getByRole("button", { name: "新增组合", exact: true }).click();
  await page.getByLabel("所属公司", { exact: true }).click();
  await expect(page.getByText(name, { exact: true }).last()).toBeVisible();
  await page.keyboard.press("Escape");
  await page.goto("/catalog/companies");
  await row.getByRole("button", { name: "编辑", exact: true }).click();
  await modal.getByRole("switch", { name: "开启公司", exact: true }).uncheck();
  await modal.getByRole("button", { name: "保存", exact: true }).click();
  await expect(modal).toHaveCount(0);
  await expect(row.getByText("未开启", { exact: true })).toBeVisible();
  await page.reload();
  await expect(row.getByText("未开启", { exact: true })).toBeVisible();
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBeTruthy();
    await page.screenshot({
      path: resolve(output, `companies-${width}.png`),
      fullPage: true,
      animations: "disabled",
    });
  }
  await page.goto("/catalog/groups");
  await page.getByRole("button", { name: "新增组合", exact: true }).click();
  await page.getByLabel("所属公司", { exact: true }).click();
  await expect(page.getByText(name, { exact: true })).toHaveCount(0);
});

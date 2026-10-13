import { test, expect } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
const root = "http://127.0.0.1:8011/api/v1/admin/console";
const dest = resolve("../../output/admin-ui-20261013/interactions");
mkdirSync(dest, { recursive: true });
test.beforeEach(async ({ page }) => {
  await page.goto("/catalog/groups");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page.getByRole("heading", { name: "组合管理" })).toBeVisible();
});
async function auth(request: any) {
  const res = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  return { Authorization: `Bearer ${(await res.json()).data.access_token}` };
}
test("company create, validation, edit prefill, cancel guard, save failure and delete", async ({
  page,
}) => {
  const name = `UI company ${Date.now()}`;
  await page.goto("/catalog/companies");
  await page
    .getByRole("button", { name: "新增公司", exact: true })
    .first()
    .click();
  const dialog = page.getByRole("dialog");
  await dialog.getByRole("button", { name: "保存", exact: true }).click();
  await expect(dialog.getByText("请填写名称", { exact: true })).toBeVisible();
  await dialog.getByLabel("名称", { exact: true }).fill(name);
  await dialog.getByRole("button", { name: "取消", exact: true }).click();
  await expect(
    page.getByText("放弃未保存的修改？", { exact: true }).last(),
  ).toBeVisible();
  await page.getByRole("button", { name: "继续编辑", exact: true }).click();
  await dialog.getByRole("button", { name: "保存", exact: true }).click();
  await expect(dialog).toHaveCount(0);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await expect(row).toBeVisible();
  await row.getByRole("button", { name: "编辑", exact: true }).click();
  await expect(dialog.getByLabel("名称", { exact: true })).toHaveValue(name);
  await dialog.getByLabel("描述", { exact: true }).fill("修改后保留");
  await page.route("**/records/companies/*", (route) =>
    route.request().method() === "PUT"
      ? route.fulfill({
          status: 500,
          contentType: "application/json",
          body: JSON.stringify({ message: "模拟保存失败" }),
        })
      : route.continue(),
  );
  const failure = page.waitForResponse(
    (r) =>
      r.request().method() === "PUT" && r.url().includes("/records/companies/"),
  );
  await dialog.getByRole("button", { name: "保存", exact: true }).click();
  expect((await failure).status()).toBe(500);
  await expect(
    dialog.getByRole("button", { name: "保存", exact: true }),
  ).not.toHaveClass(/loading/);
  await expect(dialog.getByLabel("描述", { exact: true })).toHaveValue(
    "修改后保留",
  );
  await expect(dialog).toBeVisible();
  await page.unroute("**/records/companies/*");
  await dialog.getByRole("button", { name: "保存", exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await row.getByRole("button", { name: "查看", exact: true }).click();
  await expect(dialog).toContainText("修改后保留");
  await expect(
    dialog.getByRole("button", { name: "编辑", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".ant-message-notice-error")).toHaveCount(0);
  await page.screenshot({
    path: resolve(dest, "company-detail.png"),
    animations: "disabled",
  });
  await dialog.getByRole("button", { name: "关闭", exact: true }).click();
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "删除", exact: true }).click();
  await expect(dialog).toContainText(name);
  await expect(dialog).toContainText("删除不可恢复");
  await page.screenshot({
    path: resolve(dest, "delete-confirm.png"),
    animations: "disabled",
  });
  await dialog.getByRole("button", { name: "取消", exact: true }).click();
  await expect(row).toBeVisible();
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "删除", exact: true }).click();
  await dialog.getByRole("button", { name: "删除", exact: true }).click();
  await expect(row).toHaveCount(0);
});
test("entity unsaved changes, save lock, detail edit and archived relationship blocker", async ({
  page,
  request,
}) => {
  const name = `UI group ${Date.now()}`;
  await page
    .getByRole("button", { name: "新增组合", exact: true })
    .first()
    .click();
  const dialog = page.getByRole("dialog");
  await dialog.getByLabel("组合名称 / 官方名称", { exact: true }).fill(name);
  await dialog.getByRole("button", { name: "取消", exact: true }).click();
  await page.getByRole("button", { name: "继续编辑", exact: true }).click();
  let writes = 0;
  page.on("request", (r) => {
    if (r.method() === "POST" && r.url().endsWith("/entities/groups")) writes++;
  });
  const saved = page.waitForResponse(
    (r) =>
      r.request().method() === "POST" && r.url().endsWith("/entities/groups"),
  );
  await dialog
    .getByRole("button", { name: "保存草稿", exact: true })
    .dblclick();
  const entity = (await (await saved).json()).data;
  await expect(dialog).toHaveCount(0);
  expect(writes).toBe(1);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await row.getByRole("button", { name: "查看", exact: true }).click();
  await page.getByRole("button", { name: "编辑", exact: true }).click();
  await expect(
    dialog.getByLabel("组合名称 / 官方名称", { exact: true }),
  ).toHaveValue(name);
  await dialog.getByLabel("英文名称", { exact: true }).fill("Unsaved");
  await dialog.getByRole("button", { name: "取消", exact: true }).click();
  await page.getByRole("button", { name: "放弃修改", exact: true }).click();
  await expect(dialog).toHaveCount(0);
  const headers = await auth(request);
  const child = await request.post(root + "/entities/idols", {
    headers,
    data: { name: `Member ${name}`, group_id: entity.id },
  });
  expect(child.status()).toBe(200);
  await request.post(root + `/entities/groups/${entity.id}/actions`, {
    headers,
    data: { action: "archive" },
  });
  await page.goto("/catalog/groups");
  await page.getByRole("tab", { name: "已归档", exact: true }).click();
  const blocked = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await blocked.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "删除", exact: true }).click();
  await expect(dialog).toContainText("无法删除");
  await expect(
    dialog.getByRole("link", { name: "查看关联内容并处理" }),
  ).toBeVisible();
  await page.screenshot({
    path: resolve(dest, "delete-blocked.png"),
    animations: "disabled",
  });
});
test("filtered empty table, reset, selection-only batch actions, and batch archive", async ({
  page,
  request,
}) => {
  await expect(page.locator(".entity-batch-bar")).toHaveCount(0);
  await page
    .getByPlaceholder("搜索组合名称、ID…")
    .fill("no-such-group-ui-unique");
  await expect(page.getByText("无匹配结果", { exact: true })).toBeVisible();
  expect(
    await page
      .locator(".ant-table-content")
      .evaluate((el) => el.scrollWidth <= el.clientWidth),
  ).toBeTruthy();
  await page.screenshot({
    path: resolve(dest, "empty-filtered.png"),
    animations: "disabled",
  });
  await page.getByRole("button", { name: "重置筛选", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "LUMINA", exact: true }),
  ).toBeVisible();
  const headers = await auth(request),
    prefix = `UI batch ${Date.now()}`;
  for (let i = 0; i < 2; i++)
    expect(
      (
        await request.post(root + "/entities/groups", {
          headers,
          data: { name: `${prefix} ${i}` },
        })
      ).status(),
    ).toBe(200);
  await page.goto("/catalog/groups");
  await page.getByPlaceholder("搜索组合名称、ID…").fill(prefix);
  await page.locator(".ant-table-thead input[type=checkbox]").check();
  await expect(page.getByText("已选 2 项", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "批量归档", exact: true }).click();
  await page.getByRole("button", { name: "确认操作", exact: true }).click();
  await expect(page.getByText("无匹配结果", { exact: true })).toBeVisible();
  await expect(page.locator(".entity-batch-bar")).toHaveCount(0);
  await page.getByRole("tab", { name: "已归档", exact: true }).click();
  await expect(page.locator(".ant-table-tbody .ant-table-row")).toHaveCount(2);
});
test("quick create equal-width grid and compact control sizes", async ({
  page,
}) => {
  await page.getByRole("button", { name: "快速创建", exact: true }).click();
  const buttons = page.locator(".quick-create-grid .ant-btn");
  await expect(buttons).toHaveCount(9);
  await page.screenshot({
    path: resolve(dest, "quick-create.png"),
    animations: "disabled",
  });
  const rects = await buttons.evaluateAll((nodes) =>
    nodes.map((n) => ({
      w: parseFloat(getComputedStyle(n).width),
      h: parseFloat(getComputedStyle(n).height),
    })),
  );
  expect(new Set(rects.map((r) => Math.round(r.w))).size).toBe(1);
  expect(rects.every((r) => r.h === 36)).toBeTruthy();
  await page.screenshot({
    path: resolve(dest, "quick-create.png"),
    animations: "disabled",
  });
});
test("browser back and sidebar navigation protect unsaved full-page changes", async ({
  page,
}) => {
  await page.getByRole("button", { name: "小卡管理", exact: true }).click();
  await page.getByRole("button", { name: "新增小卡", exact: true }).click();
  await page.locator(".selection-card").filter({ hasText: "LUMINA" }).click();
  await page.goBack();
  await expect(
    page.getByRole("button", { name: "继续编辑", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "继续编辑", exact: true }).click();
  await expect(page).toHaveURL(/cards\/new/);
  await page.getByRole("button", { name: "组合管理", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "放弃修改", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "放弃修改", exact: true }).click();
  await expect(page).toHaveURL(/catalog\/groups$/);
});
test("no data state offers creation without an empty horizontal scrollbar", async ({
  page,
}) => {
  await page.route("**/admin/console/catalog", async (route) => {
    const response = await route.fetch();
    const body = await response.json();
    body.data.groups = [];
    await route.fulfill({ response, json: body });
  });
  await page.goto("/catalog/groups");
  await expect(page.getByText("尚无数据", { exact: true })).toBeVisible();
  const empty = page.locator(".admin-empty");
  await expect(
    empty.getByRole("button", { name: "新增组合", exact: true }),
  ).toBeVisible();
  expect(
    await page
      .locator(".ant-table-content")
      .evaluate((el) => el.scrollWidth <= el.clientWidth),
  ).toBeTruthy();
  await page.screenshot({
    path: resolve(dest, "empty-no-data.png"),
    animations: "disabled",
  });
  await empty.getByRole("button", { name: "新增组合", exact: true }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
});
test("empty cards have no horizontal scrollbar and offer reset", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/catalog/cards");
  await page
    .getByPlaceholder("搜索小卡名称、ID、艺人…")
    .fill("no-card-ui-fixture");
  await expect(page.getByText("无匹配结果", { exact: true })).toBeVisible();
  expect(
    await page
      .locator(".ant-table-content")
      .evaluate((el) => el.scrollWidth <= el.clientWidth),
  ).toBeTruthy();
  await page.getByRole("button", { name: "重置筛选", exact: true }).click();
  await expect(page.locator(".ant-table-row").first()).toBeVisible();
});

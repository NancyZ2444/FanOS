import { test, expect } from "@playwright/test";

test("Other has six inputs; Tag normalization, governance and related content work together", async ({
  page,
  request,
}) => {
  const root = "http://127.0.0.1:8011/api/v1";
  const auth = await request.post(root + "/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await auth.json()).data.access_token}`,
  };
  await page.goto("/catalog/tags");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page.getByRole("heading", { name: "标签管理" })).toBeVisible();
  const name = `Brand ${Date.now()}`;
  await page.getByRole("button", { name: "新增标签" }).first().click();
  const modal = page.getByRole("dialog");
  await modal.locator(".ant-select-selector").first().click();
  await page.getByText("其他来源", { exact: true }).last().click();
  await modal.getByLabel("标签名称", { exact: true }).fill(name);
  await modal.getByRole("button", { name: /保\s*存/ }).click();
  await expect(modal).not.toBeVisible();
  const created = await request.post(root + "/admin/console/entities/others", {
    headers,
    data: {
      name: "Tag Source",
      original_name: "Original Source",
      start_date: "2026-10-11",
      artists: [{ type: "groups", id: "group-lumina" }],
      tags: [name.toLowerCase(), name],
    },
  });
  expect(created.status()).toBe(200);
  const entity = (await created.json()).data;
  expect(entity.tag_ids).toHaveLength(1);
  await page.goto("/catalog/others");
  await page.getByRole("button", { name: "新增其他来源" }).click();
  await expect(page.getByLabel("展示名称", { exact: true })).toBeVisible();
  await expect(page.getByLabel("原始名称", { exact: true })).toBeVisible();
  await expect(page.getByLabel("所属组合", { exact: true })).toHaveCount(0);
  await page
    .getByRole("dialog")
    .getByRole("button", { name: /取\s*消/ })
    .click();
  await page.goto("/catalog/tags");
  await page.getByLabel("搜索标签", { exact: true }).fill(name);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await expect(row).toContainText("1 条关联内容");
  await row.getByRole("button", { name: "1 条关联内容" }).click();
  await expect(page.locator(".ant-drawer")).toContainText("Tag Source");
  await page
    .locator(".ant-drawer")
    .getByRole("button", { name: /查\s*看/ })
    .click();
  await expect(page).toHaveURL(
    new RegExp(`/catalog/others/${entity.id}/detail`),
  );
  await page.goto("/catalog/tags");
  await page.getByLabel("搜索标签", { exact: true }).fill(name);
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "停用", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "停用", exact: true })
    .click();
  await expect(row).toContainText("停用");
  const options = (
    await (await request.get(root + "/catalog/tags?entity_type=OTHER")).json()
  ).data.items;
  expect(options.some((t: any) => t.id === entity.tag_ids[0])).toBe(false);
  const retained = (
    await (
      await request.get(
        root + `/admin/console/entities/others/${entity.id}/detail`,
        { headers },
      )
    ).json()
  ).data.entity;
  expect(retained.tag_ids).toEqual(entity.tag_ids);
  await page.screenshot({
    path: "../../output/catalog-tags-admin.png",
    fullPage: true,
  });
});

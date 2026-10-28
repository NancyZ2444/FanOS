import { test, expect } from "@playwright/test";

// Use the configured UI proxy so this regression can run against an isolated API.
const api = "/api/v1";

test("digital album moderation, limits and system resources work end to end", async ({
  page,
  request,
}) => {
  const auth = await request.post(api + "/auth/login", {
    data: { method: "phone", phone: "13800000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await auth.json()).data.access_token}`,
  };
  const name = `Album E2E ${Date.now()}`;
  const created = await request.post(api + "/albums", {
    headers,
    data: { name },
  });
  const original = (await created.json()).data;
  const changed = await request.patch(`${api}/albums/${original.id}`, {
    headers,
    data: { revision: original.revision, visibility: "PUBLIC" },
  });
  const book = (await changed.json()).data;
  const published = await request.post(`${api}/albums/${book.id}/publish`, {
    headers,
    data: { revision: book.revision },
  });
  expect(published.ok()).toBeTruthy();
  await page.goto("/digital-albums");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(
    page.getByRole("heading", { name: "数字相册", exact: true }),
  ).toBeVisible();
  await page.getByPlaceholder("相册名称", { exact: true }).fill(name);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await row.getByRole("button", { name: /^查\s*看$/ }).click();
  await expect(page.locator(".ant-drawer")).toContainText(book.id);
  await page
    .locator(".ant-drawer")
    .getByRole("button", { name: "关闭", exact: true })
    .click();
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "限制公开", exact: true }).click();
  await page
    .getByPlaceholder("处理原因", { exact: true })
    .fill("自动化测试：复核公开内容");
  await page
    .locator(".ant-modal:visible")
    .getByRole("button", { name: "限制公开", exact: true })
    .click();
  await expect(page.locator(".ant-modal:visible")).toHaveCount(0);
  const drawer = page.locator(".ant-drawer");
  await expect(drawer).toContainText("限制公开");
  expect((await request.get(`${api}/albums/${book.id}`)).status()).toBe(403);
  await page.screenshot({
    path: "../../output/album-qa/admin-albums.png",
    fullPage: true,
  });
  await drawer.getByRole("button", { name: "恢复作品", exact: true }).click();
  await page
    .getByPlaceholder("处理原因", { exact: true })
    .fill("自动化测试：复核完成");
  await page
    .locator(".ant-modal:visible")
    .getByRole("button", { name: "恢复作品", exact: true })
    .click();
  await expect(drawer).toContainText("待作者重新发布");
  expect((await request.get(`${api}/albums/${book.id}`)).status()).toBe(403);
  const restored = (
    await (await request.get(`${api}/albums/${book.id}`, { headers })).json()
  ).data;
  expect(
    (
      await request.post(`${api}/albums/${book.id}/publish`, {
        headers,
        data: { revision: restored.revision },
      })
    ).ok(),
  ).toBeTruthy();
  expect((await request.get(`${api}/albums/${book.id}`)).status()).toBe(200);
  await drawer.getByRole("button", { name: "关闭", exact: true }).click();
  await page.getByRole("tab", { name: "额度与会员", exact: true }).click();
  await page
    .getByRole("spinbutton", { name: "普通用户单本页面数量", exact: true })
    .fill("11");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  await expect(page.getByText("相册配置已保存", { exact: true })).toBeVisible();
  expect(
    (await (await request.get(api + "/albums/quota", { headers })).json()).data
      .max_page_per_album,
  ).toBe(11);
  await page
    .getByRole("spinbutton", { name: "普通用户单本页面数量", exact: true })
    .fill("10");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  await page
    .locator(".ant-modal:visible")
    .getByRole("button", { name: "确认并保存", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await page.getByRole("tab", { name: "主题与系统素材", exact: true }).click();
  await page.getByRole("button", { name: "新增系统素材", exact: true }).click();
  const resourceId = `e2e-star-${Date.now()}`;
  await page.getByLabel("资源 ID", { exact: true }).fill(resourceId);
  await page.getByLabel("素材名称", { exact: true }).fill("E2E 星光");
  await page
    .locator(".ant-select")
    .filter({ has: page.getByLabel("素材状态", { exact: true }) })
    .click();
  await page
    .locator(".ant-select-dropdown:visible")
    .getByText("已上架", { exact: true })
    .click();
  await page
    .locator(".ant-modal:visible")
    .getByRole("button", { name: "保存", exact: true })
    .click();
  await expect(page.locator(".ant-modal:visible")).toHaveCount(0);
  await page.getByPlaceholder("搜索素材名称或编号").fill(resourceId);
  await expect(
    page.locator(".ant-table-tbody tr").filter({ hasText: resourceId }),
  ).toContainText("E2E 星光");
  const resources = (
    await (await request.get(api + "/albums/resources")).json()
  ).data.items;
  expect(
    resources.some((r: { id: string }) => r.id === resourceId),
  ).toBeTruthy();
  const latest = (
    await (await request.get(`${api}/albums/${book.id}`, { headers })).json()
  ).data;
  expect(
    (
      await request.delete(
        `${api}/albums/${book.id}?revision=${latest.revision}`,
        { headers },
      )
    ).ok(),
  ).toBeTruthy();
});

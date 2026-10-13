import { test, expect } from "@playwright/test";

const api = "http://127.0.0.1:18001/api/v1";

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
  await page.getByRole("button", { name: /^查\s*询$/ }).click();
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await row.getByRole("button", { name: /^查\s*看$/ }).click();
  await expect(page.locator(".ant-drawer")).toContainText(book.id);
  await page
    .locator(".ant-drawer")
    .getByRole("button", { name: "关闭", exact: true })
    .click();
  await row.getByRole("button", { name: "限制公开", exact: true }).click();
  await page
    .getByPlaceholder("处理原因", { exact: true })
    .fill("自动化测试：复核公开内容");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确 定", exact: true })
    .click();
  await expect(row).toContainText("限制公开");
  expect((await request.get(`${api}/albums/${book.id}`)).status()).toBe(403);
  await page.screenshot({
    path: "../../output/album-qa/admin-albums.png",
    fullPage: true,
  });
  await row.getByRole("button", { name: "解除限制", exact: true }).click();
  await page
    .getByPlaceholder("处理原因", { exact: true })
    .fill("自动化测试：复核完成");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确 定", exact: true })
    .click();
  await expect(
    row.getByRole("button", { name: "限制公开", exact: true }),
  ).toBeVisible();
  expect((await request.get(`${api}/albums/${book.id}`)).status()).toBe(200);
  await page.getByRole("tab", { name: "额度与会员", exact: true }).click();
  await page.getByLabel("普通用户实际页面上限", { exact: true }).fill("11");
  await page.getByRole("button", { name: "保存配置", exact: true }).click();
  await expect(page.getByText("相册配置已保存", { exact: true })).toBeVisible();
  expect(
    (await (await request.get(api + "/albums/quota", { headers })).json()).data
      .max_page_per_album,
  ).toBe(11);
  await page.getByLabel("普通用户实际页面上限", { exact: true }).fill("10");
  await page.getByRole("button", { name: "保存配置", exact: true }).click();
  await page.getByRole("tab", { name: "主题与系统素材", exact: true }).click();
  await page.getByRole("button", { name: "新增系统素材", exact: true }).click();
  await page.getByLabel("资源 ID", { exact: true }).fill("e2e-star");
  await page.getByLabel("名称", { exact: true }).fill("E2E 星光");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确 定", exact: true })
    .click();
  await expect(
    page.locator(".ant-table-tbody tr").filter({ hasText: "e2e-star" }),
  ).toContainText("E2E 星光");
  const resources = (
    await (await request.get(api + "/albums/resources")).json()
  ).data.items;
  expect(
    resources.some((r: { id: string }) => r.id === "e2e-star"),
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

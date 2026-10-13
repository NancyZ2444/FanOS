import { expect, test } from "@playwright/test";

test("card searches album versions, clears changed source and saves version relation", async ({
  page,
  request,
}) => {
  const root = "http://127.0.0.1:8011/api/v1/admin/console";
  const auth = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await auth.json()).data.access_token}`,
  };
  const prefix = `Card versions ${Date.now()}`;
  const ids: string[] = [];
  for (const suffix of ["One", "Two"]) {
    const res = await request.post(root + "/entities/albums", {
      headers,
      data: {
        name: `${prefix} ${suffix}`,
        group_id: "group-lumina",
        versions: [suffix + " Standard", suffix + " Limited"],
      },
    });
    expect(res.status()).toBe(200);
    ids.push((await res.json()).data.id);
  }
  const versions = (
    await (
      await request.get(root + `/records/versions?entity_id=${ids[0]}`, {
        headers,
      })
    ).json()
  ).data.items;
  const limited = versions.find((v: any) => v.data.name === "One Limited");
  await request.put(root + `/records/versions/${limited.id}`, {
    headers,
    data: {
      entity_type: "albums",
      entity_id: ids[0],
      data: { ...limited.data, code: "ONE-LTD" },
    },
  });
  await page.goto("/catalog/cards");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
  await page.goto(
    `/catalog/cards/new?group_id=group-lumina&idol_id=idol-aria&source_entity_id=${ids[0]}&source_entity_type=ALBUM`,
  );
  await page.getByRole("button", { name: /下一步/ }).click();
  await page.getByRole("button", { name: /下一步/ }).click();
  const version = page.getByLabel("专辑版本", { exact: true });
  await version.fill("ONE-LTD");
  await page.getByText("One Limited · ONE-LTD", { exact: true }).click();
  const source = page.getByLabel("来源对象", { exact: true });
  await source.fill(prefix + " Two");
  await page
    .getByText(prefix + " Two · 未设置发行日期", { exact: true })
    .click();
  await expect(
    page
      .locator(".ant-select-selection-item")
      .filter({ hasText: "One Limited" }),
  ).toHaveCount(0);
  await version.fill("Limited");
  await expect(
    page
      .locator(".ant-select-item-option-content")
      .filter({ hasText: "One Limited" }),
  ).toHaveCount(0);
  await page.getByText("Two Limited", { exact: true }).click();
  await page.getByRole("button", { name: /下一步/ }).click();
  await expect(page.getByLabel("版本名称", { exact: true })).toHaveValue(
    "Two Limited",
  );
  const saved = page.waitForResponse(
    (r) =>
      r.url().endsWith("/console/cards") && r.request().method() === "POST",
  );
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  const res = await saved;
  expect(res.status()).toBe(200);
  const card = (await res.json()).data;
  expect(card.source_entity_id).toBe(ids[1]);
  expect(card.entity_version_id).toBeTruthy();
  expect(card.version).toBe("Two Limited");
  await page.goto(`/catalog/cards/${card.id}`);
  await expect(page.getByLabel("版本名称", { exact: true })).toHaveValue(
    "Two Limited",
  );
  await expect(
    page
      .locator(".ant-select-selection-item")
      .filter({ hasText: "Two Limited" }),
  ).toBeVisible();
});

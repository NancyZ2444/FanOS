import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";

const root = "http://127.0.0.1:8011/api/v1/admin/console";

test.beforeEach(async ({ page }) => {
  await page.goto("/catalog/cards");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
});

test("album import keeps one parent for collaborative release versions and appends without replacing parent data", async ({
  page,
  request,
}) => {
  test.setTimeout(90000);
  const login = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await login.json()).data.access_token}`,
  };
  const name = `Collaborative Album ${Date.now()}`;
  await page.goto("/catalog/import?kind=albums");
  await expect(
    page.getByText("当前模板：专辑 · 新增专辑或追加版本，保留原资料"),
  ).toBeVisible();
  const downloadPromise = page.waitForEvent("download");
  await page
    .getByRole("button", { name: "下载 CSV 模板", exact: true })
    .click();
  const download = await downloadPromise;
  const templatePath = await download.path();
  expect(templatePath).not.toBeNull();
  const header = (await readFile(templatePath!, "utf8"))
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/, 1)[0]
    .split(",");
  expect(header).toContain("versions");
  expect(header).toContain("artist_names");

  const previewPromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/admin/console/imports") &&
      response.request().method() === "POST",
  );
  await page.locator("input[type=file]").setInputFiles({
    name: "collaborative-album.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      `name,versions,artist_names,description\n${name},Photo Book Ver.,Aria|Lin,Original parent description\n${name},Digipack Ver.,Aria|Lin,Ignored parent override\n`,
    ),
  });
  const preview = (await (await previewPromise).json()).data;
  expect(preview.errors).toEqual([]);
  expect(preview.rows).toHaveLength(2);
  expect(preview.rows[0].data.versions).toEqual(["Photo Book Ver."]);
  expect(preview.rows[0].data.artists).toHaveLength(2);
  await expect(page.getByRole("cell", { name, exact: true })).toHaveCount(2);
  await expect(
    page.getByRole("cell", { name: "Aria / Lin", exact: true }),
  ).toHaveCount(2);
  await expect(
    page.getByRole("cell", { name: "Photo Book Ver.", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("cell", { name: "Digipack Ver.", exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "确认导入 2 行", exact: true })
    .click();
  const importedPromise = page.waitForResponse(
    (response) =>
      response.url().endsWith(`/imports/${preview.id}/confirm`) &&
      response.request().method() === "POST",
  );
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确认导入", exact: true })
    .click();
  const importedResponse = await importedPromise;
  expect(importedResponse.status()).toBe(200);
  const imported = (await importedResponse.json()).data;
  expect(imported.imported_count).toBe(2);
  const ids = new Set(
    imported.rows.map((row: { created_id: string }) => row.created_id),
  );
  expect(ids.size).toBe(1);
  const albumId = imported.rows[0].created_id;
  expect(albumId).toBeTruthy();
  const repeated = await request.post(`${root}/imports/${preview.id}/confirm`, {
    headers,
    data: { skip_invalid: false },
  });
  expect(repeated.status()).toBe(200);
  expect((await repeated.json()).data.rows).toEqual(imported.rows);
  await page.goto(`/catalog/albums/${albumId}/detail`);
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await page.getByRole("tab", { name: "版本", exact: true }).click();
  await expect(page.locator(".ant-table-tbody tr.ant-table-row")).toHaveCount(
    2,
  );
  for (const version of ["Photo Book Ver.", "Digipack Ver."]) {
    await expect(
      page.getByRole("cell", { name: version, exact: true }),
    ).toBeVisible();
  }

  await page.goto("/catalog/import?kind=albums");
  const appendPreviewPromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/admin/console/imports") &&
      response.request().method() === "POST",
  );
  await page.locator("input[type=file]").setInputFiles({
    name: "album-new-version.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      `name,versions,artist_names,description\n${name},Jewel Case Ver.,Lin|Aria,Should not replace description\n`,
    ),
  });
  const appendPreview = (await (await appendPreviewPromise).json()).data;
  expect(appendPreview.errors).toEqual([]);
  await page
    .getByRole("button", { name: "确认导入 1 行", exact: true })
    .click();
  const appendedPromise = page.waitForResponse(
    (response) =>
      response.url().endsWith(`/imports/${appendPreview.id}/confirm`) &&
      response.request().method() === "POST",
  );
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确认导入", exact: true })
    .click();
  const appended = (await (await appendedPromise).json()).data;
  expect(appended.rows[0].created_id).toBe(albumId);
  const detail = await request.get(
    `${root}/entities/albums/${albumId}/detail`,
    { headers },
  );
  const entity = (await detail.json()).data.entity;
  expect(entity.name).toBe(name);
  expect(entity.description).toBe("Original parent description");
  expect(entity.versions).toEqual(
    expect.arrayContaining([
      "Photo Book Ver.",
      "Digipack Ver.",
      "Jewel Case Ver.",
    ]),
  );
  const versionsResponse = await request.get(
    `${root}/records/versions?entity_id=${albumId}`,
    { headers },
  );
  expect((await versionsResponse.json()).data.items).toHaveLength(3);

  const duplicatePreviewPromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/admin/console/imports") &&
      response.request().method() === "POST",
  );
  await page.locator("input[type=file]").setInputFiles({
    name: "duplicate-album-version.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      `name,versions,artist_names\n${name},Photo Book Ver.,Aria|Lin\n`,
    ),
  });
  const duplicatePreview = (await (await duplicatePreviewPromise).json()).data;
  expect(duplicatePreview.errors).toEqual(
    expect.arrayContaining([expect.objectContaining({ field: "versions" })]),
  );
  await expect(
    page.getByRole("cell", { name: "版本", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: /^确认导入 \d+ 行$/ }),
  ).toBeDisabled();
});

test("album form stores a work name separately and recalls its versions", async ({
  page,
}) => {
  const name = `Version Form Album ${Date.now()}`;
  await page.goto("/catalog/albums?create=true&idol_id=idol-aria");
  await page.getByLabel("专辑名称 / 官方名称", { exact: true }).fill(name);
  const versions = page.getByLabel("专辑版本", { exact: true });
  for (const version of ["Standard Ver.", "Limited Ver."]) {
    await versions.fill(version);
    await versions.press("Enter");
  }
  await versions.press("Escape");
  const savedPromise = page.waitForResponse(
    (response) =>
      response.url().endsWith("/entities/albums") &&
      response.request().method() === "POST",
  );
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  const savedResponse = await savedPromise;
  expect(savedResponse.status()).toBe(200);
  const album = (await savedResponse.json()).data;
  expect(album.name).toBe(name);
  expect(album.versions).toHaveLength(2);
  expect(album.versions).toEqual(
    expect.arrayContaining(["Standard Ver.", "Limited Ver."]),
  );
  await page.getByPlaceholder("搜索专辑名称、ID…").fill(name);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await row.getByRole("button", { name: "编辑", exact: true }).click();
  await expect(
    page.getByLabel("专辑名称 / 官方名称", { exact: true }),
  ).toHaveValue(name);
  await expect(page.locator(".ant-drawer-body")).toContainText("Standard Ver.");
  await expect(page.locator(".ant-drawer-body")).toContainText("Limited Ver.");
  await page.goto(`/catalog/albums/${album.id}/detail`);
  await page.getByRole("tab", { name: "版本", exact: true }).click();
  await expect(page.locator(".ant-table-tbody tr.ant-table-row")).toHaveCount(
    2,
  );
});

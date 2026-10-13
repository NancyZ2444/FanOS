import { expect, test } from "@playwright/test";
import { readFile } from "node:fs/promises";

const root = "http://127.0.0.1:8011/api/v1/admin/console";
test.beforeEach(async ({ page }) => {
  await page.goto("/catalog/cards");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
});
async function headers(request: any) {
  const response = await request.post(
    "http://127.0.0.1:8011/api/v1/auth/login",
    {
      data: { method: "phone", phone: "13900000000", code: "123456" },
    },
  );
  return {
    Authorization: `Bearer ${(await response.json()).data.access_token}`,
  };
}

test("company spreadsheet import is selectable from group form", async ({
  page,
}) => {
  const name = `Company CSV ${Date.now()}`;
  await page.goto("/catalog/companies");
  await page.getByRole("button", { name: "批量导入公司", exact: true }).click();
  await expect(
    page.getByText("当前模板：公司 · 仅新增，不覆盖已有记录"),
  ).toBeVisible();
  const checked = page.waitForResponse(
    (r) =>
      r.url().endsWith("/console/imports") && r.request().method() === "POST",
  );
  await page.locator('input[type="file"]').setInputFiles({
    name: "companies.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      `name,description\n${name},Imported company description\n`,
    ),
  });
  const task = (await (await checked).json()).data;
  expect(task.errors).toEqual([]);
  await page
    .getByRole("button", { name: "确认导入 1 行", exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确认导入", exact: true })
    .click();
  await expect(
    page.getByText("已导入 1 条公司，状态为草稿", { exact: true }),
  ).toBeVisible();
  await page.goto("/catalog/companies");
  await expect(page.getByRole("cell", { name, exact: true })).toBeVisible();
  await page.goto("/catalog/groups?create=true");
  const company = page.getByLabel("所属公司", { exact: true });
  await company.click();
  await page
    .locator(".ant-select-item-option-content")
    .filter({ hasText: name })
    .click();
  await expect(page.locator(".ant-drawer-body")).toContainText(name);
});

test("company detail lists linked groups and idols", async ({
  page,
  request,
}) => {
  const auth = await headers(request);
  const suffix = Date.now();
  const companyName = `Detail Agency ${suffix}`;
  const companyResponse = await request.post(root + "/records/companies", {
    headers: auth,
    data: { data: { name: companyName, description: "Company detail test" } },
  });
  const company = (await companyResponse.json()).data;
  const groupName = `Detail Group ${suffix}`;
  const groupResponse = await request.post(root + "/entities/groups", {
    headers: auth,
    data: { name: groupName, company_ids: [company.id] },
  });
  const group = (await groupResponse.json()).data;
  const idolName = `Detail Idol ${suffix}`;
  const idolResponse = await request.post(root + "/entities/idols", {
    headers: auth,
    data: {
      name: idolName,
      group_id: group.id,
      company_ids: [company.id],
    },
  });
  expect(idolResponse.status()).toBe(200);

  await page.goto("/catalog/companies");
  const companyRow = page.getByRole("row").filter({ hasText: companyName });
  await expect(companyRow).toContainText("1当前");
  await companyRow.getByRole("button", { name: "查看详情" }).click();
  const drawer = page.locator(".ant-drawer").filter({ hasText: companyName });
  await expect(drawer).toContainText("当前关联组合");
  await expect(drawer).toContainText("当前关联艺人");
  await expect(drawer.getByRole("button", { name: groupName })).toBeVisible();
  await expect(drawer.getByRole("button", { name: idolName })).toBeVisible();
  await expect(drawer).toContainText("当前关联");
  await drawer.getByRole("button", { name: groupName }).click();
  await expect(page).toHaveURL(
    new RegExp(`/catalog/groups/${encodeURIComponent(group.id)}/detail$`),
  );
});

test("group and idol images appear in card selection and dropdowns", async ({
  page,
  request,
}) => {
  const auth = await headers(request);
  const upload = await request.post(root + "/uploads", {
    headers: auth,
    multipart: {
      file: {
        name: "portrait.png",
        mimeType: "image/png",
        buffer: await readFile("tests/fixtures/admin-recognition.png"),
      },
    },
  });
  const url = (await upload.json()).data.url;
  const name = `Image group ${Date.now()}`;
  const g = await request.post(root + "/entities/groups", {
    headers: auth,
    data: { name, image_url: url },
  });
  const group = (await g.json()).data;
  const idolName = `Image idol ${Date.now()}`;
  await request.post(root + "/entities/idols", {
    headers: auth,
    data: { name: idolName, group_id: group.id, image_url: url },
  });
  await page.goto("/catalog/cards/new");
  const groupChoice = page.locator(".selection-card").filter({ hasText: name });
  await expect(groupChoice.locator("img")).toHaveAttribute("src", url);
  await groupChoice.click();
  await expect(page.locator(".ant-select-selector img")).toHaveAttribute(
    "src",
    url,
  );
  await page.getByRole("button", { name: /下一步/ }).click();
  const idolChoice = page
    .locator(".selection-card")
    .filter({ hasText: idolName });
  await expect(idolChoice.locator("img")).toHaveAttribute("src", url);
  await idolChoice.click();
  await page.getByRole("button", { name: /下一步/ }).click();
  await page.getByRole("button", { name: /下一步/ }).click();
  await expect(page.locator(".ant-select-selector img")).toHaveCount(2);
});

test("upload recognition opens existing draft and unknown image enters manual creation", async ({
  page,
  request,
}) => {
  const auth = await headers(request);
  const artwork = await readFile("tests/fixtures/admin-recognition.png");
  const upload = await request.post(root + "/uploads", {
    headers: auth,
    multipart: {
      file: { name: "card.png", mimeType: "image/png", buffer: artwork },
    },
  });
  const url = (await upload.json()).data.url;
  const title = `Recognize draft ${Date.now()}`;
  const created = await request.post(root + "/cards", {
    headers: auth,
    data: {
      title,
      group_id: "group-lumina",
      idol_id: "idol-aria",
      image_url: url,
    },
  });
  expect(created.status()).toBe(200);
  const card = (await created.json()).data;
  await page.goto("/catalog/cards");
  const response = page.waitForResponse((r) =>
    r.url().endsWith("/cards/recognize"),
  );
  await page
    .getByLabel("上传小卡识别图片")
    .setInputFiles("tests/fixtures/admin-card-background.png");
  await page
    .getByRole("button", { name: "确认裁剪并识别", exact: true })
    .click();
  expect((await (await response).json()).data.status).toBe("matched");
  await expect(page).toHaveURL(new RegExp(`/catalog/cards/${card.id}$`));
  await expect(
    page.getByLabel("小卡名称 Card Name", { exact: true }),
  ).toHaveValue(title);
  await page.goto("/catalog/cards");
  await page
    .getByLabel("上传小卡识别图片")
    .setInputFiles("tests/fixtures/admin-unknown.png");
  await page
    .getByRole("button", { name: "确认裁剪并识别", exact: true })
    .click();
  await expect(page).toHaveURL(/\/catalog\/cards\/new\?image_url=/);
  await expect(page.getByText(/暂未匹配到记录；另有/)).toBeVisible();
  await expect(
    page.getByText(
      "已带入上传的小卡正面，请选择组合、艺人和来源，补充信息后保存草稿。",
      { exact: true },
    ),
  ).toBeVisible();
  await page.locator(".selection-card").filter({ hasText: "LUMINA" }).click();
  await page.getByRole("button", { name: /下一步/ }).click();
  await page.locator(".selection-card").filter({ hasText: "Aria" }).click();
  await page.getByRole("button", { name: /下一步/ }).click();
  await page.getByRole("button", { name: /下一步/ }).click();
  await expect(
    page.getByAltText("小卡正面", { exact: true }).first(),
  ).toBeVisible();
  await page
    .getByLabel("小卡名称 Card Name", { exact: true })
    .fill("Manually completed scan card");
  const saved = page.waitForResponse(
    (r) =>
      r.url().endsWith("/console/cards") && r.request().method() === "POST",
  );
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  const savedCard = (await (await saved).json()).data;
  expect(savedCard.id).not.toBe(card.id);
  expect(savedCard.image_url).toContain("/recognition/");
});

test("card photo crop supports cancel, dragging, precise adjustment and saving", async ({
  page,
  request,
}) => {
  const auth = await headers(request);
  const previous = await request.post(root + "/uploads", {
    headers: auth,
    multipart: {
      file: {
        name: "old.png",
        mimeType: "image/png",
        buffer: await readFile("tests/fixtures/admin-unknown.png"),
      },
    },
  });
  const previousUrl = (await previous.json()).data.url;
  const created = await request.post(root + "/cards", {
    headers: auth,
    data: {
      title: `Crop maintenance ${Date.now()}`,
      group_id: "group-lumina",
      idol_id: "idol-aria",
      image_url: previousUrl,
    },
  });
  const card = (await created.json()).data;
  await page.goto(`/catalog/cards/${card.id}`);
  let uploads = 0;
  page.on("request", (r) => {
    if (r.url().endsWith("/console/uploads") && r.method() === "POST")
      uploads++;
  });
  const choose = () =>
    page
      .getByLabel("上传正面图片", { exact: true })
      .setInputFiles("tests/fixtures/admin-card-background.png");
  await choose();
  const dialog = page.getByRole("dialog", { name: "裁剪小卡图片" });
  const left = dialog.getByRole("spinbutton", { name: "左上角横向百分比" });
  await expect(left).toHaveValue(/2[0-9]\./);
  await dialog.getByRole("button", { name: /^取\s*消$/ }).click();
  await expect(dialog).not.toBeVisible();
  expect(uploads).toBe(0);
  await expect(page.getByAltText("正面图片", { exact: true })).toHaveAttribute(
    "src",
    previousUrl,
  );
  await choose();
  await expect(left).toBeVisible();
  const initial = Number(await left.inputValue());
  const corner = dialog.getByRole("button", {
    name: "调整左上角",
    exact: true,
  });
  const box = (await corner.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(
    box.x + box.width / 2 + 18,
    box.y + box.height / 2 + 15,
    { steps: 4 },
  );
  await page.mouse.up();
  expect(Number(await left.inputValue())).toBeGreaterThan(initial + 1);
  await corner.focus();
  const afterDrag = Number(await left.inputValue());
  await corner.press("ArrowRight");
  expect(Number(await left.inputValue())).toBeGreaterThan(afterDrag);
  await dialog.getByRole("button", { name: "恢复自动框选" }).click();
  expect(Number(await left.inputValue())).toBeCloseTo(initial, 2);
  await dialog.getByRole("button", { name: "保留整张图片" }).click();
  await expect(left).toHaveValue("0.00");
  const points = [
    [160, 100],
    [519, 100],
    [519, 619],
    [160, 619],
  ];
  for (const [i, label] of ["左上", "右上", "右下", "左下"].entries()) {
    await dialog
      .getByRole("spinbutton", { name: `${label}角横向百分比` })
      .fill(((points[i][0] / 699) * 100).toFixed(2));
    await dialog
      .getByRole("spinbutton", { name: `${label}角纵向百分比` })
      .fill(((points[i][1] / 759) * 100).toFixed(2));
  }
  await dialog.getByText("裁剪范围", { exact: true }).click();
  await page.screenshot({ path: "test-results/card-crop-preview.png" });
  const saved = page.waitForResponse(
    (r) =>
      r.url().endsWith("/console/uploads") && r.request().method() === "POST",
  );
  await dialog
    .getByRole("button", { name: "确认裁剪并上传", exact: true })
    .click();
  const response = await saved;
  expect(response.status()).toBe(200);
  const result = (await response.json()).data;
  expect(result.width).toBe(360);
  expect(result.height).toBe(520);
  expect(uploads).toBe(1);
  await expect(page.getByAltText("正面图片", { exact: true })).toHaveAttribute(
    "src",
    result.url,
  );
  const beforeSave = (
    await (await request.get(root + "/catalog", { headers: auth })).json()
  ).data.cards.find((r: any) => r.id === card.id);
  expect(beforeSave.image_url).toBe(previousUrl);
  const cardSaved = page.waitForResponse(
    (r) =>
      r.url().endsWith(`/cards/${card.id}`) && r.request().method() === "PUT",
  );
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  expect((await (await cardSaved).json()).data.image_url).toBe(result.url);
});

test("recognition crop can be cancelled without recognizing or creating records", async ({
  page,
}) => {
  let recognitions = 0;
  page.on("request", (r) => {
    if (r.url().endsWith("/cards/recognize")) recognitions++;
  });
  await page
    .getByLabel("上传小卡识别图片")
    .setInputFiles("tests/fixtures/admin-card-background.png");
  const dialog = page.getByRole("dialog", { name: "裁剪小卡图片" });
  await expect(
    dialog.getByText("已自动框选小卡，请确认完整保留卡片边缘。", {
      exact: true,
    }),
  ).toBeVisible();
  await dialog.getByRole("button", { name: /^取\s*消$/ }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page).toHaveURL(/\/catalog\/cards$/);
  expect(recognitions).toBe(0);
});

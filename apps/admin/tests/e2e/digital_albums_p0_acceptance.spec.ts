import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";

const api = "http://127.0.0.1:18102/api/v1";
const shots = resolve("../../output/digital-albums-p0-20261020/after");
type Headers = { Authorization: string };

async function login(
  request: APIRequestContext,
  phone = "13800000000",
): Promise<Headers> {
  const response = await request.post(api + "/auth/login", {
    data: { method: "phone", phone, code: "123456" },
  });
  expect(response.ok()).toBeTruthy();
  return {
    Authorization: `Bearer ${(await response.json()).data.access_token}`,
  };
}

async function open(page: Page) {
  await page.goto("/digital-albums");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(
    page.getByRole("heading", { name: "数字相册", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".ant-spin-spinning")).toHaveCount(0);
}

async function select(page: Page, label: string, option: string) {
  await page
    .locator(".ant-select")
    .filter({ has: page.getByLabel(label, { exact: true }) })
    .click();
  await page
    .locator(".ant-select-dropdown:visible")
    .getByText(option, { exact: true })
    .click();
}

async function capture(page: Page, name: string) {
  await mkdir(shots, { recursive: true });
  await expect(page.locator(".ant-spin-spinning")).toHaveCount(0);
  await page.screenshot({
    path: `${shots}/${name}.png`,
    fullPage: true,
    animations: "disabled",
  });
}

async function assertViewport(page: Page) {
  const bounds = await page.evaluate(() => ({
    content: document.documentElement.scrollWidth,
    width: window.innerWidth,
  }));
  expect(bounds.content).toBeLessThanOrEqual(bounds.width);
}

test("published preview, explicit report resolution, review and manual republish", async ({
  page,
  request,
}) => {
  const user = await login(request),
    admin = await login(request, "13900000000");
  const name = `P0 审核验收 ${Date.now()}`;
  let response = await request.post(api + "/albums", {
    headers: user,
    data: { name },
  });
  expect(response.ok()).toBeTruthy();
  let album = (await response.json()).data;
  response = await request.patch(`${api}/albums/${album.id}`, {
    headers: user,
    data: {
      revision: album.revision,
      visibility: "PUBLIC",
      description: "已发布的作品说明",
      cover: {
        background: {
          type: "GRADIENT",
          colors: ["#E8E3F2", "#EFE2E0"],
          angle: 45,
        },
        elements: [
          {
            id: "p0-title",
            type: "TEXT",
            content: "星光收藏",
            x: 0.1,
            y: 0.2,
            width: 0.8,
            height: 0.2,
            style: { color: "#342A56", font_size: 30 },
          },
          {
            id: "p0-sticker",
            type: "STICKER",
            content: "bow",
            x: 0.3,
            y: 0.55,
            width: 0.4,
            height: 0.2,
          },
        ],
      },
      card_view: {
        ...album.card_view,
        cover_style: "CUSTOM",
        default_mode: "BOOK",
      },
      pages: [
        {
          id: "p0-page",
          grid_count: 2,
          slots: [
            { id: "p0-slot-1", card_id: "card-aria-01" },
            { id: "p0-slot-2", card_id: "card-lin-01" },
          ],
        },
      ],
    },
  });
  expect(response.ok(), await response.text()).toBeTruthy();
  album = (await response.json()).data;
  response = await request.post(`${api}/albums/${album.id}/publish`, {
    headers: user,
    data: { revision: album.revision },
  });
  album = (await response.json()).data;
  response = await request.patch(`${api}/albums/${album.id}`, {
    headers: user,
    data: { revision: album.revision, description: "尚未发布的修改" },
  });
  album = (await response.json()).data;
  for (const reason of ["验收举报：图片问题", "验收举报：文字问题"]) {
    expect(
      (
        await request.post(`${api}/albums/${album.id}/report`, {
          headers: admin,
          data: { reason },
        })
      ).ok(),
    ).toBeTruthy();
  }
  await open(page);
  await page.getByPlaceholder("相册名称", { exact: true }).fill(name);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await row.getByRole("button", { name: /^查\s*看$/ }).click();
  const drawer = page.locator(".ant-drawer-content");
  await expect(
    drawer.getByText("已发布的作品说明", { exact: true }),
  ).toBeVisible();
  await expect(drawer.getByText("尚未发布的修改", { exact: true })).toHaveCount(
    0,
  );
  await expect(
    drawer.getByRole("region", { name: "完整作品预览" }),
  ).toBeVisible();
  await capture(page, "work-preview-1440");
  await drawer
    .getByRole("button", { name: "查看第 1 页", exact: true })
    .click();
  await drawer.getByRole("button", { name: "放大预览", exact: true }).click();
  await capture(page, "work-pages-1440");
  const reportRow = drawer
    .locator(".ant-table-tbody tr")
    .filter({ hasText: "验收举报：图片问题" });
  await reportRow.getByRole("checkbox").check();
  await drawer.getByRole("button", { name: "限制公开", exact: true }).click();
  const modal = page.locator(".ant-modal-content:visible");
  await modal.getByRole("button", { name: "限制公开", exact: true }).click();
  await expect(
    modal.getByText("请填写处理原因", { exact: true }),
  ).toBeVisible();
  await modal
    .getByPlaceholder("处理原因", { exact: true })
    .fill("图片内容需修改后复核");
  await modal.getByRole("button", { name: "限制公开", exact: true }).click();
  await expect(modal).toHaveCount(0);
  expect((await request.get(`${api}/albums/${album.id}`)).status()).toBe(403);
  const detail = (
    await (
      await request.get(`${api}/admin/console/digital-albums/${album.id}`, {
        headers: admin,
      })
    ).json()
  ).data;
  expect(
    detail.reports.filter(
      (r: { status: string }) => r.status.toLowerCase() === "resolved",
    ),
  ).toHaveLength(1);
  expect(
    detail.logs.some((r: { action: string }) => r.action === "restrict_public"),
  ).toBeTruthy();
  response = await request.post(`${api}/albums/${album.id}/review-request`, {
    headers: user,
    data: { revision: album.revision },
  });
  expect(response.ok(), await response.text()).toBeTruthy();
  await drawer.getByRole("button", { name: "刷新", exact: true }).click();
  await expect(
    drawer.getByRole("button", { name: "恢复作品", exact: true }),
  ).toBeDisabled();
  await drawer
    .getByRole("button", { name: "查看申请复核内容", exact: true })
    .click();
  await expect(
    drawer.getByText("尚未发布的修改", { exact: true }),
  ).toBeVisible();
  await capture(page, "review-1440");
  await drawer.getByRole("button", { name: "恢复作品", exact: true }).click();
  await modal
    .getByPlaceholder("处理原因", { exact: true })
    .fill("修改内容已复核");
  await modal.getByRole("button", { name: "恢复作品", exact: true }).click();
  await expect(modal).toHaveCount(0);
  expect((await request.get(`${api}/albums/${album.id}`)).status()).toBe(403);
  album = (
    await (
      await request.get(`${api}/albums/${album.id}`, { headers: user })
    ).json()
  ).data;
  expect(
    (
      await request.post(`${api}/albums/${album.id}/publish`, {
        headers: user,
        data: { revision: album.revision },
      })
    ).ok(),
  ).toBeTruthy();
  expect(
    (await (await request.get(`${api}/albums/${album.id}`)).json()).data
      .description,
  ).toBe("尚未发布的修改");
  await assertViewport(page);
});

test("material form validates, uploads, edits and deletes unused draft with confirmation", async ({
  page,
  request,
}) => {
  await open(page);
  await page.getByRole("tab", { name: "主题与系统素材", exact: true }).click();
  await page.getByRole("button", { name: "新增系统素材", exact: true }).click();
  const modal = page.locator(".ant-modal-content:visible");
  await modal.getByRole("button", { name: /^保\s*存$/ }).click();
  await expect(
    modal.getByText("请输入素材名称", { exact: true }),
  ).toBeVisible();
  const id = `p0-picture-${Date.now()}`;
  await page.getByLabel("素材名称", { exact: true }).fill("透明图形贴纸");
  await page.getByLabel("资源 ID", { exact: true }).fill(id);
  await select(page, "表现形式", "图片贴纸");
  const png = await page.evaluate(() => {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 64;
    const context = canvas.getContext("2d")!;
    context.fillStyle = "#8B5CF6";
    context.fillRect(16, 16, 32, 32);
    return canvas.toDataURL("image/png").split(",")[1];
  });
  await modal.locator('input[type="file"]').setInputFiles({
    name: "shape.png",
    mimeType: "image/png",
    buffer: Buffer.from(png, "base64"),
  });
  await expect(page.getByLabel("素材图片", { exact: true })).not.toHaveValue(
    "",
  );
  await capture(page, "material-form-1440");
  await modal.getByRole("button", { name: /^保\s*存$/ }).click();
  await expect(modal).toHaveCount(0);
  await page.getByPlaceholder("搜索素材名称或编号").fill(id);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: id });
  await expect(row).toContainText("草稿");
  await row.getByRole("button", { name: /^编\s*辑$/ }).click();
  await expect(page.getByLabel("素材名称", { exact: true })).toHaveValue(
    "透明图形贴纸",
  );
  await expect(page.getByLabel("资源 ID", { exact: true })).toBeDisabled();
  await page
    .getByLabel("素材名称", { exact: true })
    .fill("透明图形贴纸 · 已编辑");
  await modal.getByRole("button", { name: /^保\s*存$/ }).click();
  await expect(row).toContainText("已编辑");
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: /^删除/ }).click();
  await expect(modal).toContainText("透明图形贴纸 · 已编辑");
  await modal.getByRole("button", { name: /^取\s*消$/ }).click();
  await expect(row).toBeVisible();
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: /^删除/ }).click();
  await modal.getByRole("button", { name: /^删\s*除$/ }).click();
  await expect(row).toHaveCount(0);
  await capture(page, "material-empty-1440");
  const admin = await login(request, "13900000000");
  const resources = (
    await (
      await request.get(api + "/admin/console/album-settings", {
        headers: admin,
      })
    ).json()
  ).data.resources;
  expect(resources.some((r: { id: string }) => r.id === id)).toBeFalsy();
});

test("quota changes confirm reductions and preserve values on cancel", async ({
  page,
  request,
}) => {
  const admin = await login(request, "13900000000");
  await open(page);
  await page.getByRole("tab", { name: "额度与会员", exact: true }).click();
  const normal = page.getByRole("spinbutton", {
    name: "普通用户相册数量",
    exact: true,
  });
  await expect(normal).toHaveValue("10");
  await normal.fill("9");
  await page.getByRole("button", { name: /^保\s*存$/ }).click();
  const modal = page.locator(".ant-modal-content:visible");
  await expect(modal).toContainText("确认降低会员额度");
  await modal.getByRole("button", { name: /^取\s*消$/ }).click();
  const settings = async () =>
    (
      await (
        await request.get(api + "/admin/console/album-settings", {
          headers: admin,
        })
      ).json()
    ).data;
  expect((await settings()).limits.normal_albums).toBe(10);
  await page.getByRole("button", { name: /^保\s*存$/ }).click();
  await capture(page, "quota-impact-1440");
  await modal.getByRole("button", { name: "确认并保存", exact: true }).click();
  await expect(modal).toHaveCount(0);
  expect((await settings()).limits.normal_albums).toBe(9);
});

for (const width of [1280, 1440, 1920]) {
  test(`responsive shared controls and no document overflow at ${width}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 1000 });
    await open(page);
    await assertViewport(page);
    await capture(page, `works-${width}`);
    await page.getByRole("tab", { name: "额度与会员", exact: true }).click();
    await assertViewport(page);
    await capture(page, `benefits-${width}`);
    await page
      .getByRole("tab", { name: "主题与系统素材", exact: true })
      .click();
    const create = page.getByRole("button", {
      name: "新增系统素材",
      exact: true,
    });
    expect((await create.boundingBox())?.height).toBe(36);
    await assertViewport(page);
    await capture(page, `materials-${width}`);
  });
}

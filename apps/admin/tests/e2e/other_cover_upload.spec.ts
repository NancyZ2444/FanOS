import { expect, test, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const output = resolve(
  "../../output/admin-feedback-review-20261028/other-cover",
);
const image = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR9sAAAAASUVORK5CYII=",
  "base64",
);
const uploadFile = { name: "cover.png", mimeType: "image/png", buffer: image };
const preview =
  '<svg xmlns="http://www.w3.org/2000/svg" width="360" height="240"><rect width="360" height="240" fill="#7255bb"/><circle cx="180" cy="105" r="60" fill="#a78be0"/><text x="180" y="205" text-anchor="middle" fill="white" font-family="sans-serif" font-size="22">FAN OS · COVER</text></svg>';
const oldCover = "/media/catalog/existing-cover.webp";
const newCover = "/media/catalog/uploaded-cover.webp";

async function fixture(page: Page, status = "DRAFT") {
  const writes: { path: string; body: Record<string, unknown> }[] = [];
  const uploads: Buffer[] = [];
  const group = {
    id: "group-cover",
    name: "封面测试组合",
    status: "PUBLISHED",
  };
  let other = {
    id: "other-cover",
    name: "原有来源",
    image_url: oldCover,
    group_id: group.id,
    artists: [{ type: "groups", id: group.id, name: group.name }],
    status,
    card_count: 0,
    tags: [],
  };
  const state = { failUpload: false };
  await page.addInitScript(() => {
    sessionStorage.setItem(
      "fanos-admin-session",
      JSON.stringify({ access_token: "cover-ui-fixture" }),
    );
  });
  await page.route("**/media/**", (route) =>
    route.fulfill({ contentType: "image/svg+xml", body: preview }),
  );
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (path.endsWith("/console/uploads")) {
      uploads.push(request.postDataBuffer()!);
      await route.fulfill(
        state.failUpload
          ? {
              status: 422,
              json: { code: "INVALID_IMAGE", message: "图片上传失败" },
            }
          : { json: { code: 0, data: { url: newCover } } },
      );
      return;
    }
    const body = request.method() === "GET" ? null : request.postDataJSON();
    if (body) writes.push({ path, body });
    let data: unknown = { items: [] };
    if (path.endsWith("/console/me")) {
      data = { id: "admin-cover", name: "封面验收管理员", role: "admin" };
    } else if (path.endsWith("/console/catalog")) {
      data = {
        groups: [group],
        idols: [],
        cards: [],
        albums: [],
        events: [],
        others: [other],
        tags: [],
        records: [],
      };
    } else if (path.includes("/console/entities/others") && body) {
      other = { ...other, ...body };
      data = other;
    }
    await route.fulfill({ json: { code: 0, data } });
  });
  return { writes, uploads, state };
}

test("Other creation uploads an image, previews it, and saves only the managed media URL", async ({
  page,
}) => {
  const { writes, uploads } = await fixture(page);
  await page.goto("/catalog/others");
  await page.getByRole("button", { name: "新增其他来源", exact: true }).click();
  const drawer = page.getByRole("dialog");
  await expect(drawer.getByText("封面图片地址", { exact: true })).toHaveCount(
    0,
  );
  await expect(drawer.getByPlaceholder("https://…")).toHaveCount(0);
  await drawer.getByLabel("关联组合/艺人").click();
  await page.getByText("组合 · 封面测试组合", { exact: true }).click();
  await drawer.getByLabel("展示名称").click();
  await drawer.getByLabel("展示名称").fill("本地封面来源");
  await drawer
    .getByLabel("上传封面图片", { exact: true })
    .setInputFiles(uploadFile);
  await expect(
    drawer.getByRole("img", { name: "封面图片", exact: true }),
  ).toHaveAttribute("src", newCover);
  expect(uploads).toHaveLength(1);
  expect(uploads[0].toString()).toContain('filename="cover.png"');
  await expect(page.getByText("图片上传成功", { exact: true })).not.toBeVisible();
  mkdirSync(output, { recursive: true });
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `${output}/other-cover-upload-${width}.png`,
      fullPage: true,
      animations: "disabled",
    });
  }
  await drawer.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(drawer).toHaveCount(0);
  expect(writes).toHaveLength(1);
  expect(writes[0]).toMatchObject({
    path: "/api/v1/admin/console/entities/others",
    body: {
      name: "本地封面来源",
      image_url: newCover,
      group_id: "group-cover",
    },
  });
});

test("editing preserves the previous cover after a failed replacement", async ({
  page,
}) => {
  const { writes, uploads, state } = await fixture(page);
  await page.goto("/catalog/others");
  await page.getByRole("button", { name: "编辑", exact: true }).click();
  const drawer = page.getByRole("dialog");
  await expect(
    drawer.getByRole("img", { name: "封面图片", exact: true }),
  ).toHaveAttribute("src", oldCover);
  state.failUpload = true;
  await drawer
    .getByLabel("上传封面图片", { exact: true })
    .setInputFiles(uploadFile);
  await expect(page.getByText("图片上传失败", { exact: true })).toBeVisible();
  await expect(
    drawer.getByRole("img", { name: "封面图片", exact: true }),
  ).toHaveAttribute("src", oldCover);
  await drawer.getByLabel("展示名称").fill("只更新来源名称");
  await drawer.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(drawer).toHaveCount(0);
  expect(uploads).toHaveLength(1);
  expect(writes[0]).toMatchObject({
    body: { name: "只更新来源名称", image_url: oldCover },
  });
});

test("published Other content cannot replace the cover from its read-only form", async ({
  page,
}) => {
  await fixture(page, "PUBLISHED");
  await page.goto("/catalog/others?edit=other-cover");
  const drawer = page.getByRole("dialog");
  await expect(
    drawer.getByLabel("上传封面图片", { exact: true }),
  ).toBeDisabled();
  await expect(
    drawer.getByRole("button", { name: "更换图片", exact: true }),
  ).toBeDisabled();
  await expect(
    drawer.getByRole("button", { name: "保存草稿", exact: true }),
  ).toHaveCount(0);
});

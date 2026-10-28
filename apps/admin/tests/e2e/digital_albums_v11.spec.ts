import { expect, test } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";

test("four independent material scenes, scoped create, preview and edit", async ({
  page,
}) => {
  await page.goto("/digital-albums");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(
    page.getByRole("heading", { name: "数字相册", exact: true }),
  ).toBeVisible();
  const shots = resolve("../../output/albums-v11-20261022/screenshots");
  await mkdir(shots, { recursive: true });
  for (const [scene, name] of Object.entries({
    SHELF: "书架主题",
    ALBUM_COVER: "相册封面",
    ALBUM_PAGE: "相册内页",
    CARD_BACKGROUND: "卡片背景",
  })) {
    await page.goto(`/digital-albums/materials/${scene}`);
    await expect(
      page.getByRole("heading", { name, exact: true }),
    ).toBeVisible();
    await page
      .getByRole("button", { name: "新增系统素材", exact: true })
      .first()
      .click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("素材名称", { exact: true }).fill(`验收-${name}`);
    await dialog
      .getByLabel("资源 ID", { exact: true })
      .fill(`qa-${scene.toLowerCase()}`);
    await expect(dialog.getByLabel("使用场景", { exact: true })).toBeDisabled();
    await expect(dialog.getByText("场景示例 · 不保存作品")).toBeVisible();
    await page.screenshot({
      path: `${shots}/admin-${scene}.png`,
      fullPage: true,
      animations: 'disabled',
    });
    await dialog.getByRole("button", { name: "保存", exact: true }).click();
    await expect(dialog).not.toBeVisible();
    const row = page.getByRole("row").filter({ hasText: `验收-${name}` });
    await expect(row).toBeVisible();
    await row.getByRole("button", { name: "编辑", exact: true }).click();
    await expect(
      page.getByRole("dialog").getByLabel("资源 ID", { exact: true }),
    ).toBeDisabled();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "取消", exact: true })
      .click();
  }
  await page.goto("/digital-albums/materials/ALBUM_PAGE");
  await expect(page.getByText("验收-卡片背景", { exact: true })).toHaveCount(0);
  await expect(page.getByText("验收-相册内页", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("tab", { name: "贴纸", exact: true }),
  ).toHaveCount(0);
});

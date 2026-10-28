import { expect, test } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const regions = [
  {
    points: [
      { x: 0.05, y: 0.1 },
      { x: 0.45, y: 0.1 },
      { x: 0.45, y: 0.9 },
      { x: 0.05, y: 0.9 },
    ],
  },
  {
    points: [
      { x: 0.55, y: 0.1 },
      { x: 0.95, y: 0.1 },
      { x: 0.95, y: 0.9 },
      { x: 0.55, y: 0.9 },
    ],
  },
];
const image = Buffer.from(
  '<svg xmlns="http://www.w3.org/2000/svg" width="700" height="460"><rect width="700" height="460" fill="#243043"/><rect x="35" y="46" width="280" height="368" fill="#b96d80"/><rect x="385" y="46" width="280" height="368" fill="#658fb5"/></svg>',
);
const preview = `data:image/svg+xml;base64,${image.toString("base64")}`;

test("multi-card recognition requires explicit selection and submits only that card", async ({
  page,
}) => {
  let previewBody = "";
  let confirmedBody = "";
  await page.addInitScript(() =>
    sessionStorage.setItem(
      "fanos-admin-session",
      JSON.stringify({ access_token: "scan-ui-fixture" }),
    ),
  );
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    let data: any = {};
    if (path.endsWith("/console/me"))
      data = { id: "scan-fixture", name: "测试管理员", role: "admin" };
    else if (path.endsWith("/console/catalog"))
      data = {
        groups: [],
        idols: [],
        cards: [],
        albums: [],
        events: [],
        others: [],
        tags: [],
        records: [],
      };
    else if (path.endsWith("/cards/crop-preview")) {
      previewBody = route.request().postData() || "";
      data = { preview_url: preview, width: 700, height: 460, regions };
    } else if (path.endsWith("/cards/recognize")) {
      confirmedBody = route.request().postData() || "";
      data = {
        status: "unrecognized",
        image_url: "/media/selected-card-2.png",
        indexed_count: 10,
        unavailable_count: 0,
        candidates: [],
      };
    }
    await route.fulfill({ json: { code: 0, data } });
  });
  await page.goto("/catalog/cards");
  // API/image fixtures isolate this interaction test; backend tests exercise real decoding/detection.
  await page
    .getByLabel("上传小卡识别图片")
    .setInputFiles({ name: "cards.png", mimeType: "image/png", buffer: image });
  await expect(page.getByRole("dialog")).toBeVisible();
  const confirm = page.getByRole("button", {
    name: "确认裁剪并识别",
    exact: true,
  });
  await expect(confirm).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "选择小卡 2", exact: true }),
  ).toHaveAttribute("aria-pressed", "false");
  expect(previewBody).toContain('name="mode"');
  expect(previewBody).toContain("recognition");
  expect(confirmedBody).toBe("");
  await page.getByRole("button", { name: "选择小卡 2", exact: true }).click();
  await expect(confirm).toBeEnabled();
  await expect(
    page.getByRole("button", { name: "选择小卡 2", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  const output = resolve("../../output/admin-refresh-20261028/screenshots");
  mkdirSync(output, { recursive: true });
  await page.screenshot({
    path: resolve(output, "scan-select-second.png"),
    animations: "disabled",
  });
  await confirm.click();
  await expect(page).toHaveURL(/\/catalog\/cards\/new\?image_url=/);
  expect(confirmedBody).toContain(JSON.stringify(regions[1]));
  expect(confirmedBody).not.toContain(JSON.stringify(regions[0]));
  expect(page.url()).toContain("selected-card-2.png");
});

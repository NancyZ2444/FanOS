import { expect, test, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
const output = resolve("../../output/admin-duplicate-warning-20261028");
const group = { id: "group-ui", name: "测试组合", status: "PUBLISHED" };
const idol = {
  id: "idol-ui",
  name: "测试艺人",
  status: "PUBLISHED",
  group_id: group.id,
};
const card = {
  id: "card-existing",
  title: "已有同款",
  release_date: "2026-10-28",
  updated_at: "2026-10-28T00:00:00Z",
  created_at: "2026-10-28T00:00:00Z",
  tags: [],
  status: "PUBLISHED",
  group_id: group.id,
  idol_id: idol.id,
  image_url: "/images/default-card-back.png",
};
async function fixture(page: Page, failure = false, pending = false) {
  const writes: any[] = [];
  const checks: any[] = [];
  await page.addInitScript(() =>
    sessionStorage.setItem(
      "fanos-admin-session",
      JSON.stringify({ access_token: "duplicate-test" }),
    ),
  );
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    const method = route.request().method();
    let data: any = { items: [] };
    if (path.endsWith("/console/me"))
      data = { id: "admin-test", name: "本地测试", role: "admin" };
    else if (path.endsWith("/console/catalog"))
      data = {
        groups: [group],
        idols: [idol],
        albums: [],
        events: [],
        others: [],
        cards: [{ ...card, status: pending ? "PENDING" : card.status }],
        tags: [],
        records: [],
      };
    else if (path.endsWith("/cards/similar")) {
      checks.push(route.request().postDataJSON());
      if (failure) {
        await route.fulfill({ status: 503, json: { message: "模型暂不可用" } });
        return;
      }
      data = {
        indexed_count: 1,
        unavailable_count: 0,
        candidates: [{ score: 0.94, card }],
      };
    } else if (path.endsWith("/cards") && method === "POST") {
      writes.push(route.request().postDataJSON());
      data = { ...card, id: "created", status: "DRAFT" };
    } else if (
      path.endsWith("/cards/card-existing/actions") ||
      path.endsWith("/cards/batch")
    ) {
      writes.push(route.request().postDataJSON());
      data = card;
    } else if (path.includes("/feedback/fb-duplicate")) {
      if (method === "POST") writes.push(route.request().postDataJSON());
      data = {
        id: "fb-duplicate",
        kind: "MISSING_CARD",
        revision: 1,
        name: "待新增小卡",
        status: "PENDING",
        result: "PENDING",
        entity_type: "cards",
        entity_id: "draft-own",
        user: { id: "test", name: "测试用户" },
        created_at: "2026-10-28",
        review: {},
        history: [],
        submission: {
          missing: {
            group_id: group.id,
            idol_id: idol.id,
            title: "待新增小卡",
          },
          front: { image_url: "/media/feedback.png" },
        },
      };
    } else if (path.endsWith("/imports"))
      data = {
        items: [
          {
            id: "import-ui",
            kind: "cards",
            filename: "cards.csv",
            status: "COMPLETED",
            rows: [
              {
                row: 2,
                data: { title: "导入卡", image_url: "/media/imported.png" },
                created_id: "draft-import",
              },
            ],
            errors: [],
            imported_count: 1,
          },
        ],
      };
    await route.fulfill({ json: { code: 0, data } });
  });
  return { writes, checks };
}
test("image import reminds before creating and requires explicit continuation", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto(
    "/catalog/cards/new?group_id=group-ui&image_url=%2Fmedia%2Fnew.png",
  );
  await expect(page.getByText("发现 1 张相似小卡，新增前请核对")).toBeVisible();
  await expect(page.getByRole("link", { name: /94% 相似/ })).toHaveAttribute(
    "href",
    "/catalog/cards/card-existing/detail",
  );
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("确认不是重复图鉴");
  expect(f.writes).toHaveLength(0);
  await page.getByRole("button", { name: "返回核对", exact: true }).click();
  expect(f.writes).toHaveLength(0);
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await page.getByRole("button", { name: "已核对，继续", exact: true }).click();
  await expect.poll(() => f.writes.length).toBe(1);
  expect(f.checks.length).toBeGreaterThan(1);
});
test("failed checks do not pretend no duplicate and allow reviewed override", async ({
  page,
}) => {
  const f = await fixture(page, true);
  await page.goto(
    "/catalog/cards/new?group_id=group-ui&image_url=%2Fmedia%2Fnew.png",
  );
  await expect(page.getByText("暂未完成相似小卡检查")).toBeVisible();
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("模型暂不可用");
  expect(f.writes).toHaveLength(0);
  await page.getByRole("button", { name: "已核对，继续", exact: true }).click();
  await expect.poll(() => f.writes.length).toBe(1);
});
test("feedback creation checks existing image and excludes linked draft", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto("/catalog/additions/fb-duplicate");
  await expect(page.getByText("发现 1 张相似小卡，新增前请核对")).toBeVisible();
  expect(f.checks[0]).toEqual({
    image_url: "/media/feedback.png",
    exclude_card_id: "draft-own",
  });
  await page.getByRole("button", { name: "编辑", exact: true }).click();
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("发现 1 张相似小卡");
  expect(f.writes).toHaveLength(0);
  await page.getByRole("button", { name: "返回核对", exact: true }).click();
});
test("empty new card uses supplied default artwork and layout remains bounded", async ({
  page,
}) => {
  await fixture(page);
  await page.goto("/catalog/cards/new?group_id=group-ui");
  await page.getByText("基础信息", { exact: true }).first().click();
  mkdirSync(output, { recursive: true });
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    await expect(
      page.locator(".material-previews img, .card-art img").first(),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await expect(page.locator(".app-shell")).toHaveCount(1);
    await expect(page.locator("iframe")).toHaveCount(0);
    await expect(page.locator(".editor-footer")).toContainText("保存草稿");
    await page.evaluate(async () => {
      await document.fonts.ready;
      await new Promise(requestAnimationFrame);
      await new Promise(requestAnimationFrame);
    });
    await page.screenshot({
      animations: "disabled",
      path: resolve(output, `default-card-new-${width}.png`),
      fullPage: false,
    });
  }
});

test("import result offers per-row duplicate lookup excluding newly created draft", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto("/catalog/import?kind=cards");
  await page.getByRole("button", { name: "查看结果", exact: true }).click();
  await expect(
    page.getByText("新增前请核对相似小卡", { exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "核对相似卡", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("发现 1 张相似小卡");
  expect(f.checks[0]).toEqual({
    image_url: "/media/imported.png",
    exclude_card_id: "draft-import",
  });
  await expect(page.getByRole("link", { name: "打开草稿" })).toHaveAttribute(
    "href",
    "/catalog/cards/draft-import",
  );
  mkdirSync(output, { recursive: true });
  await page.screenshot({
    path: resolve(output, "import-similarity-1440.png"),
    fullPage: false,
  });
});

for (const batch of [false, true]) {
  test(`list ${batch ? "batch" : "single"} publication requires duplicate confirmation`, async ({
    page,
  }) => {
    const f = await fixture(page, false, true);
    await page.goto("/catalog/cards");
    if (batch) {
      await page.locator("tr[data-row-key=card-existing] input[type=checkbox]").check();
      await page.getByRole("button", { name: "批量发布", exact: true }).click();
    } else {
      await page.locator("tbody").getByRole("button", { name: /更多/ }).click();
      await page.getByText("审核通过并发布", { exact: true }).click();
    }
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "发布", exact: true })
      .click();
    await expect(
      page.locator(".ant-modal-confirm-title").filter({ hasText: "发现 1 张相似小卡，请先核对" }),
    ).toBeVisible();
    expect(f.writes).toHaveLength(0);
    expect(f.checks[0].exclude_card_id).toBe("card-existing");
    await page
      .getByRole("button", { name: "已核对，继续", exact: true })
      .click();
    await expect.poll(() => f.writes.length).toBe(1);
    expect(f.writes[0]).toEqual(
      batch
        ? { action: "publish", ids: ["card-existing"] }
        : { action: "publish" },
    );
  });
}
test("editor freezes form while saving and navigating away invalidates duplicate approval", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto(
    "/catalog/cards/new?group_id=group-ui&image_url=%2Fmedia%2Fnew.png",
  );
  await page.getByText("基础信息", { exact: true }).first().click();
  await expect(page.getByText("发现 1 张相似小卡，新增前请核对")).toBeVisible();
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("发现 1 张相似小卡");
  await expect(
    page.getByRole("button", { name: "取消", exact: true }),
  ).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "上一步", exact: true }),
  ).toBeDisabled();
  await expect(page.locator("form input").first()).toBeDisabled();
  // A route change/unmount while the context modal remains open must never write.
  await page.evaluate(() => {
    history.pushState({}, "", "/catalog/cards");
    dispatchEvent(new PopStateEvent("popstate"));
  });
  await page.getByRole("button", { name: "已核对，继续", exact: true }).click();
  expect(f.writes).toHaveLength(0);
});

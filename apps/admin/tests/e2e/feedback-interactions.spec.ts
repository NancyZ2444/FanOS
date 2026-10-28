import { test, expect, type Page } from "@playwright/test";
import { apiRoot, data, setupFeedback } from "./feedback-fixtures";

async function edit(page: Page, kind: string, id: string) {
  await page.goto(`/catalog/${kind}/${id}`);
  await page.getByRole("button", { name: "编辑", exact: true }).click();
}
async function choose(page: Page, label: string, option: string) {
  await page.getByRole("combobox", { name: label, exact: true }).press("Enter");
  await page
    .locator(".ant-select-dropdown:visible")
    .getByText(option, { exact: true })
    .click();
}
async function publish(page: Page, missing = false) {
  const label = missing ? "发布小卡并收录" : "确认更新并发布";
  await page.getByRole("button", { name: label, exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: label, exact: true })
    .click();
}

test("missing card: required note, cancel guard, failed save keeps input, retry and publish", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createMissing();
  await edit(page, "missing-cards", row.id);
  await page
    .getByRole("button", { name: "发布小卡并收录", exact: true })
    .click();
  await expect(
    page.getByText("请填写面向用户的处理说明，未采纳时须说明具体原因。"),
  ).toBeVisible();
  await page.getByLabel("小卡类型", { exact: true }).fill("REGULAR");
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("已核对专辑及小卡正面图片。");
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "继续编辑" })
    .click();
  await expect(page.getByLabel("小卡类型", { exact: true })).toHaveValue(
    "REGULAR",
  );
  const endpoint = `**/feedback/${row.id}/actions`;
  const bodies: any[] = [];
  let fail = true;
  await page.route(endpoint, async (route) => {
    bodies.push(route.request().postDataJSON());
    if (fail)
      await route.fulfill({
        status: 500,
        contentType: "application/json",
        body: JSON.stringify({ message: "本地模拟保存失败" }),
      });
    else await route.continue();
  });
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(
    page.getByText("本地模拟保存失败", { exact: true }),
  ).toBeVisible();
  await expect(page.getByLabel("小卡类型", { exact: true })).toHaveValue(
    "REGULAR",
  );
  fail = false;
  await page.getByRole("button", { name: "保存草稿", exact: true }).dblclick();
  await expect
    .poll(async () => (await setup.detail(row.id)).entity_id)
    .toBeTruthy();
  await expect(page.locator(".feedback-submit-error")).toHaveCount(0);
  expect(bodies).toHaveLength(2);
  expect(bodies[1]).toEqual(bodies[0]);
  const draft = await setup.detail(row.id);
  expect(draft.result).toBe("PENDING");
  await expect(page.getByLabel("小卡类型", { exact: true })).toHaveValue(
    "REGULAR",
  );
  await choose(page, "正面图片使用状态", "已确认获得使用授权");
  await publish(page, true);
  await expect
    .poll(async () => (await setup.detail(row.id)).result)
    .toBe("INCLUDED");
  expect((await setup.detail(row.id)).entity_id).toBe(draft.entity_id);
  await expect(
    page.getByRole("button", { name: "编辑", exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "保存草稿", exact: true }),
  ).toHaveCount(0);
});

test("correction: save review, edit prefill, reject reason validation and partial publish", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createCorrection();
  await edit(page, "corrections", row.id);
  await choose(page, "介绍处理结果", "未采纳");
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("名称按官方资料修正，介绍暂保持原值。");
  await page.getByRole("button", { name: "保存审核意见", exact: true }).click();
  await expect
    .poll(async () => (await setup.detail(row.id)).revision)
    .toBe(row.revision + 1);
  await expect(page.getByLabel("公开处理说明", { exact: true })).toHaveValue(
    "名称按官方资料修正，介绍暂保持原值。",
  );
  await page
    .getByRole("button", { name: "确认更新并发布", exact: true })
    .click();
  await expect(
    page.getByText("请填写未采纳原因。", { exact: true }),
  ).toBeVisible();
  await page
    .getByLabel("未采纳原因", { exact: true })
    .fill("缺少可核实的介绍依据。");
  await publish(page);
  await expect
    .poll(async () => (await setup.detail(row.id)).result)
    .toBe("INCLUDED");
  const done = await setup.detail(row.id);
  expect(
    done.review.decisions.find((d: any) => d.key === "description").decision,
  ).toBe("REJECT");
  expect(done.latest.fields.find((f: any) => f.key === "name").current).toBe(
    row.submission.fields.find((f: any) => f.key === "name").suggested,
  );
});

test("conflict preserves edits until explicit refresh, navigation and cancel discard are guarded", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createCorrection();
  await edit(page, "corrections", row.id);
  await page.getByLabel("内部备注", { exact: true }).fill("本地未保存的备注");
  await page.getByRole("button", { name: "返回图鉴问题纠错" }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "继续编辑" })
    .click();
  await expect(page).toHaveURL(new RegExp(row.id));
  await setup.action(row, "start", { internal_note: "另一位运营已更新" });
  await page.getByRole("button", { name: "保存审核意见" }).click();
  await expect(
    page.getByText("反馈已被其他操作更新，请刷新", { exact: true }),
  ).toBeVisible();
  await expect(page.getByLabel("内部备注", { exact: true })).toHaveValue(
    "本地未保存的备注",
  );
  await expect(
    page.getByRole("button", { name: "保存审核意见" }),
  ).toBeDisabled();
  await page.getByRole("button", { name: "刷新详情" }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "放弃修改" })
    .click();
  await page.getByRole("button", { name: "编辑", exact: true }).click();
  await expect(page.getByLabel("内部备注", { exact: true })).toHaveValue(
    "另一位运营已更新",
  );
  await page.getByLabel("内部备注", { exact: true }).fill("取消应丢弃这一行");
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "放弃修改" })
    .click();
  await page.getByRole("button", { name: "编辑", exact: true }).click();
  await expect(page.getByLabel("内部备注", { exact: true })).toHaveValue(
    "另一位运营已更新",
  );
});

test("reject confirmation identifies the record; cancel does not act, completion is read only", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createMissing();
  await edit(page, "missing-cards", row.id);
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("图片资料不足，请补充清晰正反面。");
  await page.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "无法采用", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText(row.name);
  await expect(page.getByRole("dialog")).toContainText("1 条反馈");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "取消", exact: true })
    .click();
  expect((await setup.detail(row.id)).result).toBe("PENDING");
  await page.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "无法采用", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "无法采用", exact: true })
    .click();
  await expect
    .poll(async () => (await setup.detail(row.id)).result)
    .toBe("NOT_INCLUDED");
  await expect(
    page.getByRole("button", { name: "编辑", exact: true }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "返回列表", exact: true }).click();
  const record = page
    .locator(".ant-table-tbody tr")
    .filter({ hasText: row.id });
  await expect(record).toContainText("无法采用");
  await expect(
    record.getByRole("button", { name: "编辑", exact: true }),
  ).toHaveCount(0);
});

test("filters, cursor pagination and both empty states use the same API contract", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createCorrection();
  const adminRow = await setup.detail(row.id);
  let mode = "page";
  const queries: URLSearchParams[] = [];
  await page.route("**/admin/console/feedback?*", async (route) => {
    const query = new URL(route.request().url()).searchParams;
    queries.push(query);
    const empty =
      mode === "empty" ||
      query.get("status") === "PROCESSED" ||
      query.get("handler_id");
    await route.fulfill({
      json: {
        code: 0,
        data: {
          items: empty ? [] : [adminRow],
          next_offset:
            mode === "page" && query.get("offset") === "0" ? 20 : null,
        },
      },
    });
  });
  await page.goto("/catalog/corrections");
  await page.getByRole("button", { name: "下一页" }).click();
  await expect(
    page.getByRole("navigation", { name: "列表分页" }),
  ).toContainText("第 2 页");
  expect(queries.at(-1)?.get("offset")).toBe("20");
  await page.getByRole("tab", { name: "已处理", exact: true }).click();
  await expect(page.getByText("无匹配结果", { exact: true })).toBeVisible();
  expect(queries.at(-1)?.get("offset")).toBe("0");
  await page.getByRole("button", { name: "重置筛选" }).click();
  await page.getByRole("button", { name: "高级筛选" }).click();
  await page
    .getByLabel("处理人编号", { exact: true })
    .fill("local-test-operator");
  await expect(page.getByText("无匹配结果", { exact: true })).toBeVisible();
  expect(queries.at(-1)?.get("handler_id")).toBe("local-test-operator");
  mode = "empty";
  await page.getByRole("button", { name: "重置", exact: true }).click();
  await expect(page.getByText("尚无数据", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "查看图鉴" })).toBeVisible();
  expect(queries.at(-1)?.get("handler_id")).toBeNull();
  expect(
    queries.every(
      (q) => q.get("kind") === "CORRECTION" && q.get("limit") === "20",
    ),
  ).toBe(true);
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth - innerWidth,
      ),
    ).toBeLessThanOrEqual(1);
    expect(
      await page
        .locator(".table-panel")
        .evaluate((el) => el.scrollWidth - el.clientWidth),
    ).toBeLessThanOrEqual(1);
  }
});

test("existing card match and already-fixed correction keep their original completion rules", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const missing = await setup.createMissing();
  const objects = await data(
    await request.get(apiRoot + "/feedback/objects?entity_type=cards", {
      headers: setup.headers,
    }),
  );
  const card = objects.items.find((v: any) => v.id === "card-aria-01");
  expect(card).toBeTruthy();
  await edit(page, "missing-cards", missing.id);
  await page
    .getByRole("combobox", { name: "匹配已有小卡", exact: true })
    .press("Enter");
  await page
    .locator(".ant-select-dropdown:visible .ant-select-item-option")
    .filter({ hasText: card.id })
    .click();
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("核对为已收录的小卡，关联既有记录。");
  await page.getByRole("button", { name: "关联并完成", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "关联并完成", exact: true })
    .click();
  await expect
    .poll(async () => (await setup.detail(missing.id)).result)
    .toBe("NOT_INCLUDED");
  expect((await setup.detail(missing.id)).entity_id).toBe(card.id);
  const correction = await setup.createCorrection();
  await edit(page, "corrections", correction.id);
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("已由其他修改修正，不重复采纳。");
  await page.getByRole("button", { name: "更多", exact: true }).click();
  await page
    .getByRole("menuitem", { name: "已由其他修改修正", exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确认已由其他修改修正", exact: true })
    .click();
  await expect
    .poll(async () => (await setup.detail(correction.id)).result)
    .toBe("NOT_INCLUDED");
});

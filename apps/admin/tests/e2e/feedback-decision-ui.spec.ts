import { expect, test, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const kinds = ["MISSING_CARD", "CORRECTION", "MISSING_CATALOG"] as const;
type Kind = (typeof kinds)[number];
const acceptedNote = "已采纳，待发布后更新图鉴。";
const publishLabel = (kind: Kind) =>
  kind === "MISSING_CARD"
    ? "发布小卡并收录"
    : kind === "CORRECTION"
      ? "确认更新并发布"
      : "发布并收录";
const routePath = (kind: Kind) =>
  `/catalog/${kind === "CORRECTION" ? "corrections" : "additions"}/fb-decisions`;

async function fixture(
  page: Page,
  kind: Kind,
  permissions?: string[],
  options: { missingSource?: boolean; missingAlbum?: boolean } = {},
) {
  const requests: any[] = [];
  let failNext = false;
  const group = { id: "group-ui", name: "测试组合", status: "PUBLISHED" };
  const idol = {
    id: "idol-ui",
    name: "测试艺人",
    status: "PUBLISHED",
    group_id: group.id,
  };
  const album = {
    id: "album-ui",
    name: "测试专辑",
    status: "PUBLISHED",
    group_id: group.id,
  };
  const fields = [
    {
      key: "name",
      label: "名称",
      type: "text",
      current: "旧名称",
      suggested: "已核实名称",
      mode: "SET",
      reason: "",
    },
  ];
  let feedback: any = {
    id: "fb-decisions",
    revision: 1,
    kind,
    name: "本地审核申请",
    status: "PENDING",
    status_label: "待处理",
    result: "PENDING",
    review_decision: null,
    can_publish: false,
    user: { name: "测试用户", id: "user-ui" },
    created_at: "2026-10-28T00:00:00Z",
    public_note: "",
    internal_note: "",
    entity_type:
      kind === "MISSING_CARD"
        ? "cards"
        : options.missingAlbum
          ? "albums"
          : "groups",
    entity_id: kind === "CORRECTION" ? group.id : "",
    submission:
      kind === "MISSING_CARD"
        ? {
            missing: {
              title: "待核实小卡",
              group_id: group.id,
              idol_id: idol.id,
              source_entity_type: "ALBUM",
              source_entity_id: options.missingSource ? "" : album.id,
              ...(options.missingSource
                ? { missing_source_name: "用户待补充专辑" }
                : {}),
              card_type: "REGULAR",
            },
          }
        : kind === "MISSING_CATALOG"
          ? options.missingAlbum
            ? {
                catalog: {
                  name: "待核实专辑",
                  artists: [{ type: "groups", id: group.id }],
                },
                catalog_schema: [
                  ...fields,
                  { key: "versions", label: "专辑版本", type: "list" },
                ],
              }
            : { catalog: { name: "新组合" }, catalog_schema: fields }
          : { fields },
    review: {},
    latest: { version: "v1", fields },
    history: [],
  };
  await page.addInitScript(() =>
    sessionStorage.setItem(
      "fanos-admin-session",
      JSON.stringify({ access_token: "decision-ui-fixture" }),
    ),
  );
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    let data: any = { items: [] };
    if (path.endsWith("/console/me"))
      data = {
        id: "admin-ui",
        name: "本地验证",
        role: permissions ? "custom" : "admin",
        permissions,
      };
    else if (path.endsWith("/console/catalog"))
      data = {
        groups: [group],
        idols: [idol],
        albums: [album],
        cards: [],
        events: [],
        others: [],
        tags: [],
        records: [],
      };
    else if (path.endsWith("/console/records/versions"))
      data = {
        items: [
          {
            id: "version-ui",
            entity_type: "albums",
            entity_id: album.id,
            status: "PUBLISHED",
            data: { name: "已核实版本" },
          },
        ],
      };
    else if (path.endsWith("/console/cards/similar"))
      data = { candidates: [], indexed_count: 0, unavailable_count: 0 };
    else if (path.includes("/console/feedback/fb-decisions")) {
      if (route.request().method() === "POST") {
        const body = route.request().postDataJSON();
        requests.push(body);
        if (failNext) {
          failNext = false;
          await route.fulfill({
            status: 500,
            json: { message: "模拟保存失败" },
          });
          return;
        }
        feedback = {
          ...feedback,
          revision: feedback.revision + 1,
          internal_note: body.internal_note ?? feedback.internal_note,
        };
        if (["draft", "review"].includes(body.action)) {
          feedback.review_decision = null;
          feedback.can_publish = false;
          feedback.review = {
            decisions: body.decisions,
            catalog_draft: body.changes,
            review_decision_draft: body.review_decision,
            public_note_draft: body.public_note,
          };
          if (kind === "MISSING_CARD") feedback.draft = body.changes;
        } else if (body.action === "decide") {
          feedback.review_decision = body.review_decision;
          feedback.public_note = body.public_note;
          feedback.can_publish = body.review_decision === "ACCEPTED";
          feedback.result =
            body.review_decision === "REJECTED"
              ? "NOT_INCLUDED"
              : body.review_decision === "NEEDS_INFO"
                ? "NEEDS_INFO"
                : "PENDING";
          feedback.status = feedback.can_publish ? "PROCESSING" : "PROCESSED";
          feedback.status_label = feedback.can_publish
            ? "已采纳，待发布"
            : "已处理";
          feedback.review = {
            approved_payload: {
              changes: body.changes,
              decisions: body.decisions,
              object_version: body.object_version,
            },
            decisions: body.decisions,
          };
        } else if (body.action === "publish") {
          feedback.can_publish = false;
          feedback.result = "INCLUDED";
          feedback.status = "PROCESSED";
          feedback.status_label = "已处理";
          feedback.public_note = "已采纳并发布，图鉴已更新。";
        }
      }
      data = feedback;
    } else if (path.endsWith("/console/feedback"))
      data = { items: [feedback], next_offset: null };
    await route.fulfill({ json: { code: 0, data } });
  });
  return {
    requests,
    fail: () => {
      failNext = true;
    },
  };
}
async function edit(page: Page, kind: Kind) {
  await page.goto(routePath(kind));
  if (kind !== "MISSING_CATALOG")
    await page.getByRole("button", { name: "编辑", exact: true }).click();
}
async function submit(page: Page, kind: Kind) {
  await page.getByLabel("提交处理结果", { exact: true }).click();
  if (kind !== "MISSING_CATALOG") {
    const dialog = page.getByRole("dialog");
    await dialog
      .getByRole("button", { name: "提交处理结果", exact: true })
      .click();
    await expect(dialog).toBeHidden();
  }
}
async function publish(page: Page, kind: Kind) {
  await page
    .getByRole("button", { name: publishLabel(kind), exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: publishLabel(kind), exact: true })
    .click();
}

for (const kind of kinds) {
  test(`${kind}: accepted decision is submitted before publication`, async ({
    page,
  }) => {
    const { requests } = await fixture(page, kind);
    await edit(page, kind);
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toHaveCount(0);
    await page
      .locator(".feedback-result-options label")
      .filter({ hasText: /^已采纳$/ })
      .click();
    await expect(page.getByLabel("公开处理说明", { exact: true })).toHaveValue(
      acceptedNote,
    );
    await submit(page, kind);
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toBeVisible();
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({
      action: "decide",
      review_decision: "ACCEPTED",
      public_note: acceptedNote,
      revision: 1,
    });
    await expect(
      page.getByRole("button", { name: "提交处理结果", exact: true }),
    ).toHaveCount(0);
    await publish(page, kind);
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toHaveCount(0);
    expect(requests).toHaveLength(2);
    expect(Object.keys(requests[1]).sort()).toEqual([
      "action",
      "request_key",
      "revision",
    ]);
    expect(requests[1]).toMatchObject({ action: "publish", revision: 2 });
    await expect(
      page.getByText("已采纳并发布，图鉴已更新。", { exact: true }),
    ).toBeVisible();
  });
  for (const [name, decision] of [
    ["未采纳", "REJECTED"],
    ["信息缺失待补充", "NEEDS_INFO"],
  ]) {
    test(`${kind}: ${decision} clears note and requires a reason`, async ({
      page,
    }) => {
      const { requests } = await fixture(page, kind);
      await edit(page, kind);
      await page
        .locator(".feedback-result-options label")
        .filter({ hasText: /^已采纳$/ })
        .click();
      await page
        .locator(".feedback-result-options label")
        .filter({ hasText: new RegExp(`^${name}$`) })
        .click();
      await expect(
        page.getByLabel("公开处理说明", { exact: true }),
      ).toHaveValue("");
      await page
        .getByRole("button", { name: "提交处理结果", exact: true })
        .click();
      await expect(
        page
          .locator(".ant-form-item-explain-error")
          .filter({ hasText: "请填写面向用户的处理说明" }),
      ).toBeVisible();
      expect(requests).toHaveLength(0);
      await page
        .getByLabel("公开处理说明", { exact: true })
        .fill("请补充清晰卡面及发行日期。");
      await submit(page, kind);
      await expect(
        page.getByRole("button", { name: "提交处理结果", exact: true }),
      ).toHaveCount(0);
      expect(requests[0]).toMatchObject({
        action: "decide",
        review_decision: decision,
        public_note: "请补充清晰卡面及发行日期。",
      });
      await expect(
        page.getByRole("button", { name: publishLabel(kind), exact: true }),
      ).toHaveCount(0);
    });
  }
  test(`${kind}: empty catalog refresh preserves edits; saved draft requires a new decision`, async ({
    page,
  }) => {
    const { requests } = await fixture(page, kind);
    await edit(page, kind);
    await page
      .locator(".feedback-result-options label")
      .filter({ hasText: /^已采纳$/ })
      .click();
    await submit(page, kind);
    await page.getByRole("button", { name: "编辑", exact: true }).click();
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toHaveCount(0);
    await page
      .getByLabel("公开处理说明", { exact: true })
      .fill("修改后的内部拟用说明");
    await page
      .getByRole("button", {
        name: kind === "CORRECTION" ? "保存审核意见" : "保存草稿",
        exact: true,
      })
      .click();
    await expect(page.getByLabel("公开处理说明", { exact: true })).toHaveValue(
      "修改后的内部拟用说明",
    );
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toHaveCount(0);
    await submit(page, kind);
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toBeVisible();
    expect(requests.map((r) => r.action)).toEqual([
      "decide",
      kind === "CORRECTION" ? "review" : "draft",
      "decide",
    ]);
  });
  test(`${kind}: failed save preserves input and retries idempotently`, async ({
    page,
  }) => {
    const state = await fixture(page, kind);
    await edit(page, kind);
    await page
      .locator(".feedback-result-options label")
      .filter({ hasText: /^已采纳$/ })
      .click();
    await page
      .getByLabel("公开处理说明", { exact: true })
      .fill("已核实，保存失败时不得丢失");
    state.fail();
    const save = page.getByRole("button", {
      name: kind === "CORRECTION" ? "保存审核意见" : "保存草稿",
      exact: true,
    });
    await save.click();
    await expect(page.getByText("模拟保存失败", { exact: true })).toBeVisible();
    await expect(page.getByLabel("公开处理说明", { exact: true })).toHaveValue(
      "已核实，保存失败时不得丢失",
    );
    await save.click();
    await expect(page.getByText("模拟保存失败", { exact: true })).toHaveCount(
      0,
    );
    expect(state.requests).toHaveLength(2);
    expect(state.requests[1]).toEqual(state.requests[0]);
  });
}

for (const kind of ["MISSING_CARD", "MISSING_CATALOG"] as const) {
  test(`${kind}: HTTP without randomUUID saves added album/version and retries decisions idempotently`, async ({
    page,
  }) => {
    const state = await fixture(page, kind, undefined, {
      missingSource: kind === "MISSING_CARD",
      missingAlbum: kind === "MISSING_CATALOG",
    });
    await page.addInitScript(() => {
      Object.defineProperty(crypto, "randomUUID", {
        configurable: true,
        value: undefined,
      });
    });
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await edit(page, kind);
    expect(await page.evaluate(() => typeof crypto.randomUUID)).toBe(
      "undefined",
    );
    if (kind === "MISSING_CARD") {
      const select = async (id: string, text: string) => {
        await page
          .locator(".ant-select")
          .filter({ has: page.locator(`#${id}`) })
          .click();
        await page
          .locator(".ant-select-dropdown:visible")
          .getByText(text, { exact: true })
          .click();
      };
      await select("feedback-source", "测试专辑");
      await expect(page.locator("#feedback-version")).toBeEnabled();
      await select("feedback-version", "已核实版本");
    } else {
      await page.getByLabel("名称", { exact: true }).fill("已补全专辑");
      await page
        .getByLabel("专辑版本采用值", { exact: true })
        .fill("已核实版本");
    }
    const expectedChanges =
      kind === "MISSING_CARD"
        ? {
            source_entity_id: "album-ui",
            entity_version_id: "version-ui",
            version: "已核实版本",
          }
        : { name: "已补全专辑", versions: ["已核实版本"] };
    const save = page.getByRole("button", { name: "保存草稿", exact: true });
    state.fail();
    await save.click();
    await expect(page.getByText("模拟保存失败", { exact: true })).toBeVisible();
    await expect(save).toBeEnabled();
    await save.click();
    await expect(page.getByText("模拟保存失败", { exact: true })).toHaveCount(
      0,
    );
    await expect.poll(() => state.requests.length).toBe(2);
    expect(state.requests[0].changes).toMatchObject(expectedChanges);
    expect(state.requests[1]).toEqual(state.requests[0]);
    expect(state.requests[0].request_key).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    await page
      .locator(".feedback-result-options label")
      .filter({ hasText: /^已采纳$/ })
      .click();
    state.fail();
    await submit(page, kind);
    await expect(page.getByText("模拟保存失败", { exact: true })).toBeVisible();
    await expect(page.getByLabel("公开处理说明", { exact: true })).toHaveValue(
      acceptedNote,
    );
    await submit(page, kind);
    await expect(
      page.getByRole("button", { name: publishLabel(kind), exact: true }),
    ).toBeVisible();
    expect(state.requests).toHaveLength(4);
    expect(state.requests[2]).toMatchObject({
      action: "decide",
      revision: 2,
      review_decision: "ACCEPTED",
      public_note: acceptedNote,
      changes: expectedChanges,
    });
    expect(state.requests[3]).toEqual(state.requests[2]);
    expect(state.requests[2].request_key).not.toBe(
      state.requests[0].request_key,
    );
    expect(errors).toEqual([]);
  });

  test(`${kind}: key generation failure preserves input and releases save lock`, async ({
    page,
  }) => {
    const state = await fixture(page, kind);
    await page.addInitScript(() => {
      Object.defineProperty(crypto, "randomUUID", {
        configurable: true,
        value: undefined,
      });
      Object.defineProperty(crypto, "getRandomValues", {
        configurable: true,
        value: undefined,
      });
    });
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await edit(page, kind);
    await page
      .getByLabel("公开处理说明", { exact: true })
      .fill("生成编号失败后保留填写内容");
    const save = page.getByRole("button", { name: "保存草稿", exact: true });
    await save.click();
    await expect(
      page.getByText(
        "当前浏览器无法生成安全请求编号，请刷新页面或更换浏览器后重试。",
        { exact: true },
      ),
    ).toBeVisible();
    await expect(save).toBeEnabled();
    await expect(save).not.toHaveClass(/ant-btn-loading/);
    expect(state.requests).toHaveLength(0);
    await expect(page.getByLabel("公开处理说明", { exact: true })).toHaveValue(
      "生成编号失败后保留填写内容",
    );
    await page.evaluate(() => {
      Object.defineProperty(crypto, "getRandomValues", {
        configurable: true,
        value: Crypto.prototype.getRandomValues,
      });
    });
    await save.click();
    await expect.poll(() => state.requests.length).toBe(1);
    await expect(save).not.toHaveClass(/ant-btn-loading/);
    expect(state.requests[0].public_note).toBe("生成编号失败后保留填写内容");
    expect(errors).toEqual([]);
  });
}

test("decision form follows shared dimensions at three desktop widths", async ({
  page,
}) => {
  await fixture(page, "CORRECTION");
  await edit(page, "CORRECTION");
  await page
    .locator(".feedback-result-options label")
    .filter({ hasText: /^已采纳$/ })
    .click();
  const output = resolve("../../output/admin-feedback-decision-20261028");
  mkdirSync(output, { recursive: true });
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth - innerWidth,
      ),
    ).toBeLessThanOrEqual(1);
    expect(
      await page
        .locator(".feedback-result-options .ant-radio-button-wrapper")
        .evaluateAll((els) =>
          els.map((e) => Math.round(e.getBoundingClientRect().height)),
        ),
    ).toEqual([36, 36, 36]);
    await page.locator(".feedback-result-options").scrollIntoViewIfNeeded();
    await page.screenshot({
      path: resolve(output, `review-decision-${width}.png`),
      animations: "disabled",
    });
  }
});

test("edit-only role keeps internal draft without public decision actions", async ({
  page,
}) => {
  await fixture(page, "CORRECTION", ["catalog.view", "catalog.edit"]);
  await edit(page, "CORRECTION");
  await expect(
    page.getByRole("button", { name: "保存审核意见", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "提交处理结果", exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "确认更新并发布", exact: true }),
  ).toHaveCount(0);
});

test("publish-only role can decide and publish but cannot save an internal draft", async ({
  page,
}) => {
  await fixture(page, "CORRECTION", ["catalog.view", "catalog.publish"]);
  await edit(page, "CORRECTION");
  await expect(
    page.getByRole("button", { name: "保存审核意见", exact: true }),
  ).toHaveCount(0);
  await page
    .locator(".feedback-result-options label")
    .filter({ hasText: /^已采纳$/ })
    .click();
  await submit(page, "CORRECTION");
  await expect(
    page.getByRole("button", { name: "确认更新并发布", exact: true }),
  ).toBeVisible();
});

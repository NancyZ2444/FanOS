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

async function fixture(page: Page, kind: Kind, permissions?: string[]) {
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
    entity_type: kind === "MISSING_CARD" ? "cards" : "groups",
    entity_id: kind === "CORRECTION" ? group.id : "",
    submission:
      kind === "MISSING_CARD"
        ? {
            missing: {
              title: "待核实小卡",
              group_id: group.id,
              idol_id: idol.id,
              source_entity_type: "ALBUM",
              source_entity_id: album.id,
              card_type: "REGULAR",
            },
          }
        : kind === "MISSING_CATALOG"
          ? { catalog: { name: "新组合" }, catalog_schema: fields }
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
  await page.getByRole("button", { name: "提交处理结果", exact: true }).click();
  if (kind !== "MISSING_CATALOG")
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "提交处理结果", exact: true })
      .click();
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

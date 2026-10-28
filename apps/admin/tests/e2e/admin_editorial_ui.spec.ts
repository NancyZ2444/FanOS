import { expect, test, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
const output = resolve("../../output/admin-catalog-20261028/editorial");
const png =
  "data:image/svg+xml;base64," +
  Buffer.from(
    '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="280" viewBox="0 0 200 280"><rect width="200" height="280" rx="12" fill="#7056bd"/><circle cx="100" cy="94" r="44" fill="#d8cbf5"/><path d="M28 226c0-92 144-92 144 0" fill="#b59ddf"/><text x="100" y="260" text-anchor="middle" fill="white" font-family="sans-serif" font-size="20">FAN OS</text></svg>',
  ).toString("base64");
async function fixture(page: Page) {
  const requests: { path: string; body: any }[] = [];
  let config: any = {
    enabled: false,
    type: "help_page",
    display_name: "登录帮助",
    contact: "help@example.test",
    backup: "工作日回复",
    version: 2,
  };
  const group = { id: "group-ui", name: "测试组合", status: "PUBLISHED" };
  const idol = {
    id: "idol-ui",
    name: "测试艺人",
    status: "PUBLISHED",
    group_id: group.id,
  };
  const card = {
    id: "card-ui",
    title: "测试卡面",
    image_url: png,
    idol_name: idol.name,
    idol_id: idol.id,
    group_id: group.id,
    source: "测试专辑",
    status: "PUBLISHED",
  };
  let feedback: any = {
    id: "fb-editorial",
    kind: "MISSING_CATALOG",
    revision: 1,
    name: "新增组合申请",
    status: "PENDING",
    result: "PENDING",
    status_label: "待处理",
    entity_type: "groups",
    user: { id: "user-ui", name: "测试用户" },
    created_at: "2026-10-28T01:20:00Z",
    public_note: "",
    internal_note: "",
    review: {},
    history: [{ at: "2026-10-28T01:20:00Z", note: "已收到反馈" }],
    submission: {
      catalog: { name: "新组合", region: "韩国", debut_date: "2026-01-01" },
      notes: "请核实组合资料",
      catalog_schema: [
        { key: "name", label: "官方名称", type: "text" },
        { key: "region", label: "地区", type: "text" },
        { key: "debut_date", label: "出道日期", type: "date" },
      ],
    },
  };
  const profiles: Record<string, any> = {};
  for (const kind of ["groups", "idols"])
    profiles[kind] = {
      profile_revision: 1,
      version: "v1",
      draft_version: "",
      draft: null,
      fields: [
        {
          key: "description",
          label: "简介",
          type: "long_text",
          current: "原简介",
          section: "intro",
        },
        {
          key: "name",
          label: "官方名称",
          type: "text",
          current: kind === "groups" ? group.name : idol.name,
          section: "basic",
        },
        {
          key: "name_translated",
          label: "中文名称",
          type: "text",
          current: "中文名称",
          section: "basic",
        },
        {
          key: "debut_date",
          label: "出道日期",
          type: "date",
          current: "2020-01-01",
          section: "basic",
        },
        {
          key: "region",
          label: "地区",
          type: "text",
          current: "韩国",
          section: "basic",
        },
        {
          key: "career_text",
          label: "从艺历程",
          type: "long_text",
          current: "旧历程",
          section: "career",
        },
      ],
    };
  await page.addInitScript(() =>
    sessionStorage.setItem(
      "fanos-admin-session",
      JSON.stringify({ access_token: "editorial-ui-fixture" }),
    ),
  );
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    const body =
      route.request().method() === "GET"
        ? null
        : route.request().postDataJSON();
    if (body) requests.push({ path, body });
    let data: any = { items: [] };
    if (path.endsWith("/console/me"))
      data = { id: "admin-ui", name: "验收管理员", role: "admin" };
    else if (path.endsWith("/console/catalog"))
      data = {
        groups: [group],
        idols: [idol],
        cards: [card],
        albums: [],
        events: [],
        others: [],
        tags: [],
        records: [],
      };
    else if (path.includes("/console/feedback/fb-editorial")) {
      if (body)
        feedback = {
          ...feedback,
          revision: feedback.revision + 1,
          review:
            body.action === "publish"
              ? feedback.review
              : {
                  catalog_draft: body.changes,
                  ...(body.action === "decide"
                    ? { approved_payload: { changes: body.changes } }
                    : {
                        public_note_draft: body.public_note,
                        review_decision_draft: body.review_decision,
                      }),
                },
          internal_note: body.internal_note ?? feedback.internal_note,
          ...(body.action === "decide"
            ? {
                review_decision: body.review_decision,
                public_note: body.public_note,
                can_publish: true,
                status_label: "已采纳，待发布",
              }
            : body.action === "publish"
              ? {
                  result: "INCLUDED",
                  can_publish: false,
                  status_label: "已采纳并发布",
                }
              : {}),
        };
      data = feedback;
    } else if (path.endsWith("/auth/meta"))
      data = { environment: "test", permissions: ["auth.support.manage"] };
    else if (path.endsWith("/auth/support-entry")) {
      if (body) config = { ...config, ...body, version: config.version + 1 };
      data = config;
    } else if (path.includes("/console/entities/"))
      data = {
        entity: path.includes("/groups/")
          ? group
          : path.includes("/cards/")
            ? card
            : idol,
        memberships: [
          {
            id: "member-ui",
            group_id: group.id,
            idol_id: idol.id,
            start_date: "2020-01-01",
            end_date: null,
            status: "active",
          },
        ],
        cards: [card],
        entities: [],
        assets: [],
        accounts: [],
        history: [],
      };
    else if (path.includes("/console/profiles/")) {
      const kind = path.includes("/groups/") ? "groups" : "idols";
      const profile = profiles[kind];
      if (path.endsWith("/draft")) {
        profile.draft = body;
        profile.draft_version = "d1";
      } else if (path.endsWith("/publish")) {
        for (const f of profile.fields)
          if (f.key in body.values) f.current = body.values[f.key];
        profile.profile_revision++;
        profile.version = "v2";
        profile.draft = null;
        profile.draft_version = "";
      }
      data = profile;
    }
    await route.fulfill({ json: { code: 0, data } });
  });
  return requests;
}
async function layout(page: Page, name: string) {
  for (const width of [1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth - innerWidth,
      ),
    ).toBeLessThanOrEqual(1);
    expect(
      await page
        .locator("main .ant-input:not(textarea), main .ant-select-selector")
        .evaluateAll((els) =>
          els
            .filter((e) => e.getBoundingClientRect().width > 0)
            .map((e) => Math.round(e.getBoundingClientRect().height))
            .filter((h) => h !== 36),
        ),
    ).toEqual([]);
    mkdirSync(output, { recursive: true });
    await page.screenshot({
      path: resolve(output, `${name}-${width}.png`),
      fullPage: true,
      animations: "disabled",
    });
  }
}
for (const [kind, id] of [
  ["groups", "group-ui"],
  ["idols", "idol-ui"],
])
  test(`${kind} dossier is a normal form with private draft and publication preview`, async ({
    page,
  }) => {
    const requests = await fixture(page);
    await page.goto(`/catalog/${kind}/${id}/detail?tab=profile`);
    await page.getByRole("tab", { name: "基本资料", exact: true }).click();
    await expect(page.getByRole("checkbox", { name: "官方名称" })).toHaveCount(
      0,
    );
    await expect(page.getByText("拟采用值", { exact: true })).toHaveCount(0);
    await expect(page.getByLabel("官方名称", { exact: true })).toHaveValue(
      kind === "groups" ? "测试组合" : "测试艺人",
    );
    await page.getByLabel("官方名称", { exact: true }).fill("更正后的官方名称");
    await page.getByRole("button", { name: "保存草稿", exact: true }).click();
    await expect(page.getByText("公开修订说明", { exact: true })).toHaveCount(
      0,
    );
    expect(requests.find((r) => r.path.endsWith("/draft"))?.body.summary).toBe(
      "",
    );
    await expect(
      page.getByText("处理草稿已保存，公开资料未改变"),
    ).toBeVisible();
    expect(
      requests.find((r) => r.path.endsWith("/draft"))?.body.values,
    ).toEqual({ name: "更正后的官方名称" });
    expect(
      requests.find((r) => r.path.endsWith("/draft"))?.body
        .image_rights_confirmed,
    ).toBeUndefined();
    await page.getByLabel("官方名称", { exact: true }).fill("应丢弃的值");
    await page.getByRole("button", { name: "取消", exact: true }).click();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "放弃修改" })
      .click();
    await expect(page.getByLabel("官方名称", { exact: true })).toHaveValue(
      "更正后的官方名称",
    );
    await layout(page, kind + "-profile");
    await page.getByRole("button", { name: "预览并发布" }).click();
    await expect(page.getByRole("dialog")).toContainText("当前公开资料");
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "确认发布" })
      .click();
    await expect(page.getByText(/当前版本 V2/)).toBeVisible();
  });

test("related card thumbnails and group members navigate to details", async ({
  page,
}) => {
  await fixture(page);
  await page.goto("/catalog/groups/group-ui/detail?tab=members");
  await page.getByRole("link", { name: "测试艺人", exact: true }).click();
  await expect(page).toHaveURL(/\/idols\/idol-ui\/detail/);
  await page.getByRole("tab", { name: "小卡 1", exact: true }).click();
  const card = page.getByRole("link", {
    name: "查看小卡：测试卡面",
    exact: true,
  });
  await expect(card.locator("img")).toBeVisible();
  await expect
    .poll(() =>
      card
        .locator("img")
        .evaluate(
          (image: HTMLImageElement) =>
            image.complete &&
            image.naturalWidth === 200 &&
            image.naturalHeight === 280,
        ),
    )
    .toBe(true);
  const box = await card.locator("img").boundingBox();
  expect(box?.width).toBe(40);
  expect(box?.height).toBe(56);
  await layout(page, "related-cards");
  await card.click();
  await expect(page).toHaveURL(/\/cards\/card-ui\/detail/);
  await expect(
    page.getByRole("tab", { name: "来源", exact: true }),
  ).toHaveCount(0);
});

test("support settings preview, validation, cancellation and save", async ({
  page,
}) => {
  const requests = await fixture(page);
  await page.goto("/system/auth-support");
  await expect(page.getByLabel("公开联系渠道", { exact: true })).toHaveValue(
    "help@example.test",
  );
  await page.getByLabel("展示名称", { exact: true }).fill("联系客服");
  await expect(
    page.getByRole("complementary", { name: "客服入口预览" }),
  ).toContainText("联系客服");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  await expect(page.getByText("请填写修改原因", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "放弃修改" })
    .click();
  await expect(page.getByLabel("展示名称", { exact: true })).toHaveValue(
    "登录帮助",
  );
  await layout(page, "support-settings");
  await page.getByLabel("展示名称", { exact: true }).fill("联系我们");
  await page.getByLabel("修改原因", { exact: true }).fill("更新入口名称");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  await expect(page.getByText("客服入口已保存", { exact: true })).toBeVisible();
  expect(
    requests.find((r) => r.path.endsWith("/support-entry"))?.body
      .expected_version,
  ).toBe(2);
  expect(
    requests.find((r) => r.path.endsWith("/support-entry"))?.body.display_name,
  ).toBe("联系我们");
  await expect(page.getByLabel("修改原因", { exact: true })).toHaveValue("");
});

test("catalog addition uses the shared form with draft, validation and leave protection", async ({
  page,
}) => {
  const requests = await fixture(page);
  await page.goto("/catalog/additions/fb-editorial");
  await expect(page.getByLabel("官方名称", { exact: true })).toHaveValue(
    "新组合",
  );
  await expect(
    page.getByText("测试用户 · 提交于 2026-10-28 09:20（北京时间）", {
      exact: true,
    }),
  ).toBeVisible();
  await page.getByLabel("官方名称", { exact: true }).fill("已核实组合");
  await page.getByRole("button", { name: "返回列表", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("放弃未保存的修改？");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "继续编辑" })
    .click();
  await expect(page.getByLabel("官方名称", { exact: true })).toHaveValue(
    "已核实组合",
  );
  await page.getByRole("button", { name: "提交处理结果", exact: true }).click();
  await expect(
    page.getByText("请填写面向用户的处理说明。", { exact: true }),
  ).toBeVisible();
  expect(requests.filter((r) => r.path.endsWith("/actions"))).toHaveLength(0);
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(
    page.getByText("处理草稿已保存，用户动态未更新", { exact: true }),
  ).toBeVisible();
  expect(requests.find((r) => r.path.endsWith("/actions"))?.body).toMatchObject(
    { action: "draft", changes: { name: "已核实组合" }, revision: 1 },
  );
  await layout(page, "catalog-addition");
  await page
    .locator(".feedback-result-options label")
    .filter({ hasText: /^已采纳$/ })
    .click();
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("已核实并登记官方资料");
  await page.getByRole("button", { name: "提交处理结果", exact: true }).click();
  await page.getByRole("button", { name: "发布并收录", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "发布并收录", exact: true })
    .click();
  await expect(
    page.getByText("图鉴已发布并收录", { exact: true }),
  ).toBeVisible();
  expect(
    requests.filter((r) => r.path.endsWith("/actions")).at(-1)?.body,
  ).toMatchObject({ action: "publish", revision: 3 });
  await expect(
    page.getByRole("button", { name: "发布并收录", exact: true }),
  ).toHaveCount(0);
});

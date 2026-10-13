import { readFileSync } from "node:fs";
import { test, expect } from "@playwright/test";

test("permanently delete an unlinked archived group from the list", async ({
  page,
  request,
}) => {
  const login = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await login.json()).data.access_token}`,
  };
  const name = `Delete E2E ${Date.now()}`;
  const created = await request.post(
    "http://127.0.0.1:8011/api/v1/admin/console/entities/groups",
    { headers, data: { name } },
  );
  const id = (await created.json()).data.id;
  await request.post(
    `http://127.0.0.1:8011/api/v1/admin/console/entities/groups/${id}/actions`,
    { headers, data: { action: "archive" } },
  );
  await page.goto("/catalog/groups");
  await page.getByRole("tab", { name: "已归档", exact: true }).click();
  await page.getByPlaceholder("搜索组合名称、ID…").fill(name);
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByText("删除", { exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("删除不可恢复");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "删除", exact: true })
    .click();
  await expect(row).toHaveCount(0);
  expect(
    (
      await request.delete(
        `http://127.0.0.1:8011/api/v1/admin/console/entities/groups/${id}`,
        { headers },
      )
    ).status(),
  ).toBe(404);
});

test.beforeEach(async ({ page }) => {
  await page.goto("/catalog/cards");
  await page.getByRole("button", { name: "填入账号" }).click();
  await page.getByRole("button", { name: "进入工作台" }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
});

test("group selection filters members while preserving former membership", async ({
  page,
  request,
}) => {
  const login = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await login.json()).data.access_token}`,
  };
  const root = "http://127.0.0.1:8011/api/v1/admin/console";
  const name = `Former member ${Date.now()}`;
  const created = await request.post(root + "/entities/idols", {
    headers,
    data: { name, group_id: "group-lumina" },
  });
  const idol = (await created.json()).data;
  const memberships = await request.get(
    `${root}/records/memberships?entity_id=${idol.id}`,
    { headers },
  );
  const original = (await memberships.json()).data.items[0];
  expect(
    (
      await request.post(root + "/records/memberships", {
        headers,
        data: {
          entity_type: "idols",
          entity_id: idol.id,
          data: {
            membership_id: original.data.membership_id,
            group_id: "group-lumina",
            status: "former",
            start_date: "2010-01-01",
            end_date: "2020-12-31",
          },
        },
      })
    ).status(),
  ).toBe(200);
  expect(
    (
      await request.post(root + "/records/memberships", {
        headers,
        data: {
          entity_type: "idols",
          entity_id: idol.id,
          data: {
            group_id: "group-aster",
            status: "active",
            start_date: "2021-01-01",
            is_primary: true,
          },
        },
      })
    ).status(),
  ).toBe(200);
  await page.goto("/catalog/cards/new");
  await page
    .locator(".selection-card")
    .filter({ has: page.getByRole("heading", { name: "LUMINA", exact: true }) })
    .click();
  await page.getByRole("button", { name: "下一步", exact: true }).click();
  await expect(
    page.locator(".selection-card").filter({ hasText: "Aria" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: `${name}（历史成员）`, exact: true }),
  ).toBeVisible();
  await expect(
    page.locator(".selection-card").filter({ hasText: "Yuna" }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "上一步", exact: true }).click();
  await page
    .locator(".selection-card")
    .filter({ has: page.getByRole("heading", { name: "ASTER", exact: true }) })
    .click();
  await page.getByRole("button", { name: "下一步", exact: true }).click();
  await expect(
    page.locator(".selection-card").filter({ hasText: "Aria" }),
  ).toHaveCount(0);
  await expect(
    page.locator(".selection-card").filter({ hasText: "Yuna" }),
  ).toBeVisible();
});

test("a newly created company can be selected in group and idol forms", async ({
  page,
  request,
}) => {
  const name = `Selectable agency ${Date.now()}`;
  await page.goto("/catalog/companies");
  await page
    .getByRole("button", { name: "新增公司", exact: true })
    .first()
    .click();
  await page.getByRole("dialog").getByLabel("名称", { exact: true }).fill(name);
  await page.getByRole("dialog").getByRole("button", { name: "保存" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  for (const [kind, label] of [
    ["groups", "组合"],
    ["idols", "艺人"],
  ]) {
    await page.goto(`/catalog/${kind}`);
    await page
      .getByRole("button", { name: `新增${label}`, exact: true })
      .click();
    await page
      .getByLabel(`${label}名称 / 官方名称`, { exact: true })
      .fill(`${label} ${name}`);
    await page.getByLabel("所属公司", { exact: true }).click();
    await page.getByTitle(name, { exact: true }).click();
    await page.keyboard.press("Escape");
    const saved = page.waitForResponse(
      (r) =>
        r.url().includes(`/entities/${kind}`) &&
        r.request().method() === "POST",
    );
    await page.getByRole("button", { name: "保存草稿", exact: true }).click();
    const response = await saved;
    expect(response.status()).toBe(200);
    const entity = (await response.json()).data;
    expect(entity.company).toBe(name);
    expect(entity.company_ids).toHaveLength(1);
    const login = await request.post(
      "http://127.0.0.1:8011/api/v1/auth/login",
      { data: { method: "phone", phone: "13900000000", code: "123456" } },
    );
    const relations = await request.get(
      `http://127.0.0.1:8011/api/v1/admin/console/records/company_relations?entity_id=${entity.id}`,
      {
        headers: {
          Authorization: `Bearer ${(await login.json()).data.access_token}`,
        },
      },
    );
    const relation = (await relations.json()).data.items[0];
    expect(relation.data.company_id).toBe(entity.company_ids[0]);
    await page.goto(`/catalog/${kind}/${entity.id}/detail`);
    await page.getByRole("tab", { name: "公司经历", exact: true }).click();
    const row = page.locator(".ant-table-tbody tr").filter({ hasText: name });
    await expect(row).toContainText("开始日期待核实");
    await row.getByRole("button", { name: "编辑", exact: true }).click();
    await page
      .getByRole("dialog")
      .getByLabel("备注", { exact: true })
      .fill("确认原始公司；期间仍待核实");
    const changed = page.waitForResponse(
      (r) => r.url().endsWith(relation.id) && r.request().method() === "PUT",
    );
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "保存" })
      .click();
    const edited = await changed;
    expect(edited.status()).toBe(200);
    const editedData = (await edited.json()).data.data;
    expect(editedData.source).toBe("catalog_company_selection");
    expect(editedData.date_unknown).toBe(true);
    await expect(page.getByRole("dialog")).toHaveCount(0);
  }
});

test("batch generation, validation progress and bulk field preview", async ({
  page,
  request,
}) => {
  const login = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await login.json()).data.access_token}`,
  };
  const batchName = `Browser batch ${Date.now()}`;
  const response = await request.post(
    "http://127.0.0.1:8011/api/v1/admin/console/records/batches",
    {
      headers,
      data: {
        data: {
          name: batchName,
          group_id: "group-lumina",
          source_entity_type: "ALBUM",
          source_entity_id: "album-starlit",
          version: "OFF",
        },
      },
    },
  );
  expect(response.status()).toBe(200);
  const batch = (await response.json()).data;
  await page.goto("/catalog/workbench?tab=batches");
  const row = page
    .locator(".ant-table-tbody tr")
    .filter({ hasText: batchName });
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "选择批次", exact: true }).click();
  await page.getByRole("combobox", { name: "选择成员", exact: true }).click();
  await page.getByTitle("Aria", { exact: true }).click();
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "生成成员草稿", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: `${batchName} · 1 张`, exact: true }),
  ).toBeVisible();
  await row.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "全部校验", exact: true }).click();
  await expect(page.getByText(/校验通过 0/)).toBeVisible();
  await page.getByRole("button", { name: "批量编辑", exact: true }).click();
  const cardRow = page
    .locator(".ant-table-tbody tr")
    .filter({ hasText: batchName });
  await cardRow.getByRole("checkbox").check();
  await page.getByLabel("版本", { exact: true }).fill("SPIN-OFF");
  await page.getByRole("button", { name: /预览修改 1 条/ }).click();
  await expect(page.getByRole("dialog")).toContainText("SPIN-OFF");
  await page.getByRole("button", { name: "确认整批修改", exact: true }).click();
  await expect(page.getByText("整批修改成功", { exact: true })).toBeVisible();
  const saved = await request.get(
    `http://127.0.0.1:8011/api/v1/admin/console/records/batches?entity_id=${batch.entity_id}`,
    { headers },
  );
  const batchRow = (await saved.json()).data.items.find(
    (r: any) => r.id === batch.id,
  );
  const detail = await request.get(
    `http://127.0.0.1:8011/api/v1/admin/console/entities/cards/${batchRow.data.card_ids[0]}/detail`,
    { headers },
  );
  expect((await detail.json()).data.entity.version).toBe("SPIN-OFF");
});

test("feedback current versus suggested values and acceptance", async ({
  page,
  request,
}) => {
  const login = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await login.json()).data.access_token}`,
  };
  const catalogResponse = await request.get(
    "http://127.0.0.1:8011/api/v1/admin/console/catalog",
    { headers },
  );
  const seed = (await catalogResponse.json()).data.cards.find(
    (c: any) => c.status === "PUBLISHED" && c.source_entity_type === "EVENT",
  );
  const media = await request.post(
    "http://127.0.0.1:8011/api/v1/admin/console/uploads",
    {
      headers,
      multipart: {
        file: {
          name: "review.png",
          mimeType: "image/png",
          buffer: readFileSync("tests/fixtures/admin-recognition.png"),
        },
      },
    },
  );
  const created = await request.post(
    "http://127.0.0.1:8011/api/v1/admin/console/cards",
    {
      headers,
      data: {
        ...seed,
        title: `Review ${Date.now()}`,
        card_number: "",
        image_url: (await media.json()).data.url,
        front_source: {
          source_type: "OFFICIAL",
          source_url: "https://example.test/review",
          copyright_status: "AUTHORIZED",
        },
      },
    },
  );
  expect(created.status()).toBe(200);
  const card = (await created.json()).data;
  for (const action of ["submit", "publish"])
    expect(
      (
        await request.post(
          `http://127.0.0.1:8011/api/v1/admin/console/cards/${card.id}/actions`,
          { headers, data: { action } },
        )
      ).status(),
    ).toBe(200);
  const feedback = await request.post(
    "http://127.0.0.1:8011/api/v1/catalog/feedback",
    {
      headers,
      data: {
        entity_type: "cards",
        entity_id: card.id,
        reason: "版本纠正",
        suggested: { version: "REVIEW VERSION" },
      },
    },
  );
  expect(feedback.status()).toBe(200);
  await page.goto("/catalog/review");
  const row = page.locator(".ant-table-tbody tr").filter({ hasText: card.id });
  await row.getByRole("button", { name: "查看", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("当前值");
  await page
    .getByRole("button", { name: "接受 / 编辑后接受", exact: true })
    .click();
  await page
    .locator(".ant-modal-confirm")
    .getByRole("button", { name: "确定" })
    .click();
  await expect(page.getByText("审核已处理", { exact: true })).toBeVisible();
  await expect(row).toContainText("已采纳");
  await page.goto(`/catalog/cards/${card.id}/detail`);
  await expect(page.getByText("REVIEW VERSION", { exact: true })).toBeVisible();
  await page.getByRole("tab", { name: "AI Scan", exact: true }).click();
  await expect(
    page.getByRole("tab", { name: "AI Scan", exact: true }),
  ).toBeVisible();
});

test("solo release, entity versions, context card and operational pages", async ({
  page,
  request,
}) => {
  const login = await request.post("http://127.0.0.1:8011/api/v1/auth/login", {
    data: { method: "phone", phone: "13900000000", code: "123456" },
  });
  const headers = {
    Authorization: `Bearer ${(await login.json()).data.access_token}`,
  };
  const soloResponse = await request.post(
    "http://127.0.0.1:8011/api/v1/admin/console/entities/idols",
    { headers, data: { name: `Solo ${Date.now()}` } },
  );
  const solo = (await soloResponse.json()).data;
  await page.goto(`/catalog/albums?create=true&idol_id=${solo.id}`);
  await page.getByLabel("专辑名称 / 官方名称").fill(`Solo Album ${Date.now()}`);
  const responsePromise = page.waitForResponse(
    (r) =>
      r.url().endsWith("/admin/console/entities/albums") &&
      r.request().method() === "POST",
  );
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  const album = (await (await responsePromise).json()).data;
  expect(album.artists).toEqual([{ type: "idols", id: solo.id }]);
  await page.goto(`/catalog/albums/${album.id}/detail`);
  await page.getByRole("tab", { name: "版本", exact: true }).click();
  await page
    .getByRole("button", { name: "新增版本", exact: true })
    .first()
    .click();
  await page
    .getByRole("dialog")
    .getByLabel("名称", { exact: true })
    .fill("OFF Version");
  await page.getByRole("dialog").getByRole("button", { name: "保存" }).click();
  await expect(page.getByText("OFF Version", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "新增小卡", exact: true }).click();
  await page.getByRole("button", { name: "下一步", exact: true }).click();
  await page.getByRole("button", { name: "下一步", exact: true }).click();
  await expect(page.locator(".source-summary")).toContainText(album.name);
  for (const route of [
    "/catalog/workbench",
    "/catalog/review",
    "/catalog/scan",
    "/catalog/companies",
  ]) {
    await page.goto(route);
    await expect(page.locator("main")).not.toContainText("页面不存在");
    await expect(page.getByText("无法连接服务", { exact: false })).toHaveCount(
      0,
    );
  }
  await page.getByRole("button", { name: "快速创建", exact: true }).click();
  await page.getByPlaceholder("搜索小卡、专辑等").fill("小卡");
  await expect(
    page.getByRole("button", { name: "新增小卡", exact: true }),
  ).toBeVisible();
});

test("create a card, identify missing fields, upload, preview, review, publish and take offline", async ({
  page,
  request,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.getByRole("button", { name: "新增小卡", exact: true }).click();
  await page.locator(".selection-card").filter({ hasText: "LUMINA" }).click();
  await page.getByRole("button", { name: "下一步" }).click();
  await page.locator(".selection-card").filter({ hasText: "Aria" }).click();
  await page.getByRole("button", { name: "下一步" }).click();
  await page.getByLabel("来源对象", { exact: true }).click();
  await page.getByTitle("Starlit · 2026.08.16", { exact: true }).click();
  await page.getByRole("button", { name: "下一步" }).click();
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(page.getByText("草稿已保存", { exact: true })).toBeVisible();
  const cardId = page.url().split("/").pop()!;

  expect(
    (
      await request.get(`http://127.0.0.1:8011/api/v1/catalog/cards/${cardId}`)
    ).status(),
  ).toBe(404);
  await page.getByRole("button", { name: "提交审核", exact: true }).click();
  await expect(page.getByText(/还有 \d+ 项信息需要完善/)).toBeVisible();
  await page
    .locator('input[aria-label="上传正面图片"]')
    .setInputFiles("tests/fixtures/admin-recognition.png");
  await page
    .getByRole("button", { name: "确认裁剪并上传", exact: true })
    .click();
  await expect(page.getByText("图片上传成功", { exact: true })).toBeVisible();
  await page
    .locator('[id="field-front_source.source_url"]')
    .fill("https://official.example.test/catalog");
  await page
    .locator('[id="field-front_source.copyright_status"]')
    .press("ArrowDown");
  await page.getByTitle("已授权", { exact: true }).click();
  await page.getByRole("button", { name: "预览 App", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("Aria");
  await page.getByRole("button", { name: "关闭预览", exact: true }).click();
  await page.getByRole("button", { name: "提交审核", exact: true }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
  await page.goto(`/catalog/cards/${cardId}`);
  await page
    .getByRole("button", { name: "审核通过并发布", exact: true })
    .click();
  await page.getByRole("button", { name: "确认发布", exact: true }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
  expect(
    (
      await request.get(`http://127.0.0.1:8011/api/v1/catalog/cards/${cardId}`)
    ).status(),
  ).toBe(200);
  await page.goto(`/catalog/cards/${cardId}`);
  await page.getByRole("button", { name: "下架并编辑", exact: true }).click();
  await page.getByRole("button", { name: "确认下架", exact: true }).click();
  await expect(page.getByRole("heading", { name: "小卡管理" })).toBeVisible();
  expect(
    (
      await request.get(`http://127.0.0.1:8011/api/v1/catalog/cards/${cardId}`)
    ).status(),
  ).toBe(404);
  expect(errors).toEqual([]);
});

test("every module renders and editor has no page overflow", async ({
  page,
}) => {
  const routes = [
    "/dashboard",
    "/catalog/groups",
    "/catalog/idols",
    "/catalog/albums",
    "/catalog/events",
    "/catalog/others",
    "/catalog/import",
    "/reviews/sources",
    "/operations/social",
    "/operations/accounts",
    "/operations/comments",
    "/operations/daily",
    "/operations/draws",
    "/operations/notifications",
    "/operations/announcements",
    "/operations/users",
    "/operations/reports",
    "/system/admins",
    "/system/roles",
    "/system/logs",
  ];
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  for (const route of routes) {
    await page.goto(route);
    await expect(page.locator("main h1")).toBeVisible();
    await expect(page.getByText("无法连接服务", { exact: false })).toHaveCount(
      0,
    );
  }
  await page.goto("/catalog/cards/new");
  await page.getByText("基础信息", { exact: true }).click();
  await expect(page.getByLabel("版本名称", { exact: true })).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBeTruthy();
  await page.setViewportSize({ width: 1024, height: 900 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBeTruthy();
  expect(errors).toEqual([]);
});

test("combined group and idol import creates members and supports group batch lifecycle", async ({
  page,
}) => {
  test.setTimeout(120000);
  const stamp = Date.now();
  const prefix = `BulkUI-${stamp}`;
  const groupName = `${prefix}-group`;
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));

  await page.goto("/catalog/groups");
  await page
    .getByRole("main")
    .getByRole("button", { name: "批量导入", exact: true })
    .click();
  await expect(page).toHaveURL(/kind=groups/);
  await expect(
    page.getByText(
      "当前模板：组合 + 艺人（自动关联） · 一次导入组合资料、艺人资料及成员关系",
      { exact: true },
    ),
  ).toBeVisible();
  await page.locator("input[type=file]").setInputFiles({
    name: "groups-idols.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      `group_code,group_name,idol_name\n${prefix},${groupName},${prefix}-idol-A\n${prefix},${groupName},${prefix}-idol-B\n`,
    ),
  });
  await page
    .getByRole("button", { name: "确认导入 2 行", exact: true })
    .click();
  await page.getByRole("button", { name: "确认导入", exact: true }).click();
  await expect(
    page.getByText("已导入 2 位艺人，组合、艺人、成员及公司关系已同步建立", {
      exact: true,
    }),
  ).toBeVisible();

  await page.goto("/catalog/groups");
  await page.getByPlaceholder("搜索组合名称、ID…").fill(groupName);
  const groupRow = page.locator(".ant-table-tbody tr").filter({
    has: page.getByRole("button", { name: groupName, exact: true }),
  });
  await expect(groupRow).toContainText("2");
  const selectGroup = async () => {
    await page.locator(".ant-table-thead .ant-checkbox-input").check();
    await expect(page.getByText("已选 1 项", { exact: true })).toBeVisible();
  };
  await selectGroup();
  await expect(
    page.getByRole("button", { name: "批量下架", exact: true }),
  ).toBeDisabled();
  for (const action of ["批量提交审核", "批量发布", "批量下架"]) {
    await page.getByRole("button", { name: action, exact: true }).click();
    await page.getByRole("button", { name: "确认操作", exact: true }).click();
    await expect(
      page.getByText(`${action}成功`, { exact: true }),
    ).toBeVisible();
    await selectGroup();
  }
  await page.getByRole("button", { name: "批量归档", exact: true }).click();
  await page.getByRole("button", { name: "确认操作", exact: true }).click();
  await expect(page.getByText("批量归档成功", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: groupName, exact: true }),
  ).toHaveCount(0);
  await page.getByRole("tab", { name: "已归档", exact: true }).click();
  await selectGroup();
  await page.getByRole("button", { name: "恢复草稿", exact: true }).click();
  await page.getByRole("button", { name: "确认操作", exact: true }).click();
  await expect(page.getByText("恢复草稿成功", { exact: true })).toBeVisible();
  await page.getByRole("tab", { name: "草稿", exact: true }).click();
  await expect(
    page.getByRole("button", { name: groupName, exact: true }),
  ).toBeVisible();

  await page.goto("/catalog/idols");
  await page.getByPlaceholder("搜索艺人名称、ID…").fill(`${prefix}-idol`);
  for (const suffix of ["A", "B"]) {
    await expect(
      page.getByRole("button", {
        name: `${prefix}-idol-${suffix}`,
        exact: true,
      }),
    ).toBeVisible();
  }
  expect(errors).toEqual([]);
});

test("import type switches templates and history without retaining a previous task", async ({
  page,
}) => {
  await page.goto("/catalog/import?kind=groups");
  await expect(page.locator(".import-hints")).toBeVisible();
  for (const width of [1440, 1024]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.locator(".import-hints").evaluate((element) => {
        const panel = element.closest(".panel")!;
        return (
          element.getBoundingClientRect().bottom <=
          panel.getBoundingClientRect().bottom
        );
      }),
    ).toBeTruthy();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBeTruthy();
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  const csvDownload = page.waitForEvent("download");
  await page
    .getByRole("button", { name: "下载 CSV 模板", exact: true })
    .click();
  expect((await csvDownload).suggestedFilename()).toBe(
    "FanOS-组合 + 艺人（自动关联）导入模板.csv",
  );
  await page.locator("input[type=file]").setInputFiles({
    name: "groups-idols.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      `group_code,group_name,idol_name\ntype-switch,Type switch ${Date.now()},Type switch idol ${Date.now()}\n`,
    ),
  });
  await expect(
    page.getByRole("button", { name: "确认导入 1 行", exact: true }),
  ).toBeVisible();
  await page.getByLabel("导入类型").press("ArrowDown");
  await page.getByTitle("专辑", { exact: true }).click();
  await expect(
    page.getByRole("button", { name: "确认导入 1 行", exact: true }),
  ).toHaveCount(0);
  await expect(page.getByText("groups-idols.csv", { exact: true })).toHaveCount(
    0,
  );
  const excelDownload = page.waitForEvent("download");
  await page
    .getByRole("button", { name: "下载 Excel 模板", exact: true })
    .click();
  expect((await excelDownload).suggestedFilename()).toBe(
    "FanOS-专辑导入模板.xlsx",
  );
});

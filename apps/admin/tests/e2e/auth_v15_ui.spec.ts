import { expect, test, type Page } from "@playwright/test";

// Explicit UI-contract fixtures, not business records or a substitute for API acceptance.
async function fixture(
  page: Page,
  permissions = [
    "auth.users.view",
    "auth.users.manage",
    "auth.users.password",
    "auth.whitelist.manage",
    "auth.test_code.manage",
    "auth.admins.manage",
  ],
) {
  await page.addInitScript(() =>
    sessionStorage.setItem(
      "fanos-admin-session",
      JSON.stringify({ access_token: "ui-fixture-admin" }),
    ),
  );
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    let data: any = {};
    if (path.endsWith("/console/me"))
      data = { id: "admin-fixture", name: "测试运营", role: "admin" };
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
    else if (path.endsWith("/auth/meta"))
      data = { environment: "test", permissions };
    else if (path.endsWith("/auth/users"))
      data = {
        items: [
          {
            id: "fixture-user",
            name: "本地 UI 测试用户",
            phone_masked: "138****0000",
            status: "NORMAL",
            version: 1,
            has_phone: true,
            wechat: { bound: false },
            weibo: { bound: false },
            qq: { bound: true, authorization_status: "unknown" },
            collection_count: 2,
            wishlist_count: 3,
          },
        ],
        total: 1,
      };
    else if (path.endsWith("/auth/users/fixture-user"))
      data = {
        version: 1,
        user: {
          id: "fixture-user",
          name: "本地 UI 测试用户",
          phone_masked: "138****0000",
          status: "normal",
        },
        identities: [
          {
            provider: "qq",
            bound: true,
            display_name: "测试 QQ 昵称",
            subject_masked: "tes****ject",
            app_scope: "test-app",
            authorization_status: "unknown",
            bound_at: "2026-10-28T10:00:00Z",
            updated_at: "2026-10-28T10:00:00Z",
          },
        ],
        stats: {},
        favorites: [],
        login_records: [],
        operation_records: [],
      };
    else if (path.endsWith("/auth/login-whitelist/match"))
      data = { user_id: null, whitelist_id: null };
    else if (path.endsWith("/auth/login-whitelist"))
      data = {
        items: [],
        total: 0,
        environment: "test",
        enabled: false,
        effective_count: 0,
      };
    else if (path.endsWith("/auth/test-login-config"))
      data = {
        environment: "test",
        enabled: false,
        configured: true,
        version: 4,
        updated_by: "测试运营",
      };
    await route.fulfill({ json: { code: 0, data } });
  });
}

test("App users keep masked identity, server filtering and protected actions", async ({
  page,
}) => {
  await fixture(page);
  await page.goto("/operations/users");
  await expect(
    page.getByRole("heading", { name: "App 用户", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("138****0000", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "新增用户" })).toHaveCount(0);
  await page.getByLabel("用户关键词").fill("fixture-user");
  const query = page.waitForRequest(
    (r) =>
      r.url().includes("/auth/users?") && r.url().includes("q=fixture-user"),
  );
  await page.getByRole("button", { name: "查询", exact: true }).click();
  await query;
  await expect(page.getByText("游戏账号", { exact: true })).toHaveCount(0);
});

for (const path of ["/operations/users", "/operations/users/fixture-user"]) {
  test(`password reset validates and submits a confirmed versioned request from ${path}`, async ({
    page,
  }) => {
    await fixture(page);
    const requests: Record<string, unknown>[] = [];
    await page.route(
      "**/auth/users/fixture-user/password-reset",
      async (route) => {
        requests.push(route.request().postDataJSON());
        await route.fulfill({
          json: {
            code: 0,
            data: {
              user_id: "fixture-user",
              version: 2,
              sessions_revoked: true,
            },
          },
        });
      },
    );
    await page.goto(path);
    await page.getByRole("button", { name: "更多" }).click();
    await page.getByRole("menuitem", { name: "重置登录密码" }).click();
    const dialog = page.getByRole("dialog", { name: "重置 App 登录密码" });
    await dialog.getByRole("button", { name: "重置密码", exact: true }).click();
    await expect(
      dialog.getByText("请输入新密码", { exact: true }),
    ).toBeVisible();
    expect(requests).toHaveLength(0);
    await dialog.getByLabel("新密码", { exact: true }).fill("Abc123");
    await dialog.getByLabel("确认新密码", { exact: true }).fill("Mismatch123");
    await dialog.getByRole("button", { name: "重置密码", exact: true }).click();
    await expect(
      dialog.getByText("两次输入的密码不一致", { exact: true }),
    ).toBeVisible();
    expect(requests).toHaveLength(0);
    await dialog.getByLabel("新密码", { exact: true }).fill("Ui-Reset789!");
    await dialog.getByLabel("确认新密码", { exact: true }).fill("Ui-Reset789!");
    await dialog
      .getByLabel("处理原因", { exact: true })
      .fill("已核验账户归属，协助恢复登录");
    await dialog
      .getByRole("checkbox", {
        name: "确认重置该用户密码，并下线其全部 App 会话",
      })
      .check();
    await dialog.getByRole("button", { name: "重置密码", exact: true }).click();
    await expect(dialog).toHaveCount(0);
    expect(requests).toEqual([
      {
        new_password: "Ui-Reset789!",
        reason: "已核验账户归属，协助恢复登录",
        confirmed: true,
        expected_version: 1,
      },
    ]);
    await expect(
      page.getByText("密码已重置，全部 App 会话已下线", { exact: true }),
    ).toBeVisible();
  });
}

test("account status permission does not expose password reset", async ({
  page,
}) => {
  await fixture(page, ["auth.users.view", "auth.users.manage"]);
  await page.goto("/operations/users");
  await page.getByRole("button", { name: "更多" }).click();
  await expect(
    page.getByRole("menuitem", { name: "重置登录密码" }),
  ).toHaveCount(0);
  await page.goto("/operations/users/fixture-user");
  await expect(page.getByRole("button", { name: "更多" })).toHaveCount(0);
});

test("QQ binding filter and read-only detail use the actual provider fields", async ({
  page,
}) => {
  await fixture(page, ["auth.users.view"]);
  await page.goto("/operations/users");
  await expect(
    page.getByRole("columnheader", { name: "QQ", exact: true }),
  ).toBeVisible();
  await page.getByText("QQ：全部", { exact: true }).click();
  await page.getByText("QQ：已绑定", { exact: true }).click();
  const request = page.waitForRequest(
    (r) => r.url().includes("/auth/users?") && r.url().includes("qq=bound"),
  );
  await page.getByRole("button", { name: "查询", exact: true }).click();
  await request;
  await page
    .getByRole("link", { name: "本地 UI 测试用户", exact: true })
    .click();
  await page.getByRole("tab", { name: "平台绑定", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "QQ", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("测试 QQ 昵称", { exact: true })).toBeVisible();
  await expect(page.getByText("tes****ject", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "解除QQ绑定" })).toHaveCount(0);
});

test("test code is independently gated, never echoed and validates confirmation", async ({
  page,
}) => {
  await fixture(page);
  await page.goto("/operations/login-whitelist");
  await expect(page.getByText(/测试能力已关闭/)).toBeVisible();
  await page
    .getByRole("button", { name: "测试验证码配置", exact: true })
    .click();
  const dialog = page.getByRole("dialog");
  await expect(dialog.getByText(/已配置 · 版本 4/)).toBeVisible();
  await expect(dialog.getByLabel("新默认验证码", { exact: true })).toHaveValue(
    "",
  );
  await dialog.getByLabel("新默认验证码", { exact: true }).fill("001234");
  await dialog.getByLabel("确认新验证码", { exact: true }).fill("001235");
  await dialog.getByRole("button", { name: "保存", exact: true }).click();
  await expect(dialog.getByText("两次输入不一致")).toBeVisible();
});

test("view-only role cannot see mutation or code configuration controls", async ({
  page,
}) => {
  await fixture(page, ["auth.users.view"]);
  await page.goto("/operations/login-whitelist");
  await expect(
    page.getByRole("heading", { name: "登录白名单", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "测试验证码配置", exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "新增白名单", exact: true }),
  ).toHaveCount(0);
});

test("admin login has no fixed code shortcut", async ({ page }) => {
  await page.goto("/");
  await expect(
    page.getByLabel("管理员登录账号", { exact: true }),
  ).toBeVisible();
  await expect(page.getByLabel("密码", { exact: true })).toBeVisible();
  await expect(page.getByText("123456", { exact: false })).toHaveCount(0);
  await expect(page.getByLabel("登录验证码")).toHaveCount(0);
});

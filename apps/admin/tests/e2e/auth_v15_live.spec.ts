import { expect, test, type APIResponse } from "@playwright/test";
import { randomInt } from "node:crypto";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
const root = "http://127.0.0.1:8016/api/v1";
async function data(response: APIResponse) {
  expect(response.ok(), `API returned HTTP ${response.status()}`).toBeTruthy();
  return (await response.json()).data;
}
test("independent admin and whitelist use real isolated API; App ban leaves admin intact", async ({
  page,
  request,
}) => {
  const output = resolve("../../output/auth-v15-20261027");
  mkdirSync(output, { recursive: true });
  const admin = await data(
    await request.post(root + "/admin/auth/login", {
      data: {
        account: "auth-e2e-admin",
        password: process.env.AUTH_E2E_PASSWORD,
      },
    }),
  );
  const headers = { Authorization: `Bearer ${admin.access_token}` };
  const code = String(randomInt(0, 1000000)).padStart(6, "0");
  const config = await data(
    await request.get(root + "/admin/auth/test-login-config", { headers }),
  );
  const saved = await data(
    await request.patch(root + "/admin/auth/test-login-config", {
      headers,
      data: {
        expected_version: config.version,
        enabled: true,
        default_code: code,
        reason: "隔离环境认证验收",
      },
    }),
  );
  expect(saved).not.toHaveProperty("default_code");
  const before = await data(
    await request.get(root + "/admin/auth/users", { headers }),
  );
  const whitelist = await data(
    await request.post(root + "/admin/auth/login-whitelist", {
      headers,
      data: {
        phone: "13800000126",
        expires_at: new Date(Date.now() + 86400000).toISOString(),
        owner: "自动化验收",
        purpose: "隔离环境验证",
        authorized: true,
      },
    }),
  );
  expect(
    (await data(await request.get(root + "/admin/auth/users", { headers })))
      .total,
  ).toBe(before.total);
  const challenge = await data(
    await request.post(root + "/auth/sms/challenges", {
      data: { phone: "13800000126", purpose: "login" },
    }),
  );
  const app = await data(
    await request.post(root + "/auth/login", {
      data: {
        method: "phone",
        phone: "13800000126",
        challenge_id: challenge.challenge_id,
        code,
      },
    }),
  );
  expect(
    (
      await request.get(root + "/admin/auth/users", {
        headers: { Authorization: `Bearer ${app.access_token}` },
      })
    ).status(),
  ).toBe(401);
  await page.goto("/operations/users");
  await page
    .getByLabel("管理员登录账号", { exact: true })
    .fill("auth-e2e-admin");
  await page
    .getByLabel("密码", { exact: true })
    .fill(process.env.AUTH_E2E_PASSWORD!);
  await page.getByRole("button", { name: "进入工作台", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "App 用户", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: resolve(output, "admin-app-users.png"),
    fullPage: true,
    animations: "disabled",
  });
  await page.goto(`/operations/users/${app.user.id}`);
  await expect(
    page.getByRole("heading", { name: "App 用户详情", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("tab", { name: "平台绑定", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "封禁", exact: true }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByLabel("内部处理原因").fill("隔离环境封禁验收");
  await dialog
    .getByLabel("用户可见说明")
    .fill("本地测试处置，请联系测试负责人");
  await dialog.getByRole("button", { name: "确认处理", exact: true }).click();
  await expect(dialog).toHaveCount(0);
  const banned = await data(
    await request.get(root + `/admin/auth/users/${app.user.id}`, { headers }),
  );
  expect(banned.user.status).toBe("banned");
  await page.goto("/operations/login-whitelist");
  await expect(
    page.getByRole("heading", { name: "登录白名单", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: resolve(output, "admin-login-whitelist.png"),
    fullPage: true,
    animations: "disabled",
  });
  await page
    .getByRole("button", { name: "测试验证码配置", exact: true })
    .click();
  await expect(
    page.getByRole("dialog").getByLabel("新默认验证码", { exact: true }),
  ).toHaveValue("");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "取消", exact: true })
    .click();
  expect(
    (
      await data(
        await request.get(
          root + `/admin/auth/login-whitelist/${whitelist.id}`,
          { headers },
        ),
      )
    ).effective,
  ).toBe(true);
  await page.goto("/system/admins");
  await expect(
    page.getByRole("heading", { name: "后台管理员", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: resolve(output, "admin-principals.png"),
    fullPage: true,
    animations: "disabled",
  });
});

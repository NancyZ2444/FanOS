import { expect, test, type APIResponse } from "@playwright/test";
import { randomInt } from "node:crypto";
import { readFileSync } from "node:fs";

const api = "http://127.0.0.1:8016/api/v1";
async function data(response: APIResponse) {
  expect(response.ok(), await response.text()).toBeTruthy();
  return (await response.json()).data;
}

test("missing catalog image and actual fields remain private until admin review publishes", async ({ page, request }) => {
  const admin = await data(await request.post(api + "/admin/auth/login", {
    data: { account: "auth-e2e-admin", password: process.env.AUTH_E2E_PASSWORD },
  }));
  const headers = { Authorization: `Bearer ${admin.access_token}` };
  const code = String(randomInt(0, 1000000)).padStart(6, "0");
  const config = await data(await request.get(api + "/admin/auth/test-login-config", { headers }));
  await data(await request.patch(api + "/admin/auth/test-login-config", { headers, data: {
    expected_version: config.version, enabled: true, default_code: code, reason: "独立缺失图鉴验收",
  } }));
  await data(await request.post(api + "/admin/auth/login-whitelist", { headers, data: {
    phone: "13800000127", expires_at: new Date(Date.now() + 86400000).toISOString(),
    owner: "自动验收", purpose: "缺失图鉴审核闭环", authorized: true,
  } }));
  const challenge = await data(await request.post(api + "/auth/sms/challenges", { data: { phone: "13800000127", purpose: "login" } }));
  const user = await data(await request.post(api + "/auth/login", { data: {
    method: "phone", phone: "13800000127", challenge_id: challenge.challenge_id, code,
  } }));
  const userHeaders = { Authorization: `Bearer ${user.access_token}` };
  const image = await data(await request.post(api + "/feedback/images", { headers: userHeaders, multipart: {
    file: { name: "fixture.png", mimeType: "image/png", buffer: readFileSync("tests/fixtures/admin-recognition.png") },
  } }));
  const row = await data(await request.post(api + "/feedback", { headers: userHeaders, data: {
    kind: "MISSING_CATALOG", entity_type: "groups", request_key: crypto.randomUUID(),
    fields: [{ key: "name", value: "UI missing group" }, { key: "image_url", value: image.id }, { key: "description", value: "用户提交的真实介绍" }],
    notes: "请核实后收录", links: ["https://example.test/reference"],
  } }));
  await page.addInitScript((session) => sessionStorage.setItem("fanos-admin-session", JSON.stringify(session)), admin);
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/catalog/missing-content/" + row.id);
  await expect(page.getByRole("heading", { name: "图鉴缺失收录 · 处理详情" })).toBeVisible();
  await expect(page.getByRole("img", { name: "图片", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "核实并发布收录" }).click();
  await expect(page.getByText("请填写面向用户的处理说明", { exact: true })).toBeVisible();
  await page.getByLabel("介绍采用值", { exact: true }).fill("经审核核实的介绍");
  await page.getByLabel("面向用户的说明", { exact: true }).fill("已核实并采用名称和图片，介绍已校对。");
  await page.getByRole("button", { name: "保存审核草稿" }).click();
  const detail = () => request.get(api + `/admin/console/feedback/${row.id}`, { headers }).then(data);
  await expect.poll(async () => (await detail()).revision).toBe(2);
  expect((await detail()).entity_id).toBe("");
  const publicSearch = await data(await request.get(api + "/feedback/objects?entity_type=groups&q=UI%20missing%20group", { headers: userHeaders }));
  expect(publicSearch.items).toEqual([]);
  await page.getByRole("button", { name: "核实并发布收录" }).click();
  await expect.poll(async () => (await detail()).result).toBe("INCLUDED");
  const published = await detail();
  expect(published.review.adopted_fields).toContain("image_url");
  expect(published.review.adopted_fields).not.toContain("description");
  const actual = await data(await request.get(api + `/feedback/objects/groups/${published.entity_id}`, { headers: userHeaders }));
  expect(actual.image_url).toBe(image.image_url);
  expect(actual.fields.find((f: any) => f.key === "description")?.current ?? actual.fields.find((f: any) => f.key === "intro_text")?.current).toBe("经审核核实的介绍");
  await expect(page.getByRole("button", { name: "保存审核草稿" })).toHaveCount(0);
  const album = await data(await request.post(api + "/feedback", { headers: userHeaders, data: {
    kind: "MISSING_CATALOG", entity_type: "albums", request_key: crypto.randomUUID(),
    fields: [{ key: "name", value: "Album association UI" }, { key: "artists", value: [{ type: "groups", id: "group-lumina" }] }],
  } }));
  await page.goto("/catalog/missing-content/" + album.id);
  await expect(page.locator(".feedback-value").filter({ hasText: "LUMINA" })).toBeVisible();
  await expect(page.locator(".ant-select-selection-item").filter({ hasText: "LUMINA" })).toBeVisible();
  await expect(page.getByText("group-lumina", { exact: true })).toHaveCount(0);
  await page.getByLabel("面向用户的说明", { exact: true }).fill("核实真实所属组合并收录。");
  await page.getByRole("button", { name: "核实并发布收录" }).click();
  await expect.poll(async () => (await data(await request.get(api + `/admin/console/feedback/${album.id}`, { headers }))).result).toBe("INCLUDED");
  await expect(page.locator(".feedback-value").filter({ hasText: "LUMINA" })).toHaveCount(2);
  await expect(page.getByText("group-lumina", { exact: true })).toHaveCount(0);
  expect(errors).toEqual([]);
});

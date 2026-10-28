import { test, expect } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { apiRoot, data } from "./feedback-fixtures";

test("dossier draft stays private, publication and review use the same history", async ({
  page,
  request,
}) => {
  const admin = await data(
    await request.post(apiRoot + "/auth/login", {
      data: { method: "phone", phone: "13900000000", code: "123456" },
    }),
  );
  const headers = { Authorization: `Bearer ${admin.access_token}` };
  const user = await data(
    await request.post(apiRoot + "/auth/login", {
      data: { method: "phone", phone: "13800000000", code: "123456" },
    }),
  );
  const userHeaders = { Authorization: `Bearer ${user.access_token}` };
  await page.addInitScript(
    (value) =>
      sessionStorage.setItem("fanos-admin-session", JSON.stringify(value)),
    admin,
  );
  await page.goto("/catalog/idols/idol-aria/detail?tab=profile");
  await expect(page.getByText(/当前版本 V1/)).toBeVisible();
  await page.getByRole("tab", { name: "从艺历程", exact: true }).click();
  await page
    .getByLabel("从艺历程", { exact: true })
    .fill("2020年\n出道记录\n\n2025年\n平台核实的完整正文");
  await page.getByLabel("公开修订说明").fill("核实并补充从艺历程");
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect(page.getByText("处理草稿已保存，公开资料未改变")).toBeVisible();
  const root = apiRoot + "/catalog/profiles/idols/idol-aria";
  const old = await data(await request.get(root));
  expect(
    old.fields.find((f: any) => f.key === "career_text").current,
  ).not.toContain("平台核实的完整正文");
  await page.getByRole("button", { name: "预览并发布" }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "确认发布" })
    .click();
  await expect(page.getByText(/当前版本 V2/)).toBeVisible();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  const published = await data(await request.get(root));
  expect(
    published.fields.find((f: any) => f.key === "career_text").current,
  ).toContain("\n\n2025年");
  const folder = resolve("../../output/catalog-profiles-20261022");
  mkdirSync(folder, { recursive: true });
  await page.screenshot({
    path: resolve(folder, "admin-profile.png"),
    fullPage: true,
    animations: "disabled",
  });
  const object = await data(
    await request.get(apiRoot + "/feedback/objects/idols/idol-aria", {
      headers: userHeaders,
    }),
  );
  const row = await data(
    await request.post(apiRoot + "/feedback", {
      headers: userHeaders,
      data: {
        kind: "CORRECTION",
        entity_type: "idols",
        entity_id: "idol-aria",
        object_version: object.version,
        request_key: crypto.randomUUID(),
        fields: [{ key: "honors_text", value: "2025年\n用户核实的荣誉记录" }],
        notes: "出处为官方公开资料",
      },
    }),
  );
  await page.goto("/catalog/corrections/" + row.id);
  await expect(
    page.getByText("荣誉记录", { exact: true }).first(),
  ).toBeVisible();
  await expect(
    page.getByText("2025年\n用户核实的荣誉记录", { exact: true }).first(),
  ).toBeVisible();
  await page.screenshot({
    path: resolve(folder, "admin-profile-review.png"),
    fullPage: true,
  });
  const obj = await data(
    await request.get(apiRoot + "/admin/console/profiles/idols/idol-aria", {
      headers,
    }),
  );
  await data(
    await request.post(
      apiRoot + "/admin/console/feedback/" + row.id + "/actions",
      {
        headers,
        data: {
          action: "publish",
          revision: row.revision,
          request_key: crypto.randomUUID(),
          object_version: obj.version,
          public_note: "已核对官方来源并采用",
          decisions: [{ key: "honors_text", decision: "ACCEPT" }],
        },
      },
    ),
  );
  const history = await data(await request.get(root + "/history"));
  expect(history.items).toHaveLength(3);
  expect(history.items[0].author.id).toBe(user.user.id);
});

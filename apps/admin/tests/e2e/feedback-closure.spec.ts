import { test, expect, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { apiRoot, data, setupFeedback } from "./feedback-fixtures";

const output = resolve("../../output/feedback-closure-20261020/screenshots");
async function capture(page: Page, name: string) {
  mkdirSync(output, { recursive: true });
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
  await page.screenshot({
    path: resolve(output, `${name}.png`),
    fullPage: true,
    animations: "disabled",
  });
}
async function edit(page: Page, id: string) {
  await page.goto(`/catalog/missing-cards/${id}`);
  await page.getByRole("button", { name: "编辑", exact: true }).click();
}
async function dropdown(page: Page, id: string) {
  await page
    .locator(".ant-select")
    .filter({ has: page.locator(`#${id}`) })
    .click();
  return page.locator(".ant-select-dropdown:visible");
}
async function choose(page: Page, id: string, name: string) {
  const list = await dropdown(page, id);
  await list.getByText(name, { exact: true }).click();
}
async function publish(page: Page) {
  const button = page
    .locator(".feedback-footer")
    .getByRole("button", { name: /发布小卡并收录$/ });
  await expect(button).toBeEnabled();
  await expect(button).not.toHaveClass(/ant-btn-loading/);
  await button.click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "发布小卡并收录", exact: true })
    .click();
}

test("unrecognized scan saves internally, filters source/version and publishes exactly once", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const recognized = await data(
    await request.post(
      `${apiRoot}/scan/sessions/${setup.scan.session_id}/recognize`,
      {
        headers: setup.userHeaders,
        data: {
          detected_card_ids: [setup.scan.detected_cards[0].detected_card_id],
        },
      },
    ),
  );
  expect(recognized.detected_cards[0].recognition_status).toBe("unrecognized");
  const row = await setup.createMissing({
    source_entity_id: null,
    missing_source_name: "待核实的发行名称",
  });
  const userDetail = () =>
    request
      .get(`${apiRoot}/feedback/records/${row.id}`, {
        headers: setup.userHeaders,
      })
      .then(data);
  const notices = async () =>
    (
      await data(
        await request.get(apiRoot + "/notifications/inbox", {
          headers: setup.userHeaders,
        }),
      )
    ).items.filter((n: any) => n.payload?.feedback_id === row.id);
  const before = await userDetail();
  await edit(page, row.id);
  await page
    .getByLabel("内部备注", { exact: true })
    .fill("内部核对，暂不通知用户");
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect
    .poll(async () => (await setup.detail(row.id)).entity_id)
    .toBeTruthy();
  const draft = await setup.detail(row.id);
  const afterDraft = await userDetail();
  expect(afterDraft.history).toEqual(before.history);
  expect(afterDraft.public_note).toBe(before.public_note);
  expect(afterDraft.updated_at).toBe(before.updated_at);
  expect(await notices()).toHaveLength(0);
  await capture(page, "internal-draft");

  // Materialize two source versions in the isolated fixture database.
  const version = await data(
    await request.post(apiRoot + "/admin/console/records/versions", {
      headers: setup.headers,
      data: {
        entity_type: "albums",
        entity_id: "album-starlit",
        data: { name: "Closure Moon" },
      },
    }),
  );
  await data(
    await request.post(apiRoot + "/admin/console/records/versions", {
      headers: setup.headers,
      data: {
        entity_type: "albums",
        entity_id: "album-bloom",
        data: { name: "Unrelated Petal" },
      },
    }),
  );
  const sources = await dropdown(page, "feedback-source");
  await expect(sources.getByText("Starlit", { exact: true })).toBeVisible();
  await expect(sources.getByText("Bloom", { exact: true })).toHaveCount(0);
  await expect(sources.getByText("Afterglow", { exact: true })).toHaveCount(0);
  await sources.getByText("Starlit", { exact: true }).click();
  const versions = await dropdown(page, "feedback-version");
  await expect(
    versions.getByText("Closure Moon", { exact: true }),
  ).toBeVisible();
  await expect(
    versions.getByText("Unrelated Petal", { exact: true }),
  ).toHaveCount(0);
  await versions.getByText("Closure Moon", { exact: true }).click();
  await page.getByRole("button", { name: "保存草稿", exact: true }).click();
  await expect
    .poll(async () => (await setup.detail(row.id)).draft.entity_version_id)
    .toBe(version.id);
  const selected = await setup.detail(row.id);
  expect(selected.draft.source_entity_id).toBe("album-starlit");
  expect(selected.entity_id).toBe(draft.entity_id);
  expect(await notices()).toHaveLength(0);

  // A publication validation failure must not change the revision or notify.
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("资料和版本已核对，采用提交图片。");
  await publish(page);
  await expect(page.locator(".feedback-submit-error")).toBeVisible();
  expect((await setup.detail(row.id)).revision).toBe(selected.revision);
  expect((await userDetail()).history).toEqual(before.history);
  expect(await notices()).toHaveLength(0);
  await choose(page, "feedback-front-copyright", "已确认获得使用授权");
  await publish(page);
  await expect.poll(async () => (await userDetail()).result).toBe("INCLUDED");
  expect(await notices()).toHaveLength(1);
  const adopted = await userDetail();
  expect(adopted.target_available).toBeTruthy();
  expect(adopted.entity_id).toBe(draft.entity_id);
  const card = await data(
    await request.get(`${apiRoot}/catalog/cards/${adopted.entity_id}`),
  );
  expect(card.id).toBe(adopted.entity_id);
  await capture(page, "adopted-official-card");
});

test("needs information returns to the same record and can be adopted after resubmission", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createMissing();
  await edit(page, row.id);
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("请补充卡面版本依据及清晰图片。");
  await page.getByRole("button", { name: "更多", exact: true }).click();
  await page
    .getByRole("menuitem", { name: "信息缺失待补充", exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "信息缺失待补充", exact: true })
    .click();
  const read = () =>
    request
      .get(`${apiRoot}/feedback/records/${row.id}`, {
        headers: setup.userHeaders,
      })
      .then(data);
  await expect.poll(async () => (await read()).result).toBe("NEEDS_INFO");
  const waiting = await read();
  expect(waiting.can_resubmit).toBeTruthy();
  expect(waiting.public_note).toContain("请补充");
  await capture(page, "needs-information");
  const s = waiting.submission;
  const body = {
    kind: "MISSING_CARD",
    request_key: crypto.randomUUID(),
    revision: waiting.revision,
    missing: {
      ...s.missing,
      scan_session_id: s.scan.scan_session_id,
      detected_card_id: s.scan.detected_card_id,
      front_image_id: s.front.id,
      back_image_id: s.back?.id,
    },
    notes: "已补充清晰版本资料，请重新核对。",
    links: s.links,
    evidence_ids: (s.evidence || []).map((e: any) => e.id),
  };
  const resubmitted = await data(
    await request.post(`${apiRoot}/feedback/records/${row.id}/resubmit`, {
      headers: setup.userHeaders,
      data: body,
    }),
  );
  expect(resubmitted.id).toBe(row.id);
  expect(resubmitted.result).toBe("PENDING");
  expect(
    (
      await data(
        await request.post(`${apiRoot}/feedback/records/${row.id}/resubmit`, {
          headers: setup.userHeaders,
          data: body,
        }),
      )
    ).revision,
  ).toBe(resubmitted.revision);
  await edit(page, row.id);
  await expect(
    page.getByText("已补充清晰版本资料，请重新核对。", { exact: true }),
  ).toBeVisible();
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("补充资料已核对并采用。");
  await choose(page, "feedback-front-copyright", "已确认获得使用授权");
  await publish(page);
  await expect.poll(async () => (await read()).result).toBe("INCLUDED");
  const final = await read();
  expect(
    final.history.some((h: any) => h.result === "NEEDS_INFO"),
  ).toBeTruthy();
  expect(final.can_resubmit).toBeFalsy();
});

test("cannot adopt preserves the user's record and evidence without creating an official card", async ({
  page,
  request,
}) => {
  const setup = await setupFeedback(request, page);
  const row = await setup.createMissing();
  await edit(page, row.id);
  await page
    .getByLabel("公开处理说明", { exact: true })
    .fill("暂无法核实为官方发行，保留本次提交记录。");
  await page.getByRole("button", { name: "更多", exact: true }).click();
  await page.getByRole("menuitem", { name: "无法采用", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "无法采用", exact: true })
    .click();
  const read = () =>
    request
      .get(`${apiRoot}/feedback/records/${row.id}`, {
        headers: setup.userHeaders,
      })
      .then(data);
  await expect.poll(async () => (await read()).result).toBe("NOT_INCLUDED");
  const rejected = await read();
  expect(rejected.id).toBe(row.id);
  expect(rejected.submission.front.id).toBe(row.submission.front.id);
  expect(rejected.entity_id).toBe("");
  expect(rejected.target_available).toBeFalsy();
  expect(rejected.can_resubmit).toBeFalsy();
  await capture(page, "not-adopted-record-retained");
});

import { expect, type APIRequestContext, type Page } from "@playwright/test";
import { execFileSync } from "node:child_process";
export const apiRoot = "http://127.0.0.1:8011/api/v1";
export async function data(response: any) {
  expect(response.status(), await response.text()).toBe(200);
  return (await response.json()).data;
}
export async function setupFeedback(request: APIRequestContext, page: Page) {
  const admin = await data(
    await request.post(apiRoot + "/auth/login", {
      data: { method: "phone", phone: "13900000000", code: "123456" },
    }),
  );
  const user = await data(
    await request.post(apiRoot + "/auth/login", {
      data: { method: "phone", phone: "13800000000", code: "123456" },
    }),
  );
  const headers = { Authorization: `Bearer ${user.access_token}` };
  const adminHeaders = { Authorization: `Bearer ${admin.access_token}` };
  await page.addInitScript(
    (value) =>
      sessionStorage.setItem("fanos-admin-session", JSON.stringify(value)),
    admin,
  );
  const image = execFileSync("../api/.venv/bin/python", [
    "-c",
    'from skimage import data; from PIL import Image; import sys; Image.fromarray(data.astronaut()).crop((110,20,370,395)).resize((260,375)).save(sys.stdout.buffer,format="PNG")',
  ]);
  const scan = await data(
    await request.post(apiRoot + "/scan/detect", {
      headers,
      multipart: {
        image: {
          name: "local-fixture.png",
          mimeType: "image/png",
          buffer: image,
        },
      },
    }),
  );
  expect(scan.detected_cards.length).toBeGreaterThan(0);
  const createMissing = async (extra: Record<string, unknown> = {}) =>
    data(
      await request.post(apiRoot + "/feedback", {
        headers,
        data: {
          kind: "MISSING_CARD",
          request_key: crypto.randomUUID(),
          notes: "专辑附赠小卡，请核对版本与正面图片。",
          links: ["https://example.test/album/reference"],
          missing: {
            title: "本地验收 · 星光专辑小卡",
            scan_session_id: scan.session_id,
            detected_card_id: scan.detected_cards[0].detected_card_id,
            group_id: "group-lumina",
            idol_id: "idol-aria",
            source_entity_type: "ALBUM",
            source_entity_id: "album-starlit",
            ...extra,
          },
        },
      }),
    );
  const createCorrection = async () => {
    const object = await data(
      await request.get(apiRoot + "/feedback/objects/albums/album-starlit", {
        headers,
      }),
    );
    return data(
      await request.post(apiRoot + "/feedback", {
        headers,
        data: {
          kind: "CORRECTION",
          request_key: crypto.randomUUID(),
          entity_type: "albums",
          entity_id: "album-starlit",
          object_version: object.version,
          fields: [
            { key: "name", value: `Starlit · 正式发行名称 ${Date.now()}` },
            {
              key: "description",
              mode: "UNKNOWN",
              reason: "请核实发行介绍中的版本范围",
            },
          ],
          notes: "对照专辑内页提交，请分别核对两个字段。",
        },
      }),
    );
  };
  const action = async (
    row: any,
    action: string,
    extra: Record<string, unknown> = {},
  ) =>
    data(
      await request.post(
        apiRoot + `/admin/console/feedback/${row.id}/actions`,
        {
          headers: adminHeaders,
          data: {
            action,
            revision: row.revision,
            request_key: crypto.randomUUID(),
            public_note: "本地验收处理记录",
            ...extra,
          },
        },
      ),
    );
  const detail = async (id: string) =>
    data(
      await request.get(apiRoot + `/admin/console/feedback/${id}`, {
        headers: adminHeaders,
      }),
    );
  return {
    createMissing,
    createCorrection,
    action,
    detail,
    headers: adminHeaders,
  };
}

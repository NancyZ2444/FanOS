import { useEffect, useRef, useState } from "react";
import {
  Alert,
  App,
  Button,
  DatePicker,
  Input,
  InputNumber,
  Select,
} from "antd";
import { consoleApi, send } from "../../api/client";
import { Form, Modal, useSingleSubmit } from "../../components/admin";
import type { Limits } from "./types";

type Impact = {
  requires_confirmation: boolean;
  affected_users: number;
  affected_albums: number;
  reductions: { field: string; before: number; after: number }[];
  confirmation_token?: string;
};
type PendingSave = { values: Limits; impact: Impact };
const quotaRows = [
  { label: "作品总数（两类共用）", key: "albums", max: 100, unit: "份", min: 1 },
  { label: "卡片作品容量", key: "cards", max: 450, unit: "张", min: 1 },
  { label: "单本页面数量", key: "pages", max: 50, unit: "页", min: 1 },
  { label: "每日图片取色", key: "color_daily", max: 10000, unit: "次", min: 0 },
  {
    label: "每月图片取色",
    key: "color_monthly",
    max: 100000,
    unit: "次",
    min: 0,
  },
] as const;
export default function AlbumSettings({
  limits,
  canEdit,
  onSaved,
  onDirty,
  onReset,
}: {
  limits?: Limits;
  canEdit: boolean;
  onSaved: () => Promise<void>;
  onDirty: () => void;
  onReset: () => void;
}) {
  const { message, modal } = App.useApp();
  const [form] = Form.useForm(),
    [entitlementForm] = Form.useForm();
  const [busy, setBusy] = useState(false),
    [pending, setPending] = useState<PendingSave>();
  const dirty = useRef({ limits: false, entitlement: false });
  const mark = (scope: "limits" | "entitlement") => {
    dirty.current[scope] = true;
    onDirty();
  };
  const reset = (scope: "limits" | "entitlement") => {
    dirty.current[scope] = false;
    if (dirty.current.limits || dirty.current.entitlement) onDirty();
    else onReset();
  };
  const cancel = (scope: "limits" | "entitlement", callback: () => void) => {
    const discard = () => {
      callback();
      reset(scope);
    };
    if (!dirty.current[scope]) discard();
    else
      modal.confirm({
        title: "放弃未保存的修改？",
        content: "已填写的内容尚未保存，放弃后将恢复原值。",
        okText: "放弃修改",
        cancelText: "继续编辑",
        onOk: discard,
      });
  };
  useEffect(() => {
    if (limits)
      form.setFieldsValue({
        ...limits,
        blocked_terms: limits.blocked_terms.join("\n"),
      });
  }, [limits, form]);
  const save = async (values: Limits, token?: string) => {
    await consoleApi(
      `/album-settings${token ? `?confirm_impact=${encodeURIComponent(token)}` : ""}`,
      send(values, "PUT"),
    );
    setPending(undefined);
    reset("limits");
    message.success("相册配置已保存");
    await onSaved();
  };
  const submit = useSingleSubmit(async (data: Record<string, unknown>) => {
    setBusy(true);
    try {
      const values = {
        ...data,
        blocked_terms: String(data.blocked_terms || "")
          .split("\n")
          .map((s) => s.trim())
          .filter(Boolean),
      } as Limits;
      const impact = await consoleApi<Impact>(
        "/album-settings/impact",
        send(values),
      );
      if (impact.requires_confirmation) setPending({ values, impact });
      else await save(values);
    } catch (error) {
      message.error((error as Error).message);
    } finally {
      setBusy(false);
    }
  });
  const grant = useSingleSubmit(async (values: Record<string, any>) => {
    setBusy(true);
    try {
      await consoleApi(
        `/album-entitlements/${encodeURIComponent(values.user_id.trim())}`,
        send(
          {
            plan: values.plan,
            expires_at: values.expires_at
              ? `${values.expires_at.format("YYYY-MM-DDTHH:mm:ss")}+08:00`
              : null,
          },
          "PUT",
        ),
      );
      entitlementForm.resetFields();
      reset("entitlement");
      message.success("会员权益已更新");
    } catch (error) {
      message.error((error as Error).message);
    } finally {
      setBusy(false);
    }
  });
  return (
    <div className="album-settings">
      <section className="album-panel">
        <h2>会员额度配置</h2>
        <p className="album-muted">
          按北京时间（UTC+08:00）重置取色额度。成功分析一次计一次，失败或取消不扣减。
        </p>
        <Form
          form={form}
          onValuesChange={() => mark("limits")}
          disabled={!canEdit || busy}
          onFinish={submit}
          layout="vertical"
        >
          <div className="album-quota-matrix">
            <div className="album-quota-heading">权益项目</div>
            <div className="album-quota-heading">普通用户</div>
            <div className="album-quota-heading">PRO 会员</div>
            {quotaRows.map((row) => (
              <div className="album-quota-row" key={row.key}>
                <div>
                  {row.label}
                  <span className="album-muted">（{row.unit}）</span>
                </div>
                <Form.Item
                  name={`normal_${row.key}`}
                  rules={[{ required: true, message: "请输入额度" }]}
                >
                  <InputNumber
                    aria-label={`普通用户${row.label}`}
                    min={row.min}
                    max={row.max}
                    precision={0}
                  />
                </Form.Item>
                <Form.Item
                  name={`pro_${row.key}`}
                  rules={[{ required: true, message: "请输入额度" }]}
                >
                  <InputNumber
                    aria-label={`PRO ${row.label}`}
                    min={row.min}
                    max={row.max}
                    precision={0}
                  />
                </Form.Item>
              </div>
            ))}
          </div>
          <div className="album-settings-fields">
            <Form.Item
              name="max_card_per_page"
              label="每页卡位上限"
              rules={[{ required: true }]}
              extra="所有会员类型共用，最多 9 个卡位。"
            >
              <InputNumber min={1} max={9} precision={0} />
            </Form.Item>
            <Form.Item
              name="blocked_terms"
              label="公开内容拦截词"
              extra="每行一个，用于公开内容校验。"
            >
              <Input.TextArea rows={4} maxLength={4000} />
            </Form.Item>
          </div>
          <Alert
            type="info"
            showIcon
            message="额度降低或会员到期不会删除已有相册、页面和素材。新增容量和新增素材按当前权益校验。"
          />
          {canEdit && (
            <div className="form-actions">
              <Button
                onClick={() =>
                  cancel("limits", () => {
                    if (limits)
                      form.setFieldsValue({
                        ...limits,
                        blocked_terms: limits.blocked_terms.join("\n"),
                      });
                  })
                }
              >
                取消
              </Button>
              <Button type="primary" htmlType="submit" loading={busy}>
                保存
              </Button>
            </div>
          )}
        </Form>
      </section>
      <section className="album-panel">
        <h2>人工会员授权</h2>
        <p className="album-muted">
          沿用普通 / PRO 两级会员，为指定用户更新相册权益。
        </p>
        <Form
          form={entitlementForm}
          layout="vertical"
          disabled={!canEdit || busy}
          onValuesChange={() => mark("entitlement")}
          onFinish={grant}
        >
          <div className="album-entitlement-grid">
            <Form.Item
              name="user_id"
              label="用户编号"
              rules={[
                { required: true, whitespace: true, message: "请输入用户编号" },
              ]}
            >
              <Input placeholder="用户 ID" />
            </Form.Item>
            <Form.Item
              name="plan"
              label="会员类型"
              initialValue="NORMAL"
              rules={[{ required: true }]}
            >
              <Select
                options={[
                  { value: "NORMAL", label: "普通用户" },
                  { value: "PRO", label: "PRO 会员" },
                ]}
              />
            </Form.Item>
            <Form.Item
              name="expires_at"
              label="到期时间"
              extra="北京时间；留空表示持续有效。"
            >
              <DatePicker
                showTime
                format="YYYY-MM-DD HH:mm"
                placeholder="选择到期时间"
              />
            </Form.Item>
          </div>
          {canEdit && (
            <div className="form-actions">
              <Button
                onClick={() =>
                  cancel("entitlement", () => {
                    entitlementForm.resetFields();
                  })
                }
              >
                取消
              </Button>
              <Button type="primary" htmlType="submit" loading={busy}>
                更新权益
              </Button>
            </div>
          )}
        </Form>
      </section>
      <Modal
        title="确认降低会员额度"
        open={!!pending}
        okText="确认并保存"
        confirmLoading={busy}
        onCancel={() => setPending(undefined)}
        onOk={async () => {
          if (!pending) return;
          setBusy(true);
          try {
            await save(pending.values, pending.impact.confirmation_token);
          } catch (error) {
            message.error((error as Error).message);
          } finally {
            setBusy(false);
          }
        }}
      >
        {pending && (
          <>
            <Alert
              type="warning"
              showIcon
              message="本次配置包含额度降低，已有内容继续保留。"
            />
            <dl className="album-impact">
              <dt>影响用户</dt>
              <dd>{pending.impact.affected_users} 位</dd>
              <dt>影响相册</dt>
              <dd>{pending.impact.affected_albums} 本</dd>
            </dl>
            <ul className="album-impact-reductions">
              {pending.impact.reductions.map((reduction) => {
                const type = reduction.field.startsWith("pro_")
                  ? "PRO"
                  : "普通用户";
                const label =
                  reduction.field === "max_card_per_page"
                    ? "每页卡位上限"
                    : `${type}${quotaRows.find((r) => reduction.field.endsWith(`_${r.key}`))?.label || "额度"}`;
                return (
                  <li key={reduction.field}>
                    {label}：{reduction.before} → {reduction.after}
                  </li>
                );
              })}
            </ul>
            <p>
              超出新额度的用户可以维护已有内容，新增相册、页面或取色将按新额度限制。保存后立即生效。
            </p>
          </>
        )}
      </Modal>
    </div>
  );
}

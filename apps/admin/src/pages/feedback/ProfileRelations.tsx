import { Button, Input, Select, Space } from "antd";
import type { Field, Values } from "./types";
import { ValueEditor } from "./FeedbackValues";

export function ProfileRelations({
  field,
  value,
  onChange,
  disabled,
}: {
  field: Field;
  value: Values[];
  onChange: (v: Values[]) => void;
  disabled?: boolean;
}) {
  const ops = Array.isArray(value) ? value : [];
  const accounts = field.key === "official_accounts";
  const current: Values[] = Array.isArray(field.current) ? field.current : [];
  const set = (index: number, patch: Values) =>
    onChange(ops.map((v, i) => (i === index ? { ...v, ...patch } : v)));
  return (
    <div>
      <p className="feedback-muted">
        按稳定关系逐项修订。正常退出修改结束日期；错误关系作废保留历史，不直接删除。
      </p>
      {ops.map((op, i) => (
        <section
          key={i}
          style={{ borderBottom: "1px solid #E6E8F0", paddingBlock: 12 }}
        >
          <Space wrap>
            <Select
              aria-label={`关系${i + 1}操作`}
              value={op.operation}
              disabled={disabled}
              onChange={(v) =>
                set(i, { operation: v, id: undefined, data: {} })
              }
              options={[
                { value: "ADD", label: "新增" },
                { value: "UPDATE", label: "修正" },
                { value: "DELETE", label: "作废" },
              ]}
            />
            {op.operation !== "ADD" && (
              <Select
                aria-label={`关系${i + 1}原记录`}
                style={{ minWidth: 180 }}
                disabled={disabled}
                value={op.id}
                placeholder="选择已有关系"
                options={current.map((r) => ({
                  value: r.id,
                  label: `${r.name || r.handle || ""} ${r.start_date || ""}`,
                }))}
                onChange={(id) => {
                  const r = current.find((v) => v.id === id)!;
                  const data = accounts
                    ? {
                        platform: r.platform,
                        handle: r.handle,
                        platform_account_id: r.platform_account_id,
                      }
                    : {
                        target_id: r.target_id,
                        start_date: r.start_date,
                        end_date: r.end_date,
                        ...(field.key === "memberships"
                          ? { status: r.status, role: r.role }
                          : {}),
                      };
                  set(i, { id, data });
                }}
              />
            )}
            <Button
              disabled={disabled}
              onClick={() => onChange(ops.filter((_, n) => n !== i))}
            >
              移除建议
            </Button>
          </Space>
          {op.operation !== "DELETE" && (
            <div style={{ display: "grid", gap: 8, marginTop: 12 }}>
              {!accounts && op.operation === "ADD" && (
                <ValueEditor
                  field={{
                    ...field,
                    type: "reference",
                    reference:
                      field.key === "company_relations"
                        ? "companies"
                        : field.entity_type === "groups"
                          ? "idols"
                          : "groups",
                    label: "关联对象",
                  }}
                  value={op.data?.target_id}
                  disabled={disabled}
                  onChange={(v) =>
                    set(i, { data: { ...op.data, target_id: v } })
                  }
                />
              )}
              {(accounts
                ? ["platform", "handle", "platform_account_id"]
                : [
                    "start_date",
                    "end_date",
                    ...(field.key === "memberships" ? ["role"] : []),
                  ]
              ).map((k) => (
                <Input
                  key={k}
                  aria-label={k}
                  disabled={disabled}
                  value={op.data?.[k] || ""}
                  placeholder={
                    (
                      {
                        platform: "平台",
                        handle: "显示名称",
                        platform_account_id: "账号标识",
                        start_date: "开始日期 YYYY-MM-DD",
                        end_date: "结束日期 YYYY-MM-DD（选填）",
                        role: "角色（选填）",
                      } as Values
                    )[k]
                  }
                  onChange={(e) =>
                    set(i, { data: { ...op.data, [k]: e.target.value } })
                  }
                />
              ))}
              {field.key === "memberships" && (
                <Select
                  aria-label="成员状态"
                  value={op.data?.status}
                  disabled={disabled}
                  options={[
                    { value: "active", label: "活动中" },
                    { value: "inactive", label: "暂停活动" },
                    { value: "former", label: "历史成员" },
                  ]}
                  onChange={(v) => set(i, { data: { ...op.data, status: v } })}
                />
              )}
            </div>
          )}
          <Input.TextArea
            style={{ marginTop: 8 }}
            value={op.reason || ""}
            disabled={disabled}
            placeholder="关系修订原因（作废必填）"
            onChange={(e) => set(i, { reason: e.target.value })}
            maxLength={1000}
          />
        </section>
      ))}
      <Button
        disabled={disabled || ops.length >= 20}
        onClick={() =>
          onChange([...ops, { operation: "ADD", data: {}, reason: "" }])
        }
      >
        添加关系变更
      </Button>
    </div>
  );
}

import { ProfileRelations } from "./ProfileRelations";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { Alert, Checkbox, Image, Input, Select } from "antd";
import { consoleApi } from "../../api/client";
import { companyEnabled } from "../../api/permissions";
import { Form } from "../../components/admin";
import { displayValue } from "../../design/format";
import { useConsole } from "../../state";
import type { Field, Values } from "./types";

export function ReviewSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="detail-section">
      <h2>{title}</h2>
      {children}
    </section>
  );
}
export function ReviewField({
  label,
  id,
  required,
  error,
  extra,
  children,
}: {
  label: string;
  id: string;
  required?: boolean;
  error?: string;
  extra?: ReactNode;
  children: ReactNode;
}) {
  return (
    <Form.Item
      label={label}
      htmlFor={id}
      required={required}
      validateStatus={error ? "error" : undefined}
      help={error}
      extra={extra}
    >
      {children}
    </Form.Item>
  );
}
export function ValueView({ field, value }: { field: Field; value: any }) {
  const { catalog } = useConsole();
  const catalogRows = Object.values(catalog).flat() as Values[];
  const relationName = (r: Values) =>
    r.name ||
    r.handle ||
    r.data?.handle ||
    field.current?.find?.((v: Values) => v.id === r.id)?.name ||
    Object.values(catalog)
      .flat()
      .find((v: any) => v?.id === r.data?.target_id)?.name ||
    "关联资料";
  if (field.type === "image" && value)
    return (
      <Image className="feedback-field-image" src={value} alt={field.label} />
    );
  if (field.reference && typeof value === "string" && value) {
    const choices =
      (catalog as unknown as Record<string, Values[]>)[field.reference] ||
      catalogRows;
    const item = choices.find((v) => v.id === value);
    return item ? (
      <span className="feedback-value">{item.name || item.title}</span>
    ) : (
      <span className="feedback-value">关联资料暂不可用</span>
    );
  }
  if (field.type === "multi_reference" && Array.isArray(value)) {
    return (
      <span className="feedback-value">
        {value
          .map(
            (v) =>
              v.name ||
              catalogRows.find((row) => row.id === v.id)?.name ||
              "关联资料暂不可用",
          )
          .join("、") || "—"}
      </span>
    );
  }
  if (field.type === "relations" && Array.isArray(value))
    return (
      <div style={{ whiteSpace: "pre-wrap" }}>
        {value.map((r, i) => (
          <p key={i}>
            {r.operation
              ? ({ ADD: "新增", UPDATE: "修改", DELETE: "作废" } as Values)[
                  r.operation
                ]
              : ""}{" "}
            {relationName(r)}{" "}
            {[
              r.start_date || r.data?.start_date,
              r.end_date || r.data?.end_date,
              r.status || r.data?.status,
              r.role || r.data?.role,
            ]
              .filter(Boolean)
              .join(" · ")}
            {r.reason && <span> · {r.reason}</span>}
          </p>
        ))}
      </div>
    );
  const shown = Array.isArray(value)
    ? value
        .map((v) =>
          typeof v === "object" && v
            ? v.name || v.id || displayValue(v)
            : displayValue(v),
        )
        .join("、") || "—"
    : displayValue(value);
  return (
    <span
      className="feedback-value"
      style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}
    >
      {shown}
    </span>
  );
}
export function ValueEditor({
  field,
  value,
  onChange,
  id,
  disabled,
}: {
  field: Field;
  value: any;
  onChange: (value: any) => void;
  id?: string;
  disabled?: boolean;
}) {
  const [choices, setChoices] = useState<Values[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const sequence = useRef(0);
  const load = useCallback(
    async (q = "") => {
      if (!field.reference) return;
      const ticket = ++sequence.current;
      if (field.reference === "versions" && !field.parent_id) {
        setChoices([]);
        setLoading(false);
        setError("");
        return;
      }
      setLoading(true);
      try {
        const query = new URLSearchParams({
          entity_type: field.reference,
          q,
          ...(field.parent_id ? { parent_id: field.parent_id } : {}),
        });
        const response =
          field.reference === "companies"
            ? await consoleApi("/records/companies")
            : await consoleApi(`/feedback/objects?${query}`);
        const items =
          field.reference === "companies"
            ? response.items
                .filter(
                  (row: Values) =>
                    companyEnabled(row) &&
                    (!q ||
                      row.data.name.toLowerCase().includes(q.toLowerCase())),
                )
                .map((row: Values) => ({
                  ...row,
                  name: row.data.name,
                  entity_type: "companies",
                }))
            : response.items;
        if (ticket === sequence.current) {
          setChoices(items);
          setError("");
        }
      } catch (e) {
        if (ticket === sequence.current) setError((e as Error).message);
      } finally {
        if (ticket === sequence.current) setLoading(false);
      }
    },
    [field.reference, field.parent_id],
  );
  useEffect(() => {
    setChoices([]);
    void load();
    return () => {
      sequence.current++;
    };
  }, [load]);
  const label = field.label + "采用值";
  if (field.type === "relations")
    return (
      <ProfileRelations
        field={field}
        value={value}
        onChange={onChange}
        disabled={disabled}
      />
    );
  if (field.type === "boolean")
    return (
      <Checkbox
        id={id}
        aria-label={label}
        disabled={disabled}
        checked={!!value}
        onChange={(e) => onChange(e.target.checked)}
      >
        是
      </Checkbox>
    );
  if (field.type === "enum")
    return (
      <Select
        id={id}
        aria-label={label}
        disabled={disabled}
        value={value}
        options={field.options?.map((v) => ({
          value: v,
          label: displayValue(v),
        }))}
        onChange={onChange}
      />
    );
  if (field.reference) {
    const previous: Values[] =
      field.type === "multi_reference" && Array.isArray(value) ? value : [];
    const options = [
      ...choices,
      ...previous.filter((v) => !choices.some((c) => c.id === v.id)),
    ];
    return (
      <>
        <Select
          id={id}
          aria-label={label}
          disabled={
            disabled ||
            (field.reference === "versions" && (!field.parent_id || loading))
          }
          placeholder={
            field.reference === "versions" && !field.parent_id
              ? "请先选择正式来源"
              : "搜索并选择"
          }
          loading={loading}
          className="feedback-select"
          showSearch
          filterOption={false}
          onSearch={(q) => void load(q)}
          mode={field.type === "multi_reference" ? "multiple" : undefined}
          value={
            field.type === "multi_reference"
              ? previous.map((v) => v.id)
              : value || undefined
          }
          options={options.map((v) => ({ value: v.id, label: v.name || v.id }))}
          onChange={(v) =>
            onChange(
              field.type === "multi_reference"
                ? (v as string[])
                    .map((key) => {
                      const item = choices.find((c) => c.id === key);
                      return item
                        ? { id: key, type: item.entity_type, name: item.name }
                        : previous.find((old) => old.id === key);
                    })
                    .filter(Boolean)
                : v,
            )
          }
        />
        {error && (
          <span className="feedback-field-error" role="alert">
            {error}
          </span>
        )}
      </>
    );
  }
  if (field.type === "image")
    return (
      <Alert
        type="info"
        showIcon
        message="选择“采纳”使用用户图片；替换其他图片请前往图鉴编辑。"
      />
    );
  return (
    <Input.TextArea
      id={id}
      aria-label={label}
      disabled={disabled}
      autoSize={{ minRows: field.type === "long_text" ? 6 : 2, maxRows: 18 }}
      showCount
      maxLength={field.max_length ?? 2000}
      value={Array.isArray(value) ? value.join("\n") : (value ?? "")}
      placeholder={
        field.type === "date"
          ? "YYYY-MM-DD"
          : field.type === "list"
            ? "每行一项"
            : "填写审核采用值"
      }
      onChange={(e) =>
        onChange(
          field.type === "list"
            ? e.target.value.split("\n").filter(Boolean)
            : e.target.value,
        )
      }
    />
  );
}

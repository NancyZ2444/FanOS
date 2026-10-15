import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { Alert, Checkbox, Image, Input, Select } from "antd";
import { api } from "../../api/client";
import { Form, RecordId } from "../../components/admin";
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
  if (field.type === "image" && value)
    return (
      <Image className="feedback-field-image" src={value} alt={field.label} />
    );
  if (field.reference && typeof value === "string" && value) {
    const choices =
      (catalog as unknown as Record<string, Values[]>)[field.reference] || [];
    const item = choices.find((v) => v.id === value);
    return item ? (
      <span className="feedback-value">{item.name || item.title}</span>
    ) : (
      <RecordId value={value} />
    );
  }
  const shown = Array.isArray(value)
    ? value
        .map((v) =>
          typeof v === "object" && v
            ? v.name || v.id || displayValue(v)
            : displayValue(v),
        )
        .join("、") || "—"
    : displayValue(value);
  return <span className="feedback-value">{shown}</span>;
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
      setLoading(true);
      try {
        const response = await api(
          `/feedback/objects?entity_type=${field.reference}&q=${encodeURIComponent(q)}`,
        );
        if (ticket === sequence.current) {
          setChoices(response.items);
          setError("");
        }
      } catch (e) {
        if (ticket === sequence.current) setError((e as Error).message);
      } finally {
        if (ticket === sequence.current) setLoading(false);
      }
    },
    [field.reference],
  );
  useEffect(() => {
    void load();
    return () => {
      sequence.current++;
    };
  }, [load]);
  const label = field.label + "采用值";
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
          disabled={disabled}
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
      rows={2}
      maxLength={2000}
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

import { canPermission } from "../../api/permissions";
import { useEffect, useRef, useState } from "react";
import {
  Alert,
  App,
  Button,
  Checkbox,
  Collapse,
  Input,
  Select,
  Space,
  Tag,
  Timeline,
} from "antd";
import { ApiError, consoleApi } from "../../api/client";
import {
  Form,
  PageHeader,
  RecordId,
  useFormGuard,
  useSingleSubmit,
} from "../../components/admin";
import { formatTime } from "../../design/format";
import "../catalog-editorial.css";
import { useConsole } from "../../state";
import {
  ReviewField,
  ReviewSection,
  ValueEditor,
  ValueView,
} from "./FeedbackValues";
import { kinds, type FeedbackRecord, type Field, type Values } from "./types";
import ReviewDecisionFields, {
  initialReviewResult,
} from "./ReviewDecisionFields";

function ReferenceEditor({
  field,
  value,
  disabled,
  onChange,
}: {
  field: Field;
  value: any;
  disabled: boolean;
  onChange: (value: any) => void;
}) {
  const { catalog } = useConsole();
  const [items, setItems] = useState<Values[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const request = useRef(0);
  const load = async (query = "") => {
    const ticket = ++request.current;
    setLoading(true);
    try {
      const data = await consoleApi(
        `/feedback/objects?${new URLSearchParams({ entity_type: field.reference!, q: query })}`,
      );
      if (ticket === request.current) {
        setItems(data.items);
        setError("");
      }
    } catch (e) {
      if (ticket === request.current) setError((e as Error).message);
    } finally {
      if (ticket === request.current) setLoading(false);
    }
  };
  useEffect(() => {
    void load();
    return () => {
      request.current++;
    };
  }, [field.reference]);
  const multi = field.type === "multi_reference";
  const selectedIds: string[] = multi
    ? (value || []).map((v: Values) => v.id)
    : value
      ? [value]
      : [];
  const catalogRows = Object.values(catalog).flat() as Values[];
  const choices = [
    ...items,
    ...selectedIds
      .filter((id) => !items.some((v) => v.id === id))
      .map((id) => ({
        id,
        name: catalogRows.find((v) => v.id === id)?.name || "关联资料暂不可用",
      })),
  ];
  return (
    <>
      <Select
        id={`catalog-${field.key}`}
        disabled={disabled}
        aria-label={field.label}
        showSearch
        allowClear
        loading={loading}
        mode={multi ? "multiple" : undefined}
        filterOption={false}
        onSearch={(q) => void load(q)}
        value={
          multi ? (value || []).map((v: Values) => v.id) : value || undefined
        }
        options={choices.map((v) => ({ value: v.id, label: v.name }))}
        onChange={(v) =>
          onChange(
            multi
              ? (v as string[])
                  .map((id) => {
                    const item = items.find((x) => x.id === id);
                    return item
                      ? { type: item.entity_type, id }
                      : (value || []).find((x: Values) => x.id === id);
                  })
                  .filter(Boolean)
              : v || "",
          )
        }
      />
      {error && (
        <Alert
          type="error"
          message={error}
          action={<Button onClick={() => void load()}>重试</Button>}
        />
      )}
    </>
  );
}

export default function MissingCatalogReview({
  item,
  onBack,
  onSaved,
}: {
  item: FeedbackRecord;
  onBack: () => void;
  onSaved: (item: FeedbackRecord) => void;
}) {
  const { actor } = useConsole();
  const { message, modal } = App.useApp();
  const [values, setValues] = useState<Values>({
    ...item.submission.catalog,
    ...item.review.catalog_draft,
    ...item.review.submitted_payload?.changes,
    ...item.review.approved_payload?.changes,
  });
  const [reviewResult, setReviewResult] = useState(() =>
    initialReviewResult(item),
  );
  const publicNote = reviewResult.note;
  const [editing, setEditing] = useState(!item.can_publish);
  const [internalNote, setInternalNote] = useState(item.internal_note || "");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [noteError, setNoteError] = useState("");
  const [decisionError, setDecisionError] = useState("");
  const guard = useFormGuard(editing && item.result === "PENDING", busy);
  const initial = useRef(
    JSON.stringify({ values, reviewResult, internalNote }),
  );
  useEffect(() => {
    if (
      JSON.stringify({ values, reviewResult, internalNote }) !== initial.current
    )
      guard.mark();
    else guard.reset();
  }, [values, reviewResult, internalNote]);
  const leave = () => guard.close(onBack);
  const request = useRef<{ signature: string; key: string } | undefined>(
    undefined,
  );
  const canEdit =
    item.result === "PENDING" && canPermission(actor, "catalog.edit");
  const canPublish =
    item.result === "PENDING" && canPermission(actor, "catalog.publish");
  const canReview = canEdit || canPublish;
  const editable = canReview && editing;
  const fields: Field[] =
    item.submission.catalog_schema || item.submission.fields || [];
  const change = (key: string, value: any) =>
    setValues((old) => ({ ...old, [key]: value }));
  const act = useSingleSubmit(async (action: string) => {
    if (busy) return;
    if (action === "publish" && (!item.can_publish || editing)) return;
    if (action === "decide") {
      setDecisionError(reviewResult.decision ? "" : "请选择处理结果。");
      setNoteError(publicNote.trim() ? "" : "请填写面向用户的处理说明。");
      if (!reviewResult.decision || !publicNote.trim()) return;
    }
    const body =
      action === "publish"
        ? { action, revision: item.revision }
        : {
            action,
            revision: item.revision,
            changes: values,
            public_note: publicNote,
            review_decision: reviewResult.decision,
            internal_note: internalNote,
          };
    const signature = JSON.stringify(body);
    if (request.current?.signature !== signature)
      request.current = { signature, key: crypto.randomUUID() };
    setBusy(true);
    setError("");
    setNoteError("");
    try {
      const data = await consoleApi<FeedbackRecord>(
        `/feedback/${item.id}/actions`,
        {
          method: "POST",
          body: JSON.stringify({ ...body, request_key: request.current.key }),
        },
      );
      guard.reset();
      message.success(
        action === "draft"
          ? "处理草稿已保存，用户动态未更新"
          : action === "publish"
            ? "图鉴已发布并收录"
            : "处理结果已提交并同步用户",
      );
      onSaved(data);
    } catch (e) {
      setError(
        e instanceof ApiError && e.fields.length
          ? `${e.message}：${e.fields.map((field) => field.message).join("；")}`
          : (e as Error).message,
      );
    } finally {
      setBusy(false);
    }
  });
  const publish = () =>
    modal.confirm({
      title: `发布并收录「${item.name}」？`,
      content:
        "将按已提交的审核内容更新正式图鉴并通知用户，发布仍需通过图鉴校验。",
      okText: "发布并收录",
      cancelText: "取消",
      onOk: () => act("publish"),
    });
  return (
    <>
      <PageHeader
        title="图鉴新增 · 处理详情"
        actions={
          <>
            <Button disabled={busy} onClick={leave}>
              返回列表
            </Button>
            {canReview && !editing && (
              <Button disabled={busy} onClick={() => setEditing(true)}>
                编辑
              </Button>
            )}
          </>
        }
      />
      {error && (
        <Alert
          type="error"
          showIcon
          message={error}
          description="填写内容已保留，可修正后重试。"
        />
      )}
      <section className="panel editorial-panel">
        <div className="editorial-heading">
          <div>
            <h2>{item.name}</h2>
            <p className="subtle-note">
              {item.user.name} · 提交于 {formatTime(item.created_at)}
              （北京时间）
            </p>
          </div>
          <Space wrap>
            <Tag>{kinds.find((k) => k.value === item.entity_type)?.label}</Tag>
            <Tag>{item.status_label}</Tag>
          </Space>
        </div>
        <Collapse
          className="editorial-history"
          items={[
            {
              key: "submission",
              label: "查看用户原始提交",
              children: (
                <>
                  <div className="form-grid">
                    {fields.map((field) => (
                      <div
                        key={field.key}
                        className="editorial-submitted-field"
                      >
                        <div className="subtle-note">{field.label}</div>
                        <ValueView
                          field={field}
                          value={item.submission.catalog?.[field.key]}
                        />
                      </div>
                    ))}
                  </div>
                  {!!(
                    item.submission.notes || item.submission.links?.length
                  ) && (
                    <ReviewSection title="补充说明与参考链接">
                      <p className="editorial-preserved-text">
                        {item.submission.notes || "—"}
                      </p>
                      {(item.submission.links || []).map((url: string) => (
                        <p key={url} className="editorial-preserved-text">
                          <a href={url} target="_blank" rel="noreferrer">
                            {url}
                          </a>
                        </p>
                      ))}
                    </ReviewSection>
                  )}
                </>
              ),
            },
          ]}
        />
        <Form
          className="editorial-form editorial-spaced-form"
          disabled={!editable || busy}
        >
          <ReviewSection title={editable ? "核实资料" : "核实资料与采用值"}>
            <div className="form-grid">
              {fields.map((field) => (
                <div
                  key={field.key}
                  className={
                    ["long_text", "relations", "list"].includes(field.type)
                      ? "editorial-full-width"
                      : undefined
                  }
                >
                  <ReviewField id={`catalog-${field.key}`} label={field.label}>
                    {!editable ? (
                      <ValueView field={field} value={values[field.key]} />
                    ) : field.type === "image" ? (
                      item.submission.catalog?.[field.key] ? (
                        <div className="editorial-image-field">
                          <ValueView
                            field={field}
                            value={item.submission.catalog[field.key]}
                          />
                          <Checkbox
                            id={`catalog-${field.key}`}
                            checked={!!values[field.key]}
                            disabled={busy}
                            onChange={(e) =>
                              change(
                                field.key,
                                e.target.checked
                                  ? item.submission.catalog[field.key]
                                  : "",
                              )
                            }
                          >
                            采用提交图片
                          </Checkbox>
                        </div>
                      ) : (
                        <span>未提交图片</span>
                      )
                    ) : field.reference ? (
                      <ReferenceEditor
                        field={field}
                        value={values[field.key]}
                        disabled={busy}
                        onChange={(value) => change(field.key, value)}
                      />
                    ) : ["text", "url", "date"].includes(field.type) ? (
                      <Input
                        id={`catalog-${field.key}`}
                        aria-label={field.label}
                        type={field.type === "date" ? "date" : "text"}
                        maxLength={field.max_length ?? 2000}
                        value={values[field.key] ?? ""}
                        placeholder={`请输入${field.label}`}
                        onChange={(e) => change(field.key, e.target.value)}
                      />
                    ) : (
                      <ValueEditor
                        id={`catalog-${field.key}`}
                        field={field}
                        value={values[field.key]}
                        disabled={busy}
                        onChange={(value) => change(field.key, value)}
                      />
                    )}
                  </ReviewField>
                </div>
              ))}
            </div>
          </ReviewSection>
          <ReviewSection title="处理结果与发布">
            <ReviewDecisionFields
              idPrefix="catalog"
              value={reviewResult}
              editing={editable}
              decisionError={decisionError}
              noteError={noteError}
              onChange={(value) => {
                setReviewResult(value);
                setNoteError("");
                setDecisionError("");
              }}
            />
            <ReviewField
              id="catalog-internal-note"
              label="内部备注"
              extra="仅后台可见。"
            >
              <Input.TextArea
                id="catalog-internal-note"
                value={internalNote}
                maxLength={5000}
                autoSize={{ minRows: 3, maxRows: 6 }}
                onChange={(e) => setInternalNote(e.target.value)}
              />
            </ReviewField>
          </ReviewSection>
        </Form>
        <Collapse
          items={[
            {
              key: "history",
              label: "处理记录与系统信息",
              children: (
                <>
                  <Timeline
                    items={item.history.map((event) => ({
                      children: (
                        <>
                          <span className="subtle-note">
                            {formatTime(event.at)}（北京时间）
                          </span>
                          <p>{event.note}</p>
                        </>
                      ),
                    }))}
                  />
                  <Space wrap>
                    反馈编号：
                    <RecordId value={item.id} />
                    记录版本：{item.revision}
                  </Space>
                </>
              ),
            },
          ]}
        />
        <footer className="form-actions editorial-history">
          <Button disabled={busy} onClick={leave}>
            取消
          </Button>
          {canEdit && editing && (
            <Button
              aria-label="保存草稿"
              disabled={busy}
              loading={busy}
              onClick={() => void act("draft")}
            >
              保存草稿
            </Button>
          )}
          {canPublish && editing && (
            <Button
              aria-label="提交处理结果"
              type="primary"
              disabled={busy}
              loading={busy}
              onClick={() => void act("decide")}
            >
              提交处理结果
            </Button>
          )}
          {canPublish && item.can_publish && !editing && (
            <Button
              aria-label="发布并收录"
              type="primary"
              disabled={busy}
              loading={busy}
              onClick={publish}
            >
              发布并收录
            </Button>
          )}
        </footer>
      </section>
    </>
  );
}

import { useRef, useState } from "react";
import {
  Alert,
  App,
  Button,
  Checkbox,
  Descriptions,
  Dropdown,
  Image,
  Input,
  Select,
  Tag,
  Timeline,
} from "antd";
import { ArrowLeftOutlined, DownOutlined } from "@ant-design/icons";
import { Link } from "react-router-dom";
import { ApiError, consoleApi } from "../../api/client";
import {
  EmptyState,
  Form,
  PageHeader,
  RecordId,
  Table,
  useFormGuard,
  useSingleSubmit,
} from "../../components/admin";
import { displayValue, formatTime } from "../../design/format";
import { useConsole } from "../../state";
import {
  ReviewField,
  ReviewSection,
  ValueEditor,
  ValueView,
} from "./FeedbackValues";
import {
  copyrightOptions,
  kinds,
  resultLabel,
  sourceLabels,
  statusLabels,
  type Decision,
  type FeedbackRecord,
  type Field,
  type Values,
} from "./types";

type Props = {
  item: FeedbackRecord;
  editing: boolean;
  title: string;
  onEditing: (value: boolean) => void;
  onCancel: () => void;
  onBack: () => void;
  onReload: () => void;
  onSaved: (item: FeedbackRecord, action: string) => void;
};
export default function FeedbackReview({
  item,
  editing,
  title,
  onEditing,
  onCancel,
  onBack,
  onReload,
  onSaved,
}: Props) {
  const { catalog, actor, reload } = useConsole();
  const { message, modal } = App.useApp();
  const missing = item.kind === "MISSING_CARD";
  const done = item.result !== "PENDING";
  const canEdit = actor.role === "admin" || actor.role === "content_operator";
  const canPublish = actor.role === "admin";
  const [changes, setChanges] = useState<Values>(
    () =>
      item.draft || {
        ...item.submission.missing,
        entity_version_id: item.submission.missing?.source_version_id,
        image_url: item.submission.front?.image_url,
        back_image_url: item.submission.back?.image_url,
        front_source: {
          source_type: "USER_SUBMITTED",
          copyright_status: "UNKNOWN",
        },
        back_source: {
          source_type: "USER_SUBMITTED",
          copyright_status: "UNKNOWN",
        },
      },
  );
  const [decisions, setDecisions] = useState<Decision[]>(() =>
    item.review?.decisions?.length
      ? item.review.decisions
      : (item.submission.fields || []).map((f: Field) => ({
          key: f.key,
          decision: f.mode === "UNKNOWN" ? "MODIFY" : "ACCEPT",
          value: f.suggested,
          reason: "",
        })),
  );
  const [note, setNote] = useState(item.public_note || "");
  const [internal, setInternal] = useState(item.internal_note || "");
  const [match, setMatch] = useState<string>();
  const [copyright, setCopyright] = useState<string>();
  const [busy, setBusy] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [failure, setFailure] = useState<{
    message: string;
    conflict: boolean;
  }>();
  const request = useRef<{ signature: string; key: string } | undefined>(
    undefined,
  );
  const guard = useFormGuard(editing && !done, !!busy);
  const change = (key: string, value: any) => {
    guard.mark();
    setChanges((old) => ({ ...old, [key]: value }));
  };
  const changeMany = (values: Values) => {
    guard.mark();
    setChanges((old) => ({ ...old, ...values }));
  };
  const entities =
    changes.source_entity_type === "EVENT"
      ? catalog.events
      : changes.source_entity_type === "OTHER"
        ? catalog.others
        : catalog.albums;
  const fieldValue = (value: any, editor: React.ReactNode) =>
    editing ? (
      editor
    ) : (
      <div className="feedback-read-value">{displayValue(value)}</div>
    );
  const validate = (action: string) => {
    const invalid: Record<string, string> = {};
    if (
      ["publish", "reject", "match", "already_fixed"].includes(action) &&
      !note.trim()
    )
      invalid.public_note =
        "请填写面向用户的处理说明，未采纳时须说明具体原因。";
    if (action === "match" && !match) invalid.match = "请选择已发布的小卡。";
    if (action === "publish" && !missing)
      for (const d of decisions)
        if (d.decision === "REJECT" && !d.reason?.trim())
          invalid[d.key] = "请填写未采纳原因。";
    setErrors(invalid);
    if (Object.keys(invalid).length) {
      message.error("请完善标记的必填信息");
      requestAnimationFrame(() =>
        document
          .querySelector(".feedback-review .ant-form-item-has-error")
          ?.scrollIntoView({ block: "center", behavior: "smooth" }),
      );
      return false;
    }
    return true;
  };
  const act = useSingleSubmit(async (action: string) => {
    if (done || busy || !validate(action)) return;
    setBusy(action);
    setFailure(undefined);
    // Keep the existing API body and idempotency key unchanged on retries.
    const body = {
      action,
      revision: item.revision,
      public_note: note,
      internal_note: internal,
      card_id: match,
      changes,
      decisions,
      object_version: item.latest?.version,
      sources: Object.fromEntries(
        ["front_source", "back_source", "source_info"].map((key) => [
          key,
          { copyright_status: copyright },
        ]),
      ),
    };
    const signature = JSON.stringify(body);
    const key =
      request.current?.signature === signature
        ? request.current.key
        : crypto.randomUUID();
    request.current = { signature, key };
    try {
      const updated = await consoleApi<FeedbackRecord>(
        `/feedback/${item.id}/actions`,
        { method: "POST", body: JSON.stringify({ ...body, request_key: key }) },
      );
      guard.reset();
      message.success(
        action === "publish" ? "发布成功，处理结果已更新" : "已保存处理记录",
      );
      onSaved(updated, action);
      // A catalog refresh failure must not report a successful action as a failed save.
      void reload().catch(() =>
        message.warning("处理已保存，关联图鉴暂未刷新，请稍后刷新页面。"),
      );
    } catch (e) {
      setFailure({
        message: (e as Error).message,
        conflict: e instanceof ApiError && e.status === 409,
      });
      // Preserve edits and the original version on failure; never silently rebase or resubmit.
      requestAnimationFrame(() =>
        document
          .querySelector(".feedback-submit-error")
          ?.scrollIntoView({ block: "center", behavior: "smooth" }),
      );
    } finally {
      setBusy("");
    }
  });
  const confirm = (action: string) => {
    const labels: Record<string, string> = {
      publish: missing ? "发布小卡并收录" : "确认更新并发布",
      reject: "不予采纳",
      match: "关联并完成",
      already_fixed: "确认已由其他修改修正",
    };
    if (!validate(action)) return;
    modal.confirm({
      title: `${labels[action]}「${item.name}」？`,
      content:
        action === "publish"
          ? "本次将发布 1 条图鉴反馈的处理结果，并向用户反馈结果。发布仍需通过现有图鉴校验。"
          : action === "reject"
            ? "本次将结束 1 条反馈，公开处理说明会展示给用户；不会删除图鉴记录。"
            : "本次将完成 1 条反馈并通知用户，不计为本次图片或建议收录。",
      okText: labels[action],
      cancelText: "取消",
      okButtonProps: { danger: action === "reject" },
      onOk: () => act(action),
    });
  };
  const sourceName =
    entities.find((e) => e.id === changes.source_entity_id)?.name ||
    item.submission.missing?.missing_source_name;
  const relationRoute =
    item.entity_id &&
    (item.entity_type === "cards"
      ? `/catalog/cards/${item.entity_id}`
      : kinds.some(
            (k) =>
              k.value === item.entity_type &&
              !["versions", "companies"].includes(k.value),
          )
        ? `/catalog/${item.entity_type}/${item.entity_id}/detail`
        : "");
  const images = [
    ["正面图片", item.submission.front?.image_url],
    ["背面图片", item.submission.back?.image_url],
    ["扫描原图", item.submission.scan?.original_image_url],
    ["检测裁剪图", item.submission.scan?.crop_image_url],
  ].filter(([, url]) => url);
  const scan = item.submission.scan;
  const menuItems = [
    ...(item.status === "PENDING"
      ? [
          {
            key: "start",
            label: "开始处理",
            onClick: () => guard.close(() => void act("start")),
          },
        ]
      : []),
    ...(!missing && canPublish
      ? [
          {
            key: "already_fixed",
            label: "已由其他修改修正",
            onClick: () => confirm("already_fixed"),
          },
        ]
      : []),
    ...(canPublish
      ? [
          {
            key: "reject",
            label: "不予采纳",
            danger: true,
            onClick: () => confirm("reject"),
          },
        ]
      : []),
  ];
  return (
    <div
      className={`feedback-review${editing ? "" : " feedback-review--readonly"}`}
    >
      <div className="feedback-back">
        <Button
          type="text"
          icon={<ArrowLeftOutlined aria-hidden="true" />}
          onClick={onBack}
          disabled={!!busy}
        >
          返回{title}
        </Button>
      </div>
      <PageHeader
        title={`${title} · 处理详情`}
        actions={
          <>
            {relationRoute && <Link to={relationRoute}>查看关联图鉴</Link>}
            {!editing && !done && canEdit && (
              <Button type="primary" onClick={() => onEditing(true)}>
                编辑
              </Button>
            )}
          </>
        }
      />
      <section className="panel feedback-detail-panel">
        <Form
          className="feedback-review-form"
          layout="vertical"
          disabled={!!busy || done}
        >
          <ReviewSection title="基本信息">
            <div className="feedback-record-heading">
              <h3 title={item.name}>{item.name}</h3>
              <Tag
                color={item.status === "PROCESSING" ? "processing" : "default"}
              >
                {statusLabels[item.status] || item.status_label}
              </Tag>
              <Tag
                color={
                  item.result === "INCLUDED"
                    ? "success"
                    : item.result === "NOT_INCLUDED"
                      ? "error"
                      : "default"
                }
              >
                {resultLabel(item.result, item.kind)}
              </Tag>
            </div>
            <Descriptions
              column={{ xs: 1, md: 2, xl: 3 }}
              items={[
                {
                  key: "type",
                  label: "对象类型",
                  children:
                    kinds.find((k) => k.value === item.entity_type)?.label ||
                    "—",
                },
                {
                  key: "user",
                  label: "提交用户",
                  children: item.user.name || "—",
                },
                {
                  key: "created",
                  label: "提交时间（北京时间）",
                  children: formatTime(item.created_at),
                },
              ]}
            />
            {item.submission.object &&
              item.latest?.version !== item.submission.object.version && (
                <Alert
                  type="warning"
                  showIcon
                  message="平台数据已变化，请重新核对最新值。发布时将再次校验版本。"
                />
              )}
          </ReviewSection>
          <ReviewSection title="关联内容">
            {missing ? (
              <>
                <div className="feedback-images">
                  <Image.PreviewGroup>
                    {images.map(([label, url]) => (
                      <figure key={label}>
                        <figcaption>{label}</figcaption>
                        <Image src={url} alt={label} />
                      </figure>
                    ))}
                  </Image.PreviewGroup>
                </div>
                {!!scan && (
                  <details className="optional-fields feedback-scan">
                    <summary>查看扫描信息与候选结果</summary>
                    <Descriptions
                      column={2}
                      items={[
                        {
                          key: "session",
                          label: "扫描记录编号",
                          children: <RecordId value={scan.scan_session_id} />,
                        },
                        {
                          key: "detected",
                          label: "检测对象编号",
                          children: <RecordId value={scan.detected_card_id} />,
                        },
                        {
                          key: "region",
                          label: "裁剪区域",
                          span: 2,
                          children: scan.crop_region
                            ? [
                                ["x", "左侧"],
                                ["y", "上侧"],
                                ["width", "宽度"],
                                ["height", "高度"],
                              ]
                                .filter(
                                  ([k]) =>
                                    typeof scan.crop_region[k] === "number",
                                )
                                .map(
                                  ([k, label]) =>
                                    `${label} ${Math.round(scan.crop_region[k] * 100)}%`,
                                )
                                .join(" · ") || "已记录四角裁剪位置"
                            : "—",
                        },
                      ]}
                    />
                    <ul className="feedback-candidates">
                      {scan.candidates?.length ? (
                        scan.candidates.map((c: Values) => (
                          <li key={c.card_id}>
                            {catalog.cards.find((card) => card.id === c.card_id)
                              ?.title || <RecordId value={c.card_id} />}
                            <span>
                              相似度 {Math.round(c.similarity * 100)}%
                            </span>
                          </li>
                        ))
                      ) : (
                        <li className="feedback-muted">暂无候选记录</li>
                      )}
                    </ul>
                  </details>
                )}
                {editing && !done && (
                  <div className="feedback-match">
                    <ReviewField
                      id="feedback-match"
                      label="匹配已有小卡"
                      error={errors.match}
                      extra="核对为已有小卡时可关联完成；未采用本次图片，不计为图片贡献。"
                    >
                      <div className="feedback-match-controls">
                        <Select
                          id="feedback-match"
                          className="feedback-select"
                          showSearch
                          optionFilterProp="label"
                          placeholder="选择已发布的小卡"
                          value={match}
                          onChange={(v) => {
                            guard.mark();
                            setMatch(v);
                            setErrors((old) => ({ ...old, match: "" }));
                          }}
                          options={catalog.cards
                            .filter((c) => c.status === "PUBLISHED")
                            .map((c) => ({
                              value: c.id,
                              label: `${c.title} · ${c.id}`,
                            }))}
                        />
                        <Button
                          disabled={!canPublish || !!busy}
                          onClick={() => confirm("match")}
                        >
                          关联并完成
                        </Button>
                      </div>
                    </ReviewField>
                  </div>
                )}
              </>
            ) : (
              <Descriptions
                column={1}
                items={[
                  {
                    key: "target",
                    label: "反馈对象",
                    children: relationRoute ? (
                      <Link to={relationRoute}>{item.name}</Link>
                    ) : (
                      item.name
                    ),
                  },
                  {
                    key: "scope",
                    label: "问题字段",
                    children:
                      (item.submission.fields || [])
                        .map((f: Field) => f.label)
                        .join("、") || "—",
                  },
                ]}
              />
            )}
            {item.submission.notes ||
            item.submission.evidence?.length ||
            item.submission.links?.length ? (
              <div className="feedback-evidence">
                <p className="feedback-value">{item.submission.notes || "—"}</p>
                {!!item.submission.evidence?.length && (
                  <div className="feedback-evidence-images">
                    <Image.PreviewGroup>
                      {item.submission.evidence.map((e: Values) => (
                        <Image
                          key={e.id}
                          src={e.image_url}
                          alt="用户补充凭证"
                        />
                      ))}
                    </Image.PreviewGroup>
                  </div>
                )}
                {(item.submission.links || []).map((url: string) => (
                  <a
                    key={url}
                    href={url}
                    target="_blank"
                    rel="noreferrer"
                    className="feedback-reference-link"
                  >
                    {url}
                  </a>
                ))}
              </div>
            ) : (
              <details className="optional-fields">
                <summary>用户补充说明</summary>
                <p>—</p>
              </details>
            )}
          </ReviewSection>
          {missing ? (
            <ReviewSection title="小卡信息">
              {item.submission.missing?.missing_source_name && (
                <Alert
                  type="warning"
                  showIcon
                  message={`用户反馈缺失来源：${item.submission.missing.missing_source_name}`}
                  description="可以保存草稿；请补建正式来源并重新选择后再发布。"
                  action={
                    <Link
                      to={`/catalog/${changes.source_entity_type === "EVENT" ? "events" : changes.source_entity_type === "OTHER" ? "others" : "albums"}`}
                    >
                      管理来源
                    </Link>
                  }
                />
              )}
              <div className="form-grid">
                <ReviewField id="feedback-group" label="所属组合">
                  {fieldValue(
                    catalog.groups.find((g) => g.id === changes.group_id)?.name,
                    <Select
                      id="feedback-group"
                      value={changes.group_id}
                      showSearch
                      optionFilterProp="label"
                      options={catalog.groups.map((g) => ({
                        value: g.id,
                        label: g.name,
                      }))}
                      onChange={(v) =>
                        changeMany({
                          group_id: v,
                          idol_id: null,
                          source_entity_id: "",
                          entity_version_id: null,
                        })
                      }
                    />,
                  )}
                </ReviewField>
                <ReviewField id="feedback-group-card" label="团体小卡">
                  {fieldValue(
                    !!changes.is_group_pc,
                    <Checkbox
                      id="feedback-group-card"
                      checked={changes.is_group_pc}
                      onChange={(e) =>
                        changeMany({
                          is_group_pc: e.target.checked,
                          idol_id: null,
                        })
                      }
                    >
                      无需关联单个艺人
                    </Checkbox>,
                  )}
                </ReviewField>
                {!changes.is_group_pc && (
                  <ReviewField id="feedback-idol" label="所属艺人">
                    {fieldValue(
                      catalog.idols.find((i) => i.id === changes.idol_id)?.name,
                      <Select
                        id="feedback-idol"
                        value={changes.idol_id}
                        showSearch
                        optionFilterProp="label"
                        options={catalog.idols
                          .filter((i) => i.group_id === changes.group_id)
                          .map((i) => ({ value: i.id, label: i.name }))}
                        onChange={(v) => change("idol_id", v)}
                      />,
                    )}
                  </ReviewField>
                )}
                <ReviewField id="feedback-source-type" label="来源类型">
                  {fieldValue(
                    sourceLabels[changes.source_entity_type],
                    <Select
                      id="feedback-source-type"
                      value={changes.source_entity_type}
                      options={Object.entries(sourceLabels).map(
                        ([value, label]) => ({ value, label }),
                      )}
                      onChange={(v) =>
                        changeMany({
                          source_entity_type: v,
                          source_entity_id: "",
                          entity_version_id: null,
                        })
                      }
                    />,
                  )}
                </ReviewField>
                <ReviewField id="feedback-source" label="正式来源">
                  {fieldValue(
                    sourceName,
                    <Select
                      id="feedback-source"
                      value={changes.source_entity_id || undefined}
                      showSearch
                      optionFilterProp="label"
                      allowClear
                      options={entities
                        .filter((e) => e.status === "PUBLISHED")
                        .map((e) => ({ value: e.id, label: e.name }))}
                      onChange={(v) =>
                        changeMany({
                          source_entity_id: v || "",
                          entity_version_id: null,
                        })
                      }
                    />,
                  )}
                </ReviewField>
                <ReviewField id="feedback-version" label="来源版本">
                  {editing ? (
                    <ValueEditor
                      id="feedback-version"
                      field={
                        {
                          key: "entity_version_id",
                          label: "来源版本",
                          type: "reference",
                          reference: "versions",
                        } as Field
                      }
                      value={changes.entity_version_id}
                      onChange={(v) => change("entity_version_id", v)}
                    />
                  ) : (
                    <div className="feedback-read-value">
                      {changes.version ||
                        item.submission.missing?.source_version_name ||
                        (changes.entity_version_id ? (
                          <RecordId value={changes.entity_version_id} />
                        ) : (
                          "—"
                        ))}
                    </div>
                  )}
                </ReviewField>
                <ReviewField id="feedback-double-side" label="双面小卡">
                  {fieldValue(
                    !!changes.is_double_sided,
                    <Checkbox
                      id="feedback-double-side"
                      checked={changes.is_double_sided}
                      onChange={(e) =>
                        change("is_double_sided", e.target.checked)
                      }
                    >
                      发布时必须有背面图片
                    </Checkbox>,
                  )}
                </ReviewField>
                <ReviewField id="feedback-card-type" label="小卡类型">
                  {fieldValue(
                    changes.card_type,
                    <Input
                      id="feedback-card-type"
                      placeholder="选填"
                      value={changes.card_type}
                      onChange={(e) => change("card_type", e.target.value)}
                    />,
                  )}
                </ReviewField>
              </div>
              {item.entity_id && (
                <Link to={`/catalog/cards/${item.entity_id}`}>
                  打开完整小卡编辑
                </Link>
              )}
            </ReviewSection>
          ) : (
            <ReviewSection title="字段核对">
              <Table
                className="feedback-comparison"
                rowKey="key"
                pagination={false}
                scroll={{ x: 1000 }}
                dataSource={item.submission.fields || []}
                columns={[
                  { title: "字段", dataIndex: "label", width: 112 },
                  {
                    title: "提交时当前值",
                    width: 192,
                    ellipsis: false,
                    render: (_, f: Field) => (
                      <ValueView field={f} value={f.current} />
                    ),
                  },
                  {
                    title: "用户建议",
                    width: 192,
                    ellipsis: false,
                    render: (_, f: Field) => (
                      <>
                        <ValueView
                          field={f}
                          value={
                            f.mode === "SET"
                              ? f.suggested
                              : f.mode === "CLEAR"
                                ? "应为空 / 删除"
                                : "未知正确值"
                          }
                        />
                        {f.reason && (
                          <p className="feedback-muted">{f.reason}</p>
                        )}
                      </>
                    ),
                  },
                  {
                    title: "平台最新值",
                    width: 192,
                    ellipsis: false,
                    render: (_, f: Field) => (
                      <ValueView
                        field={f}
                        value={
                          item.latest?.fields?.find(
                            (v: Field) => v.key === f.key,
                          )?.current
                        }
                      />
                    ),
                  },
                  {
                    title: "处理结果 / 采用值",
                    width: 312,
                    ellipsis: false,
                    render: (_, f: Field) => {
                      const decision = decisions.find((v) => v.key === f.key);
                      const update = (value: Partial<Decision>) => {
                        guard.mark();
                        setDecisions((old) =>
                          old.map((v) =>
                            v.key === f.key ? { ...v, ...value } : v,
                          ),
                        );
                        setErrors((old) => ({ ...old, [f.key]: "" }));
                      };
                      return editing ? (
                        <div className="feedback-decision">
                          <Select
                            aria-label={`${f.label}处理结果`}
                            disabled={done}
                            value={decision?.decision}
                            onChange={(v) => update({ decision: v })}
                            options={[
                              { value: "ACCEPT", label: "采纳" },
                              {
                                value: "MODIFY",
                                label: "修改后采纳",
                                disabled: f.type === "image",
                              },
                              { value: "REJECT", label: "未采纳" },
                            ]}
                          />
                          {decision?.decision === "MODIFY" && (
                            <ValueEditor
                              field={f}
                              value={decision.value}
                              onChange={(v) => update({ value: v })}
                            />
                          )}
                          {decision?.decision === "ACCEPT" && (
                            <ValueView
                              field={f}
                              value={f.mode === "CLEAR" ? null : f.suggested}
                            />
                          )}
                          <ReviewField
                            id={`feedback-reason-${f.key}`}
                            label={
                              decision?.decision === "REJECT"
                                ? "未采纳原因"
                                : "字段处理说明"
                            }
                            required={decision?.decision === "REJECT"}
                            error={errors[f.key]}
                          >
                            <Input.TextArea
                              id={`feedback-reason-${f.key}`}
                              rows={2}
                              maxLength={2000}
                              value={decision?.reason}
                              onChange={(e) =>
                                update({ reason: e.target.value })
                              }
                            />
                          </ReviewField>
                        </div>
                      ) : (
                        <div className="feedback-decision">
                          <Tag>
                            {item.result === "NOT_INCLUDED"
                              ? "未采纳"
                              : !item.review?.decisions?.length
                                ? "待核对"
                                : (
                                    {
                                      ACCEPT: done ? "采纳" : "拟采纳",
                                      MODIFY: done
                                        ? "修改后采纳"
                                        : "拟修改后采纳",
                                      REJECT: "未采纳",
                                    } as Values
                                  )[decision?.decision || ""] || "待核对"}
                          </Tag>
                          {item.review?.decisions?.length > 0 &&
                            item.result !== "NOT_INCLUDED" &&
                            decision?.decision !== "REJECT" && (
                              <ValueView
                                field={f}
                                value={
                                  decision?.decision === "MODIFY"
                                    ? decision.value
                                    : f.mode === "CLEAR"
                                      ? null
                                      : f.suggested
                                }
                              />
                            )}
                          <span className="feedback-muted">
                            {decision?.reason || "—"}
                          </span>
                        </div>
                      );
                    },
                  },
                ]}
              />
            </ReviewSection>
          )}
          <ReviewSection title="发布信息">
            {missing ? (
              <div className="form-grid">
                {["front", "back"]
                  .filter((side) => side === "front" || changes.back_image_url)
                  .map((side) => (
                    <ReviewField
                      key={side}
                      id={`feedback-${side}-copyright`}
                      label={`${side === "front" ? "正面" : "背面"}图片使用状态`}
                    >
                      {fieldValue(
                        copyrightOptions.find(
                          (o) =>
                            o.value ===
                            (changes[`${side}_source`]?.copyright_status ||
                              "UNKNOWN"),
                        )?.label,
                        <Select
                          id={`feedback-${side}-copyright`}
                          value={
                            changes[`${side}_source`]?.copyright_status ||
                            "UNKNOWN"
                          }
                          options={copyrightOptions}
                          onChange={(v) =>
                            change(`${side}_source`, {
                              ...changes[`${side}_source`],
                              source_type: "USER_SUBMITTED",
                              copyright_status: v,
                            })
                          }
                        />,
                      )}
                    </ReviewField>
                  ))}
              </div>
            ) : (
              (item.submission.fields || []).some(
                (f: Field) => f.type === "image",
              ) && (
                <ReviewField id="feedback-copyright" label="采用图片的使用状态">
                  {fieldValue(
                    copyrightOptions.find((o) => o.value === copyright)?.label,
                    <Select
                      id="feedback-copyright"
                      placeholder="采用图片前请独立确认使用状态"
                      value={copyright}
                      onChange={(v) => {
                        guard.mark();
                        setCopyright(v);
                      }}
                      options={copyrightOptions.filter(
                        (o) => o.value !== "UNKNOWN",
                      )}
                    />,
                  )}
                </ReviewField>
              )
            )}
            {missing && (
              <p className="feedback-muted">
                图片来源保留“用户提交”，使用状态单独审核；保存草稿不等于已收录。
              </p>
            )}
            <ReviewField
              id="feedback-public-note"
              label="公开处理说明"
              required={editing}
              error={errors.public_note}
              extra={
                editing
                  ? "发布、关联完成或不予采纳时必填，处理结果会展示给用户。"
                  : undefined
              }
            >
              {fieldValue(
                note,
                <Input.TextArea
                  id="feedback-public-note"
                  rows={3}
                  maxLength={2000}
                  showCount
                  value={note}
                  onChange={(e) => {
                    guard.mark();
                    setNote(e.target.value);
                    setErrors((old) => ({ ...old, public_note: "" }));
                  }}
                />,
              )}
            </ReviewField>
            {!editing && !internal ? (
              <details className="optional-fields">
                <summary>内部备注（未填写）</summary>
                <p>—</p>
              </details>
            ) : (
              <ReviewField
                id="feedback-internal-note"
                label="内部备注"
                extra={editing ? "仅后台可见，不回传用户。" : undefined}
              >
                {fieldValue(
                  internal,
                  <Input.TextArea
                    id="feedback-internal-note"
                    rows={2}
                    maxLength={5000}
                    value={internal}
                    onChange={(e) => {
                      guard.mark();
                      setInternal(e.target.value);
                    }}
                  />,
                )}
              </ReviewField>
            )}
          </ReviewSection>
          <ReviewSection title="处理记录">
            {item.history.length ? (
              <Timeline
                items={item.history.map((h) => ({
                  children: (
                    <div>
                      <time
                        className="feedback-muted"
                        title="北京时间（UTC+08:00）"
                      >
                        {formatTime(h.at)}
                      </time>
                      <p className="feedback-value">{h.note || "—"}</p>
                    </div>
                  ),
                }))}
              />
            ) : (
              <EmptyState description="暂无公开处理记录。" />
            )}
          </ReviewSection>
          <ReviewSection title="系统信息">
            <Descriptions
              column={{ xs: 1, md: 2 }}
              items={[
                {
                  key: "id",
                  label: "反馈编号",
                  children: <RecordId value={item.id} />,
                },
                { key: "revision", label: "记录版本", children: item.revision },
                {
                  key: "user",
                  label: "提交用户编号",
                  children: <RecordId value={item.user.id} />,
                },
                {
                  key: "handler",
                  label: "处理人编号",
                  children: <RecordId value={item.handler_id} />,
                },
                {
                  key: "entity",
                  label: "关联图鉴编号",
                  children: <RecordId value={item.entity_id} />,
                },
                {
                  key: "updated",
                  label: "更新时间（北京时间）",
                  children: formatTime(item.updated_at),
                },
              ]}
            />
          </ReviewSection>
        </Form>
        {failure && (
          <Alert
            className="feedback-submit-error"
            type="error"
            showIcon
            message={failure.message}
            description={
              failure.conflict
                ? "已保留填写内容。请刷新详情并重新核对版本后再处理。"
                : "已保留填写内容，可修正后重试。"
            }
            action={
              failure.conflict && (
                <Button onClick={() => guard.close(onReload)}>刷新详情</Button>
              )
            }
          />
        )}
        <footer className="form-actions feedback-footer">
          {editing && !done ? (
            <>
              <Button disabled={!!busy} onClick={() => guard.close(onCancel)}>
                取消
              </Button>
              {!!menuItems.length && (
                <Dropdown
                  trigger={["click"]}
                  placement="topRight"
                  menu={{ items: menuItems }}
                  disabled={!!busy || !!failure?.conflict}
                >
                  <Button>
                    更多
                    <DownOutlined aria-hidden="true" />
                  </Button>
                </Dropdown>
              )}
              <Button
                loading={busy === (missing ? "draft" : "review")}
                disabled={!!busy || !!failure?.conflict}
                onClick={() => void act(missing ? "draft" : "review")}
              >
                {missing ? "保存草稿" : "保存审核意见"}
              </Button>
              {canPublish && (
                <Button
                  type="primary"
                  loading={busy === "publish"}
                  disabled={!!busy || !!failure?.conflict}
                  onClick={() => confirm("publish")}
                >
                  {missing ? "发布小卡并收录" : "确认更新并发布"}
                </Button>
              )}
            </>
          ) : (
            <Button onClick={onBack}>返回列表</Button>
          )}
        </footer>
      </section>
    </div>
  );
}

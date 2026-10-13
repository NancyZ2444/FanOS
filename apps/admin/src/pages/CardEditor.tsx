import TagSelect from "../components/TagSelect";
import { cloneElement, useEffect, useRef, useState } from "react";
import type { ReactElement } from "react";
import {
  useLocation,
  useNavigate,
  useParams,
  useSearchParams,
} from "react-router-dom";
import {
  Alert,
  App,
  Button,
  Descriptions,
  Form,
  Input,
  Modal,
  Select,
  Space,
  Steps,
  Switch,
  Tag,
  Timeline,
} from "antd";
import {
  ArrowLeftOutlined,
  ArrowRightOutlined,
  CheckCircleFilled,
  CheckCircleOutlined,
  ClockCircleOutlined,
  EyeOutlined,
  InfoCircleOutlined,
  SaveOutlined,
  SendOutlined,
} from "@ant-design/icons";
import { ApiError, consoleApi, send } from "../api/client";
import type { Card, FieldError, SourceInfo } from "../api/types";
import {
  emptyCard,
  emptySource,
  sourceKinds,
  sourceLabels,
} from "../api/types";
import { useConsole } from "../state";
import {
  AppPreview,
  CardArt,
  editable,
  EntityAvatar,
  ImageUpload,
  Panel,
  StatusTag,
} from "../components/shared";
import { fieldSteps, validateCard } from "./cardValidation";
import { groupMembers, memberLabel } from "./memberOptions";

const stepTitles = [
  "选择组合",
  "选择艺人",
  "选择来源",
  "基础信息",
  "正反面图片",
  "标签属性",
  "App 预览",
  "审核发布",
];
const copyrightOptions = [
  { value: "UNKNOWN", label: "待确认 UNKNOWN" },
  { value: "OFFICIAL_SOURCE", label: "官方来源 OFFICIAL_SOURCE" },
  { value: "AUTHORIZED", label: "已授权 AUTHORIZED" },
  { value: "FAIR_USE_REVIEW", label: "使用审核中" },
  { value: "RESTRICTED", label: "限制使用" },
  { value: "REMOVED", label: "已移除" },
];
const sourceOptions = [
  { value: "OFFICIAL", label: "官方来源 OFFICIAL" },
  { value: "SOCIAL_MEDIA", label: "社交媒体 SOCIAL_MEDIA" },
  { value: "ADMIN_UPLOAD", label: "运营上传 ADMIN_UPLOAD" },
  { value: "USER_SUBMITTED", label: "用户提交 USER_SUBMITTED" },
  { value: "PARTNER", label: "合作方 PARTNER" },
  { value: "PUBLIC_DATABASE", label: "公开数据库" },
  { value: "OTHER", label: "其他 OTHER" },
];

export default function CardEditor() {
  const { id } = useParams();
  const location = useLocation();
  const savedErrors: FieldError[] = location.state?.validationErrors || [];
  const [params] = useSearchParams();
  const isNew = id === "new";
  const { catalog, reload, actor, loading } = useConsole();
  const navigate = useNavigate();
  const { message, modal } = App.useApp();
  const initial = catalog.cards.find((c) => c.id === id);
  const [data, setData] = useState<Partial<Card>>({
    ...emptyCard(),
    ...initial,
    ...(isNew
      ? {
          group_id: params.get("group_id") || "",
          idol_id: params.get("idol_id"),
          source_entity_id: params.get("source_entity_id") || "",
          source_entity_type: params.get("source_entity_type") || "ALBUM",
          image_url: params.get("image_url") || undefined,
        }
      : {}),
  });
  const [step, setStep] = useState(
    savedErrors.length
      ? (fieldSteps[savedErrors[0].field.split(".")[0]] ?? 3)
      : isNew
        ? 0
        : 3,
  );
  const [errors, setErrors] = useState<FieldError[]>(savedErrors);
  const [busy, setBusy] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [preview, setPreview] = useState(false);
  const [history, setHistory] = useState<any[] | null>(null);
  const [createSource, setCreateSource] = useState(false);
  const [sourceOnline, setSourceOnline] = useState(false);
  const [sourceCity, setSourceCity] = useState("");
  const [sourcePlatform, setSourcePlatform] = useState("");
  const [sourceName, setSourceName] = useState("");
  const [versions, setVersions] = useState<any[]>([]);
  const [versionsLoading, setVersionsLoading] = useState(false);
  const [versionsError, setVersionsError] = useState("");
  useEffect(() => {
    let active = true;
    setVersions([]);
    setVersionsError("");
    setVersionsLoading(!!data.source_entity_id);
    if (data.source_entity_id) {
      consoleApi(`/records/versions?entity_id=${data.source_entity_id}`)
        .then((d) => {
          if (active)
            setVersions(
              d.items.filter(
                (v: any) =>
                  v.entity_type ===
                    sourceKinds[data.source_entity_type || "ALBUM"] &&
                  (v.status !== "ARCHIVED" || v.id === data.entity_version_id),
              ),
            );
        })
        .catch((e) => {
          if (active) setVersionsError(e.message);
        })
        .finally(() => {
          if (active) setVersionsLoading(false);
        });
    }
    return () => {
      active = false;
    };
  }, [data.source_entity_id, data.source_entity_type]);
  const [reason, setReason] = useState("");
  const [rejectOpen, setRejectOpen] = useState(false);
  const loaded = useRef(false);
  const canEdit =
    (isNew || (!!initial && editable(initial.status))) &&
    actor.role !== "operation_admin";
  useEffect(() => {
    if (initial && !loaded.current) {
      setData({ ...emptyCard(), ...initial });
      loaded.current = true;
    }
  }, [initial]);
  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (dirty) {
        e.preventDefault();
      }
    };
    window.addEventListener("beforeunload", handler);
    document.body.dataset.unsaved = dirty ? "true" : "false";
    return () => {
      window.removeEventListener("beforeunload", handler);
      delete document.body.dataset.unsaved;
    };
  }, [dirty]);
  useEffect(() => {
    if (params.get("tab") === "history" && initial) loadHistory();
  }, [initial?.id]);
  const update = (key: string, value: any) => {
    setData((d) => ({
      ...d,
      [key]: value,
      ...((key === "source_entity_id" && value !== d.source_entity_id) ||
      (key === "source_entity_type" && value !== d.source_entity_type)
        ? { entity_version_id: null, version: "" }
        : {}),
    }));
    setErrors((e) => e.filter((x) => x.field !== key));
    setDirty(true);
  };
  const setSource = (
    key: "source_info" | "front_source" | "back_source",
    field: keyof SourceInfo,
    value: string,
  ) => update(key, { ...(data[key] || emptySource()), [field]: value });
  const group = catalog.groups.find((g) => g.id === data.group_id);
  const idol = catalog.idols.find((i) => i.id === data.idol_id);
  const members = groupMembers(
    catalog.idols,
    data.group_id,
    initial?.group_id === data.group_id ? initial?.idol_id : undefined,
  );
  const source = catalog[sourceKinds[data.source_entity_type || "ALBUM"]].find(
    (s) => s.id === data.source_entity_id,
  );
  const display = {
    ...data,
    group_name: group?.name,
    idol_name: idol?.name,
    source: source?.name,
  };
  const field = (
    name: string,
    label: string,
    child: ReactElement<any>,
    required = false,
  ) => {
    const error = errors.find((e) => e.field === name);
    return (
      <Form.Item
        label={label}
        htmlFor={`field-${name}`}
        required={required}
        validateStatus={error ? "error" : undefined}
        help={error?.message}
      >
        {cloneElement(child, { id: `field-${name}` })}
      </Form.Item>
    );
  };
  const versionField = () => (
    <>
      {field(
        "entity_version_id",
        data.source_entity_type === "ALBUM" ? "专辑版本" : "来源版本",
        <Select
          showSearch
          optionFilterProp="label"
          allowClear
          loading={versionsLoading}
          disabled={
            !data.source_entity_id || versionsLoading || !!versionsError
          }
          value={data.entity_version_id || undefined}
          placeholder={
            data.source_entity_id
              ? "搜索并选择版本名称或编码"
              : "请先选择来源对象"
          }
          notFoundContent={
            versionsLoading
              ? "加载版本中…"
              : "暂无可选版本，请先在专辑详情维护版本"
          }
          options={versions.map((v) => ({
            value: v.id,
            label: `${v.data.name}${v.data.code ? ` · ${v.data.code}` : ""}`,
          }))}
          onChange={(v) => {
            update("entity_version_id", v || null);
            update(
              "version",
              versions.find((r) => r.id === v)?.data.name || "",
            );
          }}
        />,
      )}
      {versionsError && (
        <Alert type="error" message={`版本加载失败：${versionsError}`} />
      )}
      {data.source_entity_type === "ALBUM" &&
        data.source_entity_id &&
        !versionsLoading &&
        !versionsError &&
        versions.length === 0 && (
          <Alert
            type="info"
            message="该专辑暂无版本，请先在专辑详情的「版本」页新增，再回来选择。"
          />
        )}
    </>
  );
  const sourceFields = (
    key: "front_source" | "back_source" | "source_info",
    short = false,
  ) => (
    <div className="form-grid">
      {field(
        `${key}.source_type`,
        "来源类型",
        <Select
          value={data[key]?.source_type || "ADMIN_UPLOAD"}
          onChange={(v) => setSource(key, "source_type", v)}
          options={sourceOptions}
        />,
      )}
      {field(
        `${key}.copyright_status`,
        "版权状态",
        <Select
          value={data[key]?.copyright_status || "UNKNOWN"}
          onChange={(v) => setSource(key, "copyright_status", v)}
          options={copyrightOptions}
        />,
      )}
      <div className="span-two">
        {field(
          `${key}.source_url`,
          short ? "原始来源链接" : "来源链接 Source URL",
          <Input
            value={data[key]?.source_url}
            placeholder="https:// 官方页面或来源地址"
            onChange={(e) => setSource(key, "source_url", e.target.value)}
          />,
          key !== "source_info",
        )}
      </div>
      {!short && (
        <>
          <div>
            {field(
              `${key}.source_platform`,
              "来源平台",
              <Input
                value={data[key]?.source_platform}
                placeholder="如：Official Store / Instagram"
                onChange={(e) =>
                  setSource(key, "source_platform", e.target.value)
                }
              />,
            )}
          </div>
          <div>
            {field(
              `${key}.copyright_note`,
              "授权说明",
              <Input
                value={data[key]?.copyright_note}
                placeholder="授权凭证、许可范围或审核说明"
                onChange={(e) =>
                  setSource(key, "copyright_note", e.target.value)
                }
              />,
            )}
          </div>
        </>
      )}
    </div>
  );
  function showErrors(list: FieldError[]) {
    setErrors(list);
    if (list.length) {
      setStep(fieldSteps[list[0].field.split(".")[0]] ?? 3);
      message.error(list[0].message);
      setTimeout(
        () => document.getElementById(`field-${list[0].field}`)?.focus(),
        100,
      );
    }
  }
  async function save(submit = false) {
    const issues = validateCard(data, submit);
    if (issues.length) {
      showErrors(issues);
      return;
    }
    setBusy(true);
    let saved: Card | undefined;
    try {
      const result = await consoleApi<Card>(
        isNew ? "/cards" : `/cards/${id}`,
        send(
          { ...data, expected_updated_at: initial?.updated_at },
          isNew ? "POST" : "PUT",
        ),
      );
      saved = result;
      setDirty(false);
      document.body.dataset.unsaved = "false";
      if (submit)
        await consoleApi(
          `/cards/${result.id}/actions`,
          send({ action: "submit" }),
        );
      await reload();
      message.success(submit ? "已提交审核" : "草稿已保存");
      navigate(
        submit
          ? "/catalog/cards?status=PENDING"
          : `/catalog/cards/${result.id}`,
        { replace: true },
      );
      setData(result);
    } catch (e) {
      if (e instanceof ApiError && e.fields.length) showErrors(e.fields);
      else message.error((e as Error).message);
      // A failed submission must keep the draft that was already persisted.
      if (saved) {
        await reload().catch(() => {});
        if (isNew)
          navigate(`/catalog/cards/${saved.id}`, {
            replace: true,
            state: { validationErrors: e instanceof ApiError ? e.fields : [] },
          });
      }
    } finally {
      setBusy(false);
    }
  }
  async function action(action: string) {
    setBusy(true);
    try {
      await consoleApi(`/cards/${id}/actions`, send({ action, reason }));
      message.success(
        action === "publish" ? "小卡已发布，App 图鉴已更新" : "操作成功",
      );
      setRejectOpen(false);
      await reload();
      navigate("/catalog/cards");
    } catch (e) {
      if (e instanceof ApiError && e.fields.length) showErrors(e.fields);
      else message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function loadHistory() {
    try {
      const result = await consoleApi(`/cards/${id}/source-history`);
      setHistory(result.items);
    } catch (e) {
      message.error((e as Error).message);
    }
  }
  const leave = () =>
    dirty
      ? modal.confirm({
          title: "还有未保存的修改",
          content: "离开后本次修改将丢失。",
          okText: "离开",
          cancelText: "继续编辑",
          onOk: () => {
            setDirty(false);
            document.body.dataset.unsaved = "false";
            navigate("/catalog/cards");
          },
        })
      : navigate("/catalog/cards");
  if (!isNew && !initial && !loading)
    return (
      <Alert
        type="error"
        showIcon
        message="小卡不存在"
        action={
          <Button onClick={() => navigate("/catalog/cards")}>返回列表</Button>
        }
      />
    );
  return (
    <div className="editor-page">
      <div className="editor-heading">
        <div>
          <button className="back-link" onClick={leave}>
            <ArrowLeftOutlined aria-hidden="true" /> 返回小卡列表
          </button>
          <h1>
            {isNew ? "新建小卡" : canEdit ? "编辑小卡" : "小卡详情"}{" "}
            <StatusTag status={initial?.status || "DRAFT"} />
          </h1>
          <div className="breadcrumb-detail">
            {group?.name || "选择组合"} <span>›</span>{" "}
            {idol?.name || (data.is_group_pc ? "团体小卡" : "选择艺人")}{" "}
            <span>›</span> {data.title || "新建小卡"}
          </div>
        </div>
        <Space>
          {!isNew && (
            <Button onClick={() => navigate(`/catalog/cards/${id}/detail`)}>
              档案详情
            </Button>
          )}
          {!isNew && (
            <Button
              icon={<ClockCircleOutlined aria-hidden="true" />}
              onClick={loadHistory}
            >
              来源历史
            </Button>
          )}
          <Button
            icon={<EyeOutlined aria-hidden="true" />}
            onClick={() => setPreview(true)}
          >
            预览 App
          </Button>
        </Space>
      </div>
      <section className="panel wizard-steps">
        <Steps
          size="small"
          current={step}
          onChange={setStep}
          items={stepTitles.map((title, index) => ({
            title,
            description: `STEP 0${index + 1}`,
          }))}
        />
      </section>
      {initial?.review_note && (
        <Alert
          showIcon
          type="warning"
          message={`审核意见：${initial.review_note}`}
          style={{ marginBottom: 16 }}
        />
      )}
      {errors.length > 0 && (
        <Alert
          showIcon
          type="error"
          message={`还有 ${errors.length} 项信息需要完善`}
          description={errors.map((e) => e.message).join("；")}
          style={{ marginBottom: 16 }}
        />
      )}
      {location.state?.scanNotice && (
        <Alert
          type="info"
          showIcon
          message={location.state.scanNotice}
          style={{ marginBottom: 16 }}
        />
      )}
      {location.state?.scanCoverageNotice && (
        <Alert
          type="warning"
          showIcon
          message={location.state.scanCoverageNotice}
          style={{ marginBottom: 16 }}
        />
      )}
      <Form layout="vertical" disabled={!canEdit} requiredMark>
        {step === 0 && (
          <Panel
            title="01 / 选择所属组合"
            subtitle="从组合开始，建立完整的小卡档案。"
          >
            <div className="selection-grid">
              <Button
                onClick={() => {
                  update("group_id", "");
                  update("idol_id", null);
                  update("source_entity_id", "");
                  setStep(1);
                }}
              >
                独立 Solo / 无组合发行
              </Button>
              {catalog.groups
                .filter((g) => g.status !== "ARCHIVED")
                .map((g) => (
                  <button
                    type="button"
                    disabled={!canEdit}
                    className={`selection-card ${data.group_id === g.id ? "selected" : ""}`}
                    key={g.id}
                    onClick={() => {
                      setData((d) => ({
                        ...d,
                        group_id: g.id,
                        idol_id: null,
                        source_entity_id: "",
                        entity_version_id: null,
                        version: "",
                      }));
                      setDirty(true);
                    }}
                  >
                    <EntityAvatar entity={g} />
                    <h3>{g.name}</h3>
                    <p>{g.name_translated || g.company}</p>
                    <span>
                      {g.member_count} 位艺人 · {g.card_count} 张小卡
                    </span>
                    {data.group_id === g.id && (
                      <CheckCircleFilled
                        aria-hidden="true"
                        className="selected-tick"
                      />
                    )}
                  </button>
                ))}
            </div>
            {field(
              "group_id",
              "所属组合",
              <Select
                showSearch
                optionFilterProp="label"
                optionRender={(o) => (
                  <>
                    <EntityAvatar
                      entity={catalog.groups.find((g) => g.id === o.value)}
                      small
                    />
                    {o.label}
                  </>
                )}
                labelRender={(o) => (
                  <>
                    <EntityAvatar
                      entity={catalog.groups.find((g) => g.id === o.value)}
                      small
                    />
                    {o.label}
                  </>
                )}
                value={data.group_id || undefined}
                placeholder="请选择组合"
                onChange={(v) => {
                  update("group_id", v);
                  update("idol_id", null);
                  update("source_entity_id", "");
                }}
                options={catalog.groups
                  .filter((g) => g.status !== "ARCHIVED")
                  .map((g) => ({ value: g.id, label: g.name }))}
              />,
              true,
            )}
          </Panel>
        )}
        {step === 1 && (
          <Panel
            title="02 / 选择艺人"
            subtitle={`选择 ${group?.name || "组合"} 的艺人，也可以创建一张团体小卡。`}
          >
            <div className="inline-setting">
              <div>
                <b>这是一张团体小卡</b>
                <p>开启后无需绑定单个艺人。</p>
              </div>
              <Switch
                checked={data.is_group_pc}
                onChange={(v) => {
                  update("is_group_pc", v);
                  if (v) update("idol_id", null);
                }}
              />
            </div>
            <div className="selection-grid">
              {members.map((i) => (
                <button
                  type="button"
                  disabled={!canEdit || data.is_group_pc}
                  key={i.id}
                  className={`selection-card ${data.idol_id === i.id ? "selected" : ""}`}
                  onClick={() => update("idol_id", i.id)}
                >
                  <EntityAvatar entity={i} circle />
                  <h3>{memberLabel(i, data.group_id)}</h3>
                  <p>{i.name_translated || i.name_ko}</p>
                  <span>{group?.name}</span>
                  {data.idol_id === i.id && (
                    <CheckCircleFilled
                      aria-hidden="true"
                      className="selected-tick"
                    />
                  )}
                </button>
              ))}
            </div>
            {!!data.group_id && !members.length && (
              <Alert
                type="info"
                message="该组合尚无成员经历，请先在艺人管理中维护成员关系。"
              />
            )}
            {!data.group_id && (
              <Alert
                type="info"
                message="Solo 发行直接选择个人艺人；历史发行保留当时组合。"
              />
            )}
          </Panel>
        )}
        {step === 2 && (
          <Panel
            title="03 / 关联小卡来源"
            subtitle="每张小卡至少关联一个专辑、活动或 Other 来源。"
          >
            <div className="source-type-tabs">
              {Object.entries(sourceLabels).map(([v, l]) => (
                <button
                  type="button"
                  disabled={!canEdit}
                  key={v}
                  className={data.source_entity_type === v ? "selected" : ""}
                  onClick={() => {
                    update("source_entity_type", v);
                    update("source_entity_id", "");
                  }}
                >
                  {l}
                </button>
              ))}
            </div>
            {field(
              "source_entity_id",
              "来源对象",
              <Select
                size="large"
                showSearch
                optionFilterProp="label"
                value={data.source_entity_id || undefined}
                placeholder="搜索并选择所属来源"
                onChange={(v) => update("source_entity_id", v)}
                options={catalog[
                  sourceKinds[data.source_entity_type || "ALBUM"]
                ]
                  .filter(
                    (s) =>
                      s.status !== "ARCHIVED" &&
                      (data.source_entity_type === "OTHER" ||
                        (s.group_id === data.group_id && !!data.group_id) ||
                        s.artists?.some(
                          (a: { id: string }) =>
                            a.id === data.idol_id || a.id === data.group_id,
                        )),
                  )
                  .map((s) => ({
                    value: s.id,
                    label: `${s.name} · ${s.release_date || s.start_date || "未设置发行日期"}`,
                  }))}
              />,
              true,
            )}
            {versionField()}
            {source && (
              <div className="source-summary">
                <div className="album-icon">♫</div>
                <div>
                  <h3>{source.name}</h3>
                  <p>
                    {group?.name} · {source.release_date || source.start_date}
                  </p>
                  <span>{source.description}</span>
                </div>
                <StatusTag status={source.status} />
              </div>
            )}
            <div className="info-note">
              <InfoCircleOutlined aria-hidden="true" />{" "}
              <Button
                type="link"
                onClick={() => {
                  setSourceName("");
                  setCreateSource(true);
                }}
              >
                在此新建来源
              </Button>
            </div>
          </Panel>
        )}
        {step === 3 && (
          <>
            <div className="editor-columns">
              <Panel
                title="基本信息"
                subtitle="为小卡建立准确、清晰的身份信息。"
              >
                <div className="form-grid">
                  {field(
                    "group_id",
                    "组合 Group",
                    <Select
                      optionRender={(o) => (
                        <>
                          <EntityAvatar
                            entity={catalog.groups.find(
                              (g) => g.id === o.value,
                            )}
                            small
                          />
                          {o.label}
                        </>
                      )}
                      labelRender={(o) => (
                        <>
                          <EntityAvatar
                            entity={catalog.groups.find(
                              (g) => g.id === o.value,
                            )}
                            small
                          />
                          {o.label}
                        </>
                      )}
                      value={data.group_id || undefined}
                      placeholder="选择组合"
                      onChange={(v) => {
                        update("group_id", v);
                        update("idol_id", null);
                        update("source_entity_id", "");
                      }}
                      options={catalog.groups.map((g) => ({
                        value: g.id,
                        label: g.name,
                      }))}
                    />,
                    true,
                  )}
                  {field(
                    "card_type",
                    "卡片类型 Card Type",
                    <Select
                      value={data.card_type}
                      onChange={(v) => update("card_type", v)}
                      options={[
                        "Regular",
                        "POB",
                        "Album",
                        "Lucky Draw",
                        "Fansign",
                        "Limited",
                        "Other",
                      ].map((v) => ({ value: v, label: v }))}
                    />,
                  )}
                  {field(
                    "idol_id",
                    "艺人 Idol",
                    <Select
                      allowClear
                      optionRender={(o) => (
                        <>
                          <EntityAvatar
                            entity={catalog.idols.find((i) => i.id === o.value)}
                            circle
                            small
                          />
                          {o.label}
                        </>
                      )}
                      labelRender={(o) => (
                        <>
                          <EntityAvatar
                            entity={catalog.idols.find((i) => i.id === o.value)}
                            circle
                            small
                          />
                          {o.label}
                        </>
                      )}
                      value={data.idol_id || undefined}
                      placeholder={data.is_group_pc ? "团体小卡" : "选择艺人"}
                      onChange={(v) => update("idol_id", v || null)}
                      options={members.map((i) => ({
                        value: i.id,
                        label: memberLabel(i, data.group_id),
                      }))}
                    />,
                    !data.is_group_pc,
                  )}
                  {field(
                    "version",
                    "版本名称",
                    <Input
                      readOnly={data.source_entity_type === "ALBUM"}
                      value={data.version}
                      placeholder={
                        data.source_entity_type === "ALBUM"
                          ? "选择专辑版本后自动填写"
                          : "如：Ver. 1 / Moon Ver."
                      }
                      onChange={(e) => update("version", e.target.value)}
                    />,
                  )}
                  {field(
                    "release_date",
                    "发行日期 Release Date",
                    <Input
                      type="date"
                      value={data.release_date?.replaceAll(".", "-")}
                      onChange={(e) => update("release_date", e.target.value)}
                    />,
                  )}
                  {field(
                    "source_entity_type",
                    "来源类型",
                    <Select
                      value={data.source_entity_type}
                      onChange={(v) => {
                        update("source_entity_type", v);
                        update("source_entity_id", "");
                      }}
                      options={Object.entries(sourceLabels).map(
                        ([value, label]) => ({ value, label }),
                      )}
                    />,
                  )}
                  {field(
                    "tags",
                    "标签 Tags",
                    <TagSelect
                      entityType="CARD"
                      value={data.tags || []}
                      onChange={(v) => update("tags", v)}
                    />,
                  )}
                  {field(
                    "source_entity_id",
                    "来源对象",
                    <Select
                      showSearch
                      optionFilterProp="label"
                      value={data.source_entity_id || undefined}
                      placeholder="搜索并选择所属来源"
                      onChange={(v) => update("source_entity_id", v)}
                      options={catalog[
                        sourceKinds[data.source_entity_type || "ALBUM"]
                      ]
                        .filter(
                          (s) =>
                            data.source_entity_type === "OTHER" ||
                            (s.group_id === data.group_id && !!data.group_id) ||
                            s.artists?.some(
                              (a: { id: string }) =>
                                a.id === data.idol_id || a.id === data.group_id,
                            ),
                        )
                        .map((s) => ({ value: s.id, label: s.name }))}
                    />,
                    true,
                  )}
                  {field(
                    "card_number",
                    "卡片编号 Card Number",
                    <Input
                      value={data.card_number}
                      placeholder="保存后由系统自动生成唯一编号"
                      readOnly
                    />,
                  )}
                </div>
                {versionField()}
                <div className="info-note">
                  <InfoCircleOutlined aria-hidden="true" />{" "}
                  保存草稿后可继续补充，提交审核前需完善所有必填项。
                </div>
              </Panel>
              <Panel title="素材图片" subtitle="正面与背面分别管理。">
                <div className="image-pair">
                  {(["image_url", "back_image_url"] as const).map((key, i) => (
                    <div key={key}>
                      <div className="material-preview">
                        <CardArt card={display} back={i === 1} />
                      </div>
                      <span className="image-side-label">
                        {i ? "BACK IMAGE · 背面" : "FRONT IMAGE · 正面"}
                      </span>
                      <ImageUpload
                        cropCard
                        disabled={!canEdit}
                        value={data[key]}
                        label={i ? "背面图片" : "正面图片"}
                        onChange={(v) => update(key, v)}
                      />
                    </div>
                  ))}
                </div>
                <p className="subtle-note">
                  建议使用清晰原图，保留完整卡片边缘。
                </p>
              </Panel>
            </div>
            <Panel
              title="来源与版权"
              extra={<Tag color="purple">仅内部可见</Tag>}
            >
              {sourceFields("source_info")}
            </Panel>
          </>
        )}
        {step === 4 && (
          <div className="editor-columns equal">
            <Panel title="正面图片" subtitle="用于图鉴封面及 AI Scan 索引。">
              {field(
                "image_url",
                "Front Image",
                <ImageUpload
                  cropCard
                  disabled={!canEdit}
                  label="正面图片"
                  value={data.image_url}
                  onChange={(v) => update("image_url", v)}
                />,
                true,
              )}
              {sourceFields("front_source")}
            </Panel>
            <Panel title="背面图片" subtitle="双面卡需要同时上传背面。">
              {field(
                "back_image_url",
                "Back Image",
                <ImageUpload
                  cropCard
                  disabled={!canEdit}
                  label="背面图片"
                  value={data.back_image_url}
                  onChange={(v) => update("back_image_url", v)}
                />,
                data.is_double_sided,
              )}
              {sourceFields("back_source")}
            </Panel>
          </div>
        )}
        {step === 5 && (
          <Panel
            title="标签与特殊属性"
            subtitle="准确的属性让小卡更容易被发现。"
          >
            <div className="form-grid">
              {field(
                "tags",
                "标签",
                <TagSelect
                  entityType="CARD"
                  value={data.tags}
                  onChange={(v) => update("tags", v)}
                />,
              )}
              {field(
                "rarity",
                "稀有度",
                <Select
                  value={data.rarity}
                  onChange={(v) => update("rarity", v)}
                  options={["N", "R", "SR", "SSR", "UR"].map((value) => ({
                    value,
                    label: value,
                  }))}
                />,
              )}
              {field(
                "edition",
                "版次 Edition",
                <Input
                  value={data.edition}
                  onChange={(e) => update("edition", e.target.value)}
                  placeholder="如：First Press"
                />,
              )}
              {field(
                "region",
                "发行地区",
                <Input
                  value={data.region}
                  onChange={(e) => update("region", e.target.value)}
                  placeholder="如：Korea"
                />,
              )}
            </div>
            <div className="attribute-grid">
              {[
                ["is_group_pc", "团体小卡", "支持不指定单个艺人"],
                ["is_double_sided", "双面小卡", "需要上传正反面图片"],
                ["is_official", "官方小卡", "官方发行的收藏小卡"],
                ["is_limited", "限定发行", "限量或限定渠道"],
                ["is_random", "随机小卡", "随机抽取或封入"],
                ["has_ar", "支持 AR", "需关联 AR 资源"],
              ].map(([key, label, desc]) => (
                <div className="inline-setting" key={key}>
                  <div>
                    <b>{label}</b>
                    <p>{desc}</p>
                  </div>
                  <Switch
                    checked={data[key]}
                    onChange={(v) => update(key, v)}
                  />
                </div>
              ))}
            </div>
            {data.has_ar && (
              <div className="form-grid">
                {field(
                  "ar_type",
                  "AR 类型",
                  <Select
                    value={data.ar_type}
                    onChange={(v) => update("ar_type", v)}
                    options={[
                      "IMAGE",
                      "VIDEO",
                      "3D",
                      "ANIMATION",
                      "WEB_AR",
                    ].map((v) => ({ value: v, label: v }))}
                  />,
                )}
                {field(
                  "ar_resource",
                  "AR 资源地址",
                  <Input
                    value={data.ar_resource}
                    placeholder="https://"
                    onChange={(e) => update("ar_resource", e.target.value)}
                  />,
                  true,
                )}
                {field(
                  "ar_status",
                  "AR 状态",
                  <Select
                    value={data.ar_status || "Draft"}
                    onChange={(v) => update("ar_status", v)}
                    options={[
                      "Draft",
                      "Processing",
                      "Ready",
                      "Failed",
                      "Offline",
                    ].map((value) => ({ value, label: value }))}
                  />,
                )}
                {field(
                  "ar_preview",
                  "AR 预览图片",
                  <Input
                    value={data.ar_preview}
                    onChange={(e) => update("ar_preview", e.target.value)}
                    placeholder="https://"
                  />,
                )}
              </div>
            )}
          </Panel>
        )}
      </Form>
      {step === 6 && (
        <Panel
          title="App 展示预览"
          subtitle="正式发布前，检查用户看到的小卡详情。"
        >
          <AppPreview card={display} />
        </Panel>
      )}
      {step === 7 && (
        <Panel
          title="准备好与粉丝见面了吗？"
          subtitle="确认内容无误后提交审核，管理员审核通过后即可发布。"
        >
          <div className="publish-summary">
            <CardArt card={display} />
            <div>
              <h2>
                {data.title ||
                  [data.source, data.version, data.card_type]
                    .filter(Boolean)
                    .join(" · ") ||
                  "小卡"}
              </h2>
              <p>
                {group?.name} · {idol?.name || "团体小卡"}
              </p>
              <Descriptions
                column={2}
                items={[
                  {
                    key: "source",
                    label: "关联来源",
                    children: source?.name || "未设置",
                  },
                  {
                    key: "version",
                    label: "版本",
                    children: data.version || "—",
                  },
                  { key: "type", label: "类型", children: data.card_type },
                  {
                    key: "date",
                    label: "发行日期",
                    children: data.release_date || "—",
                  },
                ]}
              />
              <Space>
                {data.tags?.map((t) => (
                  <Tag key={t}>{t}</Tag>
                ))}
              </Space>
            </div>
          </div>
          <div className="checklist">
            {[
              {
                label: "基本信息与所属组合",
                ok: !!data.group_id || !!data.idol_id,
              },
              {
                label: "艺人归属或团体小卡属性",
                ok: !!data.idol_id || data.is_group_pc,
              },
              { label: "至少关联一个来源对象", ok: !!data.source_entity_id },
              {
                label: "正反面图片完整",
                ok:
                  !!data.image_url &&
                  (!data.is_double_sided || !!data.back_image_url),
              },
              {
                label: "图片来源和版权已确认",
                ok:
                  validateCard(data, true).filter((e) =>
                    e.field.includes("source."),
                  ).length === 0,
              },
            ].map((c) => (
              <div key={c.label} className={c.ok ? "complete" : ""}>
                <CheckCircleOutlined aria-hidden="true" />
                {c.label}
                <span>{c.ok ? "已完成" : "待完善"}</span>
              </div>
            ))}
          </div>
        </Panel>
      )}
      <div className="editor-footer">
        <Button onClick={leave}>取消</Button>
        <span className="save-state">
          {dirty ? "有未保存的修改" : isNew ? "新建小卡档案" : "所有修改已保存"}
        </span>
        <Space>
          {step > 0 && (
            <Button onClick={() => setStep(step - 1)}>上一步</Button>
          )}
          {step < 7 && (
            <Button onClick={() => setStep(step + 1)}>
              下一步 <ArrowRightOutlined aria-hidden="true" />
            </Button>
          )}
          {canEdit && (
            <>
              <Button
                icon={<SaveOutlined aria-hidden="true" />}
                loading={busy}
                onClick={() => save()}
              >
                保存草稿
              </Button>
              <Button
                type="primary"
                icon={<SendOutlined aria-hidden="true" />}
                loading={busy}
                onClick={() => save(true)}
              >
                提交审核
              </Button>
            </>
          )}
          {initial?.status === "PENDING" && actor.role === "admin" && (
            <>
              <Button onClick={() => setRejectOpen(true)}>驳回</Button>
              <Button
                type="primary"
                loading={busy}
                onClick={() =>
                  modal.confirm({
                    title: "确认审核通过并发布？",
                    content: "发布后小卡将出现在 App 图鉴中。",
                    onOk: () => action("publish"),
                    okText: "确认发布",
                    cancelText: "取消",
                  })
                }
              >
                审核通过并发布
              </Button>
            </>
          )}
          {initial?.status === "PUBLISHED" &&
            actor.role !== "operation_admin" && (
              <Button
                onClick={() =>
                  modal.confirm({
                    title: "确认下架此小卡？",
                    content: "下架后可以编辑，需重新提交审核后发布。",
                    onOk: () => action("offline"),
                    okText: "确认下架",
                    cancelText: "取消",
                  })
                }
              >
                下架并编辑
              </Button>
            )}
          <StatusTag status={initial?.status || "DRAFT"} />
        </Space>
      </div>
      {preview && (
        <AppPreview card={display} onClose={() => setPreview(false)} />
      )}
      <Modal
        open={history !== null}
        title="图片来源 · 版本历史"
        width={760}
        footer={<Button onClick={() => setHistory(null)}>关闭</Button>}
        onCancel={() => setHistory(null)}
      >
        {history?.length ? (
          <Timeline
            items={history.map((h) => ({
              color: "purple",
              children: (
                <div className="history-entry">
                  <Tag>
                    {h.side === "FRONT" ? "正面" : "背面"} V{h.version}
                  </Tag>
                  <span>{new Date(h.created_at).toLocaleString("zh-CN")}</span>
                  <p>
                    {h.data.source_type || "历史素材"} ·{" "}
                    {h.data.copyright_status || "UNKNOWN"}
                  </p>
                  <a href={h.data.source_url} target="_blank" rel="noreferrer">
                    {h.data.source_url || "历史记录未填写来源"}
                  </a>
                  <p>操作人：{h.operator_id}</p>
                </div>
              ),
            }))}
          />
        ) : (
          <Alert
            showIcon
            message="暂无图片更换记录"
            description="从后台上传或更换图片后，将自动记录每个版本的来源。"
          />
        )}
      </Modal>
      <Modal
        open={rejectOpen}
        title="驳回审核"
        onCancel={() => setRejectOpen(false)}
        onOk={() => {
          if (!reason.trim()) {
            message.warning("请填写驳回原因");
            return;
          }
          action("reject");
        }}
        confirmLoading={busy}
      >
        <Input.TextArea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={4}
          placeholder="请填写需要修正的内容，方便运营人员修改"
        />
      </Modal>
      <Modal
        title="新建发行来源"
        open={createSource}
        onCancel={() => setCreateSource(false)}
        onOk={async () => {
          if (!sourceName.trim()) {
            message.warning("请填写名称");
            return;
          }
          if (
            data.source_entity_type === "EVENT" &&
            !(sourceOnline ? sourcePlatform : sourceCity).trim()
          ) {
            message.warning(
              sourceOnline ? "请填写线上平台" : "请填写线下活动城市",
            );
            return;
          }
          try {
            const saved = await consoleApi(
              `/entities/${sourceKinds[data.source_entity_type || "ALBUM"]}`,
              send({
                name: sourceName,
                ...(data.source_entity_type === "EVENT"
                  ? {
                      is_online: sourceOnline,
                      city: sourceCity,
                      platform: sourcePlatform,
                    }
                  : {}),
                group_id: data.group_id || "",
                idol_id: data.idol_id,
                artists: [
                  ...(data.group_id
                    ? [{ type: "groups", id: data.group_id }]
                    : []),
                  ...(data.idol_id
                    ? [{ type: "idols", id: data.idol_id }]
                    : []),
                ],
              }),
            );
            await reload();
            update("source_entity_id", saved.id);
            setCreateSource(false);
            message.success("来源草稿已创建，请审核来源后发布小卡");
          } catch (e) {
            message.error((e as Error).message);
          }
        }}
      >
        <Input
          placeholder="发行来源名称"
          value={sourceName}
          onChange={(e) => setSourceName(e.target.value)}
        />
        {data.source_entity_type === "EVENT" && (
          <Space direction="vertical" style={{ width: "100%", marginTop: 12 }}>
            <Select
              aria-label="活动方式"
              value={sourceOnline}
              onChange={setSourceOnline}
              options={[
                { value: false, label: "线下活动" },
                { value: true, label: "线上活动" },
              ]}
            />
            {sourceOnline ? (
              <Input
                aria-label="平台"
                placeholder="平台（必填）"
                value={sourcePlatform}
                maxLength={120}
                onChange={(e) => setSourcePlatform(e.target.value)}
              />
            ) : (
              <Input
                aria-label="城市"
                placeholder="城市（必填）"
                value={sourceCity}
                onChange={(e) => setSourceCity(e.target.value)}
              />
            )}
          </Space>
        )}
      </Modal>
    </div>
  );
}

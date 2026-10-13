import { PageHeader } from "../components/admin";
import { Table, Modal, Form } from "../components/admin";
import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Alert,
  App,
  Button,
  Checkbox,
  Space,
  Select,
  Steps,
  Upload,
  Input,
} from "antd";
import {
  CheckCircleOutlined,
  CloudUploadOutlined,
  DownloadOutlined,
  FileExcelOutlined,
} from "@ant-design/icons";
import type { ImportTask, ImportKind } from "../api/types";
import { importLabels } from "../api/types";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import { Panel, StatusTag } from "../components/shared";

const importFieldNames: Record<string, string> = {
  group_id: "组合唯一 ID",
  group_code: "组合编码",
  group_name: "组合名称",
  group_name_en: "组合英文名称",
  group_name_ko: "组合韩文名称",
  group_name_translated: "组合翻译名称",
  group_company: "组合所属公司",
  group_description: "组合简介",
  group_debut_date: "组合出道日期",
  group_end_date: "组合解散日期",
  group_region: "组合地区",
  group_status: "组合状态",
  group_fandom_name: "组合粉丝名称",
  group_official_website: "组合官方网站",
  group_aliases: "组合别名",
  group_image_url: "组合图片",
  group_tags: "组合标签",
  group_source_type: "组合来源类型",
  group_source_url: "组合来源链接",
  group_copyright_status: "组合版权状态",
  group_copyright_note: "组合版权备注",
  idol_id: "艺人唯一 ID",
  idol_name: "艺人本名",
  stage_name: "艺名",
  idol_name_en: "艺人英文名称",
  idol_name_ko: "艺人韩文名称",
  idol_name_translated: "艺人翻译名称",
  idol_company: "艺人所属公司",
  idol_description: "艺人简介",
  birthday: "出生日期",
  idol_region: "国籍 / 地区",
  idol_gender: "性别 / 身份",
  idol_aliases: "艺人别名",
  idol_image_url: "艺人图片",
  idol_tags: "艺人标签",
  idol_source_type: "艺人来源类型",
  idol_source_url: "艺人来源链接",
  idol_copyright_status: "艺人版权状态",
  idol_copyright_note: "艺人版权备注",
  name: "名称",
  description: "简介",
  release_date: "发行 / 开始日期",
  image_url: "图片地址",
  tags: "标签",
};

const importFieldLabel = (field: string) =>
  importFieldNames[field] ? `${importFieldNames[field]}（${field}）` : field;

const combinedModeLabel = (row: ImportTask["rows"][number]) => {
  const labels: Record<string, string> = {
    updated_group_and_idol: "更新组合与艺人，并校验成员关系",
    updated_group_created_idol: "更新组合，新增艺人并建立关系",
    created_group_updated_idol: "新增组合，更新艺人并建立关系",
    created_group_and_idol: "新增组合、艺人及成员关系",
  };
  if (row.import_mode) return labels[row.import_mode] || row.import_mode;
  if (row.data.group_id && row.data.idol_id)
    return "将更新组合与艺人，并校验关系";
  if (row.data.group_id) return "将更新组合并新增艺人";
  if (row.data.idol_id) return "将新增组合并更新艺人";
  return "将新增组合、艺人及关系";
};

const combinedCompanyLabel = (row: ImportTask["rows"][number]) => {
  const modeLabel = (mode: unknown) =>
    mode === "reuse" ? "复用系统公司" : mode === "create" ? "自动创建公司" : "";
  const groupName = String(row.data.group_company_effective_name || "");
  const idolName = String(row.data.idol_company_effective_name || "");
  const labels = [];
  if (groupName)
    labels.push(
      `组合：${groupName}（${modeLabel(row.data.group_company_mode)}）`,
    );
  if (idolName)
    labels.push(
      `艺人：${idolName}（${row.data.idol_company_inherited ? "继承组合公司，" : ""}${modeLabel(row.data.idol_company_mode)}）`,
    );
  return labels.join("；") || "未填写公司";
};

export default function Imports() {
  const { catalog, reload, actor } = useConsole();
  const [params, setParams] = useSearchParams();
  const requestedKind = (
    Object.hasOwn(importLabels, params.get("kind") || "")
      ? params.get("kind")
      : "cards"
  ) as ImportKind;
  const kind = (
    requestedKind === "groups" || requestedKind === "idols"
      ? "groups_idols"
      : requestedKind
  ) as ImportKind;
  const label = importLabels[kind];
  const isCard = kind === "cards";
  const isAlbum = kind === "albums";
  const isCompany = kind === "companies";
  const isCombined = kind === "groups_idols";
  const artistNames = (data: Record<string, unknown>) => {
    if (!Array.isArray(data.artists)) return "—";
    return (
      data.artists
        .map((artist: { type: string; id: string }) => {
          const entities =
            artist.type === "groups"
              ? catalog.groups
              : artist.type === "idols"
                ? catalog.idols
                : [];
          return (
            entities.find((entity) => entity.id === artist.id)?.name ||
            artist.id
          );
        })
        .join(" / ") || "—"
    );
  };
  const { message, modal } = App.useApp();
  const [tasks, setTasks] = useState<ImportTask[]>([]);
  const [task, setTask] = useState<ImportTask>();
  const [busy, setBusy] = useState(false);
  const [skip, setSkip] = useState(false);
  const [error, setError] = useState("");
  const [editingRow, setEditingRow] = useState<number>();
  const [rawRow, setRawRow] = useState<Record<string, unknown>>({});
  const [skippedRows, setSkippedRows] = useState<number[]>([]);
  const [rowForm] = Form.useForm();
  const editRow = async (row: number) => {
    try {
      const source = (
        await consoleApi(`/records/import_input?entity_id=${task?.id}`)
      ).items[0];
      if (!source) throw new Error("历史任务不含原始预览，请重新上传");
      const data = source.data.rows[row - 2];
      setRawRow(data);
      setSkippedRows(source.data.skipped_rows || []);
      rowForm.setFieldsValue(data);
      setEditingRow(row);
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  const updateRow = async (skipRow = false) => {
    try {
      const data = await rowForm.validateFields();
      const result = await consoleApi(
        `/imports/${task?.id}/edit-preview`,
        send({
          edits: skipRow ? [] : [{ row: editingRow, data }],
          skip_rows: skipRow
            ? [...skippedRows, editingRow]
            : skippedRows.filter((r) => r !== editingRow),
        }),
      );
      setTask(result);
      setEditingRow(undefined);
      await load();
      message.success("已重新预检");
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  const load = async (signal?: AbortSignal) => {
    try {
      const data = await consoleApi(`/imports?kind=${kind}`, { signal });
      setTasks(data.items);
    } catch (e) {
      if (!signal?.aborted) setError((e as Error).message);
    }
  };
  useEffect(() => {
    const controller = new AbortController();
    setTask(undefined);
    setTasks([]);
    setSkip(false);
    setError("");
    load(controller.signal);
    return () => controller.abort();
  }, [kind]);
  const upload = async (file: File) => {
    setBusy(true);
    setError("");
    setSkip(false);
    const form = new FormData();
    form.append("file", file);
    form.append("kind", kind);
    try {
      const data = await consoleApi<ImportTask>("/imports", {
        method: "POST",
        body: form,
      });
      setTask(data);
      await load();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
    return false;
  };
  const confirm = () =>
    modal.confirm({
      title: isCombined
        ? `确认导入 ${task?.rows.length} 行组合与艺人并建立关联？`
        : isAlbum
          ? `确认导入 ${task?.rows.length} 行专辑与版本数据？`
          : `确认导入 ${task?.rows.length} 条${label}？`,
      content: isCompany
        ? "导入后建立公司档案，可立即在组合和艺人资料中选择；已有公司不会被覆盖。"
        : isCombined
          ? `${skip ? "将跳过错误行。" : ""}group_id / idol_id 为空时新增对应档案，填写系统唯一 ID 时更新对应档案；公司存在时自动复用，不存在时自动创建，并同时关联组合与艺人。`
          : isAlbum
            ? `${skip ? "将跳过错误行。" : ""}同名且参与艺人相同的不同版本归入同一专辑；可向已有专辑追加新版本，不覆盖专辑的其他字段。新增专辑保存为草稿。`
            : skip
              ? "将跳过错误行，其余内容保存为草稿，之后仍需审核发布。"
              : "导入后保存为草稿，之后仍需审核发布。",
      okText: "确认导入",
      cancelText: "返回检查",
      onOk: async () => {
        setBusy(true);
        try {
          const data = await consoleApi<ImportTask>(
            `/imports/${task?.id}/confirm`,
            send({ skip_invalid: skip }),
          );
          setTask(data);
          message.success(
            isCombined
              ? `成功导入 ${data.imported_count} 位艺人并建立组合关联`
              : isAlbum
                ? `成功处理 ${data.imported_count} 行专辑与版本数据`
                : `成功导入 ${data.imported_count} 条${label}`,
          );
          await Promise.all([load(), reload()]);
        } catch (e) {
          message.error((e as Error).message);
        } finally {
          setBusy(false);
        }
      },
    });
  const template = async (format: "csv" | "xlsx") => {
    try {
      const blob = await consoleApi<Blob>(
        `/imports/template?kind=${kind}&format=${format}`,
        { cache: "no-store" },
      );
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `FanOS-${label}导入模板.${format}`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  return (
    <>
      <PageHeader
        title={<>批量导入</>}
        description={<>批量建立图鉴档案，逐行检查，确认后写入草稿。</>}
        actions={
          <>
            <Space>
              <Button
                icon={<DownloadOutlined aria-hidden="true" />}
                onClick={() => template("xlsx")}
              >
                下载 Excel 模板
              </Button>
              <Button onClick={() => template("csv")}>下载 CSV 模板</Button>
            </Space>
          </>
        }
      />
      <Panel>
        <div className="import-type-control">
          <label htmlFor="import-kind">导入类型</label>
          <Select
            id="import-kind"
            value={kind}
            disabled={busy}
            style={{ width: 240 }}
            onChange={(value) => setParams({ kind: value })}
            options={Object.entries(importLabels)
              .filter(([value]) => !["groups", "idols"].includes(value))
              .map(([value, text]) => ({
                value,
                label: text,
              }))}
          />
          <span>
            当前模板：{label} ·{" "}
            {isCombined
              ? "一次导入组合资料、艺人资料及成员关系"
              : isAlbum
                ? "新增专辑或追加版本，保留原资料"
                : "仅新增，不覆盖已有记录"}
          </span>
        </div>
        <Alert
          type="info"
          showIcon
          message={
            isCompany
              ? "name 为必填公司名称，description 为可选描述。导入后可在组合与艺人资料中关联公司。"
              : isCombined
                ? "每行填写一位组合成员；group_* 与 idol_* 分别维护完整资料，系统同时建立成员及公司关系。"
                : isCard
                  ? "小卡需要已发布的组合、艺人与来源，并完整填写图片和版权字段。"
                  : isAlbum
                    ? "name 填专辑作品名；versions 填版本名，多个版本用 | 分隔。artist_names 可填写多个组合或个人艺人名称，用 | 分隔并精确匹配已有档案。"
                    : kind === "others"
                      ? "其他来源需填写 name，并至少关联一个组合或艺人；支持 group_id / group_name、idol_id / idol_name 或 artist_names。"
                      : "name 必填；group_id / group_name 二选一。名称需精确匹配已有组合，未发布组合也可用于建立草稿。"
          }
          description={
            isCompany
              ? "公司名称按大小写、全半角和多余空格归一后查重，含已归档公司。错误行可修正或明确跳过。"
              : isCombined
                ? "group_code、group_name、idol_name 必填。group_company / idol_company 会匹配公司管理；idol_company 为空时继承组合公司。"
                : isCard
                  ? "标签用 | 分隔，布尔值用 true / false；确认后仍需审核发布。"
                  : isAlbum
                    ? "专辑名不拼接版本名。同名且参与艺人集合相同的不同版本行归入同一专辑；新版本可追加到已有专辑，其他专辑字段保留原值。重复版本会报错。兼容 group_name / idol_name 和 artists JSON；release_date 使用 YYYY-MM-DD，tags 用 | 分隔。"
                    : kind === "others"
                      ? "artist_names 多个名称用 | 分隔并匹配已有档案；也可用 artists JSON 填写准确 ID。起止日期使用 YYYY-MM-DD，tags 用 | 分隔，image_url 可选。"
                      : "name_en / name_ko / name_translated 为多语言名称；release_date 使用 YYYY-MM-DD（艺人为生日、组合为出道日期），tags 用 | 分隔。可选封面 image_url 使用 HTTP(S) 地址；同组合同名记录视为重复。"
          }
        />
      </Panel>
      {error && (
        <Alert
          type="error"
          message={error}
          action={<Button onClick={() => load()}>重试</Button>}
        />
      )}
      <Panel>
        <Steps
          current={
            !task
              ? 0
              : task.status === "COMPLETED"
                ? 3
                : task.errors.length
                  ? 1
                  : 2
          }
          items={["上传文件", "检查数据", "确认导入", "完成"].map((title) => ({
            title,
          }))}
        />
      </Panel>
      <div className="import-columns">
        <Panel
          title={`上传${label}数据`}
          subtitle="支持 CSV / Excel，单次最多 2,000 行，文件不超过 5 MB。"
        >
          <Upload.Dragger
            accept=".csv,.xlsx"
            disabled={busy || actor.role === "operation_admin"}
            beforeUpload={upload}
            showUploadList={false}
          >
            <CloudUploadOutlined
              aria-hidden="true"
              className="big-upload-icon"
            />
            <h3>{busy ? "正在检查文件…" : "点击上传，或将文件拖拽到这里"}</h3>
            <p>使用标准模板，确保字段名称与数据格式一致</p>
            <Button loading={busy}>选择文件</Button>
          </Upload.Dragger>
          <div className="import-hints">
            <p>
              <CheckCircleOutlined aria-hidden="true" />{" "}
              {isCompany
                ? "公司无需填写组合或艺人，关联关系在资料页维护"
                : isCombined
                  ? "同一组合的每位艺人填写一行并复用 group_code；组合资料可只填一次"
                  : isCard
                    ? "group_id / idol_id / source_entity_id 请使用后台真实 ID"
                    : isAlbum
                      ? "artist_names 支持组合与个人合作，例如 Aria|Lin"
                      : "组合可使用 group_name 关联，或填写准确的 group_id"}
            </p>
            <p>
              <CheckCircleOutlined aria-hidden="true" />{" "}
              {isCompany
                ? "description 可填写公司描述"
                : isCombined
                  ? "stage_name 填艺名，idol_name 填本名；idol_* 资料按成员逐行填写"
                  : isAlbum
                    ? "versions 单独填写，例如 Photo Book Ver.|Digipack Ver."
                    : "标签以 | 分隔；布尔值使用 true / false"}
            </p>
            <p>
              <CheckCircleOutlined aria-hidden="true" />{" "}
              {isCompany
                ? "相同公司不会重复建立或覆盖原资料"
                : isCombined
                  ? "公司按大小写、全半角和空格归一匹配；不存在时创建，已有关系不重复建立"
                  : "图片先通过小卡编辑页上传，填写可访问的图片地址"}
            </p>
          </div>
        </Panel>
        <Panel title="导入检查规则">
          <div className="rule-list">
            {[
              [
                "01",
                "字段完整性",
                isCompany
                  ? "检查公司名称与描述长度"
                  : isCombined
                    ? "检查组合与艺人的名称、日期、图片、标签和来源资料"
                    : isCard
                      ? "检查名称、组合、图片与来源"
                      : isAlbum
                        ? "检查专辑作品名、版本名、参与艺人与日期格式"
                        : "检查名称、日期格式与所属组合",
              ],
              [
                "02",
                "关联关系",
                isCompany
                  ? "建立公司档案后，由组合或艺人资料选择关联"
                  : isCombined
                    ? "聚合同组资料后建立成员关系，并关联或自动创建公司"
                    : isCard
                      ? "检查艺人与来源是否属于所选组合"
                      : "组合与艺人必须存在，名称和 ID 不能互相冲突",
              ],
              [
                "03",
                isCard ? "图片与版权" : "重复检查",
                isCompany
                  ? "检查文件内及公司管理中同名记录，包含归档公司"
                  : isCombined
                    ? "拦截同组资料冲突、重复成员关系与同名歧义"
                    : isCard
                      ? "检查双面卡素材、来源链接与授权状态"
                      : isAlbum
                        ? "同名且参与艺人相同的不同版本归入同一专辑，重复版本报错"
                        : "检查文件内及数据库中同组合同名的记录",
              ],
              ["04", "逐行反馈", "错误不会静默跳过，确认后再写入"],
            ].map(([n, t, d]) => (
              <div key={n}>
                <span>{n}</span>
                <div>
                  <b>{t}</b>
                  <p>{d}</p>
                </div>
              </div>
            ))}
          </div>
        </Panel>
      </div>
      {task && (
        <Panel
          title="数据检查结果"
          extra={
            <Space>
              <FileExcelOutlined aria-hidden="true" />
              {task.filename}
              <StatusTag status={task.status} />
            </Space>
          }
        >
          <div className="import-result-summary">
            <div>
              <strong>{task.rows.length}</strong>
              <span>可导入行</span>
            </div>
            <div>
              <strong className="warning-text">
                {new Set(task.errors.map((e) => e.row)).size}
              </strong>
              <span>待修复行</span>
            </div>
            <div>
              <strong>{task.imported_count}</strong>
              <span>已导入</span>
            </div>
          </div>
          {task.rows.length > 0 && (
            <Table
              size="small"
              rowKey="row"
              dataSource={task.rows}
              pagination={{ defaultPageSize: 5 }}
              scroll={{ x: isAlbum || isCombined ? 950 : 650 }}
              columns={[
                { title: "表格行号", dataIndex: "row" },
                {
                  title: "修正 / 跳过",
                  render: (_, r) =>
                    task.status !== "COMPLETED" ? (
                      <Button type="link" onClick={() => editRow(r.row)}>
                        修正 / 跳过
                      </Button>
                    ) : (
                      "—"
                    ),
                },
                {
                  title: isCombined ? "组合名称" : `${label}名称`,
                  render: (_, r) =>
                    String(
                      (isCombined
                        ? r.data.group_name
                        : r.data.title ||
                          r.data.name ||
                          r.data.stage_name ||
                          r.data.idol_name) || "—",
                    ),
                },
                ...(isCombined
                  ? [
                      {
                        title: "艺人名称",
                        render: (_: unknown, r: ImportTask["rows"][number]) =>
                          String(r.data.stage_name || r.data.idol_name || "—"),
                      },
                      {
                        title: "关联方式",
                        render: (_: unknown, r: ImportTask["rows"][number]) =>
                          combinedModeLabel(r),
                      },
                      {
                        title: "公司处理",
                        render: (_: unknown, r: ImportTask["rows"][number]) =>
                          combinedCompanyLabel(r),
                      },
                    ]
                  : isAlbum
                    ? [
                        {
                          title: "参与艺人",
                          render: (_: unknown, r: ImportTask["rows"][number]) =>
                            artistNames(r.data),
                        },
                        {
                          title: "专辑版本",
                          render: (
                            _: unknown,
                            r: ImportTask["rows"][number],
                          ) =>
                            Array.isArray(r.data.versions)
                              ? r.data.versions.join(" / ") || "—"
                              : "—",
                        },
                      ]
                    : [
                        {
                          title: isCompany ? "公司描述" : "所属组合 ID",
                          render: (_: unknown, r: ImportTask["rows"][number]) =>
                            String(
                              (isCompany
                                ? r.data.description
                                : r.data.group_id) || "—",
                            ),
                        },
                      ]),
                {
                  title: isCombined ? "成员关系 ID" : "创建结果",
                  render: (_, r) =>
                    (isCombined ? r.membership_id : r.created_id) ||
                    "待确认导入",
                },
              ]}
            />
          )}
          {task.errors.length > 0 && (
            <Table
              size="small"
              rowKey={(r) => `${r.row}-${r.field}`}
              dataSource={task.errors}
              pagination={{ defaultPageSize: 5 }}
              columns={[
                {
                  title: "操作",
                  render: (_, r) => (
                    <Button type="link" onClick={() => editRow(r.row)}>
                      修正 / 跳过
                    </Button>
                  ),
                },
                {
                  title: "错误行号",
                  dataIndex: "row",
                  render: (v) => `Row ${v}`,
                },
                {
                  title: "字段名称",
                  dataIndex: "field",
                  render: (field: string) => importFieldLabel(field),
                },
                { title: "错误原因", dataIndex: "message" },
                { title: "修复建议", dataIndex: "suggestion" },
                {
                  title: "允许跳过",
                  dataIndex: "can_skip",
                  render: (v) => (v ? "可以" : "不可以"),
                },
              ]}
            />
          )}
          <div className="import-confirm">
            {task.status === "COMPLETED" ? (
              <Alert
                type="success"
                showIcon
                message={
                  isCombined
                    ? `已导入 ${task.imported_count} 位艺人，组合、艺人、成员及公司关系已同步建立`
                    : isAlbum
                      ? `已处理 ${task.imported_count} 行专辑与版本数据`
                      : `已导入 ${task.imported_count} 条${label}，状态为草稿`
                }
              />
            ) : (
              <>
                <Checkbox
                  checked={skip}
                  onChange={(e) => setSkip(e.target.checked)}
                  disabled={!task.errors.length}
                >
                  跳过错误行，仅导入通过校验的数据
                </Checkbox>
                <Button
                  type="primary"
                  loading={busy}
                  disabled={
                    actor.role === "operation_admin" ||
                    !task.rows.length ||
                    (!!task.errors.length && !skip)
                  }
                  onClick={confirm}
                >
                  确认导入 {task.rows.length} 行
                </Button>
              </>
            )}
          </div>
        </Panel>
      )}
      <Panel title="导入任务记录" className="table-panel">
        <Table
          rowKey="id"
          dataSource={tasks}
          pagination={{ defaultPageSize: 5 }}
          columns={[
            { title: "文件名", dataIndex: "filename" },
            {
              title: "类型",
              dataIndex: "kind",
              render: (value: ImportKind) => importLabels[value || "cards"],
            },
            {
              title: "状态",
              dataIndex: "status",
              render: (v) => <StatusTag status={v} />,
            },
            { title: "导入数量", dataIndex: "imported_count" },
            {
              title: "创建时间",
              dataIndex: "created_at",
              render: (v) => new Date(v).toLocaleString("zh-CN"),
            },
            {
              title: "操作",
              key: "action",
              render: (_, r) => (
                <button
                  className="text-button"
                  disabled={busy}
                  onClick={() => {
                    setTask(r);
                    setSkip(false);
                  }}
                >
                  查看结果
                </button>
              ),
            },
          ]}
        />
      </Panel>
      <Modal
        title={`修正第 ${editingRow} 行`}
        open={editingRow !== undefined}
        onCancel={() => setEditingRow(undefined)}
        footer={
          <Space>
            <Button onClick={() => setEditingRow(undefined)}>取消</Button>
            <Button onClick={() => updateRow(true)}>跳过此行</Button>
            <Button type="primary" onClick={() => updateRow()}>
              保存并重新预检
            </Button>
          </Space>
        }
      >
        <Form form={rowForm} layout="vertical">
          {Object.keys(rawRow).map((field) => (
            <Form.Item key={field} name={field} label={importFieldLabel(field)}>
              <Input />
            </Form.Item>
          ))}
        </Form>
      </Modal>
    </>
  );
}

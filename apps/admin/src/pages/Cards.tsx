import { canPermission } from "../api/permissions";
import { TableToolbar } from "../components/admin";
import { RecordId, RowActions } from "../components/admin";
import { FilterBar } from "../components/admin";
import { PageHeader } from "../components/admin";
import { Table } from "../components/admin";
import { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  App,
  Button,
  Checkbox,
  Dropdown,
  Input,
  Select,
  Space,
  Tabs,
  Tooltip,
} from "antd";
import {
  AppstoreOutlined,
  BarsOutlined,
  DownOutlined,
  ExportOutlined,
  ImportOutlined,
  PlusOutlined,
  ReloadOutlined,
  SearchOutlined,
} from "@ant-design/icons";
import type { ColumnsType } from "antd/es/table";
import type { Card } from "../api/types";
import { statusLabels } from "../api/types";
import { consoleApi, send } from "../api/client";
import {
  AppPreview,
  CardArt,
  editable,
  EmptyState,
  StatusTag,
} from "../components/shared";
import { useConsole } from "../state";
import { confirmCatalogDeletion } from "../components/catalogDeletion";
import CardRecognition from "../components/CardRecognition";
import { useCardsDuplicateApproval } from "../components/CardDuplicateWarning";

export default function Cards() {
  const { catalog, reload, loading, actor } = useConsole();
  const { message, modal } = App.useApp();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const [q, setQ] = useState(params.get("q") || "");
  const [group, setGroup] = useState<string>();
  const [idol, setIdol] = useState<string>();
  const [type, setType] = useState<string>();
  const [source, setSource] = useState<string>();
  const [version, setVersion] = useState<string>();
  const [year, setYear] = useState<string>();
  const [status, setStatus] = useState(params.get("status") || "ALL");
  const [missing, setMissing] = useState(params.get("missing") === "true");
  const [selected, setSelected] = useState<React.Key[]>([]);
  const [view, setView] = useState("table");
  const [preview, setPreview] = useState<Card>();
  const [busy, setBusy] = useState(false);
  const approveDuplicates = useCardsDuplicateApproval();
  const canEdit = canPermission(actor, "catalog.edit");
  const canPublish = canPermission(actor, "catalog.publish");
  const canDelete = canPermission(actor, "catalog.delete");
  const canSelect = canEdit || canPublish || canDelete;
  const filtered = useMemo(
    () =>
      catalog.cards.filter(
        (c) =>
          (!params.get("created_date") ||
            new Date(c.created_at).toLocaleDateString("sv-SE", {
              timeZone: "Asia/Shanghai",
            }) === params.get("created_date")) &&
          (status === "ALL" ? c.status !== "ARCHIVED" : c.status === status) &&
          (!group || c.group_id === group) &&
          (!idol || c.idol_id === idol) &&
          (!type || c.card_type === type) &&
          (!source ||
            `${c.source_entity_type}:${c.source_entity_id}` === source) &&
          (!version || c.version === version) &&
          (!year || c.release_date.slice(0, 4) === year) &&
          (!missing || !c.image_url) &&
          (!q ||
            [
              c.id,
              c.title,
              c.idol_name,
              c.group_name,
              c.source,
              c.card_number,
              ...(c.tags || []),
            ].some((v) => v?.toLowerCase().includes(q.toLowerCase()))),
      ),
    [
      catalog,
      status,
      group,
      idol,
      type,
      missing,
      q,
      source,
      version,
      year,
      params.toString(),
    ],
  );
  const act = async (action: string, card?: Card) => {
    if (busy) return;
    const ids = [...selected];
    const targets = card
      ? [card]
      : catalog.cards.filter((c) => ids.includes(c.id));
    setBusy(true);
    try {
      if (action === "publish" && !(await approveDuplicates(targets))) return;
      await consoleApi(
        card
          ? action === "delete"
            ? `/cards/${card.id}`
            : `/cards/${card.id}/actions`
          : "/cards/batch",
        card && action === "delete"
          ? { method: "DELETE" }
          : send(card ? { action } : { action, ids }),
      );
      message.success("操作成功");
      setSelected([]);
      await reload();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const confirm = (action: string, card?: Card) =>
    modal.confirm({
      title:
        action === "delete"
          ? `确认永久删除${card ? "小卡" : `${selected.length} 条小卡`}？`
          : action === "publish"
            ? "确认发布小卡？"
            : action === "offline"
              ? "确认下架小卡？"
              : "确认归档小卡？",
      content:
        action === "delete"
          ? "删除不可恢复。未发布草稿可删除；曾发布后下架及归档记录须解除全部上下游关联。下游引用始终阻止删除；任一不满足条件整批不删除。"
          : action === "publish"
            ? "发布前将检查关联来源及图片完整性。通过后，小卡会在 App 图鉴中公开展示。"
            : action === "offline"
              ? "下架后 App 图鉴和每日翻卡不再展示，已有收藏与图片来源历史将保留。"
              : "归档后从默认列表移除，可在已归档中恢复。",
      okText:
        action === "delete"
          ? "删除"
          : action === "publish"
            ? "发布"
            : action === "offline"
              ? "下架"
              : "归档",
      okButtonProps: { danger: action === "delete" },
      cancelText: "取消",
      onOk: () => act(action, card),
    });
  const exportCsv = () => {
    const rows = [
      ["Card ID", "名称", "组合", "艺人", "来源", "状态"],
      ...filtered.map((c) => [
        c.id,
        c.title,
        c.group_name,
        c.idol_name,
        c.source,
        statusLabels[c.status],
      ]),
    ];
    const text =
      "\uFEFF" +
      rows
        .map((r) =>
          r
            .map(
              (v) =>
                '"' +
                String(v || "")
                  .replace(/^[=+@-]/, "'$&")
                  .replaceAll('"', '""') +
                '"',
            )
            .join(","),
        )
        .join("\n");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(
      new Blob([text], { type: "text/csv;charset=utf-8" }),
    );
    a.download = "FanOS-小卡列表.csv";
    a.click();
    URL.revokeObjectURL(a.href);
  };
  const resetFilters = () => {
    setQ("");
    setGroup(undefined);
    setIdol(undefined);
    setType(undefined);
    setMissing(false);
    setSource(undefined);
    setVersion(undefined);
    setYear(undefined);
    setStatus("ALL");
    setSelected([]);
    setParams({});
  };
  const rowActions = (c: Card) => (
    <RowActions
      onView={() => navigate(`/catalog/cards/${c.id}/detail`)}
      onEdit={canEdit ? () => navigate(`/catalog/cards/${c.id}`) : undefined}
      editDisabled={!editable(c.status)}
      editHint={
        !editable(c.status)
          ? "已发布内容需先下架，待审核内容需先驳回"
          : undefined
      }
      items={[
        { key: "preview", label: "预览 App" },
        ...(canPublish && c.status === "PENDING"
          ? [{ key: "publish", label: "审核通过并发布" }]
          : []),
        ...(canPublish && c.status === "PUBLISHED"
          ? [{ key: "offline", label: "下架小卡" }]
          : []),
        ...(canEdit && editable(c.status)
          ? [{ key: "submit", label: "提交审核" }]
          : []),
        ...(canPublish && editable(c.status)
          ? [{ key: "archive", label: "归档" }]
          : []),
        ...(canPublish && c.status === "ARCHIVED"
          ? [{ key: "restore", label: "恢复为草稿" }]
          : []),
        ...(canDelete && ["DRAFT", "OFFLINE", "ARCHIVED"].includes(c.status)
          ? [{ key: "delete", label: "删除", danger: true }]
          : []),
        { key: "history", label: "查看图片来源" },
      ].map((item) => ({
        ...item,
        onClick: () => {
          const key = item.key;
          return key === "preview"
            ? setPreview(c)
            : key === "history"
              ? navigate(`/catalog/cards/${c.id}?tab=history`)
              : ["publish", "offline", "archive", "delete"].includes(key)
                ? key === "delete"
                  ? void confirmCatalogDeletion(
                      "cards",
                      c.id,
                      c.title,
                      modal,
                      message,
                      reload,
                    )
                  : confirm(key, c)
                : act(key, c);
        },
      }))}
    />
  );
  const columns: ColumnsType<Card> = [
    {
      title: "小卡信息",
      key: "card",
      width: 300,
      render: (_, c) => (
        <div className="table-card-info">
          <CardArt card={c} small />
          <div>
            <button
              className="table-title"
              title={c.title}
              onClick={() => navigate(`/catalog/cards/${c.id}`)}
            >
              {c.title}
            </button>
            <RecordId value={c.card_number || c.id} />
            <span className="tag-subtle">
              {c.card_type} <i /> {c.version || "未设置版本"}
            </span>
          </div>
        </div>
      ),
    },
    {
      title: "组合 / 艺人",
      key: "artist",
      width: 150,
      render: (_, c) => (
        <div className="cell-stack">
          <b>{c.group_name}</b>
          <span>{c.idol_name || "团体小卡"}</span>
        </div>
      ),
    },
    {
      title: "所属来源",
      dataIndex: "source",
      width: 155,
      render: (v) => (
        <span>{v || <span className="text-placeholder">待关联来源</span>}</span>
      ),
    },
    {
      title: "状态",
      dataIndex: "status",
      width: 115,
      render: (v) => <StatusTag status={v} />,
    },
    {
      title: "更新时间",
      dataIndex: "updated_at",
      width: 155,
      render: (v, c) => (
        <div className="cell-stack">
          <span className="time-text">
            {new Date(
              v + "Z".repeat(!/[Z+]/.test(v) ? 1 : 0),
            ).toLocaleDateString("zh-CN")}
          </span>
          <span>{c.operator || "系统初始化"}</span>
        </div>
      ),
    },
    {
      title: "操作",
      key: "action",
      width: 192,
      fixed: "right",
      render: (_, c) => rowActions(c),
    },
  ];
  const statusTabs = [
    "ALL",
    "DRAFT",
    "PENDING",
    "PUBLISHED",
    "OFFLINE",
    "ARCHIVED",
  ].map((s) => ({
    key: s,
    label: (
      <span>
        {s === "ALL" ? "全部小卡" : statusLabels[s]}
        <em className="tab-count">
          {
            catalog.cards.filter((c) =>
              s === "ALL" ? c.status !== "ARCHIVED" : c.status === s,
            ).length
          }
        </em>
      </span>
    ),
  }));
  return (
    <>
      <PageHeader title={<>小卡管理</>} />
      <FilterBar
        onReset={resetFilters}
        advanced={
          <>
            {" "}
            <Select
              allowClear
              placeholder="全部卡片类型"
              value={type}
              onChange={setType}
              options={[...new Set(catalog.cards.map((c) => c.card_type))].map(
                (v) => ({ value: v, label: v }),
              )}
            />{" "}
            <Select
              allowClear
              placeholder="发行来源"
              value={source}
              onChange={setSource}
              style={{ minWidth: 200 }}
              options={[
                ...new Map(
                  catalog.cards
                    .filter((c) => c.source_entity_id)
                    .map((c) => [
                      `${c.source_entity_type}:${c.source_entity_id}`,
                      {
                        value: `${c.source_entity_type}:${c.source_entity_id}`,
                        label: `${c.source_entity_type} · ${c.source}`,
                      },
                    ]),
                ).values(),
              ]}
            />
            <Select
              allowClear
              placeholder="版本"
              value={version}
              onChange={setVersion}
              style={{ minWidth: 150 }}
              options={[
                ...new Set(catalog.cards.map((c) => c.version).filter(Boolean)),
              ].map((value) => ({ value, label: value }))}
            />
            <Select
              allowClear
              placeholder="发行年份"
              value={year}
              onChange={setYear}
              style={{ minWidth: 120 }}
              options={[
                ...new Set(
                  catalog.cards
                    .map((c) => c.release_date.slice(0, 4))
                    .filter(Boolean),
                ),
              ]
                .sort()
                .reverse()
                .map((value) => ({ value, label: value }))}
            />
            <Checkbox
              checked={missing}
              onChange={(e) => setMissing(e.target.checked)}
            >
              仅显示缺少正面图片的小卡
            </Checkbox>
          </>
        }
      >
        <Input
          allowClear
          prefix={<SearchOutlined aria-hidden="true" />}
          placeholder="搜索小卡名称、ID、艺人…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          style={{ width: 280 }}
        />
        <Select
          allowClear
          placeholder="全部组合"
          value={group}
          onChange={(v) => {
            setGroup(v);
            setIdol(undefined);
          }}
          options={catalog.groups.map((g) => ({
            value: g.id,
            label: g.name,
          }))}
        />
        <Select
          allowClear
          placeholder="全部艺人"
          value={idol}
          onChange={setIdol}
          options={catalog.idols
            .filter(
              (i) =>
                !group ||
                i.group_id === group ||
                catalog.cards.some(
                  (c) => c.group_id === group && c.idol_id === i.id,
                ),
            )
            .map((i) => ({ value: i.id, label: i.name }))}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar
          actions={
            <>
              {" "}
              <Space size={8}>
                <div className="view-switch">
                  <button
                    aria-label="列表视图"
                    className={view === "table" ? "active" : ""}
                    onClick={() => setView("table")}
                  >
                    <BarsOutlined aria-hidden="true" />
                  </button>
                  <button
                    aria-label="网格视图"
                    className={view === "grid" ? "active" : ""}
                    onClick={() => setView("grid")}
                  >
                    <AppstoreOutlined aria-hidden="true" />
                  </button>
                </div>
                <Tooltip title="刷新数据">
                  <Button
                    aria-label="刷新数据"
                    icon={<ReloadOutlined aria-hidden="true" />}
                    onClick={() => reload()}
                    loading={loading}
                  />
                </Tooltip>
                <Dropdown
                  menu={{
                    items: [
                      {
                        key: "export",
                        label: "导出当前筛选",
                        icon: <ExportOutlined aria-hidden="true" />,
                      },
                      ...(canEdit
                        ? [
                            {
                              key: "import",
                              label: "批量导入",
                              icon: <ImportOutlined aria-hidden="true" />,
                            },
                          ]
                        : []),
                    ],
                    onClick: ({ key }) =>
                      key === "export"
                        ? exportCsv()
                        : navigate("/catalog/import"),
                  }}
                >
                  <Button>
                    更多 <DownOutlined aria-hidden="true" />
                  </Button>
                </Dropdown>
                {canEdit && <CardRecognition />}
                {canEdit && (
                  <Button
                    type="primary"
                    icon={<PlusOutlined aria-hidden="true" />}
                    onClick={() => navigate("/catalog/cards/new")}
                  >
                    新增小卡
                  </Button>
                )}
              </Space>{" "}
            </>
          }
        >
          <Tabs
            activeKey={status}
            items={statusTabs}
            onChange={(s) => {
              setStatus(s);
              setParams(s === "ALL" ? {} : { status: s });
              setSelected([]);
            }}
          />
        </TableToolbar>
        {canSelect && selected.length > 0 && (
          <div className="table-meta">
            <span>
              {selected.length
                ? `已选 ${selected.length} 项`
                : `共 ${filtered.length} 张小卡`}
              {selected.length > 0 && (
                <Space className="batch-actions">
                  {canEdit && (
                    <Button
                      size="small"
                      onClick={() => act("submit")}
                      loading={busy}
                    >
                      提交审核
                    </Button>
                  )}
                  {canPublish && (
                    <Button size="small" onClick={() => confirm("publish")}>
                      批量发布
                    </Button>
                  )}
                  {canPublish && (
                    <>
                      <Button size="small" onClick={() => confirm("offline")}>
                        批量下架
                      </Button>
                      <Button size="small" onClick={() => confirm("archive")}>
                        批量归档
                      </Button>
                    </>
                  )}
                  {canDelete && (
                    <Button
                      danger
                      size="small"
                      disabled={
                        !selected.length ||
                        selected.some(
                          (id) =>
                            !filtered.some(
                              (c) =>
                                c.id === id &&
                                ["DRAFT", "OFFLINE", "ARCHIVED"].includes(
                                  c.status,
                                ),
                            ),
                        )
                      }
                      onClick={() => confirm("delete")}
                    >
                      批量永久删除
                    </Button>
                  )}
                  <button
                    className="text-button"
                    onClick={() => setSelected([])}
                  >
                    取消选择
                  </button>
                </Space>
              )}
            </span>
          </div>
        )}
        {view === "table" ? (
          <Table
            rowKey="id"
            columns={columns}
            dataSource={filtered}
            filtered={
              !!(
                q ||
                group ||
                idol ||
                type ||
                missing ||
                source ||
                version ||
                year ||
                status !== "ALL"
              )
            }
            onReset={resetFilters}
            onCreate={
              canEdit ? () => navigate("/catalog/cards/new") : undefined
            }
            createLabel="新增小卡"
            loading={loading}
            rowSelection={
              canSelect
                ? {
                    selectedRowKeys: selected,
                    onChange: setSelected,
                    preserveSelectedRowKeys: false,
                  }
                : undefined
            }
            scroll={{ x: 1060 }}
            pagination={{
              defaultPageSize: 10,
              showSizeChanger: true,
              pageSizeOptions: [10, 20, 50],
              showTotal: (t) => `共 ${t} 条记录`,
            }}
            locale={{
              emptyText: (
                <EmptyState
                  filtered={
                    !!(
                      q ||
                      group ||
                      idol ||
                      type ||
                      missing ||
                      source ||
                      version ||
                      year ||
                      status !== "ALL"
                    )
                  }
                  onReset={resetFilters}
                  onCreate={
                    canEdit ? () => navigate("/catalog/cards/new") : undefined
                  }
                  createLabel="新增小卡"
                />
              ),
            }}
          />
        ) : (
          <div className="card-grid">
            {filtered.length ? (
              filtered.map((c) => (
                <article key={c.id} className="grid-card">
                  <button className="grid-art" onClick={() => setPreview(c)}>
                    <CardArt card={c} />
                    <div className="grid-card-status">
                      <StatusTag status={c.status} />
                    </div>
                  </button>
                  <h3>{c.title}</h3>
                  <p>
                    {c.group_name} · {c.idol_name || "团卡"}
                  </p>
                  <div className="grid-card-footer">{rowActions(c)}</div>
                </article>
              ))
            ) : (
              <EmptyState
                filtered={
                  !!(
                    q ||
                    group ||
                    idol ||
                    type ||
                    missing ||
                    source ||
                    version ||
                    year ||
                    status !== "ALL"
                  )
                }
                onReset={resetFilters}
                onCreate={
                  canEdit ? () => navigate("/catalog/cards/new") : undefined
                }
                createLabel="新增小卡"
              />
            )}
          </div>
        )}
      </section>
      {preview && (
        <AppPreview card={preview} onClose={() => setPreview(undefined)} />
      )}
    </>
  );
}

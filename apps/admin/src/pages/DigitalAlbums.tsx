import { canPermission } from "../api/permissions";
import dayjs from "dayjs";
import { useEffect, useRef, useState } from "react";
import { Alert, Button, DatePicker, Input, Select, Tabs, Tag } from "antd";
import { consoleApi } from "../api/client";
import {
  PageHeader,
  FilterBar,
  Table,
  TableToolbar,
  RecordId,
  RowActions,
  useFormGuard,
} from "../components/admin";
import { displayValue } from "../design/format";
import { useConsole } from "../state";
import AlbumDetail from "./digital-albums/AlbumDetail";
import AlbumSettings from "./digital-albums/AlbumSettings";
import {
  moderationLabels,
  moderationStatus,
  type Album,
  type Limits,
  type Resource,
} from "./digital-albums/types";
import "./digital-albums/digital-albums.css";

type Settings = { limits: Limits; resources: Resource[] };
export default function DigitalAlbums() {
  const { actor } = useConsole();
  const isAdmin = canPermission(actor, "albums.manage"),
    canModerate = canPermission(actor, "reports.manage");
  const [activeTab, setActiveTab] = useState("works");
  const [settingsKey, setSettingsKey] = useState(0);
  const [rows, setRows] = useState<Album[]>([]),
    [settings, setSettings] = useState<Settings>();
  const [loading, setLoading] = useState(false),
    [error, setError] = useState("");
  const [q, setQ] = useState(""),
    [user, setUser] = useState(""),
    [status, setStatus] = useState("");
  const [moderation, setModeration] = useState("");
  const [workMode, setWorkMode] = useState("");
  const [dates, setDates] = useState<[string, string]>(["", ""]);
  const [selected, setSelected] = useState<{
    id: string;
    action?: "RESTRICTED" | "OFFLINE" | "NORMAL";
  }>();
  const version = useRef(0),
    guard = useFormGuard(true);
  const params = () =>
    new URLSearchParams({
      q,
      user_id: user,
      status,
      work_mode: workMode,
      created_from: dates[0],
      created_to: dates[1],
    });
  const refresh = async () => {
    const request = ++version.current;
    setLoading(true);
    setError("");
    try {
      const [list, configuration] = await Promise.all([
        consoleApi<{ items: Album[] }>(`/digital-albums?${params()}`),
        consoleApi<Settings>("/album-settings"),
      ]);
      if (request === version.current) {
        setRows(list.items);
        setSettings(configuration);
      }
    } catch (e) {
      if (request === version.current) setError((e as Error).message);
    } finally {
      if (request === version.current) setLoading(false);
    }
  };
  useEffect(() => {
    void consoleApi<Settings>("/album-settings")
      .then(setSettings)
      .catch((e) => setError(e.message));
  }, []);
  useEffect(() => {
    const request = ++version.current,
      controller = new AbortController();
    setLoading(true);
    setError("");
    const timer = window.setTimeout(() => {
      const query = new URLSearchParams({
        q,
        user_id: user,
        status,
        work_mode: workMode,
        created_from: dates[0],
        created_to: dates[1],
      });
      consoleApi<{ items: Album[] }>(`/digital-albums?${query}`, {
        signal: controller.signal,
      })
        .then((result) => {
          if (request === version.current) setRows(result.items);
        })
        .catch((e) => {
          if (!controller.signal.aborted && request === version.current)
            setError(e.message);
        })
        .finally(() => {
          if (request === version.current) setLoading(false);
        });
    }, 300);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [q, user, status, dates, workMode]);
  const reset = () => {
    setQ("");
    setUser("");
    setStatus("");
    setWorkMode("");
    setModeration("");
    setDates(["", ""]);
  };
  const filteredRows = rows.filter(
    (r) =>
      !moderation ||
      (moderation === "PENDING"
        ? ["PENDING", "PENDING_REVIEW"].includes(r.review_status || "")
        : moderationStatus(r) === moderation),
  );
  return (
    <div className="digital-albums-page">
      <PageHeader
        title="数字相册"
        actions={
          <Button
            loading={loading}
            onClick={() =>
              guard.close(() => {
                setSettingsKey((key) => key + 1);
                void refresh();
              })
            }
          >
            刷新
          </Button>
        }
      />
      {error && (
        <Alert
          type="error"
          showIcon
          message={error}
          action={<Button onClick={() => void refresh()}>重试</Button>}
        />
      )}
      <Tabs
        destroyOnHidden
        activeKey={activeTab}
        onChange={(tab) => guard.close(() => setActiveTab(tab))}
        items={[
          {
            key: "works",
            label: "作品管理",
            children: (
              <>
                <FilterBar
                  onReset={reset}
                  advanced={
                    <>
                      <Input
                        aria-label="作者用户编号"
                        value={user}
                        placeholder="用户 ID"
                        onChange={(e) => setUser(e.target.value)}
                      />
                      <DatePicker.RangePicker
                        aria-label="作品创建日期"
                        value={
                          dates[0] && dates[1]
                            ? [dayjs(dates[0]), dayjs(dates[1])]
                            : null
                        }
                        onChange={(_, values) =>
                          setDates([
                            values[0] ? `${values[0]}T00:00:00+08:00` : "",
                            values[1] ? `${values[1]}T23:59:59+08:00` : "",
                          ])
                        }
                      />
                    </>
                  }
                >
                  <Select
                    aria-label="作品类型筛选"
                    value={workMode}
                    onChange={setWorkMode}
                    options={[
                      { value: "", label: "全部作品类型" },
                      { value: "BOOK", label: "相册作品" },
                      { value: "CARDS", label: "卡片作品" },
                      { value: "REVIEW", label: "迁移待确认" },
                    ]}
                  />
                  <Input
                    value={q}
                    aria-label="相册名称"
                    placeholder="相册名称"
                    onChange={(e) => setQ(e.target.value)}
                  />
                  <Select
                    aria-label="作品状态筛选"
                    value={status}
                    onChange={setStatus}
                    options={[
                      { value: "", label: "全部发布状态" },
                      { value: "DRAFT", label: "草稿" },
                      { value: "PUBLISHED", label: "已发布" },
                      { value: "DELETED", label: "已删除" },
                    ]}
                  />
                  <Select
                    aria-label="处理状态筛选"
                    value={moderation}
                    onChange={setModeration}
                    options={[
                      { value: "", label: "全部处理状态" },
                      { value: "NORMAL", label: "正常" },
                      { value: "RESTRICTED", label: "限制公开" },
                      { value: "OFFLINE", label: "已下架" },
                      { value: "PENDING", label: "待复核" },
                    ]}
                  />
                </FilterBar>
                <TableToolbar>
                  <span className="album-muted">
                    查看作品、关联举报和处理记录
                  </span>
                </TableToolbar>
                <Table<Album>
                  rowKey="id"
                  dataSource={filteredRows}
                  loading={loading}
                  filtered={!!(q || user || status || moderation || dates[0])}
                  onReset={reset}
                  pagination={{ defaultPageSize: 20, showSizeChanger: true }}
                  scroll={{ x: 920 }}
                  columns={[
                    {
                      title: "作品类型",
                      width: 100,
                      render: (_, row) =>
                        row.work_mode === "CARDS"
                          ? "卡片作品"
                          : row.work_mode === "REVIEW"
                            ? "待确认"
                            : "相册作品",
                    },
                    {
                      title: "相册 / 作者",
                      width: 280,
                      render: (_, row) => (
                        <>
                          <button
                            className="table-title"
                            title={row.name}
                            onClick={() => setSelected({ id: row.id })}
                          >
                            {row.name}
                          </button>
                          <div className="album-muted">{row.author_name}</div>
                          <RecordId value={row.user_id} />
                        </>
                      ),
                    },
                    {
                      title: "内容数量",
                      width: 112,
                      render: (_, row) =>
                        row.work_mode === "CARDS"
                          ? `${row.card_count} 张`
                          : `${row.page_count} 页 / ${row.card_count} 张`,
                    },
                    {
                      title: "可见范围",
                      width: 96,
                      render: (_, row) => (
                        <Tag>
                          {row.visibility === "PUBLIC" ? "公开" : "私密"}
                        </Tag>
                      ),
                    },
                    {
                      title: "作品状态",
                      width: 128,
                      render: (_, row) => (
                        <>
                          {displayValue(row.status)}
                          <div>
                            {row.is_moderated && (
                              <Tag color="red">
                                {moderationLabels[moderationStatus(row)]}
                              </Tag>
                            )}
                            {["PENDING", "PENDING_REVIEW"].includes(
                              row.review_status || "",
                            ) && <Tag color="gold">待复核</Tag>}
                            {row.publication_blocked && (
                              <Tag color="blue">待作者重新发布</Tag>
                            )}
                          </div>
                        </>
                      ),
                    },
                    { title: "举报", dataIndex: "report_count", width: 64 },
                    { title: "更新日期", dataIndex: "updated_at", width: 152 },
                    {
                      title: "操作",
                      width: 128,
                      render: (_, row) => (
                        <RowActions
                          onView={() => setSelected({ id: row.id })}
                          items={
                            canModerate && row.status !== "DELETED"
                              ? [
                                  {
                                    key: "restrict",
                                    label: "限制公开",
                                    disabled:
                                      moderationStatus(row) === "RESTRICTED",
                                    onClick: () =>
                                      setSelected({
                                        id: row.id,
                                        action: "RESTRICTED",
                                      }),
                                  },
                                  {
                                    key: "offline",
                                    label: "下架",
                                    danger: true,
                                    disabled:
                                      moderationStatus(row) === "OFFLINE",
                                    onClick: () =>
                                      setSelected({
                                        id: row.id,
                                        action: "OFFLINE",
                                      }),
                                  },
                                  ...(row.is_moderated
                                    ? [
                                        {
                                          key: "restore",
                                          label: "恢复作品",
                                          onClick: () =>
                                            setSelected({ id: row.id }),
                                        },
                                      ]
                                    : []),
                                ]
                              : []
                          }
                        />
                      ),
                    },
                  ]}
                />
                <p className="album-list-hint">
                  默认预览已发布内容；未发布作品显示编辑内容。最多查询最近 200
                  本，可按名称、用户和日期缩小范围。时间为北京时间。
                </p>
              </>
            ),
          },
          {
            key: "limits",
            label: "额度与会员",
            children: (
              <AlbumSettings
                key={settingsKey}
                limits={settings?.limits}
                canEdit={isAdmin}
                onSaved={refresh}
                onDirty={guard.mark}
                onReset={guard.reset}
              />
            ),
          },
        ]}
      />
      <AlbumDetail
        albumId={selected?.id}
        initialAction={selected?.action}
        resources={settings?.resources || []}
        canModerate={canModerate}
        onClose={() => setSelected(undefined)}
        onChanged={refresh}
      />
    </div>
  );
}

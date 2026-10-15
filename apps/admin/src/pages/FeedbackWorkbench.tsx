import { useCallback, useEffect, useRef, useState } from "react";
import {
  Alert,
  Button,
  DatePicker,
  Input,
  Select,
  Skeleton,
  Tabs,
  Tag,
} from "antd";
import { ReloadOutlined } from "@ant-design/icons";
import dayjs from "dayjs";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import { consoleApi } from "../api/client";
import {
  CursorPagination,
  EmptyState,
  FilterBar,
  PageHeader,
  RecordId,
  RowActions,
  Table,
  TableToolbar,
} from "../components/admin";
import { useConsole } from "../state";
import FeedbackReview from "./feedback/FeedbackReview";
import {
  kinds,
  resultLabel,
  sourceLabels,
  statusLabels,
  type FeedbackKind,
  type FeedbackRecord,
  type Values,
} from "./feedback/types";
import "./feedback/feedback.css";

export default function FeedbackWorkbench({ kind }: { kind: FeedbackKind }) {
  const { actor } = useConsole();
  const { feedbackId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const [rows, setRows] = useState<FeedbackRecord[]>([]);
  const [filters, setFilters] = useState<Values>({});
  const [offset, setOffset] = useState(0);
  const [next, setNext] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [item, setItem] = useState<FeedbackRecord>();
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState("");
  const [editing, setEditing] = useState(false);
  const [resetKey, setResetKey] = useState(0);
  const [detailReload, setDetailReload] = useState(0);
  const listRequest = useRef(0);
  const title = kind === "MISSING_CARD" ? "小卡缺失收录" : "图鉴问题纠错";
  const base =
    kind === "MISSING_CARD" ? "/catalog/missing-cards" : "/catalog/corrections";
  const canEdit = actor.role === "admin" || actor.role === "content_operator";
  const load = useCallback(async () => {
    const ticket = ++listRequest.current;
    setLoading(true);
    try {
      const query = new URLSearchParams({
        kind,
        offset: String(offset),
        limit: "20",
        ...Object.fromEntries(Object.entries(filters).filter(([, v]) => v)),
      });
      const data = await consoleApi(`/feedback?${query}`);
      if (ticket !== listRequest.current) return;
      if (!data.items.length && offset > 0) {
        setOffset(Math.max(0, offset - 20));
        return;
      }
      setRows(data.items);
      setNext(data.next_offset);
      setError("");
    } catch (e) {
      if (ticket === listRequest.current) setError((e as Error).message);
    } finally {
      if (ticket === listRequest.current) setLoading(false);
    }
  }, [kind, offset, filters]);
  useEffect(() => {
    if (!feedbackId) void load();
    return () => {
      listRequest.current++;
    };
  }, [load, feedbackId]);
  useEffect(() => {
    if (!feedbackId) {
      setItem(undefined);
      return;
    }
    let active = true;
    setDetailLoading(true);
    setDetailError("");
    setItem(undefined);
    void consoleApi<FeedbackRecord>(`/feedback/${feedbackId}`)
      .then((data) => {
        if (!active) return;
        if (data.kind !== kind) {
          setDetailError("该反馈不属于当前模块，请返回对应列表查看。");
          return;
        }
        setItem(data);
        setEditing(
          !!location.state?.edit && data.result === "PENDING" && canEdit,
        );
      })
      .catch((e) => {
        if (active) setDetailError(e.message);
      })
      .finally(() => {
        if (active) setDetailLoading(false);
      });
    return () => {
      active = false;
    };
  }, [feedbackId, kind, detailReload]);
  const reset = () => {
    setFilters({});
    setOffset(0);
  };
  const filter = (key: string, value: any) => {
    setOffset(0);
    setFilters((old) => ({ ...old, [key]: value }));
  };
  const filtered = Object.values(filters).some(Boolean);
  const open = (id: string, edit = false) =>
    navigate(`${base}/${id}`, { state: { edit } });
  if (feedbackId) {
    if (detailLoading)
      return (
        <>
          <PageHeader title={`${title} · 处理详情`} />
          <section className="panel">
            <Skeleton active paragraph={{ rows: 8 }} />
          </section>
        </>
      );
    if (detailError)
      return (
        <>
          <PageHeader title={`${title} · 处理详情`} />
          <Alert
            type="error"
            showIcon
            message={detailError}
            action={
              <Button onClick={() => setDetailReload((v) => v + 1)}>
                重试
              </Button>
            }
          />
          <Button
            className="feedback-retry-back"
            onClick={() => navigate(base)}
          >
            返回列表
          </Button>
        </>
      );
    return item ? (
      <FeedbackReview
        key={`${item.id}-${item.revision}-${resetKey}`}
        item={item}
        title={title}
        editing={editing}
        onEditing={setEditing}
        onCancel={() => {
          setEditing(false);
          setResetKey((v) => v + 1);
        }}
        onBack={() => navigate(base)}
        onReload={() => setDetailReload((v) => v + 1)}
        onSaved={(data, action) => {
          setItem(data);
          setEditing(["draft", "review", "start"].includes(action));
        }}
      />
    ) : null;
  }
  return (
    <>
      <PageHeader
        title={title}
        description={
          kind === "MISSING_CARD"
            ? "核对缺失小卡，保存草稿后经发布才计为收录。"
            : "逐项核对用户建议与平台最新值，发布后更新正式图鉴。"
        }
      />
      <FilterBar
        onReset={reset}
        advanced={
          <>
            <Input
              aria-label="处理人编号"
              placeholder="处理人编号"
              allowClear
              value={filters.handler_id || ""}
              onChange={(e) => filter("handler_id", e.target.value)}
            />
            <DatePicker.RangePicker
              aria-label="提交日期"
              placeholder={["提交起日", "提交止日"]}
              value={
                filters.date_from && filters.date_to
                  ? [dayjs(filters.date_from), dayjs(filters.date_to)]
                  : null
              }
              onChange={(values) => {
                setOffset(0);
                setFilters((old) => ({
                  ...old,
                  date_from: values?.[0]?.format("YYYY-MM-DD"),
                  date_to: values?.[1]?.format("YYYY-MM-DD"),
                }));
              }}
            />
          </>
        }
      >
        <Select
          aria-label="收录结果"
          allowClear
          placeholder="全部收录结果"
          value={filters.result}
          onChange={(v) => filter("result", v)}
          options={["PENDING", "INCLUDED", "NOT_INCLUDED"].map((value) => ({
            value,
            label: resultLabel(value, kind),
          }))}
        />
        {kind === "CORRECTION" && (
          <Select
            aria-label="对象类型"
            allowClear
            placeholder="全部对象类型"
            value={filters.entity_type}
            options={kinds}
            onChange={(v) => filter("entity_type", v)}
          />
        )}
      </FilterBar>
      {error && (
        <Alert
          className="feedback-list-error"
          type="error"
          showIcon
          message={error}
          action={<Button onClick={() => void load()}>重试</Button>}
        />
      )}
      <section className="panel table-panel feedback-list">
        <TableToolbar
          actions={
            <Button
              icon={<ReloadOutlined aria-hidden="true" />}
              loading={loading}
              onClick={() => void load()}
            >
              刷新
            </Button>
          }
        >
          <Tabs
            activeKey={filters.status || "ALL"}
            onChange={(key) =>
              filter("status", key === "ALL" ? undefined : key)
            }
            items={[
              { key: "ALL", label: "全部反馈" },
              ...Object.entries(statusLabels).map(([key, label]) => ({
                key,
                label,
              })),
            ]}
          />
        </TableToolbar>
        {!loading && !error && !rows.length ? (
          <EmptyState
            filtered={filtered}
            onReset={reset}
            description={
              filtered
                ? undefined
                : "用户提交反馈后会显示在这里，可继续查看图鉴内容。"
            }
            onCreate={
              filtered
                ? undefined
                : () =>
                    navigate(
                      kind === "MISSING_CARD"
                        ? "/catalog/cards"
                        : "/catalog/groups",
                    )
            }
            createLabel="查看图鉴"
          />
        ) : (
          <Table<FeedbackRecord>
            rowKey="id"
            loading={loading}
            dataSource={rows}
            pagination={false}
            filtered={filtered}
            onReset={reset}
            scroll={{ x: 1120 }}
            columns={[
              {
                title: "反馈对象",
                width: 248,
                render: (_, r) => (
                  <div className="feedback-record-cell">
                    <button
                      className="text-button table-title"
                      title={r.name}
                      onClick={() => open(r.id)}
                    >
                      {r.name}
                    </button>
                    <RecordId value={r.id} />
                  </div>
                ),
              },
              {
                title: "反馈内容",
                width: 224,
                render: (_, r) =>
                  r.kind === "MISSING_CARD"
                    ? `扫描缺失 · ${r.submission.missing?.missing_source_name || sourceLabels[r.submission.missing?.source_entity_type] || "—"}`
                    : (r.submission.fields || [])
                        .map((f: { label: string }) => f.label)
                        .join("、") || "—",
              },
              {
                title: "提交用户",
                width: 120,
                render: (_, r) => r.user.name || "—",
              },
              { title: "提交时间", dataIndex: "created_at", width: 160 },
              {
                title: "处理状态",
                width: 104,
                render: (_, r) => (
                  <Tag
                    color={r.status === "PROCESSING" ? "processing" : "default"}
                  >
                    {statusLabels[r.status] || "—"}
                  </Tag>
                ),
              },
              {
                title: "收录结果",
                width: 104,
                render: (_, r) => (
                  <Tag
                    color={
                      r.result === "INCLUDED"
                        ? "success"
                        : r.result === "NOT_INCLUDED"
                          ? "error"
                          : "default"
                    }
                  >
                    {resultLabel(r.result, kind)}
                  </Tag>
                ),
              },
              {
                title: "操作",
                key: "actions",
                fixed: "right",
                width: 120,
                render: (_, r) => (
                  <RowActions
                    onView={() => open(r.id)}
                    onEdit={
                      canEdit && r.result === "PENDING"
                        ? () => open(r.id, true)
                        : undefined
                    }
                  />
                ),
              },
            ]}
          />
        )}
        <CursorPagination
          offset={offset}
          nextOffset={next}
          count={rows.length}
          pageSize={20}
          loading={loading}
          onChange={setOffset}
        />
      </section>
    </>
  );
}

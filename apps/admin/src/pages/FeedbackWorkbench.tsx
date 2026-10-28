import { canPermission } from "../api/permissions";
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
import MissingCatalogReview from "./feedback/MissingCatalogReview";
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

export default function FeedbackWorkbench({
  kind,
}: {
  kind: FeedbackKind | "ADDITIONS";
}) {
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
  const addition = kind !== "CORRECTION";
  const title = addition ? "图鉴新增" : "图鉴信息错误";
  const base = addition ? "/catalog/additions" : "/catalog/corrections";
  const canEdit =
    canPermission(actor, "catalog.edit") ||
    canPermission(actor, "catalog.publish");
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
        if (
          kind === "ADDITIONS"
            ? !["MISSING_CARD", "MISSING_CATALOG"].includes(data.kind)
            : data.kind !== kind
        ) {
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
    if (item && item.kind === "MISSING_CATALOG")
      return (
        <MissingCatalogReview
          key={`${item.id}-${item.revision}`}
          item={item}
          onBack={() => navigate(base)}
          onSaved={setItem}
        />
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
          addition
            ? "核对用户提交的新增申请，提交处理结果后同步用户；已采纳内容需单独发布。"
            : "逐项核对用户建议，提交处理结果后同步用户；已采纳内容需单独发布。"
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
          aria-label="处理结果"
          allowClear
          placeholder="全部处理结果"
          value={filters.result}
          onChange={(v) => filter("result", v)}
          options={["PENDING", "INCLUDED", "NOT_INCLUDED", "NEEDS_INFO"].map(
            (value) => ({
              value,
              label: resultLabel(value, "CORRECTION"),
            }),
          )}
        />
        {addition && (
          <Select
            aria-label="对象类型"
            allowClear
            placeholder="全部对象类型"
            value={filters.entity_type}
            options={kinds.filter((v) => v.value !== "companies")}
            onChange={(v) => filter("entity_type", v)}
          />
        )}
        {kind === "CORRECTION" && (
          <>
            <Select
              aria-label="纠错范围"
              placeholder="全部纠错"
              allowClear
              value={filters.profile_only}
              options={[{ value: "true", label: "资料修订" }]}
              onChange={(v) => filter("profile_only", v)}
            />
            <Select
              aria-label="资料板块"
              placeholder="全部资料板块"
              allowClear
              value={filters.section_key}
              options={Object.entries({
                intro: "简介",
                basic: "基本资料",
                career: "从艺历程",
                honors: "荣誉记录",
              }).map(([value, label]) => ({ value, label }))}
              onChange={(v) => filter("section_key", v)}
            />
            <Select
              aria-label="对象类型"
              allowClear
              placeholder="全部对象类型"
              value={filters.entity_type}
              options={kinds}
              onChange={(v) => filter("entity_type", v)}
            />
          </>
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
                    navigate(addition ? "/catalog/cards" : "/catalog/groups")
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
                title: "处理结果",
                width: 144,
                render: (_, r) => (
                  <Tag
                    color={
                      r.result === "INCLUDED"
                        ? "success"
                        : r.review_decision === "ACCEPTED"
                          ? "processing"
                          : r.result === "NOT_INCLUDED"
                            ? "error"
                            : r.result === "NEEDS_INFO"
                              ? "warning"
                              : "default"
                    }
                  >
                    {resultLabel(r.result, r.kind, r.review_decision)}
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

import { useEffect, useRef, useState } from "react";
import {
  Alert,
  App,
  Button,
  Checkbox,
  Descriptions,
  Input,
  Select,
  Spin,
  Tag,
} from "antd";
import { Link } from "react-router-dom";
import { consoleApi, send } from "../../api/client";
import {
  Drawer,
  Form,
  Modal,
  RecordId,
  Table,
  TableToolbar,
} from "../../components/admin";
import { actionLabel, displayValue, formatTime } from "../../design/format";
import AlbumPreview from "./AlbumPreview";
import {
  moderationLabels,
  moderationReasons,
  moderationStatus,
  type AlbumDetail as Detail,
  type AlbumLog,
  type AlbumReport,
  type Resource,
} from "./types";

type Action = "RESTRICTED" | "OFFLINE" | "NORMAL" | "REJECT";
const titles: Record<Action, string> = {
  RESTRICTED: "限制公开",
  OFFLINE: "下架作品",
  NORMAL: "恢复作品",
  REJECT: "驳回复核",
};
const reportClosed = (status: string) =>
  ["RESOLVED", "REJECTED", "DISMISSED"].includes(status.toUpperCase());
const logActions: Record<string, string> = {
  request_review: "提交复核申请",
  reject_review: "驳回复核",
  restore: "恢复作品",
  restrict_public: "限制公开",
  offline: "下架作品",
};
export default function AlbumDetail({
  albumId,
  resources,
  canModerate,
  initialAction,
  onClose,
  onChanged,
}: {
  albumId?: string;
  resources: Resource[];
  canModerate: boolean;
  initialAction?: Action;
  onClose: () => void;
  onChanged: () => Promise<void>;
}) {
  const { message } = App.useApp();
  const [detail, setDetail] = useState<Detail>(),
    [loading, setLoading] = useState(false),
    [error, setError] = useState("");
  const [preview, setPreview] = useState<"default" | "review">("default");
  const [action, setAction] = useState<Action>(),
    [busy, setBusy] = useState(false);
  const [selectedReports, setSelectedReports] = useState<string[]>([]);
  const [form] = Form.useForm();
  const requestVersion = useRef(0);
  const load = async (id: string, target: "default" | "review") => {
    const version = ++requestVersion.current;
    setLoading(true);
    setError("");
    try {
      const data = await consoleApi<Detail>(
        `/digital-albums/${encodeURIComponent(id)}?preview=${target}`,
      );
      if (version !== requestVersion.current) return;
      setDetail(data);
      setSelectedReports((ids) =>
        ids.filter((id) =>
          data.reports?.some((r) => r.id === id && !reportClosed(r.status)),
        ),
      );
    } catch (e) {
      if (version === requestVersion.current) setError((e as Error).message);
    } finally {
      if (version === requestVersion.current) setLoading(false);
    }
  };
  useEffect(() => {
    ++requestVersion.current;
    setDetail(undefined);
    setPreview("default");
    setSelectedReports([]);
    setAction(undefined);
    if (!albumId) return;
    let active = true;
    setLoading(true);
    setError("");
    consoleApi<Detail>(
      `/digital-albums/${encodeURIComponent(albumId)}?preview=default`,
    )
      .then((data) => {
        if (active) {
          setDetail(data);
          if (initialAction) {
            form.resetFields();
            form.setFieldValue("reason_code", "OTHER");
            setAction(initialAction);
          }
        }
      })
      .catch((e) => {
        if (active) setError(e.message);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
      ++requestVersion.current;
    };
  }, [albumId, initialAction, form]);
  const start = (value: Action) => {
    form.resetFields();
    form.setFieldValue("reason_code", "OTHER");
    setAction(value);
  };
  const pendingReview =
    !!detail?.review_request &&
    ["PENDING", "PENDING_REVIEW"].includes(detail.review_request.status);
  const currentStatus = detail ? moderationStatus(detail) : "NORMAL";
  const reviewVisible =
    preview === "review" && detail?.preview_version === "REVIEW" && !loading;
  const save = async () => {
    if (!detail || !action) return;
    if (
      pendingReview &&
      (action === "NORMAL" || action === "REJECT") &&
      !reviewVisible
    ) {
      message.warning("请先加载并查看本次申请复核内容");
      return;
    }
    let values: { reason_code: string; reason: string; note?: string };
    try {
      values = await form.validateFields();
    } catch {
      return;
    }
    setBusy(true);
    try {
      if (action === "REJECT")
        await consoleApi(
          `/digital-albums/${encodeURIComponent(detail.id)}/review-reject`,
          send({
            reason: values.reason.trim(),
            review_id: detail.review_request?.id,
          }),
        );
      else
        await consoleApi(
          `/digital-albums/${encodeURIComponent(detail.id)}/moderation`,
          send(
            {
              status: action,
              reason_code: values.reason_code,
              reason: values.reason.trim(),
              note: values.note?.trim() || "",
              resolve_report_ids: selectedReports,
              ...(action === "NORMAL" && pendingReview
                ? { review_id: detail.review_request?.id }
                : {}),
            },
            "PUT",
          ),
        );
      setAction(undefined);
      message.success(
        action === "REJECT" ? "复核已驳回" : "处理结果已保存，操作日志已记录",
      );
      setPreview("default");
      await load(detail.id, "default");
      await onChanged();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <Drawer
        title={detail?.name || "作品详情"}
        open={!!albumId}
        width={1040}
        onClose={onClose}
        extra={
          detail && (
            <Button
              loading={loading}
              onClick={() => void load(detail.id, preview)}
            >
              刷新
            </Button>
          )
        }
      >
        {error && (
          <Alert
            type="error"
            showIcon
            message={error}
            action={
              <Button onClick={() => albumId && void load(albumId, preview)}>
                重试
              </Button>
            }
          />
        )}
        <Spin spinning={loading}>
          {detail && (
            <div className="album-detail">
              <section className="album-panel">
                <TableToolbar
                  actions={
                    canModerate && detail.status !== "DELETED" ? (
                      <>
                        {currentStatus !== "RESTRICTED" && (
                          <Button onClick={() => start("RESTRICTED")}>
                            限制公开
                          </Button>
                        )}
                        {currentStatus !== "OFFLINE" && (
                          <Button danger onClick={() => start("OFFLINE")}>
                            下架
                          </Button>
                        )}
                        {pendingReview && (
                          <Button
                            danger
                            disabled={!reviewVisible}
                            onClick={() => start("REJECT")}
                          >
                            驳回复核
                          </Button>
                        )}
                        {currentStatus !== "NORMAL" &&
                          currentStatus !== "NONE" && (
                            <Button
                              type="primary"
                              disabled={pendingReview && !reviewVisible}
                              onClick={() => start("NORMAL")}
                            >
                              恢复作品
                            </Button>
                          )}
                      </>
                    ) : undefined
                  }
                >
                  <h2>基本信息</h2>
                </TableToolbar>
                <Descriptions
                  size="small"
                  column={{ xs: 1, sm: 2 }}
                  items={[
                    { key: "name", label: "作品名称", children: detail.name },
                    {
                      key: "author",
                      label: "作者",
                      children: (
                        <>
                          {detail.author_name}{" "}
                          <Link
                            to={`/users?q=${encodeURIComponent(detail.user_id)}`}
                          >
                            查看用户
                          </Link>
                        </>
                      ),
                    },
                    {
                      key: "description",
                      label: "作品说明",
                      span: 2,
                      children: detail.description || "—",
                    },
                    {
                      key: "status",
                      label: "发布状态",
                      children: (
                        <>
                          {displayValue(detail.status)} ·{" "}
                          {detail.visibility === "PUBLIC" ? "公开" : "私密"}
                          {detail.publication_blocked && (
                            <Tag color="blue">待作者重新发布</Tag>
                          )}
                        </>
                      ),
                    },
                    {
                      key: "moderation",
                      label: "处理状态",
                      children: (
                        <Tag color={detail.is_moderated ? "red" : "green"}>
                          {moderationLabels[currentStatus] || currentStatus}
                        </Tag>
                      ),
                    },
                    {
                      key: "size",
                      label: "作品内容",
                      children: detail.work_mode === 'CARDS' ? `${detail.card_count} 张小卡` : `${detail.page_count} 页 / ${detail.card_count} 张小卡`,
                    },
                    {
                      key: "published",
                      label: "发布时间",
                      children: formatTime(detail.published_at),
                    },
                  ]}
                />
                {detail.moderation_reason && (
                  <Alert
                    type="warning"
                    showIcon
                    message={detail.moderation_reason}
                    description={detail.moderation_note || undefined}
                  />
                )}
              </section>
              <section className="album-panel">
                <TableToolbar
                  actions={
                    pendingReview ? (
                      <Button
                        disabled={loading}
                        onClick={async () => {
                          const next =
                            preview === "review" ? "default" : "review";
                          setPreview(next);
                          await load(detail.id, next);
                        }}
                      >
                        {preview === "review"
                          ? "返回已发布内容"
                          : "查看申请复核内容"}
                      </Button>
                    ) : undefined
                  }
                >
                  <h2>
                    作品预览{" "}
                    <Tag>
                      {detail.preview_version === "REVIEW"
                        ? "申请复核时的内容"
                        : detail.preview_version === "PUBLISHED"
                          ? "已发布内容"
                          : "未发布的编辑内容"}
                    </Tag>
                  </h2>
                </TableToolbar>
                {pendingReview && (
                  <Alert
                    type="info"
                    showIcon
                    message={
                      reviewVisible
                        ? "正在查看本次复核申请的固定快照；恢复后仍需作者重新发布。"
                        : "作者已申请复核，请先查看申请时提交的内容，再决定恢复或驳回。"
                    }
                  />
                )}
                <AlbumPreview
                  key={`${detail.id}:${detail.preview_version}`}
                  album={detail}
                  resources={detail.resources || resources}
                  shelf={detail.shelf_snapshot}
                />
              </section>
              <section className="album-panel">
                <h2>关联举报</h2>
                <p className="album-muted">
                  仅勾选需要随本次处理一起结案的举报；未勾选的举报保持原状态。
                </p>
                <Table<AlbumReport>
                  size="small"
                  rowKey="id"
                  dataSource={detail.reports || []}
                  pagination={{ defaultPageSize: 5 }}
                  rowSelection={
                    canModerate
                      ? {
                          selectedRowKeys: selectedReports,
                          onChange: (keys) =>
                            setSelectedReports(keys.map(String)),
                          getCheckboxProps: (r) => ({
                            disabled: reportClosed(r.status),
                          }),
                        }
                      : undefined
                  }
                  columns={[
                    { title: "举报原因", dataIndex: "reason" },
                    {
                      title: "状态",
                      width: 104,
                      render: (_, report) =>
                        ({
                          PENDING: "待处理",
                          RESOLVED: "已处理",
                          REJECTED: "已驳回",
                          DISMISSED: "无需处理",
                        })[report.status.toUpperCase()] ||
                        displayValue(report.status),
                    },
                    { title: "提交时间", dataIndex: "created_at", width: 152 },
                    { title: "举报编号", dataIndex: "id", width: 144 },
                  ]}
                />
              </section>
              <section className="album-panel">
                <h2>处理日志</h2>
                <Table<AlbumLog>
                  rowKey="id"
                  dataSource={detail.logs || []}
                  pagination={{ defaultPageSize: 5 }}
                  columns={[
                    {
                      title: "业务动作",
                      width: 128,
                      render: (_, log) =>
                        logActions[log.action] || actionLabel(log.action),
                    },
                    {
                      title: "原因与备注",
                      render: (_, log) => (
                        <>
                          {moderationReasons.find(
                            (r) => r.value === log.after?.reason_code,
                          )?.label && (
                            <Tag>
                              {
                                moderationReasons.find(
                                  (r) => r.value === log.after?.reason_code,
                                )?.label
                              }
                            </Tag>
                          )}
                          {String(log.after?.reason || log.reason || "—")}
                          <div className="album-muted">
                            {String(log.after?.note || log.note || "")}
                          </div>
                          <div className="album-muted">
                            {log.before && log.after
                              ? `${moderationLabels[String(log.before.moderation_status || log.before.status)] || (log.before.is_moderated ? "限制公开" : "正常")} → ${moderationLabels[String(log.after.moderation_status || log.after.status)] || (log.after.is_moderated ? "限制公开" : "正常")}`
                              : ""}
                          </div>
                        </>
                      ),
                    },
                    {
                      title: "操作人",
                      width: 128,
                      render: (_, log) =>
                        log.actor_name || <RecordId value={log.actor_id} />,
                    },
                    { title: "处理时间", dataIndex: "created_at", width: 152 },
                  ]}
                />
              </section>
              <section className="album-panel">
                <h2>系统信息</h2>
                <Descriptions
                  size="small"
                  column={{ xs: 1, sm: 2 }}
                  items={[
                    {
                      key: "id",
                      label: "作品编号",
                      children: <RecordId value={detail.id} />,
                    },
                    {
                      key: "user",
                      label: "作者编号",
                      children: <RecordId value={detail.user_id} />,
                    },
                    {
                      key: "created",
                      label: "创建时间",
                      children: formatTime(detail.created_at),
                    },
                    {
                      key: "updated",
                      label: "更新时间",
                      children: formatTime(detail.updated_at),
                    },
                  ]}
                />
                <p className="album-muted">时间均为北京时间（UTC+08:00）。</p>
              </section>
            </div>
          )}
        </Spin>
      </Drawer>
      <Modal
        title={
          action ? `${titles[action]}「${detail?.name || ""}」` : "处理作品"
        }
        open={!!action}
        confirmLoading={busy}
        okText={action ? titles[action] : "确认"}
        okButtonProps={{
          danger: action === "OFFLINE" || action === "REJECT",
          disabled:
            (action === "NORMAL" || action === "REJECT") &&
            pendingReview &&
            !reviewVisible,
        }}
        onCancel={() => setAction(undefined)}
        onOk={save}
      >
        <Alert
          type={action === "OFFLINE" ? "warning" : "info"}
          showIcon
          message={
            action === "NORMAL"
              ? "恢复后由作者重新发布，旧的违规快照不会自动重新公开。"
              : action === "REJECT"
                ? "保留原处理状态，作者可以继续修改并重新申请复核。"
                : "公开页面和分享链接将无法访问。保留作者的编辑内容，不影响其他相册。"
          }
        />
        <Form form={form} layout="vertical" className="album-moderation-form">
          {action !== "REJECT" && (
            <Form.Item
              name="reason_code"
              label="原因分类"
              rules={[{ required: true, message: "请选择原因分类" }]}
            >
              <Select options={moderationReasons} />
            </Form.Item>
          )}
          <Form.Item
            name="reason"
            label="处理原因"
            rules={[
              { required: true, whitespace: true, message: "请填写处理原因" },
            ]}
          >
            <Input.TextArea
              placeholder="处理原因"
              rows={3}
              maxLength={200}
              showCount
            />
          </Form.Item>
          {action !== "REJECT" && (
            <Form.Item name="note" label="内部处理备注">
              <Input.TextArea
                placeholder="补充审核依据或处理说明"
                rows={2}
                maxLength={1000}
              />
            </Form.Item>
          )}
        </Form>
        {action !== "REJECT" && (
          <Checkbox checked={selectedReports.length > 0} disabled>
            同步结案已选的 {selectedReports.length} 条举报
          </Checkbox>
        )}
      </Modal>
    </>
  );
}

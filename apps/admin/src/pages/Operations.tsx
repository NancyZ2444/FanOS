import { canPermission } from "../api/permissions";
import { TableToolbar } from "../components/admin";
import { useSingleSubmit } from "../components/admin";
import {
  FilterBar,
  RowActions,
  RecordId,
  DetailFields,
} from "../components/admin";
import { PageHeader } from "../components/admin";
import { Drawer, Form, Modal, Table } from "../components/admin";
import { useEffect, useState } from "react";
import {
  Alert,
  App,
  Button,
  Input,
  InputNumber,
  Select,
  Space,
  Tabs,
} from "antd";
import { EyeOutlined, PlusOutlined, SearchOutlined } from "@ant-design/icons";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import { ImageUpload, StatusTag } from "../components/shared";
import { authApi, filtersQuery } from "./auth/shared";

export const operationNames: Record<string, string> = {
  social: "动态管理",
  accounts: "社交数据源",
  comments: "评论管理",
  daily: "卡池与概率配置",
  draws: "翻卡记录",
  notifications: "站内通知",
  announcements: "首页公告",
  users: "用户管理",
  reports: "举报管理",
};
const statusActions: Record<string, { key: string; label: string }[]> = {
  DRAFT: [{ key: "submit", label: "提交审核" }],
  REJECTED: [{ key: "submit", label: "重新提交" }],
  OFFLINE: [{ key: "submit", label: "提交审核" }],
  PENDING: [
    { key: "approve", label: "审核通过" },
    { key: "reject", label: "驳回" },
  ],
  PUBLISHED: [{ key: "offline", label: "下架" }],
  APPROVED: [{ key: "send", label: "正式发送" }],
};
export default function Operations({ kind }: { kind: string }) {
  const { catalog, actor } = useConsole();
  const { message } = App.useApp();
  const [form] = Form.useForm();
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("ALL");
  const [open, setOpen] = useState(false);
  const [record, setRecord] = useState<any>();
  const [detail, setDetail] = useState<any>();
  const [actionModal, setActionModal] = useState<{
    row: any;
    action: string;
    label: string;
  }>();
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [testRecipient, setTestRecipient] = useState<string>();
  const [testUsers, setTestUsers] = useState<
    { value: string; label: string }[]
  >([]);
  const [testRecipientError, setTestRecipientError] = useState("");
  const findTestUser = async (q: string) => {
    setTestRecipientError("");
    try {
      const result = await authApi(
        `/users?${filtersQuery({ q, status: "normal", page_size: 20 })}`,
      );
      setTestUsers(
        result.items.map((u: any) => ({
          value: u.id,
          label: `${u.name} · ${u.phone_masked} · ${u.id}`,
        })),
      );
    } catch (e) {
      setTestRecipientError((e as Error).message);
    }
  };
  const [busy, setBusy] = useState(false);
  const [preview, setPreview] = useState<any>();
  const title = operationNames[kind];
  const managed = ["daily", "notifications", "announcements"].includes(kind);
  const writable = [
    "social",
    "accounts",
    ...["daily", "notifications", "announcements"],
  ].includes(kind);
  const roleAllowed = canPermission(
    actor,
    `${kind === "accounts" ? "sources" : kind === "draws" ? "daily" : kind}.manage`,
  );
  const load = async () => {
    setLoading(true);
    setError("");
    try {
      const result = await consoleApi(`/operations/${kind}`);
      setRows(result.items);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => {
    load();
  }, [kind]);
  const edit = (row?: any) => {
    setRecord(row);
    form.resetFields();
    form.setFieldsValue(
      row
        ? {
            ...row,
            content: row.content || row.title,
            source_url: row.original_url || row.source_url,
            weights: row.weights || {},
            card_ids:
              kind === "daily" ? Object.keys(row.weights || {}) : row.card_ids,
          }
        : {
            audience: "ALL",
            target_type: "NONE",
            platform: "MANUAL",
            weights: {},
          },
    );
    setOpen(true);
  };
  const selectedCards = Form.useWatch("card_ids", form) || [];
  const targetType = Form.useWatch("target_type", form);
  const audience = Form.useWatch("audience", form);
  const save = useSingleSubmit(async () => {
    try {
      const data = await form.validateFields();
      if (kind === "daily") {
        data.weights = Object.fromEntries(
          (data.card_ids || []).map((id: string) => [
            id,
            data.weights?.[id] || 1,
          ]),
        );
      }
      setBusy(true);
      await consoleApi(
        record ? `/operations/${kind}/${record.id}` : `/operations/${kind}`,
        send(data, record ? "PUT" : "POST"),
      );
      message.success("保存成功");
      setOpen(false);
      await load();
    } catch (e) {
      if (e instanceof Error) message.error(e.message);
    } finally {
      setBusy(false);
    }
  });
  const execute = async () => {
    if (!actionModal) return;
    if (actionModal.action === "test-send" && !testRecipient) {
      setTestRecipientError("请选择真实 App 测试接收人");
      return;
    }
    const needsReason =
      ["users", "comments", "reports"].includes(kind) ||
      actionModal.action === "reject";
    if (needsReason && !reason.trim()) {
      message.warning("请填写处理原因");
      return;
    }
    setBusy(true);
    try {
      await consoleApi(
        `/operations/${kind}/${actionModal.row.id}/actions`,
        send({
          action: actionModal.action,
          reason,
          confirmation,
          test_recipient_id:
            actionModal.action === "test-send" ? testRecipient : undefined,
        }),
      );
      message.success(
        actionModal.action === "test-send"
          ? "测试通知已发送至所选 App 用户站内信"
          : "操作成功",
      );
      setActionModal(undefined);
      await load();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const actions = (r: any) => {
    if (!roleAllowed) return [];
    if (managed)
      return [
        ...(statusActions[r.status] || []),
        ...(kind === "notifications" &&
        ["DRAFT", "PENDING", "APPROVED"].includes(r.status)
          ? [{ key: "test-send", label: "测试发送" }]
          : []),
      ];
    if (kind === "users" && r.role === "user")
      return [
        {
          key: r.status === "BANNED" ? "unban" : "ban",
          label: r.status === "BANNED" ? "解除封禁" : "封禁",
        },
      ];
    if (kind === "comments")
      return r.status === "VISIBLE"
        ? [
            { key: "hide", label: "隐藏" },
            { key: "delete", label: "删除" },
          ]
        : [{ key: "restore", label: "恢复" }];
    if (kind === "reports" && r.status === "PENDING")
      return [
        { key: "resolve", label: "处理成立" },
        { key: "reject", label: "不成立" },
      ];
    if (["social", "accounts"].includes(kind))
      return [
        {
          key: r.status === "OFFLINE" ? "publish" : "offline",
          label:
            kind === "accounts"
              ? r.status === "OFFLINE"
                ? "启用"
                : "停用"
              : r.status === "OFFLINE"
                ? "发布"
                : "下架",
        },
      ];
    return [];
  };
  const visible = rows.filter(
    (r) =>
      (status === "ALL" || r.status === status) &&
      (!q ||
        [r.id, r.title, r.user_name, r.group_id, r.idol_id].some((v) =>
          String(v || "")
            .toLowerCase()
            .includes(q.toLowerCase()),
        )),
  );
  const targets =
    targetType === "CARD"
      ? catalog.cards
          .filter((c) => c.status === "PUBLISHED")
          .map((c) => ({ value: c.id, label: c.title }))
      : targetType === "ALBUM"
        ? catalog.albums.map((g) => ({ value: g.id, label: g.name }))
        : targetType === "GROUP"
          ? catalog.groups.map((g) => ({ value: g.id, label: g.name }))
          : catalog.idols.map((g) => ({ value: g.id, label: g.name }));
  const extraColumns: any[] =
    kind === "users"
      ? [
          {
            title: "收藏 / 心愿",
            key: "collection",
            render: (_: unknown, r: any) =>
              `${r.collection_count} / ${r.wishlist_count}`,
          },
          { title: "手机号", dataIndex: "phone" },
        ]
      : kind === "notifications"
        ? [
            { title: "目标人数", dataIndex: "audience_count" },
            {
              title: "成功发送",
              dataIndex: "sent_count",
              render: (v: number) => v ?? "—",
            },
          ]
        : kind === "daily"
          ? [
              {
                title: "卡片数量",
                key: "cards",
                render: (_: unknown, r: any) =>
                  Object.keys(r.weights || {}).length,
              },
            ]
          : kind === "reports"
            ? [
                { title: "举报对象", dataIndex: "target_type" },
                { title: "对象 ID", dataIndex: "target_id", ellipsis: true },
              ]
            : kind === "comments"
              ? [{ title: "用户", dataIndex: "user_name" }]
              : kind === "draws"
                ? [
                    { title: "用户 ID", dataIndex: "user_id" },
                    { title: "当日第几次", dataIndex: "draw_index" },
                  ]
                : kind === "announcements"
                  ? [{ title: "优先级", dataIndex: "priority" }]
                  : [
                      { title: "平台", dataIndex: "platform" },
                      {
                        title: "关联艺人",
                        dataIndex: "idol_id",
                        render: (v: string) =>
                          catalog.idols.find((i) => i.id === v)?.name ||
                          "组合官方",
                      },
                    ];
  return (
    <>
      <PageHeader
        title={<>{title}</>}
        description={
          <>
            {
              {
                social: "统一维护艺人动态，连接相关小卡与粉丝。",
                accounts: "管理艺人和组合的官方社交账号。",
                comments: "查看评论上下文，处理不适宜的内容。",
                daily: "配置每日翻卡卡池，按权重分配抽取机会。",
                draws: "查看真实翻卡记录与卡片去向。",
                notifications: "预览、测试、审核后，向目标用户发送站内通知。",
                announcements: "管理首页公告内容与展示优先级。",
                users: "了解用户的本命、收藏与账号状态。",
                reports: "记录举报受理、审核意见与处理结果。",
              }[kind]
            }
          </>
        }
      />
      {error && (
        <Alert
          showIcon
          type="error"
          message={error}
          action={<Button onClick={load}>重试</Button>}
        />
      )}
      <FilterBar
        onReset={() => {
          setQ("");
          setStatus("ALL");
        }}
      >
        <Input
          allowClear
          prefix={<SearchOutlined aria-hidden="true" />}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="搜索名称、内容或 ID"
          style={{ width: 350 }}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar
          actions={
            <>
              {" "}
              {writable && roleAllowed && (
                <Button
                  type="primary"
                  icon={<PlusOutlined aria-hidden="true" />}
                  onClick={() => edit()}
                >
                  新增
                  {kind === "daily"
                    ? "卡池"
                    : kind === "accounts"
                      ? "数据源"
                      : title.replace("管理", "")}
                </Button>
              )}{" "}
            </>
          }
        >
          <Tabs
            activeKey={status}
            onChange={setStatus}
            items={[
              { key: "ALL", label: "全部记录" },
              ...[...new Set(rows.map((r) => r.status))].map((s) => ({
                key: s,
                label: <StatusTag status={s} />,
              })),
            ]}
          />
        </TableToolbar>
        <Table
          rowKey="id"
          dataSource={visible}
          filtered={!!q || status !== "ALL"}
          onReset={() => {
            setQ("");
            setStatus("ALL");
          }}
          onCreate={writable && roleAllowed ? () => edit() : undefined}
          loading={loading}
          scroll={{ x: 1050 }}
          pagination={{
            defaultPageSize: 10,
            showTotal: (t) => `共 ${t} 条记录`,
          }}
          columns={[
            {
              title: kind === "users" ? "用户信息" : "内容 / 名称",
              key: "title",
              width: 320,
              render: (_, r) => (
                <div className="cell-stack">
                  <button
                    className="table-title truncate"
                    title={r.title}
                    onClick={() => setDetail(r)}
                  >
                    {r.title}
                  </button>
                  <RecordId value={r.id} />
                </div>
              ),
            },
            ...extraColumns,
            {
              title: "状态",
              dataIndex: "status",
              width: 110,
              render: (v) => <StatusTag status={v} />,
            },
            {
              title: "创建时间",
              dataIndex: "created_at",
              width: 130,
              render: (v) => new Date(v).toLocaleDateString("zh-CN"),
            },
            {
              title: "操作",
              key: "actions",
              width: 200,
              fixed: "right",
              render: (_, r) => (
                <RowActions
                  onView={() => setDetail(r)}
                  onEdit={writable && roleAllowed ? () => edit(r) : undefined}
                  editDisabled={
                    managed &&
                    !["DRAFT", "REJECTED", "OFFLINE"].includes(r.status)
                  }
                  editHint={
                    managed &&
                    !["DRAFT", "REJECTED", "OFFLINE"].includes(r.status)
                      ? "请先下架或驳回再编辑"
                      : undefined
                  }
                  items={[
                    ...(["announcements", "notifications"].includes(kind)
                      ? [
                          {
                            key: "preview",
                            label: "预览",
                            onClick: () => setPreview(r),
                          },
                        ]
                      : []),
                    ...actions(r).map((a) => ({
                      key: a.key,
                      label: a.label,
                      danger: a.key === "delete",
                      onClick: () => {
                        setActionModal({
                          row: r,
                          action: a.key,
                          label: a.label,
                        });
                        setReason("");
                        setConfirmation("");
                        setTestRecipient(undefined);
                        setTestRecipientError("");
                        if (a.key === "test-send") findTestUser("");
                      },
                    })),
                  ]}
                />
              ),
            },
          ]}
        />
      </section>
      <Drawer
        open={open}
        saving={busy}
        width={680}
        title={`${record ? "编辑" : "新增"}${title}`}
        onClose={() => setOpen(false)}
        footer={
          <div className="drawer-footer">
            <Button onClick={() => setOpen(false)}>取消</Button>
            <Space>
              {["notifications", "announcements"].includes(kind) && (
                <Button
                  icon={<EyeOutlined aria-hidden="true" />}
                  onClick={() => setPreview(form.getFieldsValue())}
                >
                  预览效果
                </Button>
              )}
              <Button type="primary" loading={busy} onClick={save}>
                保存{managed ? "草稿" : ""}
              </Button>
            </Space>
          </div>
        }
      >
        <Form form={form} layout="vertical">
          <Form.Item
            name="title"
            label={kind === "accounts" ? "平台账号 ID" : "标题 / 名称"}
            rules={[{ required: true, message: "请填写名称" }]}
          >
            <Input maxLength={160} />
          </Form.Item>
          {kind !== "daily" && (
            <Form.Item
              name="content"
              label={kind === "accounts" ? "账号昵称" : "内容"}
              rules={[{ required: kind !== "accounts", message: "请填写内容" }]}
            >
              <Input.TextArea rows={4} maxLength={500} showCount />
            </Form.Item>
          )}
          {["social", "accounts"].includes(kind) && (
            <>
              <div className="form-grid">
                <Form.Item name="group_id" label="关联组合">
                  <Select
                    allowClear
                    options={catalog.groups.map((g) => ({
                      value: g.id,
                      label: g.name,
                    }))}
                  />
                </Form.Item>
                <Form.Item name="idol_id" label="关联艺人">
                  <Select
                    allowClear
                    options={catalog.idols.map((i) => ({
                      value: i.id,
                      label: i.name,
                    }))}
                  />
                </Form.Item>
              </div>
              <Form.Item name="platform" label="平台">
                <Select
                  options={[
                    "MANUAL",
                    "INSTAGRAM",
                    "X",
                    "WEIBO",
                    "XIAOHONGSHU",
                    "DOUYIN",
                    "TIKTOK",
                    "YOUTUBE",
                    "OTHER",
                  ].map((value) => ({ value, label: value }))}
                />
              </Form.Item>
            </>
          )}
          {["social", "daily"].includes(kind) && (
            <Form.Item
              name="card_ids"
              label={kind === "daily" ? "卡池小卡" : "关联小卡"}
              rules={[
                { required: kind === "daily", message: "请选择至少一张小卡" },
              ]}
            >
              <Select
                mode="multiple"
                optionFilterProp="label"
                options={catalog.cards
                  .filter((c) => c.status === "PUBLISHED")
                  .map((c) => ({ value: c.id, label: c.title }))}
              />
            </Form.Item>
          )}
          {kind === "daily" && (
            <>
              <Alert
                type="info"
                showIcon
                message="概率 = 单卡权重 ÷ 总权重"
                description="同日已抽过的小卡会排除；本命优先规则会在候选集中重新计算权重。"
                style={{ marginBottom: 20 }}
              />
              {selectedCards.map((id: string) => (
                <Form.Item
                  key={id}
                  name={["weights", id]}
                  label={catalog.cards.find((c) => c.id === id)?.title}
                  initialValue={1}
                  rules={[{ required: true }]}
                >
                  <InputNumber min={1} max={10000} />
                </Form.Item>
              ))}
            </>
          )}
          {["social", "announcements", "notifications"].includes(kind) && (
            <Form.Item name="image_url" label="展示图片">
              <ImageUpload label="展示图片" />
            </Form.Item>
          )}
          {["announcements", "notifications"].includes(kind) && (
            <>
              <div className="form-grid">
                <Form.Item name="target_type" label="跳转类型">
                  <Select
                    onChange={() => form.setFieldValue("target_id", "")}
                    options={[
                      { value: "NONE", label: "不跳转" },
                      { value: "CARD", label: "小卡详情" },
                      { value: "ALBUM", label: "专辑详情" },
                      { value: "GROUP", label: "组合详情" },
                      { value: "IDOL", label: "艺人详情" },
                    ]}
                  />
                </Form.Item>
                {targetType !== "NONE" && (
                  <Form.Item
                    name="target_id"
                    label="跳转目标"
                    rules={[{ required: true, message: "请选择跳转目标" }]}
                  >
                    <Select
                      showSearch
                      optionFilterProp="label"
                      options={targets}
                    />
                  </Form.Item>
                )}
              </div>
            </>
          )}
          {kind === "notifications" && (
            <>
              <Form.Item name="audience" label="目标人群">
                <Select
                  options={[
                    { value: "ALL", label: "全部正常用户" },
                    { value: "FAVORITE_IDOL", label: "指定本命艺人用户" },
                  ]}
                />
              </Form.Item>
              {audience === "FAVORITE_IDOL" && (
                <Form.Item
                  name="audience_idol_id"
                  label="本命艺人"
                  rules={[{ required: true }]}
                >
                  <Select
                    options={catalog.idols.map((i) => ({
                      value: i.id,
                      label: i.name,
                    }))}
                  />
                </Form.Item>
              )}
              <Alert
                type="info"
                message="保存后可预览实际目标人数。测试发送需明确选择 App 接收人，后台管理员不自动拥有 App 身份。"
              />
            </>
          )}
          {kind === "announcements" && (
            <>
              <Form.Item
                name="priority"
                label="展示优先级（越大越优先）"
                initialValue={0}
              >
                <InputNumber min={0} max={100} />
              </Form.Item>
              <div className="form-grid">
                <Form.Item
                  name="start_time"
                  label="开始时间"
                  getValueFromEvent={(e) =>
                    e.target.value ? new Date(e.target.value).toISOString() : ""
                  }
                  getValueProps={(v) => ({
                    value: v
                      ? new Date(
                          new Date(v).getTime() -
                            new Date(v).getTimezoneOffset() * 60000,
                        )
                          .toISOString()
                          .slice(0, 16)
                      : "",
                  })}
                >
                  <Input type="datetime-local" />
                </Form.Item>
                <Form.Item
                  name="end_time"
                  label="结束时间"
                  getValueFromEvent={(e) =>
                    e.target.value ? new Date(e.target.value).toISOString() : ""
                  }
                  getValueProps={(v) => ({
                    value: v
                      ? new Date(
                          new Date(v).getTime() -
                            new Date(v).getTimezoneOffset() * 60000,
                        )
                          .toISOString()
                          .slice(0, 16)
                      : "",
                  })}
                >
                  <Input type="datetime-local" />
                </Form.Item>
              </div>
            </>
          )}
        </Form>
      </Drawer>
      <Drawer
        open={!!detail}
        title={`${title}详情`}
        extra={
          writable &&
          roleAllowed &&
          detail &&
          (!managed ||
            ["DRAFT", "REJECTED", "OFFLINE"].includes(detail.status)) ? (
            <Button
              onClick={() => {
                edit(detail);
                setDetail(undefined);
              }}
            >
              编辑
            </Button>
          ) : undefined
        }
        width={640}
        onClose={() => setDetail(undefined)}
      >
        {detail && (
          <>
            <StatusTag status={detail.status} />
            <h2>{detail.title}</h2>
            {detail.content && (
              <p className="detail-content">{detail.content}</p>
            )}
            <DetailFields
              title="基本信息"
              data={detail}
              fields={["title", "phone", "bio", "content"]}
            />
            <DetailFields
              title="关联内容"
              data={{
                ...detail,
                favorites: detail.favorite_ids
                  ?.map(
                    (id: string) =>
                      catalog.idols.find((i) => i.id === id)?.name || id,
                  )
                  .join("、"),
                collection_count: detail.collection_count,
                wishlist_count: detail.wishlist_count,
              }}
              fields={[
                "favorites",
                "collection_count",
                "wishlist_count",
                "target_id",
                "post_content",
                "audience_count",
              ]}
            />
            <DetailFields
              title="发布信息"
              data={detail}
              fields={["status", "published_at"]}
            />
            <DetailFields
              title="系统信息"
              data={detail}
              fields={["id", "created_at", "updated_at"]}
            />

            {detail.accounts && (
              <>
                <h3>第三方登录账号</h3>
                <Table
                  rowKey="platform"
                  size="small"
                  dataSource={detail.accounts}
                  pagination={false}
                  columns={[
                    { title: "平台", dataIndex: "platform" },
                    { title: "昵称", dataIndex: "display_name" },
                    { title: "账号 ID（脱敏）", dataIndex: "platform_user_id" },
                  ]}
                />
              </>
            )}
            {detail.weights && (
              <>
                <h3>小卡概率配置</h3>
                <Table
                  rowKey="id"
                  pagination={false}
                  dataSource={Object.entries(detail.weights).map(([id, w]) => ({
                    id,
                    title: catalog.cards.find((c) => c.id === id)?.title,
                    weight: Number(w),
                  }))}
                  columns={[
                    { title: "小卡", dataIndex: "title" },
                    { title: "权重", dataIndex: "weight" },
                    {
                      title: "基础概率",
                      dataIndex: "weight",
                      render: (w) =>
                        `${((w / (Object.values(detail.weights) as number[]).reduce((a, b) => a + b, 0)) * 100).toFixed(2)}%`,
                    },
                  ]}
                />
              </>
            )}
          </>
        )}
      </Drawer>
      <Modal
        open={!!actionModal}
        title={`${actionModal?.label}确认`}
        confirmLoading={busy}
        onCancel={() => setActionModal(undefined)}
        onOk={execute}
        okText={
          actionModal?.action === "delete"
            ? "删除"
            : actionModal?.label || "确认操作"
        }
        okButtonProps={{ danger: actionModal?.action === "delete" }}
        cancelText="取消"
      >
        <p>目标：{actionModal?.row.title}（1 项）</p>
        {actionModal?.action === "test-send" && (
          <>
            <Alert
              type="info"
              showIcon
              message="请选择已授权接收测试消息的真实 App 用户；只向此用户投递，不发送给目标人群。"
            />
            <Form.Item
              label="App 测试接收人"
              required
              validateStatus={testRecipientError ? "error" : undefined}
              help={testRecipientError}
            >
              <Select
                aria-label="App 测试接收人"
                showSearch
                filterOption={false}
                onSearch={findTestUser}
                options={testUsers}
                value={testRecipient}
                onChange={setTestRecipient}
                placeholder="搜索 App 用户 ID 或昵称"
              />
            </Form.Item>
          </>
        )}
        {actionModal?.action === "delete" && (
          <Alert
            type="warning"
            showIcon
            message="删除后该评论将不可见，系统保留处理记录，可通过恢复操作恢复。"
          />
        )}
        {actionModal?.action === "send" && (
          <Alert
            type="warning"
            showIcon
            message={`将正式发送给 ${actionModal.row.audience_count} 位用户`}
            description="通知进入用户站内信后无法撤回，请确认内容和跳转目标。"
          />
        )}
        {kind === "reports" && actionModal?.action === "resolve" && (
          <Alert
            type="info"
            message="请先在用户或评论模块完成所需处置，再记录本次处理结果。"
          />
        )}
        {(["users", "comments", "reports"].includes(kind) ||
          actionModal?.action === "reject") && (
          <Form layout="vertical">
            <Form.Item label="处理原因 / 审核意见" required>
              <Input.TextArea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={4}
              />
            </Form.Item>
          </Form>
        )}
        {actionModal?.action === "send" &&
          actionModal.row.audience_count > 10000 && (
            <Input
              value={confirmation}
              onChange={(e) => setConfirmation(e.target.value)}
              placeholder="请输入 SEND 确认"
            />
          )}
      </Modal>
      <Modal
        open={!!preview}
        title="移动端内容预览"
        footer={<Button onClick={() => setPreview(undefined)}>关闭</Button>}
        onCancel={() => setPreview(undefined)}
      >
        <div className="notice-preview">
          <div className="notice-app-heading">
            <span className="brand-icon">F</span>Fan OS{" "}
            <small>{kind === "announcements" ? "首页公告" : "消息中心"}</small>
          </div>
          {preview?.image_url && <img src={preview.image_url} alt="通知配图" />}
          <h3>{preview?.title || "通知标题"}</h3>
          <p>{preview?.content || "通知正文内容"}</p>
          <span>
            跳转目标：{preview?.target_type || "NONE"}{" "}
            {preview?.target_id || ""}
          </span>
        </div>
        {preview?.audience_count !== undefined && (
          <p className="subtle-note">
            预计覆盖 {preview.audience_count} 位用户
          </p>
        )}
      </Modal>
    </>
  );
}

import { useEffect, useState } from "react";
import {
  Alert,
  App,
  Button,
  DatePicker,
  Descriptions,
  Drawer,
  Form,
  Input,
  InputNumber,
  Modal,
  Select,
  Space,
  Table,
  Tabs,
  Tag,
} from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";

type Album = {
  id: string;
  user_id: string;
  author_name: string;
  name: string;
  description: string;
  visibility: string;
  status: string;
  page_count: number;
  card_count: number;
  report_count: number;
  is_moderated: boolean;
  created_at: string;
  updated_at: string;
  pages: { id: string; slots: { id: string; card_id: string | null }[] }[];
  cards: Record<
    string,
    { title: string; image_url?: string; available?: boolean }
  >;
};
type Resource = {
  id: string;
  name: string;
  kind: string;
  status: string;
  sort_order: number;
  config: Record<string, unknown>;
};
type Limits = {
  normal_albums: number;
  pro_albums: number;
  normal_pages: number;
  pro_pages: number;
  max_card_per_page: number;
  blocked_terms: string[];
};

export default function DigitalAlbums() {
  const { actor } = useConsole();
  const { message } = App.useApp();
  const [rows, setRows] = useState<Album[]>([]),
    [resources, setResources] = useState<Resource[]>([]);
  const [loading, setLoading] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [q, setQ] = useState(""),
    [user, setUser] = useState(""),
    [status, setStatus] = useState("");
  const [dates, setDates] = useState<[string, string]>(["", ""]);
  const [detail, setDetail] = useState<Album>(),
    [action, setAction] = useState<Album>(),
    [reason, setReason] = useState("");
  const [resource, setResource] = useState<Resource>(),
    [resourceOpen, setResourceOpen] = useState(false);
  const [limitsForm] = Form.useForm(),
    [resourceForm] = Form.useForm(),
    [entitlementForm] = Form.useForm();
  const isAdmin = actor.role === "admin";
  const canModerate = isAdmin || actor.role === "operation_admin";
  const load = async () => {
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({
        q,
        user_id: user,
        status,
        created_from: dates[0],
        created_to: dates[1],
      });
      const [albums, settings] = await Promise.all([
        consoleApi<{ items: Album[] }>(`/digital-albums?${params}`),
        consoleApi<{ limits: Limits; resources: Resource[] }>(
          "/album-settings",
        ),
      ]);
      setRows(albums.items);
      setResources(settings.resources);
      limitsForm.setFieldsValue({
        ...settings.limits,
        blocked_terms: settings.limits.blocked_terms.join("\n"),
      });
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => {
    void load();
  }, []);
  const run = async (operation: () => Promise<unknown>, success: string) => {
    setBusy(true);
    try {
      await operation();
      message.success(success);
      await load();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const editResource = (row?: Resource) => {
    setResource(row);
    resourceForm.resetFields();
    resourceForm.setFieldsValue(
      row
        ? { ...row, config: JSON.stringify(row.config, null, 2) }
        : {
            kind: "STICKER",
            status: "PUBLISHED",
            sort_order: 0,
            config: '{"symbol":"✦"}',
          },
    );
    setResourceOpen(true);
  };
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>数字相册</h1>
          <p>官方小卡引用作品；相册不会改变用户 Owned / Wishlist。</p>
        </div>
        <Button onClick={() => void load()} loading={loading}>
          刷新
        </Button>
      </div>
      {error && (
        <Alert
          type="error"
          showIcon
          message={error}
          action={<Button onClick={() => void load()}>重试</Button>}
        />
      )}
      <Tabs
        items={[
          {
            key: "works",
            label: "作品管理",
            children: (
              <>
                <Space wrap style={{ marginBottom: 16 }}>
                  <Input
                    value={q}
                    placeholder="相册名称"
                    onChange={(e) => setQ(e.target.value)}
                    onPressEnter={() => void load()}
                  />
                  <Input
                    value={user}
                    placeholder="用户 ID"
                    onChange={(e) => setUser(e.target.value)}
                  />
                  <Select
                    value={status}
                    onChange={setStatus}
                    style={{ width: 140 }}
                    options={[
                      { value: "", label: "全部状态" },
                      { value: "DRAFT", label: "草稿" },
                      { value: "PUBLISHED", label: "已发布" },
                      { value: "DELETED", label: "已删除" },
                    ]}
                  />
                  <DatePicker.RangePicker
                    onChange={(_, values) =>
                      setDates([
                        values[0] ? `${values[0]}T00:00:00` : "",
                        values[1] ? `${values[1]}T23:59:59` : "",
                      ])
                    }
                  />
                  <Button type="primary" onClick={() => void load()}>
                    查询
                  </Button>
                </Space>
                <Table
                  rowKey="id"
                  dataSource={rows}
                  loading={loading}
                  pagination={{ pageSize: 20, showSizeChanger: true }}
                  scroll={{ x: 1000 }}
                  columns={[
                    {
                      title: "相册 / 作者",
                      dataIndex: "name",
                      render: (_, row) => (
                        <>
                          <Button type="link" onClick={() => setDetail(row)}>
                            {row.name}
                          </Button>
                          <div>
                            {row.author_name} · {row.user_id}
                          </div>
                        </>
                      ),
                    },
                    {
                      title: "页面 / 小卡",
                      render: (_, row) =>
                        `${row.page_count} 页 / ${row.card_count} 张`,
                    },
                    {
                      title: "权限",
                      dataIndex: "visibility",
                      render: (value) => (
                        <Tag>{value === "PUBLIC" ? "公开" : "私密"}</Tag>
                      ),
                    },
                    {
                      title: "状态",
                      render: (_, row) => (
                        <>
                          {row.status}
                          <br />
                          {row.is_moderated && <Tag color="red">限制公开</Tag>}
                        </>
                      ),
                    },
                    { title: "举报", dataIndex: "report_count" },
                    {
                      title: "更新日期",
                      dataIndex: "updated_at",
                      render: (value) => value.slice(0, 19).replace("T", " "),
                    },
                    {
                      title: "操作",
                      render: (_, row) => (
                        <Space>
                          <Button onClick={() => setDetail(row)}>查看</Button>
                          <Button
                            danger={!row.is_moderated}
                            disabled={!canModerate || row.status === "DELETED"}
                            onClick={() => {
                              setAction(row);
                              setReason("");
                            }}
                          >
                            {row.is_moderated ? "解除限制" : "限制公开"}
                          </Button>
                        </Space>
                      ),
                    },
                  ]}
                />
                <Alert
                  type="info"
                  showIcon
                  message="管理端查看的是可编辑版本；访客只看到上次发布的快照。最多查询最近 200 本作品，可按名称、用户和日期缩小范围。"
                />
              </>
            ),
          },
          {
            key: "limits",
            label: "额度与会员",
            children: (
              <Space direction="vertical" style={{ width: "100%" }}>
                <Form
                  form={limitsForm}
                  layout="vertical"
                  disabled={!isAdmin || busy}
                  onFinish={(values) =>
                    void run(
                      () =>
                        consoleApi(
                          "/album-settings",
                          send(
                            {
                              ...values,
                              blocked_terms: String(values.blocked_terms || "")
                                .split("\n")
                                .map((v) => v.trim())
                                .filter(Boolean),
                            },
                            "PUT",
                          ),
                        ),
                      "相册配置已保存",
                    )
                  }
                  style={{ maxWidth: 560 }}
                >
                  {(
                    [
                      ["normal_albums", "普通用户相册上限", 100],
                      ["pro_albums", "PRO 相册上限", 100],
                      ["normal_pages", "普通用户实际页面上限", 50],
                      ["pro_pages", "PRO 实际页面上限", 50],
                      ["max_card_per_page", "每页卡位上限", 9],
                    ] as const
                  ).map(([name, label, max]) => (
                    <Form.Item
                      key={name}
                      name={name}
                      label={label}
                      rules={[{ required: true }]}
                    >
                      <InputNumber min={1} max={max} />
                    </Form.Item>
                  ))}
                  <Form.Item
                    name="blocked_terms"
                    label="公开内容拦截词（每行一个）"
                  >
                    <Input.TextArea rows={4} maxLength={4000} />
                  </Form.Item>
                  <Button type="primary" htmlType="submit" loading={busy}>
                    保存配置
                  </Button>
                </Form>
                <Alert
                  type="info"
                  showIcon
                  message="会员到期后保留已有相册和页面；仍可编辑、排序、删除，新增容量按当前权益校验。此处为运营授权，不接入支付。"
                />
                <Form
                  form={entitlementForm}
                  layout="inline"
                  disabled={!isAdmin || busy}
                  onFinish={(values) =>
                    void run(async () => {
                      await consoleApi(
                        `/album-entitlements/${encodeURIComponent(values.user_id)}`,
                        send(
                          {
                            plan: values.plan,
                            expires_at:
                              values.expires_at?.toISOString() || null,
                          },
                          "PUT",
                        ),
                      );
                      entitlementForm.resetFields();
                    }, "会员权益已更新")
                  }
                >
                  <Form.Item name="user_id" rules={[{ required: true }]}>
                    <Input placeholder="用户 ID" />
                  </Form.Item>
                  <Form.Item name="plan" initialValue="NORMAL">
                    <Select
                      style={{ width: 130 }}
                      options={[
                        { value: "NORMAL", label: "普通用户" },
                        { value: "PRO", label: "PRO" },
                      ]}
                    />
                  </Form.Item>
                  <Form.Item name="expires_at">
                    <DatePicker showTime placeholder="到期时间（可空）" />
                  </Form.Item>
                  <Button htmlType="submit" loading={busy}>
                    更新权益
                  </Button>
                </Form>
              </Space>
            ),
          },
          {
            key: "resources",
            label: "主题与系统素材",
            children: (
              <>
                <Button
                  type="primary"
                  disabled={!isAdmin}
                  onClick={() => editResource()}
                  style={{ marginBottom: 16 }}
                >
                  新增系统素材
                </Button>
                <Table
                  rowKey="id"
                  dataSource={resources}
                  pagination={false}
                  columns={[
                    { title: "名称", dataIndex: "name" },
                    { title: "ID", dataIndex: "id" },
                    { title: "类型", dataIndex: "kind" },
                    { title: "状态", dataIndex: "status" },
                    { title: "排序", dataIndex: "sort_order" },
                    {
                      title: "配置",
                      dataIndex: "config",
                      render: (value) => <code>{JSON.stringify(value)}</code>,
                    },
                    {
                      title: "操作",
                      render: (_, row) => (
                        <Button
                          disabled={!isAdmin}
                          onClick={() => editResource(row)}
                        >
                          编辑 / 上下架
                        </Button>
                      ),
                    },
                  ]}
                />
                <Alert
                  type="info"
                  message="仅支持系统符号贴纸、书架颜色和纯色 / 渐变背景；不接受用户上传素材。下架后禁止新增使用，已有作品保留布局。"
                />
              </>
            ),
          },
        ]}
      />
      <Drawer
        title={detail?.name}
        open={!!detail}
        onClose={() => setDetail(undefined)}
        width={720}
      >
        {detail && (
          <>
            <Descriptions
              column={2}
              items={[
                { key: "id", label: "ID", children: detail.id },
                { key: "author", label: "作者", children: detail.author_name },
                {
                  key: "visibility",
                  label: "权限",
                  children: detail.visibility,
                },
                { key: "status", label: "状态", children: detail.status },
                {
                  key: "description",
                  label: "描述",
                  children: detail.description,
                },
              ]}
            />
            {detail.pages.map((page, index) => (
              <div key={page.id}>
                <h3>第 {index + 1} 页</h3>
                <Space wrap>
                  {page.slots.map((slot) => (
                    <div key={slot.id} style={{ width: 96 }}>
                      <div
                        style={{
                          height: 140,
                          background: "#f1eefe",
                          display: "grid",
                          placeItems: "center",
                        }}
                      >
                        {slot.card_id &&
                        detail.cards[slot.card_id]?.image_url &&
                        detail.cards[slot.card_id]?.available !== false ? (
                          <img
                            src={detail.cards[slot.card_id].image_url}
                            alt={detail.cards[slot.card_id].title}
                            style={{
                              maxWidth: "100%",
                              maxHeight: "100%",
                              objectFit: "contain",
                            }}
                          />
                        ) : slot.card_id ? (
                          "小卡暂不可用"
                        ) : (
                          "空卡位"
                        )}
                      </div>
                      <small>
                        {slot.card_id
                          ? detail.cards[slot.card_id]?.title || slot.card_id
                          : "—"}
                      </small>
                    </div>
                  ))}
                </Space>
              </div>
            ))}
          </>
        )}
      </Drawer>
      <Modal
        title={action?.is_moderated ? "解除相册公开限制" : "限制相册公开展示"}
        open={!!action}
        confirmLoading={busy}
        onCancel={() => setAction(undefined)}
        onOk={() => {
          if (!action || !reason.trim()) {
            message.warning("请填写处理原因");
            return;
          }
          void run(async () => {
            await consoleApi(
              `/digital-albums/${action.id}/moderation`,
              send(
                { offline: !action.is_moderated, reason: reason.trim() },
                "PUT",
              ),
            );
            setAction(undefined);
          }, "处理结果已记录审计日志");
        }}
      >
        <p>
          不删除用户小卡和编辑数据；限制后分享链接与他人收藏中将不可公开访问。
        </p>
        <Input.TextArea
          rows={3}
          value={reason}
          maxLength={200}
          onChange={(e) => setReason(e.target.value)}
          placeholder="处理原因"
        />
      </Modal>
      <Modal
        title={resource ? "编辑系统素材" : "新增系统素材"}
        open={resourceOpen}
        confirmLoading={busy}
        onCancel={() => setResourceOpen(false)}
        onOk={async () => {
          try {
            const values = await resourceForm.validateFields();
            const config = JSON.parse(values.config);
            void run(async () => {
              await consoleApi(
                `/album-resources/${encodeURIComponent(values.id)}`,
                send({ ...values, config }, "PUT"),
              );
              setResourceOpen(false);
            }, "素材已保存");
          } catch (e) {
            if (e instanceof SyntaxError) message.error("配置不是有效 JSON");
          }
        }}
      >
        <Form form={resourceForm} layout="vertical">
          <Form.Item
            name="id"
            label="资源 ID"
            rules={[{ required: true }, { pattern: /^[a-zA-Z0-9_-]{1,40}$/ }]}
          >
            <Input disabled={!!resource} />
          </Form.Item>
          <Form.Item name="name" label="名称" rules={[{ required: true }]}>
            <Input maxLength={50} />
          </Form.Item>
          <Form.Item name="kind" label="类型">
            <Select
              options={[
                { value: "SHELF", label: "书架" },
                { value: "STICKER", label: "系统贴纸" },
                { value: "BACKGROUND", label: "背景" },
              ]}
            />
          </Form.Item>
          <Form.Item name="status" label="状态">
            <Select
              options={[
                { value: "PUBLISHED", label: "上架" },
                { value: "OFFLINE", label: "下架" },
              ]}
            />
          </Form.Item>
          <Form.Item name="sort_order" label="排序">
            <InputNumber />
          </Form.Item>
          <Form.Item
            name="config"
            label="配置 JSON"
            rules={[{ required: true }]}
          >
            <Input.TextArea rows={5} maxLength={8000} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}

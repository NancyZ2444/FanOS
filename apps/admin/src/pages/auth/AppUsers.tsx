import { useEffect, useRef, useState } from "react";
import dayjs from "dayjs";
import {
  Link,
  useNavigate,
  useParams,
  useSearchParams,
} from "react-router-dom";
import {
  Alert,
  App,
  Avatar,
  Button,
  Checkbox,
  DatePicker,
  Descriptions,
  Empty,
  Input,
  Select,
  Space,
  Spin,
  Tabs,
  Tag,
} from "antd";
import {
  PageHeader,
  FilterBar,
  TableToolbar,
  Table,
  RowActions,
  RecordId,
  Modal,
  Form,
} from "../../components/admin";
import { send } from "../../api/client";
import { formatTime } from "../../design/format";
import {
  authApi,
  authorizationLabel,
  channelLabel,
  filtersQuery,
  LoadError,
  useAuthMeta,
} from "./shared";

const statuses = [
  { value: "", label: "全部状态" },
  { value: "normal", label: "正常" },
  { value: "banned", label: "已封禁" },
];
const bindingOptions = (label: string) => [
  { value: "", label: `${label}：全部` },
  { value: "bound", label: `${label}：已绑定` },
  { value: "unbound", label: `${label}：未绑定` },
];
const userName = (r: any) => r.name || r.nickname || r.id;
const mask = (r: any) => r.phone_masked || r.masked_phone || "未绑定手机号";
function Binding({ value }: { value: any }) {
  if (!value?.bound) return <span className="muted">未绑定</span>;
  return (
    <div className="cell-stack">
      <span>已绑定</span>
      <small>{authorizationLabel(value.authorization_status)}</small>
    </div>
  );
}

export default function AppUsers() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const initial = Object.fromEntries(params.entries());
  const [draft, setDraft] = useState<Record<string, string>>(initial);
  const [data, setData] = useState<any>({ items: [], total: 0 });
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [action, setAction] = useState<{ user: any; kind: string }>();
  const { can, error: metaError, retry } = useAuthMeta();
  const sequence = useRef(0);
  const load = async () => {
    const seq = ++sequence.current;
    setLoading(true);
    setError("");
    try {
      const result = await authApi(
        `/users?${filtersQuery({ ...Object.fromEntries(params), page: params.get("page") || 1, page_size: 20 })}`,
      );
      if (seq === sequence.current) setData(result);
    } catch (e) {
      if (seq === sequence.current) setError((e as Error).message);
    } finally {
      if (seq === sequence.current) setLoading(false);
    }
  };
  useEffect(() => {
    load();
  }, [params.toString()]);
  const reset = () => {
    setDraft({});
    setParams({});
  };
  const field = (key: string, value: string) =>
    setDraft((d) => ({ ...d, [key]: value }));
  return (
    <>
      <PageHeader
        title="App 用户"
        description="查看 FanOS 用户、登录方式及平台关联信息。App 用户和登录白名单不会获得后台权限。"
      />
      <LoadError error={metaError} retry={retry} />
      <LoadError error={error} retry={load} />
      <FilterBar
        onReset={reset}
        onSearch={() => setParams(filtersQuery({ ...draft, page: 1 }))}
        advanced={
          <DatePicker.RangePicker
            aria-label="注册时间范围"
            value={
              draft.registered_from && draft.registered_to
                ? [dayjs(draft.registered_from), dayjs(draft.registered_to)]
                : null
            }
            onChange={(v) =>
              setDraft((d) => ({
                ...d,
                registered_from: v?.[0]?.startOf("day").toISOString() || "",
                registered_to: v?.[1]?.endOf("day").toISOString() || "",
              }))
            }
          />
        }
      >
        <Input
          aria-label="用户关键词"
          placeholder="用户 ID、昵称或完整手机号（精确匹配）"
          value={draft.q || ""}
          onChange={(e) => field("q", e.target.value)}
          style={{ width: 320 }}
          allowClear
        />
        <Select
          aria-label="账号状态"
          value={draft.status || ""}
          options={statuses}
          onChange={(v) => field("status", v)}
          style={{ width: 140 }}
        />
        {["wechat", "weibo", "qq"].map((p) => (
          <Select
            key={p}
            aria-label={`${channelLabel(p)}绑定`}
            value={draft[p] || ""}
            options={bindingOptions(channelLabel(p))}
            onChange={(v) => field(p, v)}
            style={{ width: 150 }}
          />
        ))}
        <Select
          aria-label="测试登录"
          value={draft.whitelist || ""}
          options={[
            { value: "", label: "测试登录：全部" },
            { value: "effective", label: "有效白名单" },
            { value: "ineffective", label: "普通短信" },
          ]}
          onChange={(v) => field("whitelist", v)}
          style={{ width: 160 }}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar actions={<Button onClick={load}>刷新</Button>}>
          共 {data.total} 位 App 用户
        </TableToolbar>
        <Table
          rowKey="id"
          loading={loading}
          dataSource={data.items}
          filtered={!!params.toString()}
          onReset={reset}
          locale={{ emptyText: <Empty description="暂无用户" /> }}
          scroll={{ x: 1420 }}
          pagination={{
            current: Number(params.get("page") || 1),
            pageSize: 20,
            showSizeChanger: false,
            total: data.total,
            onChange: (page) =>
              setParams(filtersQuery({ ...Object.fromEntries(params), page })),
          }}
          columns={[
            {
              title: "用户信息",
              key: "user",
              width: 260,
              render: (_, r: any) => (
                <Space>
                  <Avatar src={r.avatar_url}>{userName(r).slice(0, 1)}</Avatar>
                  <div className="cell-stack">
                    <Link to={`/operations/users/${r.id}`}>{userName(r)}</Link>
                    <RecordId value={r.id} />
                  </div>
                </Space>
              ),
            },
            {
              title: "手机号 / 状态",
              key: "phone",
              render: (_, r: any) => (
                <div className="cell-stack">
                  <span>{mask(r)}</span>
                  <Tag color={r.status === "banned" ? "error" : "success"}>
                    {r.status === "banned" ? "已封禁" : "正常"}
                  </Tag>
                </div>
              ),
            },
            {
              title: "微信",
              key: "wechat",
              render: (_, r: any) => <Binding value={r.wechat} />,
            },
            {
              title: "微博",
              key: "weibo",
              render: (_, r: any) => (
                <>
                  <Binding value={r.weibo} />
                  {r.weibo?.bound && (
                    <small>主页{r.weibo_visible ? "展示" : "隐藏"}</small>
                  )}
                </>
              ),
            },
            {
              title: "QQ",
              key: "qq",
              render: (_, r: any) => <Binding value={r.qq} />,
            },
            {
              title: "测试登录",
              key: "test",
              render: (_, r: any) => (
                <Tag color={r.whitelist_effective ? "purple" : "default"}>
                  {r.whitelist_effective ? "当前环境有效白名单" : "普通短信"}
                </Tag>
              ),
            },
            {
              title: "收藏 / 心愿",
              key: "counts",
              render: (_, r: any) =>
                `${r.collection_count ?? 0} / ${r.wishlist_count ?? 0}`,
            },
            {
              title: "注册 / 最近登录",
              key: "time",
              render: (_, r: any) => (
                <div className="cell-stack">
                  <span>{formatTime(r.created_at)}</span>
                  <small>
                    {formatTime(r.last_login_at)} ·{" "}
                    {channelLabel(r.last_login_channel)}
                  </small>
                </div>
              ),
            },
            {
              title: "操作",
              key: "actions",
              fixed: "right",
              width: 140,
              render: (_, r: any) => (
                <RowActions
                  onView={() => navigate(`/operations/users/${r.id}`)}
                  items={[
                    ...(can("auth.whitelist.manage") && r.has_phone !== false
                      ? [
                          {
                            key: "whitelist",
                            label: r.whitelist_id ? "查看白名单" : "加入白名单",
                            onClick: () =>
                              navigate(
                                `/operations/login-whitelist?user_id=${encodeURIComponent(r.id)}`,
                              ),
                          },
                        ]
                      : []),
                    ...(can("auth.users.manage")
                      ? [
                          {
                            key: "ban",
                            label: r.status === "banned" ? "解封" : "封禁",
                            danger: r.status !== "banned",
                            onClick: () =>
                              setAction({
                                user: r,
                                kind: r.status === "banned" ? "unban" : "ban",
                              }),
                          },
                          {
                            key: "sessions",
                            label: "下线 App 会话",
                            onClick: () =>
                              setAction({ user: r, kind: "revoke_sessions" }),
                          },
                        ]
                      : []),
                    ...(can("auth.users.password") && r.has_phone !== false
                      ? [
                          {
                            key: "password_reset",
                            label: "重置登录密码",
                            danger: true,
                            onClick: () =>
                              setAction({ user: r, kind: "password_reset" }),
                          },
                        ]
                      : []),
                  ]}
                />
              ),
            },
          ]}
        />
      </section>
      {action && (
        <UserAction
          action={action}
          onClose={() => setAction(undefined)}
          onSaved={load}
        />
      )}
    </>
  );
}

export function UserAction({
  action,
  onClose,
  onSaved,
}: {
  action: { user: any; kind: string; identity?: any };
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form] = Form.useForm();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const saving = useRef(false);
  const { message } = App.useApp();
  const titles: Record<string, string> = {
    ban: "封禁 App 用户",
    unban: "解除封禁",
    revoke_sessions: "下线全部 App 会话",
    note: "编辑内部备注",
    unbind: "解除平台绑定",
    password_reset: "重置 App 登录密码",
  };
  const save = async () => {
    if (saving.current) return;
    saving.current = true;
    try {
      const values = await form.validateFields();
      setBusy(true);
      setError("");
      const payload =
        action.kind === "password_reset"
          ? {
              new_password: values.new_password,
              reason: values.reason,
              confirmed: values.confirmed,
              expected_version: action.user.version,
            }
          : {
              ...values,
              action: action.kind,
              expected_version: action.identity?.version ?? action.user.version,
              banned_until: values.banned_until?.toISOString(),
            };
      const result = await authApi(
        action.kind === "unbind"
          ? `/users/${action.user.id}/identities/${action.identity.provider}/unbind`
          : action.kind === "password_reset"
            ? `/users/${action.user.id}/password-reset`
            : `/users/${action.user.id}/actions`,
        send(payload),
      );
      if (action.kind === "unbind")
        message.info(
          result.provider_revoked === true
            ? "本地解绑及平台撤销已完成"
            : "本地解绑已完成；平台授权撤销结果请查看操作记录",
        );
      else
        message.success(
          action.kind === "password_reset"
            ? "密码已重置，全部 App 会话已下线"
            : "操作已完成",
        );
      form.resetFields();
      onClose();
      onSaved();
    } catch (e) {
      if (e instanceof Error) setError(e.message);
    } finally {
      saving.current = false;
      setBusy(false);
    }
  };
  return (
    <Modal
      open
      title={titles[action.kind]}
      onCancel={() => {
        if (!saving.current) {
          form.resetFields();
          onClose();
        }
      }}
      onOk={save}
      confirmLoading={busy}
      cancelButtonProps={{ disabled: busy }}
      okButtonProps={{ danger: action.kind === "password_reset" }}
      okText={action.kind === "password_reset" ? "重置密码" : "确认处理"}
    >
      <p>
        {userName(action.user)} · {mask(action.user)}
      </p>
      <Alert
        showIcon
        type="warning"
        message={
          action.kind === "unbind"
            ? "仅解除当前平台身份，无法再通过该身份登录原账号；资产保留，微博主页展示关闭。平台撤销可能需要额外处理。"
            : action.kind === "password_reset"
              ? "重置后旧密码失效，全部 App 会话下线。用户编号、收藏、卡册等资产保留；封禁状态保持不变。新密码不会在详情或操作记录中显示。"
              : "仅影响 App 用户，不改变后台管理员身份，不删除业务记录。封禁或下线后需重新登录。"
        }
      />
      <LoadError error={error} />
      <Form
        form={form}
        initialValues={{ internal_note: action.user.internal_note }}
        style={{ marginTop: 16 }}
      >
        {action.kind === "password_reset" && (
          <>
            <Form.Item
              name="new_password"
              label="新密码"
              rules={[
                { required: true, message: "请输入新密码" },
                {
                  validator: (_, value) =>
                    !value || /^(?=.*[A-Za-z])(?=.*[0-9])\S{8,64}$/.test(value)
                      ? Promise.resolve()
                      : Promise.reject(
                          new Error(
                            "密码需为 8–64 位，包含字母和数字，不能含空格",
                          ),
                        ),
                },
              ]}
            >
              <Input.Password autoComplete="new-password" maxLength={64} />
            </Form.Item>
            <Form.Item
              name="confirm_password"
              label="确认新密码"
              dependencies={["new_password"]}
              rules={[
                { required: true, message: "请再次输入新密码" },
                {
                  validator: (_, value) =>
                    !value || value === form.getFieldValue("new_password")
                      ? Promise.resolve()
                      : Promise.reject(new Error("两次输入的密码不一致")),
                },
              ]}
            >
              <Input.Password autoComplete="new-password" maxLength={64} />
            </Form.Item>
          </>
        )}
        {action.kind === "note" && (
          <Form.Item name="internal_note" label="内部备注">
            <Input.TextArea rows={3} maxLength={2000} />
          </Form.Item>
        )}
        <Form.Item
          name="reason"
          label={action.kind === "ban" ? "内部处理原因" : "处理原因"}
          rules={[{ required: true, whitespace: true, message: "请填写原因" }]}
          extra={
            action.kind === "password_reset"
              ? "请填写内部处理原因，不要填写密码或验证码。"
              : undefined
          }
        >
          <Input.TextArea maxLength={500} rows={3} />
        </Form.Item>
        {action.kind === "password_reset" && (
          <Form.Item
            name="confirmed"
            valuePropName="checked"
            rules={[
              {
                validator: (_, value) =>
                  value === true
                    ? Promise.resolve()
                    : Promise.reject(
                        new Error("请确认重置密码并下线全部 App 会话"),
                      ),
              },
            ]}
          >
            <Checkbox>确认重置该用户密码，并下线其全部 App 会话</Checkbox>
          </Form.Item>
        )}
        {action.kind === "ban" && (
          <>
            <Form.Item
              name="public_message"
              label="用户可见说明"
              rules={[
                {
                  required: true,
                  whitespace: true,
                  message: "请填写可公开说明",
                },
              ]}
            >
              <Input.TextArea rows={2} maxLength={300} />
            </Form.Item>
            <Form.Item name="banned_until" label="封禁截止时间（选填）">
              <DatePicker showTime style={{ width: "100%" }} />
            </Form.Item>
          </>
        )}
        {action.kind === "unbind" && (
          <>
            <p>
              {channelLabel(action.identity.provider)} ·{" "}
              {action.identity.subject_masked || "脱敏身份"}
            </p>
            <Form.Item
              name="ticket_number"
              label="工单编号"
              rules={[{ required: true }]}
            >
              <Input />
            </Form.Item>
            <Form.Item
              name="identity_verified"
              valuePropName="checked"
              rules={[
                {
                  validator: (_, v) =>
                    v
                      ? Promise.resolve()
                      : Promise.reject(new Error("请先完成身份核验")),
                },
              ]}
            >
              <Checkbox>已完成身份核验</Checkbox>
            </Form.Item>
          </>
        )}
      </Form>
    </Modal>
  );
}

export function AppUserDetail() {
  const { userId } = useParams();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const [data, setData] = useState<any>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [action, setAction] = useState<any>();
  const [phone, setPhone] = useState("");
  const [reveal, setReveal] = useState(false);
  const [form] = Form.useForm();
  const [revealError, setRevealError] = useState("");
  const { can } = useAuthMeta();
  const load = async () => {
    setError("");
    setBusy(true);
    try {
      setData(await authApi(`/users/${userId}`));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    setPhone("");
    load();
  }, [userId]);
  const u = data?.user;
  const actionButton = (kind: string, label: string) => (
    <Button
      onClick={() =>
        setAction({
          user: {
            ...u,
            internal_note: data.internal_note,
            version: data.version,
          },
          kind,
        })
      }
    >
      {label}
    </Button>
  );
  return (
    <>
      <PageHeader
        title="App 用户详情"
        description="账号处置不会授予后台权限，也不会删除用户资产。"
        actions={<Button onClick={() => navigate(-1)}>返回列表</Button>}
      />
      <LoadError error={error} retry={load} />
      {busy && <Spin />}
      {u && (
        <>
          <section className="panel" style={{ padding: 24, marginBottom: 24 }}>
            <Space align="start">
              <Avatar src={u.avatar_url} size={56}>
                {userName(u).slice(0, 1)}
              </Avatar>
              <div>
                <h2>{userName(u)}</h2>
                <RecordId value={u.id} />
                <p>
                  {phone || mask(u)} ·{" "}
                  {u.status === "banned" ? "已封禁" : "正常"}
                </p>
                <p className="muted">
                  注册于 {formatTime(u.created_at)} · 最近登录{" "}
                  {formatTime(u.last_login_at)} ·{" "}
                  {u.whitelist_effective ? "有效白名单" : "普通短信"}
                </p>
              </div>
            </Space>
            <Space wrap>
              {can("auth.whitelist.manage") && u.has_phone !== false && (
                <Button
                  onClick={() =>
                    navigate(
                      `/operations/login-whitelist?user_id=${encodeURIComponent(u.id)}`,
                    )
                  }
                >
                  {u.whitelist_id ? "查看白名单" : "加入白名单"}
                </Button>
              )}
              {can("auth.users.manage") && (
                <>
                  {actionButton("revoke_sessions", "下线全部 App 会话")}
                  {actionButton(
                    u.status === "banned" ? "unban" : "ban",
                    u.status === "banned" ? "解封" : "封禁",
                  )}
                </>
              )}
              {can("auth.users.password") && u.has_phone !== false && (
                <RowActions
                  items={[
                    {
                      key: "password_reset",
                      label: "重置登录密码",
                      danger: true,
                      onClick: () =>
                        setAction({
                          user: { ...u, version: data.version },
                          kind: "password_reset",
                        }),
                    },
                  ]}
                />
              )}
              {can("auth.users.sensitive") && (
                <Button
                  onClick={() => {
                    setReveal(true);
                    form.resetFields();
                    setRevealError("");
                  }}
                >
                  查看完整手机号（审计）
                </Button>
              )}
              {phone && (
                <Button
                  onClick={async () => {
                    try {
                      const result = await authApi(
                        `/users/${userId}/sensitive`,
                        send({ reason: "复制已授权查看的客服核验号码" }),
                      );
                      await navigator.clipboard.writeText(result.phone);
                    } catch (e) {
                      setError((e as Error).message);
                    }
                  }}
                >
                  复制号码（审计）
                </Button>
              )}
            </Space>
          </section>
          <Tabs
            activeKey={params.get("tab") || "profile"}
            onChange={(tab) => setParams({ tab })}
            items={[
              {
                key: "profile",
                label: "基础资料",
                children: (
                  <section className="panel" style={{ padding: 24 }}>
                    <Descriptions
                      column={2}
                      items={[
                        {
                          key: "bio",
                          label: "简介",
                          children: data.bio || "未填写",
                        },
                        {
                          key: "level",
                          label: "等级 / 经验",
                          children: `${data.level ?? "—"} / ${data.experience ?? "—"}`,
                        },
                        {
                          key: "favorites",
                          label: "本命",
                          children:
                            (data.favorites || u.favorites || [])
                              .map((v: any) =>
                                typeof v === "string" ? v : v.name,
                              )
                              .join("、") || "未设置",
                        },
                        ...Object.entries(data.stats || {}).map(
                          ([key, value]) => ({
                            key,
                            label:
                              (
                                {
                                  collection_count: "已拥有",
                                  wishlist_count: "心愿单",
                                  album_count: "卡册",
                                  photo_count: "照片",
                                  following_count: "关注",
                                  follower_count: "粉丝",
                                } as Record<string, string>
                              )[key] || key,
                            children: String(value),
                          }),
                        ),
                        {
                          key: "note",
                          label: "内部备注",
                          children: data.internal_note || "未填写",
                        },
                      ]}
                    />
                    {can("auth.users.manage") &&
                      actionButton("note", "编辑内部备注")}
                  </section>
                ),
              },
              {
                key: "identities",
                label: "平台绑定",
                children: (
                  <Space
                    direction="vertical"
                    style={{ width: "100%" }}
                    size={16}
                  >
                    <section className="panel" style={{ padding: 24 }}>
                      <h3>手机号</h3>
                      <p>{mask(u)}</p>
                    </section>
                    {["wechat", "weibo", "qq"].map((provider) => {
                      const identity = (data.identities || []).find(
                        (v: any) => v.provider === provider,
                      );
                      return (
                        <section
                          key={provider}
                          className="panel"
                          style={{ padding: 24 }}
                        >
                          <h3>{channelLabel(provider)}</h3>
                          {identity?.bound ? (
                            <>
                              <Descriptions
                                column={2}
                                items={[
                                  {
                                    key: "name",
                                    label: "平台昵称",
                                    children: identity.display_name || "—",
                                  },
                                  {
                                    key: "subject",
                                    label: "身份标识",
                                    children: identity.subject_masked,
                                  },
                                  {
                                    key: "scope",
                                    label: "应用范围",
                                    children: identity.app_scope || "—",
                                  },
                                  {
                                    key: "auth",
                                    label: "授权状态",
                                    children: authorizationLabel(
                                      identity.authorization_status,
                                    ),
                                  },
                                  {
                                    key: "created",
                                    label: "绑定时间",
                                    children: formatTime(identity.bound_at),
                                  },
                                  {
                                    key: "updated",
                                    label: "资料更新时间",
                                    children: formatTime(identity.updated_at),
                                  },
                                ]}
                              />
                              {can("auth.identities.unbind") && (
                                <Button
                                  danger
                                  onClick={() =>
                                    setAction({
                                      user: u,
                                      identity,
                                      kind: "unbind",
                                    })
                                  }
                                >
                                  解除{channelLabel(provider)}绑定
                                </Button>
                              )}
                            </>
                          ) : (
                            <p className="muted">未绑定</p>
                          )}
                        </section>
                      );
                    })}
                  </Space>
                ),
              },
              {
                key: "logins",
                label: "登录记录",
                children: (
                  <Table
                    rowKey="id"
                    dataSource={data.login_records || []}
                    pagination={{ pageSize: 20 }}
                    columns={[
                      {
                        title: "时间",
                        dataIndex: "created_at",
                        render: formatTime,
                      },
                      {
                        title: "渠道",
                        dataIndex: "channel",
                        render: channelLabel,
                      },
                      {
                        title: "认证方式",
                        dataIndex: "method",
                        render: channelLabel,
                      },
                      { title: "结果", dataIndex: "result" },
                      { title: "错误原因", dataIndex: "error_code" },
                      { title: "设备摘要", dataIndex: "device_summary" },
                      { title: "脱敏 IP", dataIndex: "ip_masked" },
                      { title: "请求 ID", dataIndex: "request_id" },
                    ]}
                  />
                ),
              },
              {
                key: "operations",
                label: "操作记录",
                children: (
                  <Table
                    rowKey="id"
                    dataSource={data.operation_records || []}
                    pagination={{ pageSize: 20 }}
                    columns={[
                      {
                        title: "时间",
                        dataIndex: "created_at",
                        render: formatTime,
                      },
                      { title: "操作者", dataIndex: "actor_name" },
                      { title: "来源", dataIndex: "source" },
                      {
                        title: "动作",
                        dataIndex: "action",
                        render: (value: string) =>
                          value === "user.password_reset"
                            ? "重置 App 登录密码"
                            : value,
                      },
                      {
                        title: "脱敏变化",
                        key: "change",
                        render: (_, r: any) => r.summary || "—",
                      },
                      { title: "原因", dataIndex: "reason" },
                      { title: "工单", dataIndex: "ticket_number" },
                      { title: "结果", dataIndex: "result" },
                    ]}
                  />
                ),
              },
            ]}
          />
        </>
      )}
      {!u && !busy && !error && <Empty description="用户不存在" />}
      {action && (
        <UserAction
          action={action}
          onClose={() => setAction(undefined)}
          onSaved={load}
        />
      )}
      <Modal
        open={reveal}
        title="查看敏感手机号"
        onCancel={() => setReveal(false)}
        onOk={async () => {
          try {
            const v = await form.validateFields();
            const result = await authApi(`/users/${userId}/sensitive`, send(v));
            setPhone(result.phone);
            setReveal(false);
          } catch (e) {
            if (e instanceof Error) setRevealError(e.message);
          }
        }}
      >
        <LoadError error={revealError} />
        <Alert
          type="info"
          message="本次访问将记录审计，仅用于已授权的客服核验。"
        />
        <Form form={form}>
          <Form.Item
            name="reason"
            label="查看原因"
            rules={[{ required: true, whitespace: true }]}
          >
            <Input.TextArea maxLength={300} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}

import { useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  Alert,
  App,
  Button,
  Checkbox,
  DatePicker,
  Descriptions,
  Input,
  Select,
  Space,
  Switch,
  Tag,
} from "antd";
import dayjs from "dayjs";
import {
  Drawer,
  FilterBar,
  Form,
  Modal,
  PageHeader,
  RowActions,
  Table,
  TableToolbar,
} from "../../components/admin";
import { send } from "../../api/client";
import { formatTime } from "../../design/format";
import { authApi, filtersQuery, LoadError, useAuthMeta } from "./shared";

export default function LoginWhitelist() {
  const [params, setParams] = useSearchParams();
  const [draft, setDraft] = useState<Record<string, string>>(
    Object.fromEntries(params),
  );
  const [data, setData] = useState<any>({ items: [], total: 0 });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [edit, setEdit] = useState<any>();
  const [detail, setDetail] = useState<any>();
  const [toggle, setToggle] = useState<any>();
  const [code, setCode] = useState(false);
  const [actionForm] = Form.useForm();
  const [actionError, setActionError] = useState("");
  const { message } = App.useApp();
  const { meta, can, error: metaError, retry } = useAuthMeta();
  const seq = useRef(0);
  const load = async () => {
    const id = ++seq.current;
    setLoading(true);
    setError("");
    try {
      const d = await authApi(
        `/login-whitelist?${filtersQuery({ ...Object.fromEntries(params), page: params.get("page") || 1, page_size: 20 })}`,
      );
      if (id === seq.current) setData(d);
    } catch (e) {
      if (id === seq.current) setError((e as Error).message);
    } finally {
      if (id === seq.current) setLoading(false);
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
  const newRecord = () =>
    setEdit({ user_id: params.get("user_id") || undefined });
  return (
    <>
      <PageHeader
        title="登录白名单"
        description="管理测试阶段使用固定验证码登录 App 的手机号；其余手机号使用真实短信。不会创建用户或授予后台权限。"
        actions={
          can("auth.test_code.manage") && (
            <Button onClick={() => setCode(true)}>测试验证码配置</Button>
          )
        }
      />
      <LoadError error={metaError} retry={retry} />
      <LoadError error={error} retry={load} />
      {data.environment && (
        <Alert
          showIcon
          type={data.enabled ? "info" : "warning"}
          message={`当前环境：${data.environment} · 测试能力${data.enabled ? "已开启" : "已关闭"} · 当前有效 ${data.effective_count ?? 0} 个`}
          description={
            !data.enabled
              ? "环境测试能力关闭，所有号码使用真实短信；启用的白名单记录不代表当前生效。"
              : "有效白名单使用服务端固定码，本页面不显示任何验证码。"
          }
          style={{ marginBottom: 16 }}
        />
      )}
      <FilterBar
        onReset={reset}
        onSearch={() => setParams(filtersQuery({ ...draft, page: 1 }))}
        advanced={
          <DatePicker.RangePicker
            aria-label="到期时间范围"
            value={
              draft.expires_from && draft.expires_to
                ? [dayjs(draft.expires_from), dayjs(draft.expires_to)]
                : null
            }
            onChange={(v) =>
              setDraft((d) => ({
                ...d,
                expires_from: v?.[0]?.startOf("day").toISOString() || "",
                expires_to: v?.[1]?.endOf("day").toISOString() || "",
              }))
            }
          />
        }
      >
        <Input
          aria-label="白名单关键词"
          style={{ width: 320 }}
          value={draft.q || ""}
          onChange={(e) => field("q", e.target.value)}
          placeholder="手机号、关联用户 ID 或用途"
          allowClear
        />
        <Select
          aria-label="白名单状态"
          value={draft.status || ""}
          onChange={(v) => field("status", v)}
          style={{ width: 150 }}
          options={[
            { value: "", label: "全部状态" },
            { value: "enabled", label: "启用" },
            { value: "disabled", label: "停用" },
            { value: "expired", label: "已到期" },
          ]}
        />
        <Select
          aria-label="注册状态"
          value={draft.registered || ""}
          onChange={(v) => field("registered", v)}
          style={{ width: 150 }}
          options={[
            { value: "", label: "全部注册状态" },
            { value: "true", label: "已注册" },
            { value: "false", label: "未注册" },
          ]}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar
          actions={
            <Space>
              <Button onClick={load}>刷新</Button>
              {can("auth.whitelist.manage") && (
                <Button type="primary" onClick={newRecord}>
                  新增白名单
                </Button>
              )}
            </Space>
          }
        >
          共 {data.total} 条记录
        </TableToolbar>
        <Table
          rowKey="id"
          dataSource={data.items}
          loading={loading}
          filtered={!!params.toString()}
          onReset={reset}
          scroll={{ x: 1250 }}
          pagination={{
            current: Number(params.get("page") || 1),
            pageSize: 20,
            showSizeChanger: false,
            total: data.total,
            onChange: (page) =>
              setParams(filtersQuery({ ...Object.fromEntries(params), page })),
          }}
          columns={[
            { title: "手机号", dataIndex: "phone_masked" },
            {
              title: "关联用户",
              key: "user",
              render: (_, r: any) =>
                r.user_id ? (
                  <Link to={`/operations/users/${r.user_id}`}>
                    {r.user_name || r.user_id}
                  </Link>
                ) : (
                  "未注册"
                ),
            },
            {
              title: "记录 / 生效状态",
              key: "status",
              render: (_, r: any) => (
                <div className="cell-stack">
                  <span>
                    {r.status === "expired" || r.status === "EXPIRED"
                      ? "已到期"
                      : r.enabled
                        ? "启用"
                        : "停用"}
                  </span>
                  <Tag color={r.effective ? "purple" : "default"}>
                    {r.effective ? "当前生效" : "当前不生效"}
                  </Tag>
                </div>
              ),
            },
            { title: "有效期至", dataIndex: "expires_at" },
            {
              title: "负责人 / 用途",
              key: "owner",
              render: (_, r: any) => (
                <div className="cell-stack">
                  <span>{r.owner}</span>
                  <small>{r.purpose}</small>
                </div>
              ),
            },
            { title: "最近固定码登录", dataIndex: "last_test_login_at" },
            {
              title: "更新人 / 时间",
              key: "updated",
              render: (_, r: any) => (
                <div className="cell-stack">
                  <span>{r.updated_by || "—"}</span>
                  <small>{formatTime(r.updated_at)}</small>
                </div>
              ),
            },
            {
              title: "操作",
              key: "actions",
              fixed: "right",
              width: 180,
              render: (_, r: any) => (
                <RowActions
                  onView={() => setDetail(r)}
                  onEdit={
                    can("auth.whitelist.manage") ? () => setEdit(r) : undefined
                  }
                  items={
                    can("auth.whitelist.manage")
                      ? [
                          {
                            key: "toggle",
                            label: r.enabled ? "停用" : "启用",
                            danger: r.enabled,
                            onClick: () => {
                              setToggle(r);
                              actionForm.resetFields();
                              setActionError("");
                            },
                          },
                        ]
                      : []
                  }
                />
              ),
            },
          ]}
        />
      </section>
      <Drawer
        open={!!detail}
        title="登录白名单详情"
        onClose={() => setDetail(undefined)}
      >
        <Descriptions
          column={1}
          items={
            detail
              ? [
                  {
                    key: "phone",
                    label: "手机号",
                    children: detail.phone_masked,
                  },
                  { key: "env", label: "环境", children: data.environment },
                  {
                    key: "effective",
                    label: "生效状态",
                    children: detail.effective ? "当前生效" : "当前不生效",
                  },
                  {
                    key: "expiry",
                    label: "有效期至",
                    children: formatTime(detail.expires_at),
                  },
                  { key: "owner", label: "负责人", children: detail.owner },
                  { key: "purpose", label: "用途", children: detail.purpose },
                  {
                    key: "user",
                    label: "关联用户",
                    children: detail.user_id ? (
                      <Link to={`/operations/users/${detail.user_id}`}>
                        {detail.user_id}
                      </Link>
                    ) : (
                      "未注册；首次验证登录后创建"
                    ),
                  },
                ]
              : []
          }
        />
      </Drawer>
      {edit && (
        <WhitelistEditor
          key={edit.id || edit.user_id || "new"}
          record={edit}
          environment={meta?.environment || data.environment}
          onClose={() => setEdit(undefined)}
          onSaved={load}
          onExisting={setEdit}
        />
      )}
      {code && <TestCodeConfig onClose={() => setCode(false)} onSaved={load} />}
      <Modal
        open={!!toggle}
        title={toggle?.enabled ? "停用白名单" : "启用白名单"}
        onCancel={() => setToggle(undefined)}
        okText="确认"
        onOk={async () => {
          if (!toggle) return;
          try {
            const values = await actionForm.validateFields();
            await authApi(
              `/login-whitelist/${toggle.id}`,
              send(
                {
                  ...values,
                  enabled: !toggle.enabled,
                  expected_version: toggle.version,
                },
                "PATCH",
              ),
            );
            message.success("白名单状态已更新");
            setToggle(undefined);
            await load();
          } catch (e) {
            if (e instanceof Error) setActionError(e.message);
          }
        }}
      >
        <p>
          {toggle?.phone_masked} · {data.environment} · 有效期至{" "}
          {formatTime(toggle?.expires_at)}
        </p>
        <Alert
          showIcon
          type="warning"
          message={
            toggle?.enabled
              ? "停用将使未完成固定码挑战失效，不自动撤销已登录会话。下线会话请前往用户详情单独处理。"
              : "已到期记录必须先编辑延长有效期；实际生效仍取决于环境开关。"
          }
        />
        <LoadError error={actionError} />
        <Form form={actionForm}>
          <Form.Item
            name="reason"
            label="处理原因"
            rules={[{ required: true, whitespace: true }]}
          >
            <Input.TextArea rows={2} maxLength={500} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}

function WhitelistEditor({
  record,
  environment,
  onClose,
  onSaved,
  onExisting,
}: {
  record: any;
  environment: string;
  onClose: () => void;
  onSaved: () => void;
  onExisting: (record: any) => void;
}) {
  const [form] = Form.useForm();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [match, setMatch] = useState<any>();
  const [matchError, setMatchError] = useState("");
  const [checking, setChecking] = useState(false);
  const { message } = App.useApp();
  const phone = Form.useWatch("phone", form);
  const sequence = useRef(0);
  useEffect(() => {
    if (record.id) return;
    const seq = ++sequence.current;
    setMatch(undefined);
    setMatchError("");
    setChecking(false);
    if (!record.user_id && !/^1[3-9]\d{9}$/.test(phone || "")) return;
    setChecking(true);
    const timer = setTimeout(
      () =>
        authApi(
          "/login-whitelist/match",
          send(record.user_id ? { user_id: record.user_id } : { phone }),
        )
          .then((d) => {
            if (seq === sequence.current) setMatch(d);
          })
          .catch((e) => {
            if (seq === sequence.current) setMatchError(e.message);
          })
          .finally(() => {
            if (seq === sequence.current) setChecking(false);
          }),
      350,
    );
    return () => clearTimeout(timer);
  }, [phone, record.user_id]);
  const save = async () => {
    try {
      const v = await form.validateFields();
      if (!record.id && (!match || checking || matchError)) {
        setError("请等待手机号匹配成功后再保存");
        return;
      }
      if (!record.id && match?.whitelist_id) {
        setError("已有白名单记录，请查看原记录后编辑");
        return;
      }
      setBusy(true);
      setError("");
      await authApi(
        record.id ? `/login-whitelist/${record.id}` : "/login-whitelist",
        send(
          {
            ...v,
            ...(record.user_id && !record.id
              ? { user_id: record.user_id }
              : {}),
            expires_at: v.expires_at.toISOString(),
            expected_version: record.version,
            authorized: v.authorized === true,
          },
          record.id ? "PATCH" : "POST",
        ),
      );
      message.success("白名单已保存");
      onClose();
      onSaved();
    } catch (e) {
      if (e instanceof Error) setError(e.message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Modal
      open
      title={record.id ? "编辑白名单" : "新增白名单"}
      onCancel={onClose}
      onOk={save}
      confirmLoading={busy}
    >
      <LoadError error={error} />
      <Form
        form={form}
        initialValues={{
          ...record,
          expires_at: record.expires_at ? dayjs(record.expires_at) : undefined,
        }}
      >
        {record.id || record.user_id ? (
          <Form.Item label="手机号（只读）">
            <Input
              value={
                record.phone_masked ||
                match?.phone_masked ||
                "正在读取用户号码…"
              }
              readOnly
            />
          </Form.Item>
        ) : (
          <Form.Item
            name="phone"
            label="手机号"
            rules={[
              { required: true },
              { pattern: /^1[3-9]\d{9}$/, message: "请输入有效大陆手机号" },
            ]}
          >
            <Input addonBefore="+86" maxLength={11} autoComplete="off" />
          </Form.Item>
        )}
        {!record.id && (
          <>
            {checking && <p>正在匹配账号…</p>}
            <LoadError error={matchError} />
            {match && (
              <Alert
                style={{ marginBottom: 16 }}
                type={match.whitelist_id ? "warning" : "info"}
                message={
                  match.whitelist_id
                    ? "该号码已有白名单，请查看并编辑原记录"
                    : match.user_id
                      ? `已关联用户：${match.user_name || match.user_id}`
                      : "该号码未注册，首次完成登录验证后才会创建账号"
                }
                action={
                  match.whitelist_id && (
                    <Button
                      onClick={async () => {
                        try {
                          const original = await authApi(
                            `/login-whitelist/${match.whitelist_id}`,
                          );
                          onExisting(original);
                        } catch (e) {
                          setError((e as Error).message);
                        }
                      }}
                    >
                      查看原记录
                    </Button>
                  )
                }
              />
            )}
          </>
        )}
        <Form.Item label="适用环境">
          <Input readOnly value={environment || "读取中"} />
        </Form.Item>
        <Form.Item
          name="expires_at"
          label="有效期至（北京时间）"
          rules={[
            { required: true, message: "请选择截止时间" },
            {
              validator: (_, v) =>
                !v || v.valueOf() > Date.now()
                  ? Promise.resolve()
                  : Promise.reject(new Error("有效期必须晚于当前时间")),
            },
          ]}
        >
          <DatePicker showTime style={{ width: "100%" }} />
        </Form.Item>
        <Form.Item
          name="owner"
          label="负责人"
          rules={[{ required: true, whitespace: true }]}
        >
          <Input maxLength={80} />
        </Form.Item>
        <Form.Item
          name="purpose"
          label="测试用途"
          rules={[{ required: true, whitespace: true }]}
        >
          <Input.TextArea rows={2} maxLength={300} />
        </Form.Item>
        {record.id ? (
          <Form.Item
            name="reason"
            label="修改原因"
            rules={[{ required: true, whitespace: true }]}
          >
            <Input.TextArea rows={2} maxLength={300} />
          </Form.Item>
        ) : (
          <Form.Item
            name="authorized"
            valuePropName="checked"
            rules={[
              {
                validator: (_, v) =>
                  v
                    ? Promise.resolve()
                    : Promise.reject(new Error("需确认已获授权")),
              },
            ]}
          >
            <Checkbox>已获授权使用该测试号码；保存后默认启用</Checkbox>
          </Form.Item>
        )}
      </Form>
    </Modal>
  );
}

export function TestCodeConfig({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form] = Form.useForm();
  const [config, setConfig] = useState<any>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const { message } = App.useApp();
  const load = () => {
    setError("");
    authApi("/test-login-config")
      .then((d) => {
        setConfig(d);
        form.setFieldsValue({ enabled: d.enabled });
      })
      .catch((e) => setError(e.message));
  };
  useEffect(load, []);
  return (
    <Modal
      open
      title="测试验证码配置"
      onCancel={onClose}
      confirmLoading={busy}
      okButtonProps={{ disabled: !config }}
      onOk={async () => {
        try {
          const v = await form.validateFields();
          setBusy(true);
          setError("");
          const payload = {
            enabled: v.enabled,
            expected_version: config.version,
            reason: v.reason,
            ...(v.default_code ? { default_code: v.default_code } : {}),
          };
          await authApi("/test-login-config", send(payload, "PATCH"));
          const current = await authApi("/test-login-config");
          setConfig(current);
          form.resetFields(["default_code", "confirmation"]);
          message.success("测试验证码配置已生效");
          onClose();
          onSaved();
        } catch (e) {
          if (e instanceof Error) setError(e.message);
        } finally {
          setBusy(false);
        }
      }}
    >
      <LoadError error={error} retry={!config ? load : undefined} />
      {config && (
        <>
          <Descriptions
            column={1}
            items={[
              {
                key: "environment",
                label: "适用环境",
                children: config.environment,
              },
              {
                key: "status",
                label: "当前状态",
                children: `${config.configured ? "已配置" : "未配置"} · 版本 ${config.version}`,
              },
              {
                key: "updated",
                label: "最近更新",
                children: `${formatTime(config.updated_at)} · ${config.updated_by || "—"}`,
              },
            ]}
          />
          <Alert
            type="warning"
            showIcon
            message="影响当前环境全部有效白名单。轮换或关闭会立即使旧固定码挑战失效，普通短信不受影响。原验证码永不回显。"
          />
          <Form form={form} style={{ marginTop: 16 }}>
            <Form.Item name="enabled" label="测试能力" valuePropName="checked">
              <Switch />
            </Form.Item>
            <Form.Item
              name="default_code"
              label="新默认验证码"
              dependencies={["enabled"]}
              rules={[
                { pattern: /^\d{6}$/, message: "请输入 6 位数字，允许前导零" },
                {
                  validator: (_, v) =>
                    form.getFieldValue("enabled") && !config.configured && !v
                      ? Promise.reject(new Error("首次启用前必须配置验证码"))
                      : Promise.resolve(),
                },
              ]}
            >
              <Input.Password
                autoComplete="new-password"
                maxLength={6}
                placeholder={
                  config.configured ? "留空保持现值" : "请输入 6 位数字"
                }
              />
            </Form.Item>
            <Form.Item
              name="confirmation"
              label="确认新验证码"
              dependencies={["default_code"]}
              rules={[
                {
                  validator: (_, v) =>
                    (v || "") === (form.getFieldValue("default_code") || "")
                      ? Promise.resolve()
                      : Promise.reject(new Error("两次输入不一致")),
                },
              ]}
            >
              <Input.Password autoComplete="new-password" maxLength={6} />
            </Form.Item>
            <Form.Item
              name="reason"
              label="修改原因（不得填写验证码）"
              dependencies={["default_code"]}
              rules={[
                { required: true, whitespace: true },
                {
                  validator: (_, v) =>
                    /\d{6}/.test(v || "")
                      ? Promise.reject(new Error("原因中不得包含验证码"))
                      : Promise.resolve(),
                },
              ]}
            >
              <Input.TextArea rows={2} maxLength={300} />
            </Form.Item>
            <Form.Item
              name="acknowledged"
              valuePropName="checked"
              rules={[
                {
                  validator: (_, v) =>
                    v
                      ? Promise.resolve()
                      : Promise.reject(new Error("请确认影响范围")),
                },
              ]}
            >
              <Checkbox>
                确认影响全部当前环境有效白名单及未完成固定码挑战
              </Checkbox>
            </Form.Item>
          </Form>
        </>
      )}
    </Modal>
  );
}

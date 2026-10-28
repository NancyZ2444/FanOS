import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { App, Button, Input, Select, Switch, Tag } from "antd";
import {
  PageHeader,
  FilterBar,
  Form,
  Modal,
  Table,
  TableToolbar,
  RowActions,
} from "../components/admin";
import { consoleApi, send } from "../api/client";
import { roleLabels, type Role } from "../api/types";
import { filtersQuery, LoadError, useAuthMeta } from "./auth/shared";

export default function AdminUsers() {
  const [params, setParams] = useSearchParams();
  const [draft, setDraft] = useState<Record<string, string>>(
    Object.fromEntries(params),
  );
  const [data, setData] = useState<any>({ items: [], total: 0 });
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [record, setRecord] = useState<any>();
  const [mode, setMode] = useState<"edit" | "reset">("edit");
  const [form] = Form.useForm();
  const [saveError, setSaveError] = useState("");
  const [busy, setBusy] = useState(false);
  const { can } = useAuthMeta();
  const { message } = App.useApp();
  const load = async () => {
    setLoading(true);
    setError("");
    try {
      setData(
        await consoleApi(
          "/admins?" +
            filtersQuery({
              ...Object.fromEntries(params),
              page: params.get("page") || 1,
              page_size: 20,
            }),
        ),
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => {
    load();
  }, [params.toString()]);
  const edit = (row: any = {}, kind: "edit" | "reset" = "edit") => {
    setRecord(row);
    setMode(kind);
    setSaveError("");
    form.resetFields();
    form.setFieldsValue({
      role: "content_operator",
      is_active: true,
      ...row,
      password: undefined,
      reason: undefined,
    });
  };
  const reset = () => {
    setDraft({});
    setParams({});
  };
  return (
    <>
      <PageHeader
        title="后台管理员"
        description="独立管理员账号、凭证及后台权限。新增管理员不会创建或关联 App 用户。"
      />
      <LoadError error={error} retry={load} />
      <FilterBar
        onReset={reset}
        onSearch={() => setParams(filtersQuery({ ...draft, page: 1 }))}
      >
        <Input
          value={draft.q || ""}
          onChange={(e) => setDraft((d) => ({ ...d, q: e.target.value }))}
          placeholder="管理员账号或名称"
          style={{ width: 280 }}
        />
        <Select
          value={draft.role || ""}
          style={{ width: 160 }}
          onChange={(role) => setDraft((d) => ({ ...d, role }))}
          options={[
            { value: "", label: "全部角色" },
            ...Object.entries(roleLabels).map(([value, label]) => ({
              value,
              label,
            })),
          ]}
        />
        <Select
          value={draft.status || ""}
          style={{ width: 140 }}
          onChange={(status) => setDraft((d) => ({ ...d, status }))}
          options={[
            { value: "", label: "全部状态" },
            { value: "active", label: "启用" },
            { value: "disabled", label: "停用" },
          ]}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar
          actions={
            <>
              {can("auth.admins.manage") && (
                <Button type="primary" onClick={() => edit()}>
                  新增管理员
                </Button>
              )}
            </>
          }
        >
          共 {data.total ?? data.items.length} 位后台管理员
        </TableToolbar>
        <Table
          rowKey="id"
          loading={loading}
          dataSource={data.items}
          pagination={{
            current: Number(params.get("page") || 1),
            pageSize: 20,
            showSizeChanger: false,
            total: data.total,
            onChange: (page) =>
              setParams(filtersQuery({ ...Object.fromEntries(params), page })),
          }}
          columns={[
            { title: "登录账号", dataIndex: "account" },
            { title: "名称", dataIndex: "name" },
            {
              title: "角色",
              dataIndex: "role",
              render: (r: Role) => roleLabels[r],
            },
            {
              title: "状态",
              dataIndex: "is_active",
              render: (v) => (
                <Tag color={v ? "success" : "default"}>
                  {v ? "启用" : "停用"}
                </Tag>
              ),
            },
            { title: "创建时间", dataIndex: "created_at" },
            { title: "最近后台登录", dataIndex: "last_login_at" },
            {
              title: "操作",
              key: "actions",
              render: (_, r: any) =>
                can("auth.admins.manage") && (
                  <RowActions
                    onEdit={() => edit(r)}
                    items={[
                      {
                        key: "reset",
                        label: "重置凭证",
                        onClick: () => edit(r, "reset"),
                      },
                    ]}
                  />
                ),
            },
          ]}
        />
      </section>
      <Modal
        open={!!record}
        title={
          mode === "reset"
            ? "重置后台凭证"
            : record?.id
              ? "编辑后台管理员"
              : "新增后台管理员"
        }
        onCancel={() => setRecord(undefined)}
        confirmLoading={busy}
        onOk={async () => {
          try {
            const v = await form.validateFields();
            setBusy(true);
            setSaveError("");
            await consoleApi(
              mode === "reset"
                ? `/admins/${record.id}/reset-password`
                : record.id
                  ? `/admins/${record.id}`
                  : "/admins",
              send(
                { ...v, expected_version: record.version },
                mode === "edit" && record.id ? "PATCH" : "POST",
              ),
            );
            message.success("后台账号已更新");
            setRecord(undefined);
            await load();
          } catch (e) {
            if (e instanceof Error) setSaveError(e.message);
          } finally {
            setBusy(false);
          }
        }}
      >
        <LoadError error={saveError} />
        <p>
          权限、停用或凭证变更将按安全策略撤销后台会话；不影响同一人的 App
          身份。
        </p>
        <Form form={form}>
          <Form.Item
            name="account"
            label="管理员登录账号"
            rules={[{ required: mode !== "reset" }]}
          >
            <Input readOnly={!!record?.id} autoComplete="off" maxLength={80} />
          </Form.Item>
          {mode === "edit" && (
            <>
              <Form.Item
                name="name"
                label="显示名称"
                rules={[{ required: true, whitespace: true }]}
              >
                <Input maxLength={40} />
              </Form.Item>
              <Form.Item
                name="role"
                label="后台角色"
                rules={[{ required: true }]}
              >
                <Select
                  options={Object.entries(roleLabels).map(([value, label]) => ({
                    value,
                    label,
                  }))}
                />
              </Form.Item>
              <Form.Item
                name="is_active"
                label="允许后台登录"
                valuePropName="checked"
              >
                <Switch />
              </Form.Item>
            </>
          )}
          {(mode === "reset" || !record?.id) && (
            <Form.Item
              name="password"
              label="新密码"
              rules={[
                { required: true },
                { min: 12, message: "请使用至少 12 位密码" },
              ]}
            >
              <Input.Password autoComplete="new-password" />
            </Form.Item>
          )}
          <Form.Item
            name="reason"
            label="变更原因"
            rules={[{ required: true, whitespace: true }]}
          >
            <Input.TextArea maxLength={300} rows={2} />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}

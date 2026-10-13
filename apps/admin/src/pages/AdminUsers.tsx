import { useSingleSubmit } from "../components/admin";
import {
  TableToolbar,
  FilterBar,
  RowActions,
  BusinessData,
  Drawer,
} from "../components/admin";
import { PageHeader } from "../components/admin";
import { Form, Modal, Table } from "../components/admin";
import { useEffect, useState } from "react";
import { Alert, App, Button, Input, Select, Switch, Tag } from "antd";
import { PlusOutlined } from "@ant-design/icons";
import { consoleApi, send } from "../api/client";
import { roleLabels } from "../api/types";
import type { Role } from "../api/types";
export default function AdminUsers() {
  const { message } = App.useApp();
  const [form] = Form.useForm();
  const [q, setQ] = useState("");
  const [viewRecord, setViewRecord] = useState<any>();
  const [rows, setRows] = useState<any[]>([]);
  const [open, setOpen] = useState(false);
  const [record, setRecord] = useState<any>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const load = () =>
    consoleApi("/admins")
      .then((d) => setRows(d.items))
      .catch((e) => setError(e.message));
  useEffect(() => {
    load();
  }, []);
  const edit = (row?: any) => {
    setRecord(row);
    form.resetFields();
    form.setFieldsValue(row || { role: "content_operator", is_active: true });
    setOpen(true);
  };
  const save = useSingleSubmit(async () => {
    try {
      const data = await form.validateFields();
      setBusy(true);
      await consoleApi(
        record ? `/admins/${record.id}` : "/admins",
        send(data, record ? "PATCH" : "POST"),
      );
      message.success("后台账号已保存");
      setOpen(false);
      await load();
    } catch (e) {
      if (e instanceof Error) message.error(e.message);
    } finally {
      setBusy(false);
    }
  });
  return (
    <>
      <PageHeader title="管理员账号" />
      {error && <Alert type="error" message={error} />}
      <FilterBar onReset={() => setQ("")}>
        <Input
          allowClear
          placeholder="搜索管理员姓名或手机号"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar
          actions={
            <>
              <Button
                type="primary"
                icon={<PlusOutlined aria-hidden="true" />}
                onClick={() => edit()}
              >
                新增管理员
              </Button>
            </>
          }
        >
          后台账号
        </TableToolbar>
        <Table
          rowKey="id"
          dataSource={rows.filter((r) =>
            [r.name, r.phone].some((v) => v?.includes(q)),
          )}
          filtered={!!q}
          onReset={() => setQ("")}
          onCreate={() => edit()}
          createLabel="新增管理员"
          pagination={{ defaultPageSize: 10 }}
          columns={[
            { title: "管理员", dataIndex: "name" },
            { title: "手机号", dataIndex: "phone" },
            {
              title: "角色",
              dataIndex: "role",
              render: (v: Role) => roleLabels[v],
            },
            {
              title: "状态",
              dataIndex: "is_active",
              render: (v) => (
                <Tag color={v ? "success" : "default"}>
                  {v ? "正常" : "已停用"}
                </Tag>
              ),
            },
            {
              title: "创建时间",
              dataIndex: "created_at",
              render: (v) => new Date(v).toLocaleDateString("zh-CN"),
            },
            {
              title: "操作",
              key: "action",
              render: (_, r) => (
                <RowActions
                  onView={() => setViewRecord(r)}
                  onEdit={() => edit(r)}
                />
              ),
            },
          ]}
        />
      </section>
      <Drawer
        open={!!viewRecord}
        title="管理员详情"
        onClose={() => setViewRecord(undefined)}
        extra={
          <Button
            onClick={() => {
              edit(viewRecord);
              setViewRecord(undefined);
            }}
          >
            编辑
          </Button>
        }
      >
        <BusinessData data={viewRecord} />
      </Drawer>
      <Modal
        open={open}
        title={record ? "编辑管理员权限" : "新增管理员"}
        onCancel={() => setOpen(false)}
        onOk={save}
        confirmLoading={busy}
        okText="保存"
        cancelText="取消"
      >
        <Form form={form} layout="vertical">
          {!record && (
            <>
              <Form.Item
                name="name"
                label="姓名"
                rules={[{ required: true, message: "请填写姓名" }]}
              >
                <Input maxLength={40} />
              </Form.Item>
              <Form.Item
                name="phone"
                label="登录手机号"
                rules={[
                  { required: true },
                  { pattern: /^1\d{10}$/, message: "请输入 11 位手机号" },
                ]}
              >
                <Input />
              </Form.Item>
            </>
          )}
          <Form.Item name="role" label="后台角色" rules={[{ required: true }]}>
            <Select
              options={Object.entries(roleLabels).map(([value, label]) => ({
                value,
                label,
              }))}
            />
          </Form.Item>
          <Form.Item name="is_active" label="允许登录" valuePropName="checked">
            <Switch />
          </Form.Item>
          <Alert
            type="info"
            showIcon
            message="角色修改立即生效，并写入操作日志。"
          />
        </Form>
      </Modal>
    </>
  );
}

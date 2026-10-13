import { useSingleSubmit } from "../components/admin";
import { displayValue } from "../design/format";
import { FilterBar, TableToolbar, RowActions } from "../components/admin";
import { PageHeader } from "../components/admin";
import { Drawer, Form, Modal, Table } from "../components/admin";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { App, Button, Input, Select, Tag } from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import type { CatalogTag, TagType } from "../components/TagSelect";
import { StatusTag } from "../components/shared";
const types: TagType[] = ["ALBUM", "EVENT", "OTHER", "CARD"];
export default function Tags() {
  const { actor, reload } = useConsole();
  const { message, modal } = App.useApp();
  const navigate = useNavigate();
  const [items, setItems] = useState<CatalogTag[]>([]);
  const [scope, setScope] = useState<string>();
  const [q, setQ] = useState("");
  const [status, setStatus] = useState<string>();
  const [editing, setEditing] = useState<CatalogTag | null>();
  const [contents, setContents] = useState<any>();
  const [busy, setBusy] = useState(false);
  const [form] = Form.useForm();
  const canEdit = actor.role !== "operation_admin";
  const load = () =>
    consoleApi<{ items: CatalogTag[] }>("/tags")
      .then((d) => setItems(d.items))
      .catch((e) => message.error(e.message));
  useEffect(() => {
    load();
  }, []);
  const edit = (tag: CatalogTag | null) => {
    form.resetFields();
    form.setFieldsValue(
      tag || { entity_type: scope || "CARD", status: "ACTIVE" },
    );
    setEditing(tag);
  };
  const save = useSingleSubmit(async () => {
    try {
      const data = await form.validateFields();
      setBusy(true);
      await consoleApi(
        editing ? `/tags/${editing.id}` : "/tags",
        send(data, editing ? "PUT" : "POST"),
      );
      setEditing(undefined);
      await Promise.all([load(), reload()]);
      message.success("标签已保存");
    } catch (e) {
      if (e instanceof Error) message.error(e.message);
    } finally {
      setBusy(false);
    }
  });
  const toggle = async (tag: CatalogTag) => {
    try {
      await consoleApi(
        `/tags/${tag.id}`,
        send(
          {
            name: tag.name,
            status: tag.status === "ACTIVE" ? "DISABLED" : "ACTIVE",
          },
          "PUT",
        ),
      );
      await Promise.all([load(), reload()]);
      message.success(
        tag.status === "ACTIVE" ? "已停用，历史关联保留" : "已启用",
      );
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  return (
    <>
      <PageHeader
        title="标签管理"
        description="标签按专辑、活动、其他来源、小卡分别管理；停用后保留历史关联。"
      />
      <FilterBar
        onReset={() => {
          setQ("");
          setScope(undefined);
          setStatus(undefined);
        }}
      >
        <Input
          aria-label="搜索标签"
          placeholder="搜索 标签名称"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          allowClear
        />
        <Select
          aria-label="Tag Entity Type"
          placeholder="全部对象类型"
          allowClear
          value={scope}
          onChange={setScope}
          options={types.map((value) => ({
            value,
            label: displayValue(value),
          }))}
          style={{ width: 190 }}
        />
        <Select
          placeholder="全部状态"
          allowClear
          value={status}
          onChange={setStatus}
          options={[
            { value: "ACTIVE", label: "启用" },
            { value: "DISABLED", label: "停用" },
          ]}
          style={{ width: 140 }}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar
          actions={
            canEdit ? (
              <Button type="primary" onClick={() => edit(null)}>
                新增标签
              </Button>
            ) : undefined
          }
        >
          标签库
        </TableToolbar>
        <Table
          rowKey="id"
          filtered={!!(q || scope || status)}
          onReset={() => {
            setQ("");
            setScope(undefined);
            setStatus(undefined);
          }}
          onCreate={canEdit ? () => edit(null) : undefined}
          createLabel="新增标签"
          dataSource={items.filter(
            (t) =>
              (!scope || t.entity_type === scope) &&
              (!status || t.status === status) &&
              t.name.toLocaleLowerCase().includes(q.toLocaleLowerCase()),
          )}
          columns={[
            { title: "标签名称", dataIndex: "name" },
            { title: "对象类型", dataIndex: "entity_type" },
            {
              title: "来源",
              render: (_, t) =>
                t.source === "INTERNAL" ? "后台创建" : "用户提交",
            },
            {
              title: "状态",
              render: (_, t) => (
                <Tag color={t.status === "ACTIVE" ? "green" : "default"}>
                  {t.status === "ACTIVE" ? "启用" : "停用"}
                </Tag>
              ),
            },
            {
              title: "关联内容数",
              render: (_, t) => (
                <Button
                  type="link"
                  onClick={() =>
                    consoleApi(`/tags/${t.id}/contents`)
                      .then(setContents)
                      .catch((e) => message.error(e.message))
                  }
                >
                  {t.usage_count} 条关联内容
                </Button>
              ),
            },
            {
              title: "操作",
              render: (_, t) => (
                <RowActions
                  onView={() =>
                    consoleApi(`/tags/${t.id}/contents`)
                      .then(setContents)
                      .catch((e) => message.error(e.message))
                  }
                  onEdit={canEdit ? () => edit(t) : undefined}
                  items={
                    actor.role === "admin"
                      ? [
                          {
                            key: "toggle",
                            label: t.status === "ACTIVE" ? "停用" : "启用",
                            onClick: () =>
                              modal.confirm({
                                title: `${t.status === "ACTIVE" ? "停用" : "启用"}标签「${t.name}」？`,
                                content:
                                  "历史关联保留；停用后不再出现在新增内容的可选标签中。",
                                okText: t.status === "ACTIVE" ? "停用" : "启用",
                                cancelText: "取消",
                                onOk: () => toggle(t),
                              }),
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
      <Modal
        title={editing ? "编辑标签" : "新增标签"}
        open={editing !== undefined}
        onCancel={() => setEditing(undefined)}
        onOk={save}
        confirmLoading={busy}
        okText="保存"
      >
        <Form form={form} layout="vertical">
          <Form.Item
            name="entity_type"
            label="对象类型"
            rules={[{ required: true }]}
          >
            <Select
              disabled={!!editing}
              options={types.map((value) => ({
                value,
                label: displayValue(value),
              }))}
            />
          </Form.Item>
          <Form.Item name="name" label="标签名称" rules={[{ required: true }]}>
            <Input maxLength={80} />
          </Form.Item>
          {editing && (
            <Form.Item name="status" label="状态">
              <Select
                disabled={actor.role !== "admin"}
                options={[
                  { value: "ACTIVE", label: "启用" },
                  { value: "DISABLED", label: "停用" },
                ]}
              />
            </Form.Item>
          )}
          <p>
            名称自动去除多余空格、统一全半角并忽略大小写去重。停用不会删除历史关联。
          </p>
        </Form>
      </Modal>
      <Drawer
        title={`关联内容 · ${contents?.tag.name || ""}`}
        open={!!contents}
        onClose={() => setContents(undefined)}
        width={680}
      >
        <Table<any>
          rowKey="id"
          dataSource={contents?.items || []}
          columns={[
            { title: "内容", dataIndex: "name" },
            {
              title: "状态",
              render: (_, r) => <StatusTag status={r.status} />,
            },
            {
              title: "操作",
              render: (_, r) => (
                <Button
                  onClick={() =>
                    navigate(
                      r.kind === "cards"
                        ? `/catalog/cards/${r.id}`
                        : `/catalog/${r.kind}/${r.id}/detail`,
                    )
                  }
                >
                  查看
                </Button>
              ),
            },
          ]}
        />
      </Drawer>
    </>
  );
}

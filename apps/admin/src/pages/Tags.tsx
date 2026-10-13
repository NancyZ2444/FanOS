import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  App,
  Button,
  Drawer,
  Form,
  Input,
  Modal,
  Select,
  Space,
  Table,
  Tag,
} from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import type { CatalogTag, TagType } from "../components/TagSelect";
import { StatusTag } from "../components/shared";
const types: TagType[] = ["ALBUM", "EVENT", "OTHER", "CARD"];
export default function Tags() {
  const { actor, reload } = useConsole();
  const { message } = App.useApp();
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
  const save = async () => {
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
  };
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
      <div className="page-heading">
        <div>
          <h1>Tag 管理</h1>
          <p>
            按实体类型管理平级标签。同名标签可分别存在于 Album、Event、Other 和
            Card。
          </p>
        </div>
        {canEdit && (
          <Button type="primary" onClick={() => edit(null)}>
            创建 Tag
          </Button>
        )}
      </div>
      <section className="panel">
        <Space wrap style={{ marginBottom: 20 }}>
          <Input
            aria-label="搜索 Tag"
            placeholder="搜索 Tag Name"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            allowClear
          />
          <Select
            aria-label="Tag Entity Type"
            placeholder="全部 Entity Type"
            allowClear
            value={scope}
            onChange={setScope}
            options={types.map((value) => ({ value, label: value }))}
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
        </Space>
        <Table
          rowKey="id"
          dataSource={items.filter(
            (t) =>
              (!scope || t.entity_type === scope) &&
              (!status || t.status === status) &&
              t.name.toLocaleLowerCase().includes(q.toLocaleLowerCase()),
          )}
          columns={[
            { title: "Tag Name", dataIndex: "name" },
            { title: "Entity Type", dataIndex: "entity_type" },
            {
              title: "Source",
              render: (_, t) =>
                t.source === "INTERNAL"
                  ? "后台创建 INTERNAL"
                  : "用户提交 USER_SUBMITTED",
            },
            {
              title: "Status",
              render: (_, t) => (
                <Tag color={t.status === "ACTIVE" ? "green" : "default"}>
                  {t.status === "ACTIVE" ? "启用" : "停用"}
                </Tag>
              ),
            },
            {
              title: "Usage Count",
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
                <Space>
                  {canEdit && <Button onClick={() => edit(t)}>编辑</Button>}
                  {actor.role === "admin" && (
                    <Button onClick={() => toggle(t)}>
                      {t.status === "ACTIVE" ? "停用" : "启用"}
                    </Button>
                  )}
                </Space>
              ),
            },
          ]}
        />
      </section>
      <Modal
        title={editing ? "编辑 Tag" : "创建 Tag"}
        open={editing !== undefined}
        onCancel={() => setEditing(undefined)}
        onOk={save}
        confirmLoading={busy}
        okText="保存"
      >
        <Form form={form} layout="vertical">
          <Form.Item
            name="entity_type"
            label="Entity Type"
            rules={[{ required: true }]}
          >
            <Select
              disabled={!!editing}
              options={types.map((value) => ({ value, label: value }))}
            />
          </Form.Item>
          <Form.Item name="name" label="Tag Name" rules={[{ required: true }]}>
            <Input maxLength={80} />
          </Form.Item>
          {editing && (
            <Form.Item name="status" label="Status">
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

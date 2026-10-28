import { useState } from "react";
import {
  Alert,
  App,
  Button,
  Input,
  InputNumber,
  Select,
  Switch,
  Tabs,
  Tag,
  Upload,
} from "antd";
import { UploadOutlined } from "@ant-design/icons";
import { consoleApi, send } from "../../api/client";
import {
  FilterBar,
  Form,
  Modal,
  RecordId,
  RowActions,
  Table,
  TableToolbar,
} from "../../components/admin";
import { ResourcePreview } from "./AlbumPreview";
import MaterialPreview from "./MaterialPreview";
import { resourceKinds, resourceStatuses, type Resource } from "./types";

type Values = Omit<Resource, "config"> & {
  visual_type: "SYMBOL" | "IMAGE" | "SOLID" | "GRADIENT";
  image_url?: string;
  symbol?: string;
  colors?: string[];
  ledge?: string;
  angle?: number;
};
const hexRules = [
  { required: true, message: "请选择或填写颜色" },
  { pattern: /^#[0-9a-fA-F]{6}$/, message: "请使用 #RRGGBB 格式" },
];
function ColorInput({
  value,
  onChange,
}: {
  value?: string;
  onChange?: (value: string) => void;
}) {
  return (
    <div className="album-color-input">
      <input
        type="color"
        aria-label="颜色选择"
        value={/^#[0-9a-fA-F]{6}$/.test(value || "") ? value : "#E8EBE3"}
        onChange={(e) => onChange?.(e.target.value.toUpperCase())}
      />
      <Input
        value={value}
        onChange={(e) => onChange?.(e.target.value.toUpperCase())}
        maxLength={7}
        placeholder="#RRGGBB"
      />
    </div>
  );
}
function fromValues(values: Values): Resource {
  const config: Resource["config"] =
    values.kind === "STICKER"
      ? values.visual_type === "IMAGE"
        ? { image_url: values.image_url }
        : { symbol: values.symbol }
      : values.kind === "SHELF"
        ? {
            colors: values.colors,
            ledge: values.ledge,
            ...(values.image_url ? { image_url: values.image_url } : {}),
          }
        : {
            type:
              values.visual_type === "IMAGE"
                ? "IMAGE"
                : values.visual_type === "GRADIENT"
                  ? "GRADIENT"
                  : "SOLID",
            colors:
              values.visual_type === "SOLID"
                ? values.colors?.slice(0, 1)
                : values.colors,
            angle: values.angle || 0,
            ...(values.visual_type === "IMAGE"
              ? { image_url: values.image_url }
              : {}),
          };
  return {
    id: values.id?.trim(),
    name: values.name?.trim(),
    kind: values.kind,
    status: values.status,
    sort_order: values.sort_order || 0,
    scene: values.scene,
    membership: values.membership || "ALL",
    locked_preview: values.locked_preview ?? true,
    config,
  };
}
export default function ResourceManager({
  resources,
  canEdit,
  onSaved,
  scene = "ALBUM_COVER",
}: {
  resources: Resource[];
  canEdit: boolean;
  onSaved: () => Promise<void>;
  scene?: NonNullable<Resource["scene"]>;
}) {
  const { message, modal } = App.useApp();
  const [query, setQuery] = useState(""),
    [kind, setKind] = useState(""),
    [status, setStatus] = useState("");
  const [membership, setMembership] = useState("");
  const [coverTab, setCoverTab] = useState("BACKGROUND");
  const kinds = resourceKinds.filter((k) =>
    scene === "SHELF"
      ? k.value === "SHELF"
      : k.value === "BACKGROUND" ||
        k.value === "COLOR" ||
        (scene === "ALBUM_COVER" && k.value === "STICKER"),
  );
  const base = `/album-materials/${scene}`;
  const [editing, setEditing] = useState<Resource | null>(),
    [view, setView] = useState<Resource>();
  const [busy, setBusy] = useState(false),
    [uploading, setUploading] = useState(false);
  const [form] = Form.useForm<Values>();
  const values = Form.useWatch([], form) as Values | undefined;
  const preview = values?.kind ? fromValues(values) : undefined;
  const rows = resources.filter(
    (r) =>
      r.scene === scene &&
      (scene !== "ALBUM_COVER" ||
        (coverTab === "STICKER"
          ? r.kind === "STICKER"
          : r.kind !== "STICKER")) &&
      (!membership || r.membership === membership) &&
      (!kind || r.kind === kind) &&
      (!status || r.status === status) &&
      (!query ||
        `${r.id} ${r.name}`.toLowerCase().includes(query.trim().toLowerCase())),
  );
  const reset = () => {
    setQuery("");
    setKind("");
    setStatus("");
    setMembership("");
  };
  const edit = (row: Resource | null) => {
    form.resetFields();
    form.setFieldsValue(
      row
        ? {
            ...row,
            ...row.config,
            colors: row.config.colors || ["#E8EBE3", "#F5EAFE"],
            visual_type:
              row.kind === "STICKER"
                ? row.config.image_url
                  ? "IMAGE"
                  : "SYMBOL"
                : row.config.type ||
                  (row.kind === "SHELF" ? "GRADIENT" : "SOLID"),
            scene,
            membership: row.membership || "ALL",
            locked_preview: row.locked_preview ?? true,
          }
        : {
            kind:
              scene === "SHELF"
                ? "SHELF"
                : scene === "ALBUM_COVER" && coverTab === "STICKER"
                  ? "STICKER"
                  : "BACKGROUND",
            status: "DRAFT",
            scene,
            membership: "ALL",
            locked_preview: true,
            sort_order: 0,
            visual_type:
              scene === "ALBUM_COVER" && coverTab === "STICKER"
                ? "SYMBOL"
                : "SOLID",
            symbol: "✦",
            colors: ["#E8EBE3", "#F5EAFE"],
            ledge: "#B9B0A2",
            angle: 45,
          },
    );
    setEditing(row);
  };
  const save = async () => {
    let data: Values;
    try {
      data = await form.validateFields();
    } catch {
      return;
    }
    setBusy(true);
    try {
      const resource = fromValues(data);
      await consoleApi(
        editing ? `${base}/${encodeURIComponent(editing.id)}` : base,
        send(resource, editing ? "PUT" : "POST"),
      );
      setEditing(undefined);
      message.success("素材已保存");
      await onSaved();
    } catch (error) {
      message.error((error as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const changeStatus = (resource: Resource, status: Resource["status"]) => {
    const action = status === "PUBLISHED" ? "上架" : "下架";
    modal.confirm({
      title: `${action}「${resource.name}」？`,
      okText: action,
      cancelText: "取消",
      content:
        status === "OFFLINE"
          ? "下架后无法新增使用；已使用的作品仍保留素材和视觉效果。"
          : "上架后，符合会员范围的用户可以在 App 中选择使用。",
      onOk: async () => {
        try {
          const {
            id,
            name,
            kind,
            sort_order,
            config,
            scene,
            membership,
            locked_preview,
          } = resource;
          await consoleApi(
            `${base}/${encodeURIComponent(id)}`,
            send(
              {
                id,
                name,
                kind,
                sort_order,
                config,
                scene,
                membership: membership || "ALL",
                locked_preview: locked_preview ?? true,
                status,
              },
              "PUT",
            ),
          );
          message.success(`素材已${action}`);
          await onSaved();
        } catch (error) {
          message.error((error as Error).message);
          throw error;
        }
      },
    });
  };
  const remove = (resource: Resource) =>
    modal.confirm({
      title: `删除「${resource.name}」？`,
      okText: "删除",
      okButtonProps: { danger: true },
      cancelText: "取消",
      content:
        "将永久删除 1 条素材草稿，不可恢复。仅从未上架且未被作品使用的草稿可删除，系统会再次校验关联。",
      onOk: async () => {
        try {
          await consoleApi(`${base}/${encodeURIComponent(resource.id)}`, {
            method: "DELETE",
          });
          message.success("素材已删除");
          await onSaved();
        } catch (error) {
          message.error((error as Error).message);
          throw error;
        }
      },
    });
  return (
    <>
      {scene === "ALBUM_COVER" && (
        <Tabs
          activeKey={coverTab}
          onChange={setCoverTab}
          items={[
            { key: "BACKGROUND", label: "背景" },
            { key: "STICKER", label: "贴纸" },
          ]}
        />
      )}
      <FilterBar onReset={reset}>
        <Input
          placeholder="搜索素材名称或编号"
          aria-label="搜索素材名称或编号"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <Select
          aria-label="素材类型筛选"
          value={kind}
          onChange={setKind}
          options={[{ value: "", label: "全部类型" }, ...kinds]}
        />
        <Select
          aria-label="会员范围筛选"
          value={membership}
          onChange={setMembership}
          options={[
            { value: "", label: "全部会员范围" },
            { value: "ALL", label: "所有用户" },
            { value: "PRO", label: "PRO 专属" },
          ]}
        />
        <Select
          aria-label="素材状态筛选"
          value={status}
          onChange={setStatus}
          options={[{ value: "", label: "全部状态" }, ...resourceStatuses]}
        />
      </FilterBar>
      <TableToolbar
        actions={
          <Button type="primary" disabled={!canEdit} onClick={() => edit(null)}>
            新增系统素材
          </Button>
        }
      >
        系统素材
      </TableToolbar>
      <Table<Resource>
        rowKey="id"
        dataSource={rows}
        filtered={!!(query || kind || status)}
        onReset={reset}
        onCreate={canEdit ? () => edit(null) : undefined}
        createLabel="新增系统素材"
        pagination={{ defaultPageSize: 20 }}
        scroll={{ x: 840 }}
        columns={[
          {
            title: "素材",
            width: 280,
            render: (_, row) => (
              <div className="album-resource-cell">
                <ResourcePreview resource={row} />
                <div>
                  <button
                    className="table-title"
                    onClick={() => setView(row)}
                    title={row.name}
                  >
                    {row.name}
                  </button>
                  <RecordId value={row.id} />
                </div>
              </div>
            ),
          },
          {
            title: "类型 / 场景",
            width: 144,
            render: (_, row) => (
              <>
                {resourceKinds.find((k) => k.value === row.kind)?.label}
                <div className="album-muted">
                  {row.kind === "SHELF"
                    ? "书架"
                    : row.kind === "STICKER"
                      ? "封面"
                      : row.scene === "ALBUM_COVER"
                        ? "封面"
                        : row.scene === "ALBUM_PAGE"
                          ? "内页"
                          : "卡片背景"}
                </div>
              </>
            ),
          },
          {
            title: "会员范围",
            width: 128,
            render: (_, row) => (
              <Tag color={row.membership === "PRO" ? "purple" : undefined}>
                {row.membership === "PRO" ? "PRO 专属" : "所有用户"}
              </Tag>
            ),
          },
          {
            title: "状态",
            width: 104,
            render: (_, row) => (
              <Tag
                color={
                  row.status === "PUBLISHED"
                    ? "green"
                    : row.status === "OFFLINE"
                      ? "default"
                      : "gold"
                }
              >
                {resourceStatuses.find((s) => s.value === row.status)?.label}
              </Tag>
            ),
          },
          { title: "排序", dataIndex: "sort_order", width: 80 },
          {
            title: "操作",
            width: 184,
            render: (_, row) => (
              <RowActions
                onView={() => setView(row)}
                onEdit={canEdit ? () => edit(row) : undefined}
                items={
                  canEdit
                    ? [
                        {
                          key: "status",
                          label: row.status === "PUBLISHED" ? "下架" : "上架",
                          onClick: () =>
                            changeStatus(
                              row,
                              row.status === "PUBLISHED"
                                ? "OFFLINE"
                                : "PUBLISHED",
                            ),
                        },
                        {
                          key: "delete",
                          label: "删除",
                          danger: true,
                          disabled:
                            row.status !== "DRAFT" ||
                            row.published_once ||
                            row.used_once,
                          onClick: () => remove(row),
                        },
                      ]
                    : []
                }
              />
            ),
          },
        ]}
      />
      <Alert
        type="info"
        showIcon
        message="已上架或已使用的素材通过下架停止新增使用；历史作品保留原有视觉效果。贴纸用于封面，图片支持 PNG / WebP，背景和书架另支持 JPG。"
      />
      <Modal
        title={editing ? "编辑系统素材" : "新增系统素材"}
        open={editing !== undefined}
        onCancel={() => setEditing(undefined)}
        onOk={save}
        confirmLoading={busy || uploading}
        okButtonProps={{ disabled: uploading }}
        width={800}
        destroyOnHidden
      >
        <div className="album-resource-editor">
          <Form
            form={form}
            layout="horizontal"
            labelCol={{ flex: "100px" }}
            disabled={busy || uploading}
          >
            <div className="album-form-grid">
              <Form.Item
                name="name"
                label="素材名称"
                rules={[
                  {
                    required: true,
                    whitespace: true,
                    message: "请输入素材名称",
                  },
                ]}
              >
                <Input maxLength={80} />
              </Form.Item>
              <Form.Item
                name="id"
                label="资源 ID"
                rules={[
                  { required: true, message: "请输入资源编号" },
                  {
                    pattern: /^[a-zA-Z0-9_-]{1,64}$/,
                    message: "使用字母、数字、下划线或短横线，最多 64 位",
                  },
                ]}
                extra="唯一编号，创建后不可修改。"
              >
                <Input disabled={!!editing} placeholder="例如 spring-flower" />
              </Form.Item>
              <Form.Item
                name="kind"
                label="素材类型"
                rules={[{ required: true }]}
              >
                <Select
                  disabled={!!editing}
                  options={kinds.filter(
                    (k) =>
                      scene !== "ALBUM_COVER" ||
                      (coverTab === "STICKER"
                        ? k.value === "STICKER"
                        : k.value !== "STICKER"),
                  )}
                  onChange={(kind) =>
                    form.setFieldsValue({
                      visual_type:
                        kind === "STICKER"
                          ? "SYMBOL"
                          : kind === "SHELF"
                            ? "GRADIENT"
                            : "SOLID",
                      scene,
                      image_url: undefined,
                    })
                  }
                />
              </Form.Item>
              <Form.Item
                name="status"
                label="素材状态"
                rules={[{ required: true }]}
              >
                <Select
                  options={resourceStatuses.filter(
                    (s) => !editing?.published_once || s.value !== "DRAFT",
                  )}
                />
              </Form.Item>
              <Form.Item name="scene" label="使用场景">
                <Select
                  disabled
                  options={[
                    { value: "SHELF", label: "书架主题" },
                    { value: "ALBUM_COVER", label: "相册封面" },
                    { value: "ALBUM_PAGE", label: "相册内页" },
                    { value: "CARD_BACKGROUND", label: "卡片背景" },
                  ]}
                />
              </Form.Item>
              <Form.Item name="membership" label="会员范围">
                <Select
                  options={[
                    { value: "ALL", label: "所有用户" },
                    { value: "PRO", label: "PRO 专属" },
                  ]}
                />
              </Form.Item>
              <Form.Item
                name="sort_order"
                label="排序"
                extra="数字越小，展示越靠前。"
              >
                <InputNumber precision={0} min={0} max={100000} />
              </Form.Item>
              <Form.Item
                name="locked_preview"
                label="非会员可见"
                valuePropName="checked"
                extra="展示锁定预览，提示所需权益。"
              >
                <Switch
                  disabled={values?.membership !== "PRO"}
                  checkedChildren="是"
                  unCheckedChildren="否"
                />
              </Form.Item>
            </div>
            <h3 className="album-section-title">素材内容</h3>
            {values?.kind !== "SHELF" && (
              <Form.Item name="visual_type" label="表现形式">
                <Select
                  options={
                    values?.kind === "STICKER"
                      ? [
                          { value: "SYMBOL", label: "符号贴纸" },
                          { value: "IMAGE", label: "图片贴纸" },
                        ]
                      : [
                          { value: "SOLID", label: "纯色" },
                          { value: "GRADIENT", label: "渐变色" },
                          ...(values?.kind === "BACKGROUND"
                            ? [{ value: "IMAGE", label: "图片背景" }]
                            : []),
                        ]
                  }
                />
              </Form.Item>
            )}
            {values?.kind === "STICKER" && values?.visual_type === "SYMBOL" && (
              <Form.Item
                name="symbol"
                label="符号内容"
                rules={[
                  { required: true, whitespace: true, message: "请输入符号" },
                ]}
              >
                <Input maxLength={24} />
              </Form.Item>
            )}
            {(values?.visual_type === "IMAGE" || values?.kind === "SHELF") && (
              <Form.Item
                name="image_url"
                label={
                  values?.kind === "SHELF" ? "书架图片（可选）" : "素材图片"
                }
                rules={
                  values?.visual_type === "IMAGE"
                    ? [{ required: true, message: "请上传素材图片" }]
                    : []
                }
              >
                <Input
                  placeholder="上传后自动填入图片地址"
                  readOnly
                  addonAfter={
                    values?.image_url ? (
                      <button
                        type="button"
                        className="album-text-button"
                        disabled={busy || uploading}
                        onClick={() =>
                          form.setFieldValue("image_url", undefined)
                        }
                      >
                        清除
                      </button>
                    ) : undefined
                  }
                />
              </Form.Item>
            )}
            {(values?.visual_type === "IMAGE" || values?.kind === "SHELF") && (
              <Upload
                accept={
                  values.kind === "STICKER"
                    ? "image/png,image/webp"
                    : "image/jpeg,image/png,image/webp"
                }
                showUploadList={false}
                beforeUpload={(file) => {
                  const types =
                    values.kind === "STICKER"
                      ? ["image/png", "image/webp"]
                      : ["image/jpeg", "image/png", "image/webp"];
                  if (
                    !types.includes(file.type) ||
                    file.size > 10 * 1024 * 1024
                  ) {
                    message.error(
                      "请选择符合格式要求、大小不超过 10 MB 的图片",
                    );
                    return Upload.LIST_IGNORE;
                  }
                  setUploading(true);
                  const body = new FormData();
                  body.append("file", file);
                  body.append("kind", values.kind);
                  void consoleApi<{ url: string }>("/album-resources/upload", {
                    method: "POST",
                    body,
                  })
                    .then((data) => {
                      form.setFieldValue("image_url", data.url);
                      message.success("图片已上传");
                    })
                    .catch((error) => message.error(error.message))
                    .finally(() => setUploading(false));
                  return false;
                }}
              >
                <Button
                  icon={<UploadOutlined />}
                  loading={uploading}
                  disabled={busy}
                >
                  上传图片
                </Button>
                <span className="album-upload-help">
                  {values.kind === "STICKER"
                    ? "PNG / WebP，保留透明背景"
                    : "JPG / PNG / WebP"}{" "}
                  · ≤ 10 MB
                </span>
              </Upload>
            )}
            {values?.kind !== "STICKER" && values?.visual_type !== "IMAGE" && (
              <>
                <div className="album-form-grid">
                  <Form.Item
                    name={["colors", 0]}
                    label={
                      values?.visual_type === "SOLID" ? "颜色" : "起始颜色"
                    }
                    rules={hexRules}
                  >
                    <ColorInput />
                  </Form.Item>
                  {(values?.visual_type === "GRADIENT" ||
                    values?.kind === "SHELF") && (
                    <Form.Item
                      name={["colors", 1]}
                      label="结束颜色"
                      rules={hexRules}
                    >
                      <ColorInput />
                    </Form.Item>
                  )}
                  {values?.colors?.slice(2).map((_, index) => (
                    <Form.Item
                      key={index + 2}
                      name={["colors", index + 2]}
                      label={`过渡颜色 ${index + 1}`}
                      rules={hexRules}
                    >
                      <ColorInput />
                    </Form.Item>
                  ))}
                  {values?.kind === "SHELF" ? (
                    <Form.Item name="ledge" label="层板颜色" rules={hexRules}>
                      <ColorInput />
                    </Form.Item>
                  ) : (
                    values?.visual_type === "GRADIENT" && (
                      <Form.Item name="angle" label="渐变角度">
                        <InputNumber min={-360} max={360} addonAfter="°" />
                      </Form.Item>
                    )
                  )}
                </div>
              </>
            )}
          </Form>
          <aside className="album-resource-preview-panel">
            <h3>效果预览</h3>
            {preview && <MaterialPreview resource={preview} />}
            <p>
              {values?.kind === "SHELF"
                ? "书架背景与层板示意"
                : values?.kind === "STICKER"
                  ? "贴纸按原始比例展示，保留透明区域。"
                  : values?.scene === "ALBUM_PAGE"
                    ? "用于相册内页背景"
                    : values?.scene === "ALBUM_COVER"
                      ? "用于相册封面背景"
                      : "用于卡片作品背景"}
            </p>
            {values?.membership === "PRO" && (
              <Tag color="purple">
                PRO 专属{values.locked_preview ? " · 非会员可见锁定预览" : ""}
              </Tag>
            )}
          </aside>
        </div>
      </Modal>
      <Modal
        title={view?.name || "素材预览"}
        open={!!view}
        onCancel={() => setView(undefined)}
        footer={
          <div className="toolbar-actions">
            <Button onClick={() => setView(undefined)}>关闭</Button>
            {canEdit && (
              <Button
                type="primary"
                onClick={() => {
                  edit(view!);
                  setView(undefined);
                }}
              >
                编辑
              </Button>
            )}
          </div>
        }
      >
        {view && (
          <div className="album-resource-detail">
            <MaterialPreview resource={view} />
            <dl>
              <dt>编号</dt>
              <dd>
                <RecordId value={view.id} />
              </dd>
              <dt>类型</dt>
              <dd>{resourceKinds.find((k) => k.value === view.kind)?.label}</dd>
              <dt>状态</dt>
              <dd>
                {resourceStatuses.find((s) => s.value === view.status)?.label}
              </dd>
              <dt>会员范围</dt>
              <dd>{view.membership === "PRO" ? "PRO 专属" : "所有用户"}</dd>
              <dt>历史使用</dt>
              <dd>
                {view.used_once ? "已被作品使用，保留历史关联" : "尚无使用记录"}
              </dd>
            </dl>
          </div>
        )}
      </Modal>
    </>
  );
}

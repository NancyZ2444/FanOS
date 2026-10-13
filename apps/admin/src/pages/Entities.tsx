import TagSelect from "../components/TagSelect";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useSearchParams } from "react-router-dom";
import {
  App,
  Button,
  Drawer,
  Dropdown,
  Form,
  Input,
  Select,
  Space,
  Table,
  Tabs,
  Tag,
} from "antd";
import { PlusOutlined, SearchOutlined } from "@ant-design/icons";
import type { CatalogEntity, Kind } from "../api/types";
import { names, statusLabels } from "../api/types";
import { ApiError, consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import { confirmCatalogDeletion } from "../components/catalogDeletion";
import {
  editable,
  EmptyState,
  ImageUpload,
  StatusTag,
} from "../components/shared";

export default function Entities({ kind }: { kind: Kind }) {
  const { catalog, actor, reload, loading } = useConsole();
  const { message, modal } = App.useApp();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [form] = Form.useForm();
  const isOnline = Form.useWatch("is_online", form) === true;
  const [q, setQ] = useState("");
  const [group, setGroup] = useState<string>();
  const [status, setStatus] = useState("ALL");
  const [company, setCompany] = useState<string>();
  const [year, setYear] = useState<string>();
  const [hasSocial, setHasSocial] = useState<boolean>();
  const [hasCard, setHasCard] = useState<boolean>();
  const [hasIdol, setHasIdol] = useState<boolean>();
  const [record, setRecord] = useState<CatalogEntity>();
  const [open, setOpen] = useState(false);
  const [companies, setCompanies] = useState<any[]>([]);
  const selectedCompanies: string[] | undefined = Form.useWatch(
    "company_ids",
    form,
  );
  const [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState<React.Key[]>([]);
  useEffect(() => {
    setSelected([]);
  }, [kind, q, group, status, company, year, hasSocial, hasCard, hasIdol]);
  const canEdit = actor.role !== "operation_admin";
  const readOnly = !!record && !editable(record.status);
  const items = catalog[kind].filter(
    (r) =>
      (status === "ALL" ? r.status !== "ARCHIVED" : r.status === status) &&
      (!group ||
        r.group_id === group ||
        r.artists?.some((a: any) => a.type === "groups" && a.id === group)) &&
      (!company || r.company === company) &&
      (!year ||
        (r.debut_date || r.release_date || r.start_date || "").slice(0, 4) ===
          year) &&
      (hasSocial === undefined || !!r.social_count === hasSocial) &&
      (hasCard === undefined || r.card_count > 0 === hasCard) &&
      (hasIdol === undefined || (r.member_count || 0) > 0 === hasIdol) &&
      (!params.get("created_date") ||
        new Date(r.created_at).toLocaleDateString("sv-SE", {
          timeZone: "Asia/Shanghai",
        }) === params.get("created_date")) &&
      (!q ||
        [r.id, r.name, r.name_en, r.name_ko, r.name_translated].some((v) =>
          v?.toLowerCase().includes(q.toLowerCase()),
        )),
  );
  const edit = (row?: CatalogEntity) => {
    if (["groups", "idols"].includes(kind))
      consoleApi("/records/companies")
        .then((d) => setCompanies(d.items))
        .catch((e) => message.error(e.message));
    setRecord(row);
    form.resetFields();
    form.setFieldsValue(
      row
        ? {
            ...row,
            company_ids: row.company_ids?.length ? row.company_ids : undefined,
            company_effective_date: "",
            artist_keys: (
              row.artists ||
              (row.group_id ? [{ type: "groups", id: row.group_id }] : [])
            ).map((a: { type: string; id: string }) => `${a.type}:${a.id}`),
            description: row.description || row.bio,
            release_date: (
              row.release_date ||
              row.start_date ||
              row.birth_date ||
              row.debut_date
            )?.replaceAll(".", "-"),
          }
        : {
            group_id: group || params.get("group_id") || undefined,
            idol_id: params.get("idol_id") || undefined,
            artist_keys: params.get("idol_id")
              ? [`idols:${params.get("idol_id")}`]
              : group || params.get("group_id")
                ? [`groups:${group || params.get("group_id")}`]
                : [],
            source_info: {
              source_type: "ADMIN_UPLOAD",
              copyright_status: "UNKNOWN",
            },
          },
    );
    setOpen(true);
  };
  useEffect(() => {
    if (params.get("create") === "true") edit();
  }, [kind, params.toString()]);
  const save = async () => {
    try {
      const data = await form.validateFields();
      if (data.artist_keys) {
        data.artists = data.artist_keys.map((value: string) => {
          const [type, id] = value.split(":");
          return { type, id };
        });
        data.group_id =
          data.artists.find((a: { type: string }) => a.type === "groups")?.id ||
          "";
        data.idol_id =
          data.artists.find((a: { type: string }) => a.type === "idols")?.id ||
          null;
        delete data.artist_keys;
      }
      setBusy(true);
      await consoleApi(
        record ? `/entities/${kind}/${record.id}` : `/entities/${kind}`,
        send(data, record ? "PUT" : "POST"),
      );
      message.success("已保存为草稿");
      setOpen(false);
      await reload();
    } catch (e) {
      if (e instanceof ApiError) {
        if (e.fields.length)
          form.setFields(
            e.fields.map((f) => ({
              name: f.field.split("."),
              errors: [f.message],
            })),
          );
        message.error(e.message);
      }
    } finally {
      setBusy(false);
    }
  };
  const action = (row: CatalogEntity, type: string) => {
    if (type === "delete") {
      void confirmCatalogDeletion(
        kind,
        row.id,
        row.name,
        modal,
        message,
        reload,
      );
      return;
    }
    let reason = "";
    modal.confirm({
      title: `确认${{ delete: "永久删除", submit: "提交审核", publish: "发布", offline: "下架", archive: "归档", restore: "恢复草稿", reject: "驳回" }[type] || type}「${row.name}」？`,
      okButtonProps: { danger: type === "delete" },
      content:
        type === "delete" ? (
          "删除不可恢复。所属组合、艺人、发行来源和其他上下游关联必须全部解除，否则删除会被拒绝。"
        ) : type === "reject" ? (
          <Input.TextArea
            aria-label="驳回原因"
            placeholder="请填写驳回原因"
            onChange={(e) => {
              reason = e.target.value;
            }}
          />
        ) : type === "publish" ? (
          "发布后将同步到 App 图鉴。"
        ) : (
          "操作将记录到后台日志。"
        ),
      okText: "确认",
      cancelText: "取消",
      onOk: async () => {
        if (type === "reject" && !reason.trim()) {
          message.warning("请填写驳回原因");
          throw new Error("请填写驳回原因");
        }
        try {
          await consoleApi(
            type === "delete"
              ? `/entities/${kind}/${row.id}`
              : `/entities/${kind}/${row.id}/actions`,
            type === "delete"
              ? { method: "DELETE" }
              : send({ action: type, reason }),
          );
          message.success("操作成功");
          await reload();
        } catch (e) {
          message.error((e as Error).message);
        }
      },
    });
  };
  const label = names[kind].replace("管理", "");
  const batchActions = [
    {
      key: "submit",
      label: "批量提交审核",
      states: ["DRAFT", "REJECTED", "OFFLINE"],
    },
    ...(actor.role === "admin"
      ? [{ key: "publish", label: "批量发布", states: ["PENDING"] }]
      : []),
    ...(actor.role === "admin"
      ? [
          { key: "offline", label: "批量下架", states: ["PUBLISHED"] },
          {
            key: "archive",
            label: "批量归档",
            states: ["DRAFT", "REJECTED", "OFFLINE"],
          },
        ]
      : []),
    { key: "restore", label: "恢复草稿", states: ["ARCHIVED"] },
    ...(actor.role === "admin"
      ? [
          {
            key: "delete",
            label: "批量永久删除",
            states: ["DRAFT", "OFFLINE", "ARCHIVED"],
          },
        ]
      : []),
  ];
  const selectedRows = items.filter((r) => selected.includes(r.id));
  const batch = (type: string, actionLabel: string) =>
    modal.confirm({
      title: `确认${actionLabel} ${selected.length} 条${label}？`,
      content:
        type === "delete"
          ? "删除不可恢复。允许未发布草稿；曾发布后下架及归档记录须解除上下游关联。任何下游引用仍会阻止删除，任一不满足条件则整批不删除。"
          : "仅处理选中的记录，不级联修改关联内容。若任一记录状态已变化，整批操作将取消。",
      okButtonProps: { danger: type === "delete" },
      okText: "确认操作",
      cancelText: "取消",
      onOk: async () => {
        setBusy(true);
        try {
          await consoleApi(
            `/entities/${kind}/batch`,
            send({ ids: selected, action: type }),
          );
          setSelected([]);
          message.success(`${actionLabel}成功`);
          await reload();
        } catch (e) {
          message.error((e as Error).message);
        } finally {
          setBusy(false);
        }
      },
    });
  return (
    <>
      <div className="page-heading">
        <div>
          <div className="eyebrow">CATALOG / {kind.toUpperCase()}</div>
          <h1>
            {names[kind]}{" "}
            <span className="heading-count">{catalog[kind].length}</span>
          </h1>
          <p>
            {kind === "groups"
              ? "从每一个组合开始，连接艺人、作品与收藏。"
              : kind === "idols"
                ? "维护艺人资料，建立清晰的组合成员关系。"
                : "统一管理小卡的发行来源与关联内容。"}
          </p>
        </div>
      </div>
      {["albums", "events", "others"].includes(kind) && (
        <div className="catalog-tabs">
          {(["albums", "events", "others"] as Kind[]).map((k) => (
            <button
              key={k}
              className={kind === k ? "active" : ""}
              onClick={() => navigate(`/catalog/${k}`)}
            >
              {names[k]}
            </button>
          ))}
        </div>
      )}
      <section className="panel filters">
        <div className="filter-row">
          <Input
            value={q}
            allowClear
            onChange={(e) => setQ(e.target.value)}
            prefix={<SearchOutlined aria-hidden="true" />}
            placeholder={`搜索${label}名称、ID…`}
            style={{ width: 320 }}
          />
          {kind !== "groups" && (
            <Select
              value={group}
              allowClear
              onChange={setGroup}
              placeholder="全部组合"
              options={catalog.groups.map((g) => ({
                value: g.id,
                label: g.name,
              }))}
            />
          )}
          {["groups", "idols"].includes(kind) && (
            <>
              <Select
                allowClear
                placeholder="全部公司"
                value={company}
                onChange={setCompany}
                options={[
                  ...new Set(
                    catalog[kind].map((r) => r.company).filter(Boolean),
                  ),
                ].map((value) => ({ value, label: value }))}
              />
              <Select
                allowClear
                placeholder="社交账号"
                value={hasSocial}
                onChange={setHasSocial}
                options={[
                  { value: true, label: "已配置" },
                  { value: false, label: "未配置" },
                ]}
              />
            </>
          )}
          {kind !== "idols" && (
            <Select
              allowClear
              placeholder={kind === "groups" ? "出道年份" : "发行年份"}
              value={year}
              onChange={setYear}
              options={[
                ...new Set(
                  catalog[kind]
                    .map((r) =>
                      (
                        r.debut_date ||
                        r.release_date ||
                        r.start_date ||
                        ""
                      ).slice(0, 4),
                    )
                    .filter(Boolean),
                ),
              ]
                .sort()
                .reverse()
                .map((value) => ({ value, label: value }))}
            />
          )}
          <Select
            allowClear
            placeholder="关联小卡"
            value={hasCard}
            onChange={setHasCard}
            options={[
              { value: true, label: "有小卡" },
              { value: false, label: "无小卡" },
            ]}
          />
          {kind === "groups" && (
            <Select
              allowClear
              placeholder="组合成员"
              value={hasIdol}
              onChange={setHasIdol}
              options={[
                { value: true, label: "有成员" },
                { value: false, label: "无成员" },
              ]}
            />
          )}
          <Button
            onClick={() => {
              setQ("");
              setGroup(undefined);
              setCompany(undefined);
              setYear(undefined);
              setHasSocial(undefined);
              setHasCard(undefined);
              setHasIdol(undefined);
            }}
          >
            清空筛选
          </Button>
        </div>
      </section>
      <section className="panel table-panel">
        <div className="table-toolbar">
          <Tabs
            activeKey={status}
            onChange={setStatus}
            items={[
              "ALL",
              "DRAFT",
              "PENDING",
              "PUBLISHED",
              "OFFLINE",
              "REJECTED",
              "ARCHIVED",
            ].map((s) => ({
              key: s,
              label: s === "ALL" ? `全部${label}` : statusLabels[s],
            }))}
          />
          {canEdit && (
            <Space>
              <Button onClick={() => navigate(`/catalog/import?kind=${kind}`)}>
                批量导入
              </Button>
              <Button
                type="primary"
                icon={<PlusOutlined aria-hidden="true" />}
                onClick={() => edit()}
              >
                新建{label}
              </Button>
            </Space>
          )}
        </div>
        {canEdit && (
          <div className="entity-batch-bar">
            <span>
              {selected.length
                ? `已选择 ${selected.length} 条${label}`
                : `共 ${items.length} 条记录 · 勾选后可批量操作`}
            </span>
            {selected.length > 0 && (
              <>
                <Space wrap>
                  {batchActions.map((a) => (
                    <Button
                      size="small"
                      key={a.key}
                      danger={a.key === "delete"}
                      loading={busy}
                      disabled={
                        selected.length > 100 ||
                        selectedRows.length !== selected.length ||
                        !selectedRows.every((r) => a.states.includes(r.status))
                      }
                      onClick={() => batch(a.key, a.label)}
                    >
                      {a.label}
                    </Button>
                  ))}
                  <Button
                    size="small"
                    type="text"
                    onClick={() => setSelected([])}
                  >
                    取消选择
                  </Button>
                </Space>
                <small>
                  {selected.length > 100
                    ? "单次最多操作 100 条，请减少选择"
                    : "仅启用所有选中记录均可执行的操作；已发布内容需先下架再归档。"}
                </small>
              </>
            )}
          </div>
        )}
        <Table
          rowKey="id"
          loading={loading}
          dataSource={items}
          rowSelection={
            canEdit
              ? {
                  selectedRowKeys: selected,
                  onChange: setSelected,
                  preserveSelectedRowKeys: false,
                }
              : undefined
          }
          scroll={{ x: 950 }}
          locale={{ emptyText: <EmptyState /> }}
          pagination={{
            defaultPageSize: 10,
            showSizeChanger: true,
            pageSizeOptions: [10, 20, 50, 100],
            showTotal: (t) => `共 ${t} 条记录`,
          }}
          columns={[
            {
              title: `${label}信息`,
              key: "name",
              width: 280,
              render: (_, r) => (
                <div className="table-card-info">
                  <div
                    className={`entity-avatar ${kind === "idols" ? "circle" : ""}`}
                  >
                    {r.image_url ? (
                      <img src={r.image_url} alt="" />
                    ) : (
                      r.name.slice(0, 1)
                    )}
                  </div>
                  <div>
                    <button className="table-title" onClick={() => edit(r)}>
                      {r.name}
                    </button>
                    <span className="record-id">
                      {r.name_translated || r.name_ko || r.id}
                    </span>
                  </div>
                </div>
              ),
            },
            ...(kind === "others"
              ? [
                  { title: "原始名称", dataIndex: "original_name" },
                  {
                    title: "起止日期",
                    render: (_: unknown, r: CatalogEntity) =>
                      [r.start_date, r.end_date].filter(Boolean).join(" — ") ||
                      "—",
                  },
                  {
                    title: "Tags",
                    render: (_: unknown, r: CatalogEntity) =>
                      (r.tags || []).map((tag: string) => (
                        <Tag key={tag}>{tag}</Tag>
                      )),
                  },
                ]
              : kind !== "groups"
                ? [
                    {
                      title: kind === "idols" ? "当前组合" : "发行 / 活动艺人",
                      key: "group",
                      render: (_: unknown, r: CatalogEntity) =>
                        r.artist_name ||
                        catalog.groups.find((g) => g.id === r.group_id)?.name ||
                        "Solo",
                    },
                  ]
                : [{ title: "艺人数", dataIndex: "member_count" }]),
            {
              title: "关联小卡",
              dataIndex: "card_count",
              render: (v: number, r: CatalogEntity) => (
                <button
                  className="text-button"
                  onClick={() =>
                    navigate(`/catalog/cards?q=${encodeURIComponent(r.name)}`)
                  }
                >
                  {v} 张
                </button>
              ),
            },
            {
              title: "状态",
              dataIndex: "status",
              render: (v) => <StatusTag status={v} />,
            },
            {
              title: "更新时间",
              dataIndex: "updated_at",
              render: (v) => new Date(v).toLocaleDateString("zh-CN"),
            },
            {
              title: "操作",
              key: "actions",
              width: 230,
              render: (_, r) => (
                <Space>
                  <button
                    className="text-button"
                    onClick={() => navigate(`/catalog/${kind}/${r.id}/detail`)}
                  >
                    详情
                  </button>
                  <button className="text-button" onClick={() => edit(r)}>
                    {canEdit && editable(r.status) ? "编辑" : "查看"}
                  </button>
                  {canEdit && editable(r.status) && (
                    <button
                      className="text-button"
                      onClick={() => action(r, "submit")}
                    >
                      提交审核
                    </button>
                  )}
                  {actor.role === "admin" && r.status === "PENDING" && (
                    <button
                      className="text-button"
                      onClick={() => action(r, "publish")}
                    >
                      审核发布
                    </button>
                  )}
                  {actor.role === "admin" && r.status === "PUBLISHED" && (
                    <button
                      className="text-button muted"
                      onClick={() => action(r, "offline")}
                    >
                      下架
                    </button>
                  )}
                  {canEdit &&
                    (editable(r.status) ||
                      r.status === "ARCHIVED" ||
                      (actor.role === "admin" && r.status === "PENDING")) && (
                      <Dropdown
                        menu={{
                          items:
                            r.status === "PENDING"
                              ? [{ key: "reject", label: "驳回审核" }]
                              : r.status === "ARCHIVED"
                                ? [
                                    { key: "restore", label: "恢复草稿" },
                                    ...(actor.role === "admin"
                                      ? [
                                          {
                                            key: "delete",
                                            label: "永久删除",
                                            danger: true,
                                          },
                                        ]
                                      : []),
                                  ]
                                : actor.role === "admin"
                                  ? [
                                      { key: "archive", label: "归档" },
                                      ...(r.status === "DRAFT" ||
                                      r.status === "OFFLINE"
                                        ? [
                                            {
                                              key: "delete",
                                              label: "永久删除",
                                              danger: true,
                                            },
                                          ]
                                        : []),
                                    ]
                                  : [],
                          onClick: ({ key }) => action(r, key),
                        }}
                      >
                        <button className="text-button">更多</button>
                      </Dropdown>
                    )}
                </Space>
              ),
            },
          ]}
        />
      </section>
      <Drawer
        open={open}
        onClose={() => setOpen(false)}
        width={640}
        title={`${record ? (readOnly ? "查看" : "编辑") : "新建"}${label}`}
        extra={record && <StatusTag status={record.status} />}
        footer={
          <div className="drawer-footer">
            <Button onClick={() => setOpen(false)}>取消</Button>
            {canEdit && !readOnly && (
              <Button type="primary" loading={busy} onClick={save}>
                保存草稿
              </Button>
            )}
            {readOnly && (
              <span className="subtle-note">
                已发布或待审核内容需先下架／驳回后编辑
              </span>
            )}
          </div>
        }
      >
        <Form form={form} layout="vertical" disabled={!canEdit || readOnly}>
          {kind === "others" ? (
            <div className="form-grid">
              <Form.Item
                name="name"
                label="Name / 展示名称"
                rules={[{ required: true }]}
              >
                <Input maxLength={120} />
              </Form.Item>
              <Form.Item name="original_name" label="Original Name / 原始名称">
                <Input maxLength={180} />
              </Form.Item>
              <Form.Item name="start_date" label="Start Date / 开始日期">
                <Input type="date" />
              </Form.Item>
              <Form.Item name="end_date" label="End Date / 结束日期">
                <Input type="date" />
              </Form.Item>
              <div className="span-two">
                <Form.Item name="description" label="Description / 说明">
                  <Input.TextArea rows={4} maxLength={2000} />
                </Form.Item>
                <Form.Item name="tags" label="Tags">
                  <TagSelect entityType="OTHER" />
                </Form.Item>
              </div>
            </div>
          ) : (
            <>
              <div className="form-grid">
                <Form.Item
                  name="name"
                  label={`${label}名称 / 官方名称`}
                  rules={[{ required: true, message: `请填写${label}名称` }]}
                  extra={
                    kind === "albums"
                      ? "填写专辑作品名，版本名在专辑版本中单独维护。"
                      : undefined
                  }
                >
                  <Input maxLength={120} />
                </Form.Item>
                <Form.Item name="name_translated" label="中文名称">
                  <Input />
                </Form.Item>
                <Form.Item name="name_en" label="英文名称">
                  <Input />
                </Form.Item>
                <Form.Item name="name_ko" label="韩文名称">
                  <Input />
                </Form.Item>
                {kind === "idols" && (
                  <Form.Item name="group_id" label="所属组合">
                    <Select
                      disabled={!!record}
                      allowClear
                      placeholder="独立 Solo 艺人可不选择组合"
                      options={catalog.groups.map((g) => ({
                        value: g.id,
                        label: g.name,
                      }))}
                    />
                  </Form.Item>
                )}
                {!["groups", "idols"].includes(kind) && (
                  <Form.Item
                    name="artist_keys"
                    label="发行 / 活动艺人（组合、个人、合作）"
                    initialValue={
                      record?.artists?.map(
                        (a: { type: string; id: string }) =>
                          `${a.type}:${a.id}`,
                      ) ||
                      (record?.group_id
                        ? [`groups:${record.group_id}`]
                        : undefined)
                    }
                    rules={[
                      {
                        required: true,
                        message: "请至少选择一个组合或个人艺人",
                      },
                    ]}
                  >
                    <Select
                      mode="multiple"
                      showSearch
                      optionFilterProp="label"
                      options={[
                        ...catalog.groups.map((g) => ({
                          value: `groups:${g.id}`,
                          label: `组合 · ${g.name}`,
                        })),
                        ...catalog.idols.map((i) => ({
                          value: `idols:${i.id}`,
                          label: `个人 · ${i.name}`,
                        })),
                      ]}
                    />
                  </Form.Item>
                )}
                {kind === "albums" && (
                  <Form.Item
                    name="versions"
                    label="专辑版本"
                    extra="输入版本名后回车，可维护多个版本；专辑名称不会拼接版本名。"
                  >
                    <Select
                      mode="tags"
                      tokenSeparators={["|"]}
                      placeholder="如 Photo Book Ver. / Digipack Ver."
                    />
                  </Form.Item>
                )}
                {kind === "events" && (
                  <>
                    <Form.Item name="end_date" label="结束日期">
                      <Input type="date" />
                    </Form.Item>
                    <Form.Item
                      name="is_online"
                      label="活动方式"
                      initialValue={false}
                    >
                      <Select
                        options={[
                          { value: false, label: "线下活动" },
                          { value: true, label: "线上活动" },
                        ]}
                      />
                    </Form.Item>
                    {isOnline ? (
                      <Form.Item
                        name="platform"
                        label="平台"
                        rules={[
                          {
                            required: true,
                            whitespace: true,
                            message: "请填写线上平台",
                          },
                        ]}
                      >
                        <Input
                          maxLength={120}
                          placeholder="如 Weverse、YouTube"
                        />
                      </Form.Item>
                    ) : (
                      <Form.Item
                        name="city"
                        label="城市"
                        rules={[
                          {
                            required: true,
                            whitespace: true,
                            message: "请填写线下活动城市",
                          },
                        ]}
                      >
                        <Input />
                      </Form.Item>
                    )}
                    <Form.Item name="venue" label="场馆">
                      <Input />
                    </Form.Item>
                    <Form.Item name="parent_event_id" label="父活动 / 巡演">
                      <Select
                        allowClear
                        options={catalog.events
                          .filter((e) => e.id !== record?.id)
                          .map((e) => ({ value: e.id, label: e.name }))}
                      />
                    </Form.Item>
                    <Form.Item name="album_id" label="关联专辑">
                      <Select
                        allowClear
                        options={catalog.albums.map((e) => ({
                          value: e.id,
                          label: e.name,
                        }))}
                      />
                    </Form.Item>
                    <Form.Item name="business_status" label="活动状态">
                      <Select
                        options={["Upcoming", "Ended", "Cancelled"].map(
                          (value) => ({ value, label: value }),
                        )}
                      />
                    </Form.Item>
                  </>
                )}
                {kind === "groups" && (
                  <>
                    <Form.Item name="business_status" label="组合状态">
                      <Select
                        options={["Active", "Hiatus", "Disbanded"].map(
                          (value) => ({
                            value,
                            label: value,
                          }),
                        )}
                      />
                    </Form.Item>
                    <Form.Item name="end_date" label="解散日期">
                      <Input type="date" />
                    </Form.Item>
                    <Form.Item name="fandom_name" label="粉丝名称">
                      <Input />
                    </Form.Item>
                    <Form.Item name="official_website" label="官方网站">
                      <Input />
                    </Form.Item>
                  </>
                )}
                {kind === "idols" && (
                  <>
                    <Form.Item name="real_name" label="本名">
                      <Input />
                    </Form.Item>
                    <Form.Item name="gender" label="性别">
                      <Input />
                    </Form.Item>
                  </>
                )}
                <Form.Item name="aliases" label="别名">
                  <Select mode="tags" />
                </Form.Item>
                {["groups", "idols"].includes(kind) && (
                  <>
                    <Form.Item
                      name="company_ids"
                      label="所属公司"
                      extra={
                        record?.company && !record.company_ids?.length
                          ? `原始公司：${record.company}；未选择时保留原值。`
                          : "选择公司管理中的公司；公司变更会保留原有经历。"
                      }
                    >
                      <Select
                        mode="multiple"
                        allowClear
                        showSearch
                        optionFilterProp="label"
                        placeholder="请选择公司"
                        options={companies.map((c) => ({
                          value: c.id,
                          label: c.data.name,
                        }))}
                      />
                    </Form.Item>
                    {selectedCompanies !== undefined &&
                      [...selectedCompanies].sort().join() !==
                        [...(record?.company_ids || [])].sort().join() &&
                      (selectedCompanies.length > 0 ||
                        !!record?.company_ids?.length) && (
                        <Form.Item
                          name="company_effective_date"
                          label="公司归属生效日期"
                          extra="首次建立关系可留空，表示日期待核实；已有关系变更时必填。"
                          rules={[
                            {
                              required:
                                !!record?.company_ids?.length &&
                                [...selectedCompanies].sort().join() !==
                                  [...record.company_ids].sort().join(),
                            },
                          ]}
                        >
                          <Input type="date" />
                        </Form.Item>
                      )}
                    <Form.Item name="cover_image" label="封面图片">
                      <ImageUpload label="封面图片" />
                    </Form.Item>
                  </>
                )}
                <Form.Item
                  name="release_date"
                  label={
                    kind === "groups"
                      ? "出道日期"
                      : kind === "idols"
                        ? "出生日期"
                        : "发行 / 开始日期"
                  }
                >
                  <Input type="date" />
                </Form.Item>
                {!["groups", "idols"].includes(kind) && (
                  <Form.Item name="type" label="类型">
                    <Input
                      placeholder={
                        kind === "albums"
                          ? "Mini Album"
                          : "如：Fansign / Concert"
                      }
                    />
                  </Form.Item>
                )}
                <Form.Item name="region" label="地区 / 国籍">
                  <Input />
                </Form.Item>
                <div className="span-two">
                  <Form.Item name="description" label="简介">
                    <Input.TextArea rows={4} />
                  </Form.Item>
                  <Form.Item name="tags" label="标签">
                    {kind === "albums" || kind === "events" ? (
                      <TagSelect
                        entityType={kind === "albums" ? "ALBUM" : "EVENT"}
                      />
                    ) : (
                      <Select mode="tags" tokenSeparators={[",", "，"]} />
                    )}
                  </Form.Item>
                  <Form.Item
                    name="image_url"
                    label={kind === "idols" ? "艺人头像" : "封面 / 头像"}
                  >
                    <ImageUpload
                      label="封面图片"
                      disabled={!canEdit || readOnly}
                    />
                  </Form.Item>
                </div>
              </div>
              <h3 className="form-section-title">
                来源与版权 <Tag>仅内部可见</Tag>
              </h3>
              <div className="form-grid">
                <Form.Item
                  name={["source_info", "source_type"]}
                  label="来源类型"
                >
                  <Select
                    options={[
                      "OFFICIAL",
                      "SOCIAL_MEDIA",
                      "ADMIN_UPLOAD",
                      "PARTNER",
                      "OTHER",
                    ].map((value) => ({ value, label: value }))}
                  />
                </Form.Item>
                <Form.Item
                  name={["source_info", "copyright_status"]}
                  label="版权状态"
                >
                  <Select
                    options={[
                      "UNKNOWN",
                      "AUTHORIZED",
                      "OFFICIAL_SOURCE",
                      "RESTRICTED",
                    ].map((value) => ({ value, label: value }))}
                  />
                </Form.Item>
                <div className="span-two">
                  <Form.Item
                    name={["source_info", "source_url"]}
                    label="来源链接"
                    rules={[
                      { type: "url", message: "请输入有效的 HTTP(S) 链接" },
                    ]}
                  >
                    <Input placeholder="https://" />
                  </Form.Item>
                </div>
              </div>
            </>
          )}
        </Form>
      </Drawer>
    </>
  );
}

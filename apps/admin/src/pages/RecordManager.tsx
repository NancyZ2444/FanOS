import { useSingleSubmit } from "../components/admin";
import { displayValue } from "../design/format";
import {
  TableToolbar,
  RowActions,
  BusinessData,
  FilterBar,
} from "../components/admin";
import { Drawer, Form, Modal, Table } from "../components/admin";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  App,
  Button,
  Descriptions,
  Input,
  InputNumber,
  Image,
  Select,
  Space,
  Spin,
  Tag,
} from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import { groupMembers, memberLabel } from "./memberOptions";
import { ImageUpload } from "../components/shared";

const labels: Record<string, string> = {
  versions: "版本",
  sources: "来源关联",
  memberships: "成员关系",
  companies: "公司",
  company_relations: "公司经历",
  batches: "小卡批次",
};
export default function RecordManager({
  kind,
  entityType = "",
  entityId = "",
  onSaved,
}: {
  kind: string;
  entityType?: string;
  entityId?: string;
  onSaved?: () => void;
}) {
  const { catalog, actor, reload } = useConsole();
  const navigate = useNavigate();
  const { message, modal } = App.useApp();
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<any[]>([]);
  const [companies, setCompanies] = useState<any[]>([]);
  const [versions, setVersions] = useState<any[]>([]);
  const [current, setCurrent] = useState<any>();
  const [viewRecord, setViewRecord] = useState<any>();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [companyDetailOpen, setCompanyDetailOpen] = useState(false);
  const [companyDetailBusy, setCompanyDetailBusy] = useState(false);
  const [companyDetail, setCompanyDetail] = useState<any>();
  const [members, setMembers] = useState<string[]>([]);
  const [per, setPer] = useState(1);
  const [validation, setValidation] = useState<any[]>([]);
  const [form] = Form.useForm();
  const sourceId = Form.useWatch("source_entity_id", form);
  useEffect(() => {
    if (kind === "batches" && sourceId)
      consoleApi(`/records/versions?entity_id=${sourceId}`)
        .then((d) => setVersions(d.items))
        .catch((e) => message.error(e.message));
    else setVersions([]);
  }, [kind, sourceId]);
  const batchCards = catalog.cards.filter(
    (c) =>
      current &&
      (c.batch_id === current.id || current.data.card_ids?.includes(c.id)),
  );
  const load = () =>
    consoleApi(`/records/${kind}${entityId ? `?entity_id=${entityId}` : ""}`)
      .then((d) => {
        setRows(d.items);
        setCurrent((r: any) =>
          r ? d.items.find((item: any) => item.id === r.id) || r : r,
        );
      })
      .catch((e) => message.error(e.message));
  useEffect(() => {
    load();
    if (kind === "company_relations")
      consoleApi("/records/companies")
        .then((d) => setCompanies(d.items))
        .catch((e) => message.error(e.message));
  }, [kind, entityId]);
  const edit = (r?: any) => {
    if (kind === "company_relations")
      consoleApi("/records/companies")
        .then((d) => setCompanies(d.items))
        .catch((e) => message.error(e.message));
    setCurrent(r);
    form.resetFields();
    form.setFieldsValue(r?.data || {});
    setOpen(true);
  };
  const save = useSingleSubmit(async () => {
    try {
      const data = await form.validateFields();
      setBusy(true);
      await consoleApi(
        `/records/${kind}${current && !current.id.startsWith("legacy-") ? `/${current.id}` : ""}`,
        send(
          {
            entity_type: entityType,
            entity_id: entityId,
            data: ["companies", "company_relations"].includes(kind)
              ? { ...current?.data, ...data }
              : data,
          },
          current && !current.id.startsWith("legacy-") ? "PUT" : "POST",
        ),
      );
      setOpen(false);
      message.success("已保存");
      await load();
      await reload();
      onSaved?.();
    } catch (e) {
      if (e instanceof Error) message.error(e.message);
    } finally {
      setBusy(false);
    }
  });
  const sources = Object.entries(catalog)
    .filter(([k]) => !["groups", "idols", "cards"].includes(k))
    .flatMap(([k, items]) =>
      items.map((e: any) => ({ value: `${k}:${e.id}`, label: e.name })),
    );
  const batchAction = async (id: string, action: string, body: object = {}) => {
    try {
      const result = await consoleApi(`/batches/${id}/${action}`, send(body));
      setValidation(result.items || []);
      await load();
      await reload();
      message.success("操作完成");
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  const viewCompany = async (row: any) => {
    setCompanyDetailOpen(true);
    setCompanyDetail({ company: row, groups: [], idols: [] });
    setCompanyDetailBusy(true);
    try {
      setCompanyDetail(await consoleApi(`/records/companies/${row.id}/detail`));
    } catch (e) {
      message.error((e as Error).message);
      setCompanyDetailOpen(false);
    } finally {
      setCompanyDetailBusy(false);
    }
  };
  const companyRelationColumns = (entityKind: "groups" | "idols") => [
    {
      title: entityKind === "groups" ? "组合" : "艺人",
      dataIndex: "name",
      render: (name: string, row: any) => (
        <Button
          type="link"
          onClick={() =>
            navigate(
              `/catalog/${entityKind}/${encodeURIComponent(row.entity_id)}/detail`,
            )
          }
        >
          {name}
        </Button>
      ),
    },
    ...(entityKind === "idols"
      ? [
          {
            title: "所属组合",
            render: (_: unknown, row: any) =>
              row.groups?.map((group: any) => group.name).join(" / ") || "—",
          },
        ]
      : []),
    {
      title: "关联状态",
      dataIndex: "relation_status",
      render: (status: string) => (
        <Tag color={status === "current" ? "green" : "default"}>
          {status === "current" ? "当前关联" : "历史关联"}
        </Tag>
      ),
    },
    {
      title: "有效期",
      render: (_: unknown, row: any) =>
        row.date_unknown
          ? "开始日期待核实"
          : `${row.start_date || "—"} 至 ${row.end_date || "至今"}`,
    },
    { title: "档案状态", dataIndex: "status" },
  ];
  return (
    <>
      <FilterBar onReset={() => setQ("")}>
        <Input
          allowClear
          placeholder={`搜索${labels[kind]}名称或编号`}
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
      </FilterBar>
      <TableToolbar
        actions={
          <>
            <Button onClick={load}>刷新</Button>
            {kind === "companies" && actor.role !== "operation_admin" && (
              <Button
                onClick={() => navigate("/catalog/import?kind=companies")}
              >
                批量导入公司
              </Button>
            )}
            {actor.role !== "operation_admin" && (
              <Button type="primary" onClick={() => edit()}>
                新增{labels[kind]}
              </Button>
            )}
          </>
        }
      >
        {labels[kind]}记录
      </TableToolbar>
      <Table
        rowKey="id"
        dataSource={rows.filter(
          (r) =>
            !q ||
            [r.id, r.data.name, r.data.group_id, r.data.company_id].some((v) =>
              v?.toLowerCase().includes(q.toLowerCase()),
            ),
        )}
        filtered={!!q}
        onReset={() => setQ("")}
        onCreate={actor.role !== "operation_admin" ? () => edit() : undefined}
        createLabel={`新增${labels[kind]}`}
        pagination={{ defaultPageSize: 10 }}
        columns={[
          {
            title: "名称 / 关系",
            render: (_, r) =>
              r.data.name ||
              catalog.groups.find((g) => g.id === r.data.group_id)?.name ||
              companies.find((c) => c.id === r.data.company_id)?.data.name ||
              sources.find((s) => s.value === `${r.data.type}:${r.data.id}`)
                ?.label ||
              r.id,
          },
          {
            title: "状态 / 有效期",
            render: (_, r) =>
              `${displayValue(r.data.status || r.status)} ${r.data.start_date || (r.data.date_unknown ? "开始日期待核实" : r.data.release_date || "")} ${r.data.end_date || ""}`,
          },
          ...(kind === "companies"
            ? [
                {
                  title: "关联组合",
                  render: (_: unknown, r: any) => (
                    <Space size={4}>
                      <b>{r.group_count || 0}</b>
                      <span>当前</span>
                      {!!r.group_history_count && (
                        <Tag>历史 {r.group_history_count}</Tag>
                      )}
                    </Space>
                  ),
                },
                {
                  title: "关联艺人",
                  render: (_: unknown, r: any) => (
                    <Space size={4}>
                      <b>{r.idol_count || 0}</b>
                      <span>当前</span>
                      {!!r.idol_history_count && (
                        <Tag>历史 {r.idol_history_count}</Tag>
                      )}
                    </Space>
                  ),
                },
              ]
            : []),
          {
            title: "操作",
            width: 200,
            render: (_, r) => (
              <RowActions
                onView={() =>
                  kind === "companies" ? viewCompany(r) : setViewRecord(r)
                }
                onEdit={
                  actor.role !== "operation_admin" ? () => edit(r) : undefined
                }
                items={[
                  ...(kind === "batches"
                    ? [
                        {
                          key: "select",
                          label: "选择批次",
                          onClick: () => {
                            setCurrent(r);
                            setMembers([]);
                            setValidation([]);
                          },
                        },
                        {
                          key: "validate",
                          label: "全部校验",
                          onClick: () => batchAction(r.id, "validate"),
                        },
                        ...(actor.role === "admin"
                          ? [
                              {
                                key: "publish",
                                label: "发布合格卡",
                                onClick: () =>
                                  modal.confirm({
                                    title: "发布所有校验通过的小卡？",
                                    okText: "发布",
                                    cancelText: "取消",
                                    onOk: () =>
                                      batchAction(r.id, "publish-ready"),
                                  }),
                              },
                            ]
                          : []),
                      ]
                    : []),
                  ...(actor.role === "admin" &&
                  !["memberships", "company_relations"].includes(kind)
                    ? [
                        {
                          key: "delete",
                          label: "删除",
                          danger: true,
                          onClick: () =>
                            modal.confirm({
                              title: `删除「${r.data.name || labels[kind]}」？`,
                              content:
                                "将删除 1 条记录，删除不可恢复。被引用的记录会阻止删除，请先在关联内容中解除关系。",
                              okText: "删除",
                              cancelText: "取消",
                              okButtonProps: { danger: true },
                              onOk: async () => {
                                try {
                                  await consoleApi(`/records/${kind}/${r.id}`, {
                                    method: "DELETE",
                                  });
                                  await load();
                                  await reload();
                                  onSaved?.();
                                  message.success("已删除");
                                } catch (e) {
                                  message.error((e as Error).message);
                                  throw e;
                                }
                              },
                            }),
                        },
                      ]
                    : []),
                ]}
              />
            ),
          },
        ]}
      />
      {kind === "batches" && current && !open && (
        <section className="panel" style={{ padding: 16 }}>
          <h3>
            {current.data.name} · {batchCards.length} 张
          </h3>
          <Space wrap style={{ marginBottom: 12 }}>
            <Tag>
              正面已上传 {batchCards.filter((c) => c.image_url).length} /{" "}
              {batchCards.length}
            </Tag>
            <Tag>
              校验通过 {validation.filter((r) => !r.errors?.length).length} /{" "}
              {validation.length || "未校验"}
            </Tag>
            <Tag>
              已发布 {batchCards.filter((c) => c.status === "PUBLISHED").length}
            </Tag>
            <Button
              onClick={() =>
                navigate(`/catalog/workbench?tab=images&batch_id=${current.id}`)
              }
            >
              上传图片
            </Button>
            <Button
              onClick={() =>
                navigate(`/catalog/workbench?tab=bulk&batch_id=${current.id}`)
              }
            >
              批量编辑
            </Button>
          </Space>
          <Space wrap>
            <Select
              mode="multiple"
              aria-label="选择成员"
              placeholder="选择成员"
              style={{ minWidth: 260 }}
              value={members}
              onChange={setMembers}
              options={groupMembers(catalog.idols, current.data.group_id).map(
                (i) => ({
                  value: i.id,
                  label: memberLabel(i, current.data.group_id),
                }),
              )}
            />
            <InputNumber
              min={1}
              max={10}
              value={per}
              onChange={(v) => setPer(v || 1)}
            />
            <Button
              disabled={
                !members.length ||
                !!current.data.card_ids?.length ||
                !!current.data.generated_at
              }
              onClick={() =>
                batchAction(current.id, "generate", {
                  member_ids: members,
                  cards_per_member: per,
                })
              }
            >
              生成成员草稿
            </Button>
          </Space>
          <Table
            rowKey="id"
            dataSource={batchCards.map((c) => ({
              ...c,
              errors: validation.find((r) => r.id === c.id)?.errors,
            }))}
            columns={[
              {
                title: "小卡",
                dataIndex: "title",
                render: (title, r) => (
                  <Button
                    type="link"
                    onClick={() => navigate(`/catalog/cards/${r.id}`)}
                  >
                    {title}
                  </Button>
                ),
              },
              { title: "艺人", dataIndex: "idol_name" },
              {
                title: "正面",
                render: (_, r) =>
                  r.image_url ? (
                    <Image width={45} src={r.image_url} />
                  ) : (
                    "缺少图片"
                  ),
              },
              {
                title: "背面",
                render: (_, r) =>
                  r.back_image_url ? (
                    <Image width={45} src={r.back_image_url} />
                  ) : (
                    "—"
                  ),
              },
              { title: "状态", dataIndex: "status" },
              {
                title: "校验",
                render: (_, r) =>
                  r.errors === undefined
                    ? "未校验"
                    : r.errors.length
                      ? r.errors.map((e: any) => e.message).join("；")
                      : "通过",
              },
              {
                title: "操作",
                render: (_, r) =>
                  actor.role !== "operation_admin" &&
                  ["DRAFT", "REJECTED", "OFFLINE", "ARCHIVED"].includes(
                    r.status,
                  ) && (
                    <Button
                      danger
                      type="link"
                      onClick={() =>
                        modal.confirm({
                          title: "解除小卡与当前批次的关联？",
                          content:
                            "小卡和其他归属保留。此操作会记录到变更历史。",
                          onOk: () =>
                            batchAction(current.id, "remove-card", {
                              card_id: r.id,
                            }),
                        })
                      }
                    >
                      解除批次关联
                    </Button>
                  ),
              },
            ]}
          />
        </section>
      )}
      <Drawer
        title={companyDetail?.company?.data?.name || "公司详情"}
        extra={
          companyDetail?.company && actor.role !== "operation_admin" ? (
            <Button
              onClick={() => {
                edit(companyDetail.company);
                setCompanyDetailOpen(false);
              }}
            >
              编辑
            </Button>
          ) : undefined
        }
        open={companyDetailOpen}
        onClose={() => setCompanyDetailOpen(false)}
        width={820}
        destroyOnHidden
      >
        <Spin spinning={companyDetailBusy}>
          {companyDetail && (
            <Space direction="vertical" size={24} style={{ width: "100%" }}>
              <Descriptions bordered size="small" column={{ xs: 1, sm: 2 }}>
                <Descriptions.Item label="公司 ID">
                  {companyDetail.company.id}
                </Descriptions.Item>
                <Descriptions.Item label="状态">
                  {displayValue(companyDetail.company.status)}
                </Descriptions.Item>
                <Descriptions.Item label="当前关联组合">
                  {companyDetail.company.group_count || 0}
                </Descriptions.Item>
                <Descriptions.Item label="当前关联艺人">
                  {companyDetail.company.idol_count || 0}
                </Descriptions.Item>
                <Descriptions.Item label="描述" span={2}>
                  {companyDetail.company.data?.description || "—"}
                </Descriptions.Item>
              </Descriptions>
              <section style={{ width: "100%" }}>
                <h3>关联组合（{companyDetail.groups?.length || 0}）</h3>
                <Table
                  rowKey="relation_id"
                  size="small"
                  pagination={false}
                  dataSource={companyDetail.groups || []}
                  columns={companyRelationColumns("groups")}
                  scroll={{ x: 620 }}
                />
              </section>
              <section style={{ width: "100%" }}>
                <h3>关联艺人（{companyDetail.idols?.length || 0}）</h3>
                <Table
                  rowKey="relation_id"
                  size="small"
                  pagination={false}
                  dataSource={companyDetail.idols || []}
                  columns={companyRelationColumns("idols")}
                  scroll={{ x: 720 }}
                />
              </section>
            </Space>
          )}
        </Spin>
      </Drawer>
      <Drawer
        open={!!viewRecord}
        title={`${labels[kind]}详情`}
        onClose={() => setViewRecord(undefined)}
        extra={
          actor.role !== "operation_admin" ? (
            <Button
              onClick={() => {
                edit(viewRecord);
                setViewRecord(undefined);
              }}
            >
              编辑
            </Button>
          ) : undefined
        }
      >
        <BusinessData data={viewRecord?.data} />
      </Drawer>
      <Modal
        title={`${current ? "编辑" : "新增"}${labels[kind]}`}
        open={open}
        onCancel={() => setOpen(false)}
        onOk={save}
        confirmLoading={busy}
        destroyOnHidden
      >
        <Form form={form} layout="vertical">
          {["versions", "companies", "batches"].includes(kind) && (
            <Form.Item name="name" label="名称" rules={[{ required: true }]}>
              <Input />
            </Form.Item>
          )}
          {kind === "versions" && (
            <>
              <Form.Item name="code" label="版本编码">
                <Input />
              </Form.Item>
              <Form.Item name="release_date" label="发行日期">
                <Input type="date" />
              </Form.Item>
              <Form.Item name="cover" label="版本封面">
                <ImageUpload label="版本封面" />
              </Form.Item>
              <Form.Item name="description" label="描述">
                <Input.TextArea />
              </Form.Item>
            </>
          )}
          {kind === "companies" && (
            <Form.Item name="description" label="描述">
              <Input.TextArea maxLength={2000} />
            </Form.Item>
          )}
          {kind === "sources" && (
            <Form.Item
              name="source_key"
              label="上游来源"
              rules={[{ required: true }]}
            >
              <Select
                showSearch
                optionFilterProp="label"
                options={sources.filter(
                  (s) => !s.value.endsWith(`:${entityId}`),
                )}
                onChange={(value) => {
                  const [type, id] = value.split(":");
                  form.setFieldsValue({ type, id });
                }}
              />
            </Form.Item>
          )}
          {kind === "sources" && (
            <>
              <Form.Item name="type" hidden>
                <Input />
              </Form.Item>
              <Form.Item name="id" hidden>
                <Input />
              </Form.Item>
            </>
          )}
          {kind === "memberships" && (
            <>
              <Form.Item
                name="group_id"
                label="组合"
                rules={[{ required: true }]}
              >
                <Select
                  disabled={!!current}
                  options={catalog.groups.map((g) => ({
                    value: g.id,
                    label: g.name,
                  }))}
                />
              </Form.Item>
              <Form.Item name="status" label="成员状态" initialValue="active">
                <Select
                  options={[
                    { value: "active", label: "活动中" },
                    { value: "inactive", label: "活动暂停" },
                    { value: "former", label: "已退出" },
                  ]}
                />
              </Form.Item>
              <Form.Item name="relationship_type" label="身份">
                <Select
                  options={["MEMBER", "SUB_UNIT", "SOLO", "PROJECT_GROUP"].map(
                    (value) => ({ value, label: displayValue(value) }),
                  )}
                />
              </Form.Item>
              <Form.Item name="is_primary" label="主身份">
                <Select
                  options={[
                    { value: true, label: "是" },
                    { value: false, label: "否" },
                  ]}
                />
              </Form.Item>
              <Form.Item name="member_role" label="成员职务">
                <Input />
              </Form.Item>
              <Form.Item name="display_order" label="显示顺序">
                <InputNumber min={0} />
              </Form.Item>
              <Form.Item name="is_original_member" label="初始成员">
                <Select
                  options={[
                    { value: true, label: "是" },
                    { value: false, label: "否" },
                  ]}
                />
              </Form.Item>
              <Form.Item name="membership_id" hidden>
                <Input />
              </Form.Item>
            </>
          )}
          {kind === "company_relations" && (
            <>
              <Form.Item
                name="company_id"
                label="公司"
                rules={[{ required: true }]}
              >
                <Select
                  options={companies.map((c) => ({
                    value: c.id,
                    label: c.data.name,
                  }))}
                />
              </Form.Item>
              <Form.Item name="relation_type" label="关系类型">
                <Input placeholder="Agency / Label" />
              </Form.Item>
            </>
          )}
          {["memberships", "company_relations"].includes(kind) && (
            <>
              <Form.Item
                name="start_date"
                label="开始日期"
                extra={
                  kind === "company_relations" && current?.data.date_unknown
                    ? "原始数据未提供开始日期，可保持待核实。"
                    : undefined
                }
                rules={[
                  {
                    required:
                      kind === "memberships" || !current?.data.date_unknown,
                  },
                ]}
              >
                <Input type="date" />
              </Form.Item>
              <Form.Item name="end_date" label="结束日期">
                <Input type="date" />
              </Form.Item>
              <Form.Item name="remark" label="备注">
                <Input.TextArea />
              </Form.Item>
            </>
          )}
          {kind === "batches" && (
            <>
              <Form.Item name="group_id" label="组合（Solo 可留空）">
                <Select
                  allowClear
                  options={catalog.groups.map((g) => ({
                    value: g.id,
                    label: g.name,
                  }))}
                />
              </Form.Item>
              <Form.Item
                name="source_key"
                label="发行来源"
                rules={[{ required: true }]}
              >
                <Select
                  options={sources}
                  onChange={(value) => {
                    const [k, id] = value.split(":");
                    form.setFieldsValue({
                      source_entity_id: id,
                      source_entity_type: (
                        {
                          albums: "ALBUM",
                          events: "EVENT",
                          others: "OTHER",
                        } as Record<string, string>
                      )[k],
                    });
                  }}
                />
              </Form.Item>
              <Form.Item name="source_entity_id" hidden>
                <Input />
              </Form.Item>
              <Form.Item name="source_entity_type" hidden>
                <Input />
              </Form.Item>
              <Form.Item name="entity_version_id" label="发行版本">
                <Select
                  allowClear
                  options={versions.map((v) => ({
                    value: v.id,
                    label: v.data.name,
                  }))}
                  onChange={(id) =>
                    form.setFieldsValue({
                      version:
                        versions.find((v) => v.id === id)?.data.name || "",
                    })
                  }
                />
              </Form.Item>
              <Form.Item name="version" label="版本文本">
                <Input />
              </Form.Item>
              <Form.Item name="edition" label="Edition">
                <Input />
              </Form.Item>
              <Form.Item name="card_type" label="卡类型">
                <Input />
              </Form.Item>
              <Form.Item name="release_date" label="发行日期">
                <Input type="date" />
              </Form.Item>
              <Form.Item name="tags" label="标签">
                <Select mode="tags" />
              </Form.Item>
            </>
          )}
        </Form>
      </Modal>
    </>
  );
}

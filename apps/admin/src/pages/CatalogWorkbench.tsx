import TagSelect from "../components/TagSelect";
import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  App,
  Alert,
  Button,
  Form,
  Input,
  Modal,
  Select,
  Space,
  Table,
  Tabs,
  Tag,
} from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import RecordManager from "./RecordManager";
import { groupMembers, memberLabel } from "./memberOptions";

export default function CatalogWorkbench({ mode }: { mode: string }) {
  const { catalog, actor, reload } = useConsole();
  const { message, modal } = App.useApp();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [rows, setRows] = useState<any[]>([]);
  const [quality, setQuality] = useState<any[]>([]);
  const [q, setQ] = useState("");
  const [selected, setSelected] = useState<React.Key[]>([]);
  const [preview, setPreview] = useState<any[]>([]);
  const [changes, setChanges] = useState<any>();
  const [form] = Form.useForm();
  const selectedGroup = Form.useWatch("group_id", form);
  const [review, setReview] = useState<any>();
  const [target, setTarget] = useState<string>();
  const [reason, setReason] = useState("");
  const [mergeSource, setMergeSource] = useState<string>();
  const [mergeTarget, setMergeTarget] = useState<string>();
  const [mergePlan, setMergePlan] = useState<any>();
  const [suggested, setSuggested] = useState<any[]>([]);
  const [images, setImages] = useState<
    { file: File; card_id?: string; side: string }[]
  >([]);
  const changedFields = (row: any) =>
    [
      "group_id",
      "idol_id",
      "source_entity_type",
      "source_entity_id",
      "entity_version_id",
      "version",
      "edition",
      "card_type",
      "tags",
      "is_official",
      "is_limited",
    ].filter(
      (k) => JSON.stringify(row.before[k]) !== JSON.stringify(row.after[k]),
    );
  const load = () => {
    if (mode === "scan")
      consoleApi("/scan-index")
        .then((d) => setRows(d.items))
        .catch((e) => message.error(e.message));
    if (mode === "review") {
      consoleApi("/review-queue")
        .then((d) => setRows(d.items))
        .catch((e) => message.error(e.message));
      consoleApi("/quality")
        .then((d) => setQuality(d.items))
        .catch((e) => message.error(e.message));
    }
  };
  useEffect(() => {
    load();
    setSelected([]);
    setPreview([]);
  }, [mode]);
  const bulk = async (apply = false) => {
    try {
      const values = apply ? changes : await form.validateFields();
      const filtered = Object.fromEntries(
        Object.entries(values).filter(
          ([k, v]) => k !== "source_key" && v !== undefined && v !== "",
        ),
      );
      const data = await consoleApi(
        "/cards/bulk-edit",
        send({
          ids: selected,
          changes: filtered,
          preview: !apply,
          expected: apply
            ? Object.fromEntries(preview.map((r) => [r.id, r.updated_at]))
            : {},
        }),
      );
      if (apply) {
        setPreview([]);
        setSelected([]);
        message.success("整批修改成功");
        await reload();
      } else {
        setChanges(filtered);
        setPreview(data.items);
      }
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  const act = async (action: string) => {
    try {
      await consoleApi(
        `/review-queue/${review.queue}/${review.id}/actions`,
        send({
          action,
          reason,
          card_id: target,
          changes: Object.fromEntries(
            suggested.map((s) => [
              s.field,
              s.edited && typeof s.original !== "string"
                ? JSON.parse(s.value)
                : s.value,
            ]),
          ),
        }),
      );
      setReview(undefined);
      load();
      await reload();
      message.success("审核已处理");
    } catch (e) {
      message.error((e as Error).message);
    }
  };
  const upload = async () => {
    try {
      if (images.some((i) => !i.card_id))
        throw new Error("请为每张图片指定小卡");
      for (const item of images) {
        const body = new FormData();
        body.append("file", item.file);
        const media = await consoleApi("/uploads", {
          method: "POST",
          body,
        });
        const card = (
          await consoleApi(`/entities/cards/${item.card_id}/detail`)
        ).entity;
        if (!["DRAFT", "REJECTED", "OFFLINE"].includes(card.status))
          throw new Error("请先下架小卡再替换图片");
        await consoleApi(
          `/cards/${card.id}`,
          send(
            {
              ...card,
              [item.side === "FRONT" ? "image_url" : "back_image_url"]:
                media.url,
              expected_updated_at: card.updated_at,
            },
            "PUT",
          ),
        );
        await reload();
      }
      message.success("图片上传完成，请补充来源后审核发布");
      setImages([]);
    } catch (e) {
      message.error((e as Error).message);
      await reload();
    }
  };
  const bulkPanel = (
    <section className="panel" style={{ padding: 16 }}>
      <Space wrap>
        <Input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="搜索小卡名称 / ID"
        />
        <Button onClick={() => navigate("/catalog/cards")}>小卡列表</Button>
      </Space>
      <Table
        rowKey="id"
        rowSelection={{ selectedRowKeys: selected, onChange: setSelected }}
        dataSource={catalog.cards.filter(
          (c) =>
            ["DRAFT", "REJECTED", "OFFLINE"].includes(c.status) &&
            (!params.get("batch_id") ||
              c.batch_id === params.get("batch_id")) &&
            `${c.title} ${c.id}`.includes(q),
        )}
        columns={[
          { title: "小卡", dataIndex: "title" },
          { title: "艺人", dataIndex: "idol_name" },
          { title: "来源", dataIndex: "source" },
          { title: "版本", dataIndex: "version" },
        ]}
      />
      <Form form={form} layout="inline">
        <Form.Item name="version" label="版本">
          <Input />
        </Form.Item>
        <Form.Item name="edition" label="Edition">
          <Input />
        </Form.Item>
        <Form.Item name="card_type" label="卡类型">
          <Input />
        </Form.Item>
        <Form.Item name="group_id" label="组合">
          <Select
            allowClear
            onChange={() => form.setFieldValue("idol_id", undefined)}
            style={{ width: 150 }}
            options={catalog.groups.map((g) => ({
              value: g.id,
              label: g.name,
            }))}
          />
        </Form.Item>
        <Form.Item name="idol_id" label="艺人">
          <Select
            allowClear
            style={{ width: 150 }}
            options={groupMembers(catalog.idols, selectedGroup).map((i) => ({
              value: i.id,
              label: memberLabel(i, selectedGroup),
            }))}
          />
        </Form.Item>
        <Form.Item name="source_key" label="来源">
          <Select
            style={{ width: 180 }}
            options={Object.entries(catalog)
              .filter(([k]) => !["groups", "idols", "cards"].includes(k))
              .flatMap(([k, items]) =>
                items.map((e: any) => ({
                  value: `${k}:${e.id}`,
                  label: e.name,
                })),
              )}
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
        <Form.Item name="add_tags" label="添加标签">
          <TagSelect entityType="CARD" />
        </Form.Item>
        <Form.Item name="remove_tags" label="移除标签">
          <TagSelect entityType="CARD" />
        </Form.Item>
        <Form.Item name="is_official" label="官方">
          <Select
            style={{ width: 100 }}
            options={[
              { value: true, label: "是" },
              { value: false, label: "否" },
            ]}
          />
        </Form.Item>
        <Form.Item name="is_limited" label="限定">
          <Select
            style={{ width: 100 }}
            options={[
              { value: true, label: "是" },
              { value: false, label: "否" },
            ]}
          />
        </Form.Item>
      </Form>
      <Button
        style={{ marginTop: 12 }}
        disabled={
          !selected.length ||
          selected.length > 100 ||
          actor.role === "operation_admin"
        }
        onClick={() => bulk()}
      >
        预览修改 {selected.length} 条
      </Button>
    </section>
  );
  return (
    <>
      <Space style={{ marginBottom: 16 }}>
        <h2>
          {
            {
              workbench: "批次与批量编辑",
              review: "图鉴审核与质量",
              scan: "AI Scan 索引",
              companies: "公司管理",
            }[mode]
          }
        </h2>
        <Button onClick={load}>刷新</Button>
      </Space>
      {mode === "companies" && (
        <section className="panel" style={{ padding: 16 }}>
          <RecordManager kind="companies" />
        </section>
      )}
      {mode === "workbench" && (
        <Tabs
          key={params.get("tab")}
          defaultActiveKey={params.get("tab") || "batches"}
          items={[
            {
              key: "merge",
              label: "人工合并小卡",
              children: (
                <section className="panel" style={{ padding: 16 }}>
                  <Space wrap>
                    <Select
                      style={{ width: 260 }}
                      placeholder="重复记录（将归档）"
                      value={mergeSource}
                      onChange={setMergeSource}
                      options={catalog.cards
                        .filter(
                          (c) => !["ARCHIVED", "PENDING"].includes(c.status),
                        )
                        .map((c) => ({ value: c.id, label: c.title }))}
                    />
                    <Select
                      style={{ width: 260 }}
                      placeholder="保留的主记录"
                      value={mergeTarget}
                      onChange={setMergeTarget}
                      options={catalog.cards
                        .filter((c) =>
                          ["PUBLISHED", "OFFLINE"].includes(c.status),
                        )
                        .map((c) => ({ value: c.id, label: c.title }))}
                    />
                    <Button
                      disabled={
                        actor.role !== "admin" ||
                        !mergeSource ||
                        !mergeTarget ||
                        mergeSource === mergeTarget
                      }
                      onClick={async () => {
                        try {
                          setMergePlan(
                            await consoleApi(
                              "/cards/merge",
                              send({
                                source_id: mergeSource,
                                target_id: mergeTarget,
                              }),
                            ),
                          );
                        } catch (e) {
                          message.error((e as Error).message);
                        }
                      }}
                    >
                      预览关联迁移
                    </Button>
                  </Space>
                </section>
              ),
            },
            {
              key: "batches",
              label: "小卡批次",
              children: (
                <section className="panel" style={{ padding: 16 }}>
                  <RecordManager kind="batches" />
                </section>
              ),
            },
            { key: "bulk", label: "批量编辑", children: bulkPanel },
            {
              key: "images",
              label: "图片批量上传",
              children: (
                <section className="panel" style={{ padding: 16 }}>
                  <Alert message="手动指定每张图片的小卡与正反面；不启用智能匹配。图片逐张保存，失败后已完成部分会保留。" />
                  <input
                    type="file"
                    multiple
                    accept="image/png,image/jpeg,image/webp"
                    aria-label="批量上传图片"
                    onChange={(e) =>
                      setImages(
                        Array.from(e.target.files || []).map((file) => ({
                          file,
                          side: "FRONT",
                        })),
                      )
                    }
                  />
                  <Table
                    rowKey={(_, i) => String(i)}
                    dataSource={images}
                    columns={[
                      { title: "文件", render: (_, r) => r.file.name },
                      {
                        title: "小卡",
                        render: (_, r, i) => (
                          <Select
                            style={{ width: 240 }}
                            value={r.card_id}
                            options={catalog.cards
                              .filter(
                                (c) =>
                                  ["DRAFT", "REJECTED", "OFFLINE"].includes(
                                    c.status,
                                  ) &&
                                  (!params.get("batch_id") ||
                                    c.batch_id === params.get("batch_id")),
                              )
                              .map((c) => ({ value: c.id, label: c.title }))}
                            onChange={(id) =>
                              setImages((old) =>
                                old.map((v, n) =>
                                  n === i ? { ...v, card_id: id } : v,
                                ),
                              )
                            }
                          />
                        ),
                      },
                      {
                        title: "图片面",
                        render: (_, r, i) => (
                          <Select
                            value={r.side}
                            options={[
                              { value: "FRONT", label: "正面" },
                              { value: "BACK", label: "背面" },
                            ]}
                            onChange={(side) =>
                              setImages((old) =>
                                old.map((v, n) =>
                                  n === i ? { ...v, side } : v,
                                ),
                              )
                            }
                          />
                        ),
                      },
                    ]}
                  />
                  <Button
                    disabled={
                      !images.length || actor.role === "operation_admin"
                    }
                    onClick={upload}
                  >
                    确认上传
                  </Button>
                </section>
              ),
            },
          ]}
        />
      )}
      {mode === "scan" && (
        <section className="panel">
          <Table
            rowKey="id"
            dataSource={rows}
            columns={[
              {
                title: "小卡",
                dataIndex: "title",
                render: (title, row) => (
                  <Button
                    type="link"
                    onClick={() => navigate(`/catalog/cards/${row.id}`)}
                  >
                    {title}
                  </Button>
                ),
              },
              {
                title: "索引状态",
                dataIndex: "status",
                render: (v) => <Tag>{v}</Tag>,
              },
              { title: "失败原因", dataIndex: "failure_reason" },
              { title: "尝试次数", dataIndex: "attempts" },
              {
                title: "操作",
                render: (_, row) => (
                  <Button
                    disabled={
                      actor.role === "operation_admin" ||
                      row.status === "Disabled"
                    }
                    onClick={async () => {
                      try {
                        await consoleApi(
                          `/scan-index/${row.id}/retry`,
                          send({}),
                        );
                        message.success("已提交索引任务");
                        load();
                      } catch (e) {
                        message.error((e as Error).message);
                      }
                    }}
                  >
                    重新生成
                  </Button>
                ),
              },
            ]}
          />
        </section>
      )}
      {mode === "review" && (
        <Tabs
          items={[
            {
              key: "review",
              label: "反馈审核",
              children: (
                <section className="panel">
                  <Table
                    rowKey="id"
                    dataSource={rows}
                    columns={[
                      { title: "类型", dataIndex: "queue" },
                      { title: "状态", dataIndex: "status" },
                      { title: "关联对象", dataIndex: "entity_id" },
                      {
                        title: "操作",
                        render: (_, row) => (
                          <Button
                            onClick={() => {
                              setReview(row);
                              setTarget(undefined);
                              setReason("");
                              setSuggested(
                                Object.entries(row.data.suggested || {}).map(
                                  ([field, value]) => ({
                                    field,
                                    value,
                                    original: value,
                                  }),
                                ),
                              );
                            }}
                          >
                            查看 / 审核
                          </Button>
                        ),
                      },
                    ]}
                  />
                </section>
              ),
            },
            {
              key: "quality",
              label: "数据质量",
              children: (
                <section className="panel">
                  <Table
                    rowKey="id"
                    dataSource={quality}
                    columns={[
                      { title: "对象", dataIndex: "name" },
                      {
                        title: "问题",
                        render: (_, row) =>
                          row.issues.map((e: any) => e.message).join("；"),
                      },
                      {
                        title: "操作",
                        render: (_, row) => (
                          <Button
                            onClick={() =>
                              navigate(
                                row.kind === "cards"
                                  ? `/catalog/cards/${row.id}`
                                  : `/catalog/${row.kind}/${row.id}/detail`,
                              )
                            }
                          >
                            查看完善
                          </Button>
                        ),
                      },
                    ]}
                  />
                </section>
              ),
            },
          ]}
        />
      )}
      <Modal
        title="批量修改预览"
        width={900}
        open={preview.length > 0}
        onCancel={() => setPreview([])}
        onOk={() => bulk(true)}
        okText="确认整批修改"
      >
        <Alert message="仅草稿、驳回和下架记录可编辑。确认时重新校验状态及更新时间；任一失败整批回滚。" />
        <Table
          rowKey="id"
          dataSource={preview}
          columns={[
            { title: "小卡", render: (_, r) => r.before.title },
            {
              title: "修改前",
              render: (_, r) =>
                changedFields(r)
                  .map((k) => `${k}: ${JSON.stringify(r.before[k])}`)
                  .join("；"),
            },
            {
              title: "修改后",
              render: (_, r) =>
                changedFields(r)
                  .map((k) => `${k}: ${JSON.stringify(r.after[k])}`)
                  .join("；"),
            },
          ]}
        />
      </Modal>
      <Modal
        title="确认人工合并"
        open={!!mergePlan}
        onCancel={() => setMergePlan(undefined)}
        okText="迁移关联并归档重复记录"
        okButtonProps={{ danger: true }}
        onOk={async () => {
          try {
            await consoleApi(
              "/cards/merge",
              send({
                source_id: mergeSource,
                target_id: mergeTarget,
                preview: false,
                expected: mergePlan.expected,
              }),
            );
            await reload();
            setMergePlan(undefined);
            message.success("关联已迁移，重复记录已归档");
          } catch (e) {
            message.error((e as Error).message);
          }
        }}
      >
        <Alert message="核对发行来源与版本，不能仅凭同图判断重复。收藏数量会累加，Wishlist 和数字卡册关联会保留。" />
        <Table
          rowKey="id"
          pagination={false}
          dataSource={mergePlan ? [mergePlan.source, mergePlan.target] : []}
          columns={[
            { title: "小卡", dataIndex: "title" },
            { title: "艺人", dataIndex: "idol_name" },
            { title: "来源", dataIndex: "source" },
            { title: "版本", dataIndex: "version" },
          ]}
        />
        <p>
          {mergePlan?.relations
            ?.map((r: any) => `${r.label} ${r.count} 条`)
            .join("；")}
        </p>
      </Modal>
      <Modal
        title="反馈审核"
        width={800}
        open={!!review}
        onCancel={() => setReview(undefined)}
        footer={
          <Space>
            <Button onClick={() => setReview(undefined)}>关闭</Button>
            {actor.role === "admin" && (
              <>
                <Button danger onClick={() => act("reject")}>
                  驳回
                </Button>
                {review?.queue === "scan" ? (
                  <>
                    <Button onClick={() => act("ignore")}>忽略</Button>
                    <Button disabled={!target} onClick={() => act("match")}>
                      匹配已有小卡
                    </Button>
                    <Button
                      onClick={() => {
                        navigate(
                          `/catalog/cards/new?image_url=${encodeURIComponent(review?.data.image_url || "")}`,
                        );
                        setReview(undefined);
                      }}
                    >
                      转新建草稿
                    </Button>
                  </>
                ) : (
                  <Button
                    onClick={() =>
                      modal.confirm({
                        title: "确认接受反馈？",
                        content:
                          "已发布目标将经过重新校验后更新；校验失败整笔回滚。",
                        onOk: () =>
                          act(
                            review?.queue === "report"
                              ? "accept"
                              : "edit_accept",
                          ),
                      })
                    }
                  >
                    接受 / 编辑后接受
                  </Button>
                )}
              </>
            )}
          </Space>
        }
      >
        <p>{review?.data.reason || review?.data.notes}</p>
        {review?.queue === "contribution" && (
          <>
            <p>
              资料和本次新增 Tag 共用一次审核。接受后同步发布；驳回不创建
              Tag。请先补齐关联与发布所需字段。
            </p>
            {!!review?.data.context?.missing_references && (
              <pre>
                {JSON.stringify(
                  review.data.context.missing_references,
                  null,
                  2,
                )}
              </pre>
            )}
            <Select<string>
              placeholder="补充审核字段"
              style={{ width: "100%", marginBottom: 12 }}
              value={undefined}
              options={[
                "group_id",
                "idol_id",
                "artists",
                "source_entity_type",
                "source_entity_id",
                "entity_version_id",
                "image_url",
                "back_image_url",
                "front_source",
                "back_source",
                "source_info",
                "city",
                "is_online",
                "platform",
                "tags",
              ]
                .filter((field) => !suggested.some((s) => s.field === field))
                .map((value) => ({ value, label: value }))}
              onChange={(field) => {
                const value = ["tags", "artists"].includes(field)
                  ? []
                  : ["front_source", "back_source", "source_info"].includes(
                        field,
                      )
                    ? {}
                    : field === "is_online"
                      ? false
                      : "";
                setSuggested((old) => [
                  ...old,
                  { field, value, original: value },
                ]);
              }}
            />
          </>
        )}
        {(review?.data.image_url || review?.data.evidence_image) && (
          <img
            src={review.data.image_url || review.data.evidence_image}
            alt="用户扫描图片"
            style={{ maxWidth: 220 }}
          />
        )}
        {review?.data.source_url && (
          <p>
            来源：
            <a href={review.data.source_url} target="_blank" rel="noreferrer">
              查看证据来源
            </a>
          </p>
        )}
        {review?.data.contributor && <p>提交人：{review.data.contributor}</p>}
        {review?.queue === "scan" && (
          <>
            <Select
              style={{ width: "100%" }}
              showSearch
              optionFilterProp="label"
              value={target}
              onChange={setTarget}
              placeholder="匹配已有官方小卡"
              options={catalog.cards
                .filter((c) => ["PUBLISHED", "OFFLINE"].includes(c.status))
                .map((c) => ({ value: c.id, label: c.title }))}
            />
            <p>
              候选：
              {review?.data.candidates
                ?.map((c: any) => `${c.card_id} (${c.similarity})`)
                .join("；")}
            </p>
          </>
        )}
        <Table
          rowKey="field"
          dataSource={suggested}
          pagination={false}
          columns={[
            { title: "字段", dataIndex: "field" },
            {
              title: "当前值",
              render: (_, r) =>
                String(
                  (
                    (catalog.cards.find((c) => c.id === review?.entity_id) ||
                      Object.values(catalog)
                        .flat()
                        .find((e: any) => e.id === review?.entity_id) ||
                      {}) as Record<string, any>
                  )[r.field] || "",
                ),
            },
            {
              title: "建议值",
              render: (_, r, i) => (
                <Input
                  value={
                    typeof r.value === "string"
                      ? r.value
                      : JSON.stringify(r.value)
                  }
                  onChange={(e) =>
                    setSuggested((old) =>
                      old.map((v, n) =>
                        n === i
                          ? { ...v, value: e.target.value, edited: true }
                          : v,
                      ),
                    )
                  }
                />
              ),
            },
          ]}
        />
        <Input.TextArea
          placeholder="审核原因"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
      </Modal>
    </>
  );
}

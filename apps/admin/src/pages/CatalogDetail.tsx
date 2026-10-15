import { displayValue } from "../design/format";
import { DetailFields, BusinessData } from "../components/admin";
import { editable } from "../components/shared";
import { Table } from "../components/admin";
import { useEffect, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  Skeleton,
  Alert,
  App,
  Button,
  Descriptions,
  Image,
  Space,
  Tabs,
  Tag,
} from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import { names } from "../api/types";
import RecordManager from "./RecordManager";
import MediaIngestionStatus from "../components/MediaIngestionStatus";

export default function CatalogDetail() {
  const { kind = "groups", id = "" } = useParams();
  const { catalog, actor } = useConsole();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const tabKeys = [
    "overview",
    "assets",
    "entities",
    "cards",
    "history",
    ...(kind === "cards"
      ? ["source", "scan", "feedback"]
      : ["groups", "idols"].includes(kind)
        ? ["members", "company", "social"]
        : kind === "others"
          ? []
          : ["versions", "sources"]),
  ];
  const requestedTab = params.get("tab") || "overview";
  const activeTab = tabKeys.includes(requestedTab) ? requestedTab : "overview";
  const { message } = App.useApp();
  const [data, setData] = useState<any>();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const load = async () => {
    setLoading(true);
    setData(undefined);
    setError("");
    try {
      setData(await consoleApi(`/entities/${kind}/${id}/detail`));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => {
    load();
  }, [kind, id]);
  const entity = data?.entity;
  const create = (type: string) =>
    navigate(
      type === "cards"
        ? `/catalog/cards/new?${kind === "groups" ? `group_id=${id}` : kind === "idols" ? `idol_id=${id}` : `source_entity_id=${id}&source_entity_type=${kind === "albums" ? "ALBUM" : kind === "events" ? "EVENT" : "OTHER"}&group_id=${entity?.group_id || ""}&idol_id=${entity?.idol_id || entity?.artists?.find((a: { type: string }) => a.type === "idols")?.id || ""}`}`
        : `/catalog/${type}?create=true&${kind === "groups" ? "group_id" : "idol_id"}=${id}`,
    );
  const content = (children: React.ReactNode) => (
    <section className="panel" style={{ padding: 20 }}>
      {children}
    </section>
  );
  const members = (data?.memberships || []).map((m: any) => ({
    ...m,
    name:
      kind === "groups"
        ? catalog.idols.find((i) => i.id === m.idol_id)?.name
        : catalog.groups.find((g) => g.id === m.group_id)?.name,
  }));
  if (loading)
    return (
      <section className="panel" aria-label="正在加载详情">
        <Skeleton active paragraph={{ rows: 8 }} />
      </section>
    );
  if (error && !data)
    return (
      <Alert
        type="error"
        message={error}
        action={<Button onClick={load}>重试</Button>}
      />
    );
  return (
    <>
      <div className="catalog-detail-heading">
        <div className="catalog-detail-title">
          <Button onClick={() => navigate(`/catalog/${kind}`)}>返回列表</Button>
          <h1>{entity?.name || entity?.title || "详情"}</h1>
        </div>
        {(kind === "cards" || actor.role !== "operation_admin") && (
          <Space wrap className="catalog-detail-actions">
            {actor.role !== "operation_admin" && (
              <Button
                type="primary"
                disabled={!entity || !editable(entity.status)}
                title={
                  entity && !editable(entity.status)
                    ? "已发布内容需先下架，待审核内容需先驳回"
                    : "编辑资料"
                }
                onClick={() =>
                  navigate(
                    kind === "cards"
                      ? `/catalog/cards/${id}`
                      : `/catalog/${kind}?edit=${encodeURIComponent(id)}`,
                  )
                }
              >
                编辑
              </Button>
            )}
            {kind === "cards" ? (
              <Button onClick={() => navigate(`/catalog/cards/${id}`)}>
                维护与审核
              </Button>
            ) : (
              [
                ...(kind === "groups"
                  ? ["idols", "albums", "events"]
                  : kind === "idols"
                    ? ["albums", "events"]
                    : []),
                "cards",
              ].map((type) => (
                <Button key={type} onClick={() => create(type)}>
                  新增
                  {type === "cards"
                    ? "小卡"
                    : names[type as keyof typeof names].replace("管理", "")}
                </Button>
              ))
            )}
          </Space>
        )}
      </div>
      {error && (
        <Alert
          type="error"
          message={error}
          action={<Button onClick={load}>重试</Button>}
        />
      )}
      {kind === "albums" && entity?.merged_into && (
        <Alert
          type="info"
          showIcon
          message="该版本记录已归档并归入父专辑"
          description={`原记录 ID ${id} 已保留；版本数据已归入「${catalog.albums.find((album) => album.id === entity.merged_into)?.name || "父专辑"}」，请前往父专辑的版本页查看和维护。`}
          action={
            <Button
              onClick={() =>
                navigate(
                  `/catalog/albums/${encodeURIComponent(entity.merged_into)}/detail?tab=versions`,
                )
              }
            >
              查看父专辑版本
            </Button>
          }
          style={{ marginBottom: 16 }}
        />
      )}
      <Tabs
        activeKey={activeTab}
        onChange={(tab) => {
          const nextParams = new URLSearchParams(params);
          if (tab === "overview") nextParams.delete("tab");
          else nextParams.set("tab", tab);
          setParams(nextParams, { replace: true });
        }}
        items={[
          {
            key: "overview",
            label: "概览",
            children: content(
              <div>
                <DetailFields
                  title="基本信息"
                  data={entity || {}}
                  fields={[
                    ...(kind === "cards"
                      ? [
                          "title",
                          "title_translated",
                          "title_en",
                          "title_ko",
                          "card_type",
                          "rarity",
                          "is_group_pc",
                          "is_double_sided",
                          "is_official",
                          "is_limited",
                          "is_random",
                          "has_ar",
                          "ar_type",
                          "ar_resource",
                          "version",
                          "edition",
                          "card_number",
                        ]
                      : ["name", "name_translated", "name_en", "name_ko"]),
                    ...(kind === "events"
                      ? [
                          "original_name",
                          "city",
                          "venue",
                          "is_online",
                          "platform",
                          "business_status",
                        ]
                      : kind === "others"
                        ? ["original_name"]
                        : kind === "groups"
                          ? [
                              "business_status",
                              "fandom_name",
                              "official_website",
                              "aliases",
                            ]
                          : kind === "idols"
                            ? ["real_name", "gender", "birth_date", "aliases"]
                            : kind === "albums"
                              ? ["type", "aliases"]
                              : []),
                    "description",
                    "region",
                    "tags",
                  ]}
                />
                <DetailFields
                  title="关联内容"
                  data={entity || {}}
                  fields={
                    kind === "cards"
                      ? [
                          "group_name",
                          "idol_name",
                          "source",
                          "source_entity_type",
                          "source_entity_id",
                        ]
                      : ["groups", "idols"].includes(kind)
                        ? ["company", "group_name"]
                        : [
                            "artist_name",
                            ...(kind === "events"
                              ? ["album_id", "parent_event_id"]
                              : []),
                          ]
                  }
                  resolve={(key, value) => {
                    if (!value) return undefined;
                    const kinds: Record<string, string> = {
                      album_id: "albums",
                      parent_event_id: "events",
                      source_entity_id:
                        entity?.source_entity_type === "ALBUM"
                          ? "albums"
                          : entity?.source_entity_type === "EVENT"
                            ? "events"
                            : "others",
                    };
                    const target = kinds[key];
                    const row = target
                      ? (catalog as any)[target]?.find(
                          (r: any) => r.id === value,
                        )
                      : undefined;
                    return row ? (
                      <Button
                        type="link"
                        onClick={() =>
                          navigate(`/catalog/${target}/${value}/detail`)
                        }
                      >
                        {row.name}
                      </Button>
                    ) : undefined;
                  }}
                />
                <DetailFields
                  title="发布信息"
                  data={entity || {}}
                  fields={[
                    "status",
                    ...(["groups", "idols"].includes(kind)
                      ? ["debut_date"]
                      : ["events", "others"].includes(kind)
                        ? ["start_date", "end_date"]
                        : ["release_date"]),
                    "published_at",
                    "review_note",
                  ]}
                />
                <DetailFields
                  title="系统信息"
                  data={{ ...entity, id }}
                  fields={["id", "created_at", "updated_at", "operator"]}
                />
                <p className="subtle-note">时间均为北京时间（UTC+08:00）</p>
              </div>,
            ),
          },
          {
            key: "assets",
            label: kind === "cards" ? "图片 / 素材" : "素材",
            children: content(
              <>
                <MediaIngestionStatus
                  kind={kind}
                  id={id}
                  canEdit={actor.role !== "operation_admin"}
                />
                <Space wrap>
                  {[
                    ["主图 / 正面", entity?.image_url],
                    ["背面", entity?.back_image_url],
                    ["封面", entity?.cover_image],
                    ["AR 预览", entity?.ar_preview],
                  ]
                    .filter(([, url]) => !!url)
                    .map(([label, url]) => (
                      <div key={label}>
                        <div>{label}</div>
                        <Image src={url} width={180} />
                      </div>
                    ))}
                </Space>
                {kind === "cards" && (
                  <Table<any>
                    rowKey="id"
                    dataSource={data?.assets || []}
                    columns={[
                      { title: "面", dataIndex: "side" },
                      { title: "版本", dataIndex: "version" },
                      { title: "时间", dataIndex: "created_at" },
                      {
                        title: "来源",
                        render: (_, r) => r.data.source_url || "—",
                      },
                      {
                        title: "版权",
                        render: (_, r) => r.data.copyright_status || "UNKNOWN",
                      },
                      {
                        title: "图片",
                        render: (_, r) => (
                          <Image src={r.data.image_url} width={60} />
                        ),
                      },
                    ]}
                  />
                )}
              </>,
            ),
          },
          ...(kind === "cards"
            ? [
                {
                  key: "source",
                  label: "来源",
                  children: content(
                    <>
                      <Descriptions
                        items={[
                          {
                            key: "kind",
                            label: "来源类型",
                            children: displayValue(entity?.source_entity_type),
                          },
                          {
                            key: "source",
                            label: "发行来源",
                            children: entity?.source || "—",
                          },
                          {
                            key: "copyright",
                            label: "版权状态",
                            children: displayValue(
                              entity?.source_info?.copyright_status ||
                                "UNKNOWN",
                            ),
                          },
                          {
                            key: "url",
                            label: "来源链接",
                            children: entity?.source_info?.source_url || "—",
                          },
                        ]}
                      />
                      <RecordManager
                        kind="sources"
                        entityType="cards"
                        entityId={id}
                      />
                    </>,
                  ),
                },
                {
                  key: "scan",
                  label: "AI Scan",
                  children: content(
                    <>
                      <Descriptions
                        items={[
                          {
                            key: "state",
                            label: "索引状态",
                            children: displayValue(
                              data?.scan?.status || "Pending",
                            ),
                          },
                          {
                            key: "reason",
                            label: "失败原因",
                            children: data?.scan?.failure_reason || "—",
                          },
                          {
                            key: "attempt",
                            label: "尝试次数",
                            children: data?.scan?.attempts || 0,
                          },
                        ]}
                      />
                      {actor.role !== "operation_admin" && (
                        <Button
                          disabled={
                            !entity?.image_url || entity?.status === "ARCHIVED"
                          }
                          onClick={async () => {
                            try {
                              await consoleApi(
                                `/scan-index/${id}/retry`,
                                send({}),
                              );
                              message.success("已加入索引任务");
                              await load();
                            } catch (e) {
                              message.error((e as Error).message);
                            }
                          }}
                        >
                          重试生成索引
                        </Button>
                      )}
                    </>,
                  ),
                },
                {
                  key: "feedback",
                  label: "用户反馈",
                  children: content(
                    <>
                      <Button onClick={() => navigate("/catalog/review")}>
                        进入审核中心
                      </Button>
                      <Table<any>
                        rowKey="id"
                        dataSource={data?.feedback || []}
                        columns={[
                          { title: "状态", dataIndex: "status" },
                          {
                            title: "反馈原因",
                            render: (_, r) => r.data.reason,
                          },
                          {
                            title: "提交人",
                            render: (_, r) => r.data.contributor,
                          },
                        ]}
                      />
                    </>,
                  ),
                },
              ]
            : []),
          ...(["groups", "idols"].includes(kind)
            ? [
                {
                  key: "members",
                  label: kind === "groups" ? "成员 / 经历" : "组合经历",
                  children: content(
                    <>
                      <Table
                        rowKey="id"
                        dataSource={members}
                        pagination={{ defaultPageSize: 10 }}
                        columns={[
                          { title: "组合 / 艺人", dataIndex: "name" },
                          { title: "加入日期", dataIndex: "start_date" },
                          { title: "退出日期", dataIndex: "end_date" },
                          {
                            title: "状态",
                            dataIndex: "status",
                            render: (v) => <Tag>{displayValue(v)}</Tag>,
                          },
                        ]}
                      />
                      {kind === "idols" && (
                        <RecordManager
                          kind="memberships"
                          entityType={kind}
                          entityId={id}
                          onSaved={load}
                        />
                      )}
                    </>,
                  ),
                },
              ]
            : []),
          {
            key: "entities",
            label: "关联实体",
            children: content(
              <Table<any>
                rowKey="id"
                dataSource={data?.entities || []}
                columns={[
                  {
                    title: "名称",
                    dataIndex: "name",
                    render: (name, row) => (
                      <Button
                        type="link"
                        onClick={() =>
                          navigate(
                            `/catalog/${row.entity_type}/${row.id}/detail`,
                          )
                        }
                      >
                        {name}
                      </Button>
                    ),
                  },
                  { title: "类型", dataIndex: "entity_type" },
                  { title: "状态", dataIndex: "status" },
                ]}
              />,
            ),
          },
          {
            key: "cards",
            label: `小卡 ${data?.cards?.length || 0}`,
            children: content(
              <Table<any>
                rowKey="id"
                dataSource={data?.cards || []}
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
                  { title: "艺人", dataIndex: "idol_name" },
                  { title: "来源", dataIndex: "source" },
                  { title: "状态", dataIndex: "status" },
                ]}
              />,
            ),
          },
          ...(!["groups", "idols", "cards", "others"].includes(kind)
            ? [
                {
                  key: "versions",
                  label: "版本",
                  children: content(
                    <RecordManager
                      kind="versions"
                      entityType={kind}
                      entityId={id}
                    />,
                  ),
                },
                {
                  key: "sources",
                  label: "来源链",
                  children: content(
                    <RecordManager
                      kind="sources"
                      entityType={kind}
                      entityId={id}
                    />,
                  ),
                },
              ]
            : []),
          ...(["groups", "idols"].includes(kind)
            ? [
                {
                  key: "company",
                  label: "公司经历",
                  children: content(
                    <RecordManager
                      kind="company_relations"
                      entityType={kind}
                      entityId={id}
                    />,
                  ),
                },
                {
                  key: "social",
                  label: "动态 / 社交账号",
                  children: content(
                    <>
                      <Button onClick={() => navigate("/operations/accounts")}>
                        管理社交数据源
                      </Button>
                      <Table
                        rowKey="id"
                        dataSource={data?.accounts || []}
                        columns={[
                          { title: "平台", dataIndex: "platform" },
                          { title: "账号", dataIndex: "handle" },
                          {
                            title: "启用",
                            dataIndex: "is_active",
                            render: (v) => (v ? "是" : "否"),
                          },
                        ]}
                      />
                      <Table
                        rowKey="id"
                        dataSource={data?.social || []}
                        columns={[
                          { title: "动态", dataIndex: "title" },
                          { title: "平台", dataIndex: "platform" },
                        ]}
                      />
                    </>,
                  ),
                },
              ]
            : []),
          {
            key: "history",
            label: "变更历史",
            children: content(
              <Table<any>
                rowKey="id"
                dataSource={data?.history || []}
                expandable={{
                  expandedRowRender: (r) => (
                    <div className="audit-diff">
                      <div>
                        <h3>变更前</h3>
                        <BusinessData data={r.before} />
                      </div>
                      <div>
                        <h3>变更后</h3>
                        <BusinessData data={r.after} />
                      </div>
                    </div>
                  ),
                }}
                columns={[
                  { title: "时间", dataIndex: "created_at" },
                  { title: "操作人", dataIndex: "actor_id" },
                  { title: "操作", dataIndex: "action" },
                ]}
              />,
            ),
          },
        ]}
      />
    </>
  );
}

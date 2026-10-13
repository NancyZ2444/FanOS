import { useEffect, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  Alert,
  App,
  Button,
  Descriptions,
  Image,
  Space,
  Table,
  Tabs,
  Tag,
} from "antd";
import { consoleApi, send } from "../api/client";
import { useConsole } from "../state";
import { names } from "../api/types";
import RecordManager from "./RecordManager";

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
        : kind === "others" ? [] : ["versions", "sources"]),
  ];
  const requestedTab = params.get("tab") || "overview";
  const activeTab = tabKeys.includes(requestedTab) ? requestedTab : "overview";
  const { message } = App.useApp();
  const [data, setData] = useState<any>();
  const [error, setError] = useState("");
  const load = () =>
    consoleApi(`/entities/${kind}/${id}/detail`)
      .then(setData)
      .catch((e) => setError(e.message));
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
  return (
    <>
      <div className="catalog-detail-heading">
        <div className="catalog-detail-title">
          <Button onClick={() => navigate(`/catalog/${kind}`)}>返回列表</Button>
          <h1>{entity?.name || entity?.title || "详情"}</h1>
        </div>
        {(kind === "cards" || actor.role !== "operation_admin") && (
          <Space wrap className="catalog-detail-actions">
            {kind === "cards" ? (
              <Button onClick={() => navigate(`/catalog/cards/${id}`)}>
                打开小卡编辑器
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
                    : names[type as keyof typeof names]}
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
              <Descriptions
                column={2}
                items={Object.entries(entity || {})
                  .filter(
                    ([key, value]) =>
                      value !== null &&
                      [
                        "id",
                        "name",
                        "original_name",
                        "start_date",
                        "tags",
                        "name_en",
                        "name_ko",
                        "name_translated",
                        "artist_name",
                        "description",
                        "release_date",
                        "status",
                        "company",
                        "region",
                        "city",
                        "platform",
                        "venue",
                        "business_status",
                        "end_date",
                        "title",
                        "idol_name",
                        "group_name",
                        "source",
                        "source_entity_type",
                        "source_entity_id",
                        "version",
                        "edition",
                        "card_number",
                        "is_online",
                        "album_id",
                        "parent_event_id",
                      ].includes(key),
                  )
                  .map(([key, value]) => ({
                    key,
                    label:
                      (
                        {
                          id: "ID",
                          name: "名称",
                          original_name: "原始名称",
                          start_date: "开始日期",
                          tags: "Tags",
                          artist_name: "艺人",
                          description: "简介",
                          release_date: "日期",
                          status: "发布状态",
                          company: "公司",
                          region: "地区",
                          city: "城市",
                          venue: "场馆",
                          business_status: "业务状态",
                          end_date: "结束日期",
                        } as Record<string, string>
                      )[key] || key,
                    children: String(value),
                  }))}
              />,
            ),
          },
          {
            key: "assets",
            label: kind === "cards" ? "图片 / 素材" : "素材",
            children: content(
              <>
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
                            children: entity?.source_entity_type,
                          },
                          {
                            key: "source",
                            label: "发行来源",
                            children: entity?.source || "—",
                          },
                          {
                            key: "copyright",
                            label: "版权状态",
                            children:
                              entity?.source_info?.copyright_status ||
                              "UNKNOWN",
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
                            children: data?.scan?.status || "Pending",
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
                        pagination={{ pageSize: 10 }}
                        columns={[
                          { title: "组合 / 艺人", dataIndex: "name" },
                          { title: "加入日期", dataIndex: "start_date" },
                          { title: "退出日期", dataIndex: "end_date" },
                          {
                            title: "状态",
                            dataIndex: "status",
                            render: (v) => <Tag>{v}</Tag>,
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
                    <pre style={{ whiteSpace: "pre-wrap" }}>
                      {JSON.stringify(
                        { 修改前: r.before, 修改后: r.after },
                        null,
                        2,
                      )}
                    </pre>
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

import { TableToolbar, RowActions } from "../components/admin";
import { FilterBar } from "../components/admin";
import { PageHeader } from "../components/admin";
import { Table } from "../components/admin";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Input, Tabs, Tag } from "antd";
import { SearchOutlined } from "@ant-design/icons";
import { useConsole } from "../state";
import { CardArt, StatusTag, editable } from "../components/shared";

export default function Sources() {
  const { catalog, actor } = useConsole();
  const navigate = useNavigate();
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState("issues");
  const rows = catalog.cards
    .filter((c) => c.status !== "ARCHIVED")
    .flatMap((c) =>
      ["FRONT", "BACK"]
        .filter((side) => side === "FRONT" || c.back_image_url)
        .map((side) => {
          const s = (side === "FRONT" ? c.front_source : c.back_source) || {};
          const issues = [
            ...(!s.source_url ? ["缺少来源链接"] : []),
            ...(!s.copyright_status || s.copyright_status === "UNKNOWN"
              ? ["版权待确认"]
              : []),
            ...(["RESTRICTED", "REMOVED", "FAIR_USE_REVIEW"].includes(
              s.copyright_status,
            )
              ? ["版权需复核"]
              : []),
            ...(s.source_type === "USER_SUBMITTED" ? ["用户提交素材"] : []),
          ];
          return { id: c.id + side, card: c, side, source: s, issues };
        }),
    )
    .filter(
      (r) =>
        (filter === "all" || r.issues.length) &&
        (!q ||
          [r.card.title, r.card.group_name, r.source.source_url].some((v) =>
            v?.toLowerCase().includes(q.toLowerCase()),
          )),
    );
  return (
    <>
      <PageHeader
        title={<>来源与版权审核</>}
        actions={
          <>
            <Tag color="purple">正反面独立管理</Tag>
          </>
        }
      />
      <FilterBar onReset={() => setQ("")}>
        <Input
          prefix={<SearchOutlined aria-hidden="true" />}
          allowClear
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="搜索小卡、组合、来源链接"
          style={{ width: 360 }}
        />
      </FilterBar>
      <section className="panel table-panel">
        <TableToolbar>
          <Tabs
            activeKey={filter}
            onChange={setFilter}
            items={[
              { key: "issues", label: "需要处理" },
              { key: "all", label: "全部图片来源" },
            ]}
          />
        </TableToolbar>
        <Table
          rowKey="id"
          filtered={!!q}
          onReset={() => setQ("")}
          dataSource={rows}
          scroll={{ x: 1000 }}
          pagination={{ defaultPageSize: 10 }}
          columns={[
            {
              title: "小卡 / 图片",
              key: "name",
              width: 290,
              render: (_, r) => (
                <div className="table-card-info">
                  <CardArt card={r.card} small back={r.side === "BACK"} />
                  <div>
                    <b>{r.card.title}</b>
                    <span className="record-id">
                      {r.side === "FRONT" ? "正面图片" : "背面图片"} ·{" "}
                      {r.card.group_name}
                    </span>
                  </div>
                </div>
              ),
            },
            {
              title: "来源链接",
              key: "url",
              width: 220,
              ellipsis: true,
              render: (_, r) =>
                r.source.source_url ? (
                  <a
                    href={r.source.source_url}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {r.source.source_url}
                  </a>
                ) : (
                  "尚未填写"
                ),
            },
            {
              title: "检查结果",
              key: "issues",
              render: (_, r) =>
                r.issues.length ? (
                  r.issues.map((v) => (
                    <Tag key={v} color="orange">
                      {v}
                    </Tag>
                  ))
                ) : (
                  <Tag color="success">信息完整</Tag>
                ),
            },
            {
              title: "小卡状态",
              key: "status",
              render: (_, r) => <StatusTag status={r.card.status} />,
            },
            {
              title: "操作",
              key: "action",
              width: 192,
              render: (_, r) => (
                <RowActions
                  onView={() => navigate(`/catalog/cards/${r.card.id}/detail`)}
                  onEdit={
                    actor.role !== "operation_admin"
                      ? () => navigate(`/catalog/cards/${r.card.id}`)
                      : undefined
                  }
                  editDisabled={!editable(r.card.status)}
                  editHint={
                    !editable(r.card.status)
                      ? "已发布内容需先下架，待审核内容需先驳回"
                      : undefined
                  }
                  items={[
                    {
                      key: "history",
                      label: "来源历史",
                      onClick: () =>
                        navigate(`/catalog/cards/${r.card.id}?tab=history`),
                    },
                  ]}
                />
              ),
            },
          ]}
        />
      </section>
    </>
  );
}

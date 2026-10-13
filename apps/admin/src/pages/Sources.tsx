import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Input, Table, Tabs, Tag } from "antd";
import { SearchOutlined } from "@ant-design/icons";
import { useConsole } from "../state";
import { CardArt, StatusTag } from "../components/shared";

export default function Sources() {
  const { catalog } = useConsole();
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
      <div className="page-heading">
        <div>
          <div className="eyebrow">SOURCE REVIEW</div>
          <h1>来源与版权审核</h1>
          <p>追踪每张图片的来源，保留每一次变更的依据。</p>
        </div>
        <Tag color="purple">正反面独立管理</Tag>
      </div>
      <section className="panel filters">
        <Input
          prefix={<SearchOutlined aria-hidden="true" />}
          allowClear
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="搜索小卡、组合、来源链接"
          style={{ width: 360 }}
        />
      </section>
      <section className="panel table-panel">
        <div className="table-toolbar">
          <Tabs
            activeKey={filter}
            onChange={setFilter}
            items={[
              { key: "issues", label: "需要处理" },
              { key: "all", label: "全部图片来源" },
            ]}
          />
          <span className="subtle-note">共 {rows.length} 条记录</span>
        </div>
        <Table
          rowKey="id"
          dataSource={rows}
          scroll={{ x: 1000 }}
          pagination={{ pageSize: 10 }}
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
              width: 170,
              render: (_, r) => (
                <div className="row-links">
                  <button
                    className="text-button"
                    onClick={() => navigate(`/catalog/cards/${r.card.id}`)}
                  >
                    查看 / 完善
                  </button>
                  <button
                    className="text-button"
                    onClick={() =>
                      navigate(`/catalog/cards/${r.card.id}?tab=history`)
                    }
                  >
                    来源历史
                  </button>
                </div>
              ),
            },
          ]}
        />
      </section>
    </>
  );
}

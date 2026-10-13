import { BusinessData, RecordId } from "../components/admin";
import { actionLabel } from "../design/format";
import { FilterBar } from "../components/admin";
import { PageHeader } from "../components/admin";
import { Drawer, Table } from "../components/admin";
import { useEffect, useState } from "react";
import { Alert, Button, Descriptions, Input, Tag } from "antd";
import { SearchOutlined } from "@ant-design/icons";
import { consoleApi } from "../api/client";
import { Panel } from "../components/shared";
import { roleLabels } from "../api/types";

export default function System({ tab }: { tab: "roles" | "logs" }) {
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState("");
  const [q, setQ] = useState("");
  const [detail, setDetail] = useState<any>();
  const load = () =>
    consoleApi("/logs")
      .then((d) => setRows(d.items))
      .catch((e) => setError(e.message));
  useEffect(() => {
    if (tab === "logs") load();
  }, [tab]);
  return (
    <>
      <PageHeader title={<>{tab === "logs" ? "操作日志" : "角色与权限"}</>} />
      {tab === "roles" ? (
        <>
          <div className="role-grid">
            {Object.entries(roleLabels).map(([key, label]) => (
              <Panel key={key} title={label}>
                <p>
                  {key === "admin"
                    ? "拥有所有后台模块权限，包括图鉴审核发布与系统日志。"
                    : key === "content_operator"
                      ? "维护图鉴、艺人、来源和社交动态，提交小卡审核。"
                      : "管理每日翻卡、通知、公告、用户、评论与举报。"}
                </p>
              </Panel>
            ))}
          </div>
          <Panel title="权限矩阵" className="table-panel">
            <Table
              pagination={false}
              rowKey="module"
              dataSource={[
                {
                  module: "图鉴查看",
                  admin: "✓",
                  content: "✓",
                  operation: "✓",
                },
                {
                  module: "图鉴创建、编辑与导入",
                  admin: "✓",
                  content: "✓",
                  operation: "—",
                },
                {
                  module: "小卡审核发布",
                  admin: "✓",
                  content: "—",
                  operation: "—",
                },
                {
                  module: "社交动态与数据源",
                  admin: "✓",
                  content: "✓",
                  operation: "—",
                },
                {
                  module: "翻卡、通知与公告",
                  admin: "✓",
                  content: "—",
                  operation: "✓",
                },
                {
                  module: "用户与评论、举报处理",
                  admin: "✓",
                  content: "—",
                  operation: "✓",
                },
                {
                  module: "完整操作日志",
                  admin: "✓",
                  content: "—",
                  operation: "—",
                },
              ]}
              columns={[
                { title: "模块与操作", dataIndex: "module" },
                { title: "超级管理员", dataIndex: "admin" },
                { title: "内容运营", dataIndex: "content" },
                { title: "运营管理员", dataIndex: "operation" },
              ]}
            />
          </Panel>
        </>
      ) : (
        <>
          {error && (
            <Alert
              type="error"
              message={error}
              action={<Button onClick={load}>重试</Button>}
            />
          )}
          <FilterBar onReset={() => setQ("")}>
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              prefix={<SearchOutlined aria-hidden="true" />}
              placeholder="搜索操作人、操作、对象 ID"
              style={{ width: 380 }}
            />
          </FilterBar>
          <section className="panel table-panel">
            <Table
              rowKey="id"
              filtered={!!q}
              onReset={() => setQ("")}
              dataSource={rows.filter((r) =>
                [r.actor_id, r.action, r.target_id].some((v) => v.includes(q)),
              )}
              pagination={{ defaultPageSize: 12 }}
              scroll={{ x: 1000 }}
              columns={[
                {
                  title: "操作时间",
                  dataIndex: "created_at",
                  render: (v) => new Date(v).toLocaleString("zh-CN"),
                },
                { title: "操作人", dataIndex: "actor_id" },
                {
                  title: "操作",
                  dataIndex: "action",
                  render: (v) => <Tag color="purple">{v}</Tag>,
                },
                { title: "对象类型", dataIndex: "target_type" },
                { title: "对象 ID", dataIndex: "target_id", ellipsis: true },
                {
                  title: "操作",
                  key: "action",
                  render: (_, r) => (
                    <button
                      className="text-button"
                      onClick={() => setDetail(r)}
                    >
                      查看
                    </button>
                  ),
                },
              ]}
            />
          </section>
          <div className="page-footnote">显示最近 500 条操作记录</div>
        </>
      )}
      <Drawer
        open={!!detail}
        title="操作记录详情"
        width={780}
        onClose={() => setDetail(undefined)}
      >
        {detail && (
          <>
            <Descriptions
              column={1}
              items={[
                {
                  key: "action",
                  label: "操作",
                  children: actionLabel(detail.action),
                },
                {
                  key: "actor",
                  label: "操作人",
                  children: <RecordId value={detail.actor_id} />,
                },
                {
                  key: "target",
                  label: "对象",
                  children: <RecordId value={detail.target_id} />,
                },
              ]}
            />
            <div className="audit-diff">
              <div>
                <h3>变更前</h3>
                <BusinessData data={detail.before} />
              </div>
              <div>
                <h3>变更后</h3>
                <BusinessData data={detail.after} />
              </div>
            </div>
          </>
        )}
      </Drawer>
    </>
  );
}

import { BusinessData, RecordId } from "../components/admin";
import { actionLabel } from "../design/format";
import { FilterBar } from "../components/admin";
import { PageHeader } from "../components/admin";
import { Drawer, Table } from "../components/admin";
import { useEffect, useState } from "react";
import { Alert, Button, Descriptions, Input, Tag } from "antd";
import { SearchOutlined } from "@ant-design/icons";
import { consoleApi } from "../api/client";
import RolePermissions from "./RolePermissions";

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
        <RolePermissions />
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

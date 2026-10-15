import { useCallback, useEffect, useState } from "react";
import { Alert, App, Button, Space, Tag } from "antd";
import { consoleApi, send } from "../api/client";
import { Table } from "./admin";

type Task = {
  id: string;
  field: string;
  state: string;
  attempts: number;
  error?: string;
};
const states: Record<string, string> = {
  pending: "等待下载",
  downloading: "下载中",
  retrying: "等待重试",
  failed: "下载失败",
  ready: "已转存",
  superseded: "已被新图片替换",
};
const fields: Record<string, string> = {
  image_url: "主图",
  cover_image: "封面",
  front_image_url: "正面",
  back_image_url: "背面",
  cover: "版本封面",
};

export default function MediaIngestionStatus({
  kind,
  id,
  canEdit,
}: {
  kind: string;
  id: string;
  canEdit: boolean;
}) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const { message } = App.useApp();
  const load = useCallback(async () => {
    try {
      const data = await consoleApi<{ items: Task[] }>(`/media/${kind}/${id}`);
      setTasks(data.items);
      setError("");
    } catch (e) {
      setError((e as Error).message);
    }
  }, [kind, id]);
  useEffect(() => {
    void load();
  }, [load]);
  useEffect(() => {
    if (
      !tasks.some((t) =>
        ["pending", "downloading", "retrying"].includes(t.state),
      )
    )
      return;
    const timer = window.setInterval(() => {
      void load();
    }, 10000);
    return () => window.clearInterval(timer);
  }, [tasks, load]);
  const act = async (path: string) => {
    if (busy) return;
    setBusy(true);
    try {
      await consoleApi(path, send({}));
      message.success("已加入后台任务");
      await load();
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <section style={{ marginBottom: 20 }}>
      <Space style={{ marginBottom: 12 }} wrap>
        <strong>图片转存</strong>
        <Button onClick={load}>刷新状态</Button>
        {canEdit && (
          <Button
            loading={busy}
            onClick={() => act(`/media/${kind}/${id}/queue`)}
          >
            补下载历史图片
          </Button>
        )}
      </Space>
      <p className="subtle-note">
        导入后由后台下载并生成缩略图，App
        只读取自有图片；下载失败不会中断资料导入。
      </p>
      {error && <Alert type="warning" message={error} />}
      <Table<Task>
        size="small"
        rowKey="id"
        dataSource={tasks}
        pagination={{ pageSize: 5 }}
        columns={[
          {
            title: "图片",
            dataIndex: "field",
            render: (v: string) => fields[v] || v,
          },
          {
            title: "状态",
            dataIndex: "state",
            render: (v: string) => (
              <Tag
                color={
                  v === "ready" ? "green" : v === "failed" ? "red" : "default"
                }
              >
                {states[v] || v}
              </Tag>
            ),
          },
          { title: "尝试次数", dataIndex: "attempts" },
          {
            title: "说明",
            dataIndex: "error",
            render: (v: string) => v || "—",
          },
          {
            title: "操作",
            render: (_, task) =>
              canEdit && ["failed", "retrying"].includes(task.state) ? (
                <Button
                  size="small"
                  disabled={busy}
                  onClick={() => act(`/media/tasks/${task.id}/retry`)}
                >
                  重试下载
                </Button>
              ) : (
                "—"
              ),
          },
        ]}
      />
    </section>
  );
}

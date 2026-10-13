import { PageHeader } from "../components/admin";
import { Table } from "../components/admin";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Alert, Button, Space, Tag } from "antd";
import {
  ArrowRightOutlined,
  AuditOutlined,
  BookOutlined,
  CheckCircleOutlined,
  FileImageOutlined,
  LinkOutlined,
  TeamOutlined,
} from "@ant-design/icons";
import { consoleApi } from "../api/client";
import { useConsole } from "../state";
import { CardArt, Panel, StatusTag } from "../components/shared";

export default function Dashboard() {
  const { actor, catalog } = useConsole();
  const navigate = useNavigate();
  const [stats, setStats] = useState<Record<string, number>>({});
  const [error, setError] = useState("");
  const [catalogStats, setCatalogStats] = useState<any>();
  const load = () =>
    consoleApi("/dashboard")
      .then(setStats)
      .catch((e) => setError(e.message));
  useEffect(() => {
    load();
    consoleApi("/catalog-dashboard")
      .then(setCatalogStats)
      .catch((e) => setError(e.message));
  }, []);
  const tasks = [
    {
      name: "待审核小卡",
      key: "pending",
      desc: "检查内容与图片版权，完成发布",
      to: "/catalog/cards?status=PENDING",
      icon: <AuditOutlined aria-hidden="true" />,
    },
    {
      name: "待完善图片",
      key: "missing_images",
      desc: "补齐正面图片，完善图鉴素材",
      to: "/catalog/cards?missing=true",
      icon: <FileImageOutlined aria-hidden="true" />,
    },
    {
      name: "来源异常",
      key: "source_issues",
      desc: "确认来源链接和版权状态",
      to: "/reviews/sources",
      icon: <LinkOutlined aria-hidden="true" />,
    },
  ];
  return (
    <>
      <PageHeader
        title={<>欢迎回来，{actor.name}</>}
        actions={
          <>
            <span className="dashboard-date">
              {new Date().toLocaleDateString("zh-CN", {
                year: "numeric",
                month: "long",
                day: "numeric",
                weekday: "long",
              })}
            </span>
          </>
        }
      />
      {error && (
        <Alert
          type="error"
          message={error}
          action={<Button onClick={load}>重新加载</Button>}
        />
      )}
      <div className="metric-grid">
        {[
          {
            title: "小卡总数",
            key: "cards",
            sub: `${stats.published || 0} 张已发布`,
            icon: <BookOutlined aria-hidden="true" />,
            path: "/catalog/cards",
          },
          {
            title: "组合 / 艺人",
            key: "groups",
            sub: `${stats.idols || 0} 位艺人`,
            icon: <TeamOutlined aria-hidden="true" />,
            path: "/catalog/groups",
          },
          {
            title: "平台用户",
            key: "users",
            sub: "当前已注册用户",
            icon: <TeamOutlined aria-hidden="true" />,
            path: "/operations/users",
          },
          {
            title: "翻卡记录",
            key: "draws",
            sub: "累计成功翻卡次数",
            icon: <CheckCircleOutlined aria-hidden="true" />,
            path: "/operations/draws",
          },
        ].map((m) => (
          <button
            className="metric-card"
            key={m.key}
            onClick={() => navigate(m.path)}
          >
            <div>
              <span>{m.title}</span>
              <i>{m.icon}</i>
            </div>
            <strong>{stats[m.key] ?? "—"}</strong>
            <p>
              {m.sub}
              <ArrowRightOutlined aria-hidden="true" />
            </p>
          </button>
        ))}
      </div>
      {catalogStats && (
        <Panel title="运营待办与今日新增">
          <div className="dashboard-shortcuts">
            {Object.entries({
              DRAFT: "草稿小卡",
              OFFLINE: "下架小卡",
              scan_unknown: "扫描待处理",
              contributions: "用户贡献",
              import_errors: "导入异常",
            }).map(([key, label]) => (
              <Button
                key={key}
                onClick={() =>
                  navigate(
                    key === "groups" || key === "idols"
                      ? `/catalog/${key}`
                      : key === "entities"
                        ? "/catalog/albums"
                        : key === "import_errors"
                          ? "/catalog/import"
                          : ["scan_unknown", "contributions"].includes(key)
                            ? "/catalog/review"
                            : `/catalog/cards?status=${key}`,
                  )
                }
              >
                {label} {catalogStats.counts[key]}
              </Button>
            ))}
          </div>
          <p>
            今日新增：
            <Space wrap>
              {Object.entries(catalogStats.today).map(([kind, count]) => (
                <Tag
                  key={kind}
                  onClick={() =>
                    navigate(
                      `/catalog/${kind}?created_date=${new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Shanghai" })}`,
                    )
                  }
                  style={{ cursor: "pointer" }}
                >
                  {
                    (
                      {
                        groups: "组合",
                        idols: "艺人",
                        albums: "专辑",
                        events: "活动",
                        others: "Other",
                        cards: "小卡",
                      } as Record<string, string>
                    )[kind]
                  }{" "}
                  +{String(count)}
                </Tag>
              ))}
            </Space>
          </p>
          <Table
            rowKey="id"
            dataSource={catalogStats.recent}
            pagination={{ defaultPageSize: 5 }}
            columns={[
              { title: "时间", dataIndex: "created_at" },
              { title: "操作人", dataIndex: "actor_id" },
              { title: "最近操作", dataIndex: "action" },
              { title: "对象", dataIndex: "target_id" },
            ]}
          />
        </Panel>
      )}
      <Panel title="待处理事项" subtitle="从这里开始今天的内容维护。">
        <div className="task-grid">
          {tasks.map((t) => (
            <button
              className="task-card"
              key={t.key}
              onClick={() => navigate(t.to)}
            >
              <span className="task-icon">{t.icon}</span>
              <div>
                <h3>
                  {t.name}
                  <strong>{stats[t.key] ?? "—"}</strong>
                </h3>
                <p>{t.desc}</p>
              </div>
              <ArrowRightOutlined aria-hidden="true" />
            </button>
          ))}
        </div>
      </Panel>
      <div className="dashboard-columns">
        <Panel
          title="最近更新的小卡"
          className="table-panel"
          extra={
            <Button type="link" onClick={() => navigate("/catalog/cards")}>
              查看全部 <ArrowRightOutlined aria-hidden="true" />
            </Button>
          }
        >
          <Table
            rowKey="id"
            dataSource={catalog.cards.slice(0, 5)}
            pagination={false}
            columns={[
              {
                title: "小卡",
                key: "card",
                render: (_, c) => (
                  <div className="table-card-info">
                    <CardArt card={c} small />
                    <div>
                      <button
                        className="table-title"
                        onClick={() => navigate(`/catalog/cards/${c.id}`)}
                      >
                        {c.title}
                      </button>
                      <span className="record-id">
                        {c.group_name} · {c.idol_name}
                      </span>
                    </div>
                  </div>
                ),
              },
              {
                title: "状态",
                dataIndex: "status",
                render: (v) => <StatusTag status={v} />,
              },
            ]}
          />
        </Panel>
        <Panel title="图鉴录入指南" subtitle="一条清晰的内容链路。">
          <div className="guide-steps">
            {[
              ["1", "建立组合与艺人", "维护组合资料和成员归属"],
              ["2", "录入专辑与来源", "关联专辑、活动或 Other 来源"],
              ["3", "完善小卡档案", "上传正反面，确认来源与版权"],
              ["4", "预览、审核与发布", "让收藏内容进入 App 图鉴"],
            ].map(([n, t, d]) => (
              <div key={n}>
                <span>{n}</span>
                <div>
                  <h4>{t}</h4>
                  <p>{d}</p>
                </div>
              </div>
            ))}
          </div>
          <Button
            type="primary"
            block
            onClick={() => navigate("/catalog/cards/new")}
          >
            开始录入小卡 <ArrowRightOutlined aria-hidden="true" />
          </Button>
        </Panel>
      </div>
    </>
  );
}

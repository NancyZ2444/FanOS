import { Form, Modal } from "./components/admin";
import Tags from "./pages/Tags";
import { useCallback, useEffect, useState } from "react";
import {
  Link,
  Navigate,
  Route,
  Routes,
  useLocation,
  useBlocker,
  useNavigate,
} from "react-router-dom";
import {
  Alert,
  App as AntApp,
  Avatar,
  Badge,
  Button,
  Dropdown,
  Input,
  Result,
  Skeleton,
  Spin,
} from "antd";
import {
  AuditOutlined,
  BellOutlined,
  BookOutlined,
  CommentOutlined,
  DashboardOutlined,
  DownOutlined,
  FileProtectOutlined,
  GiftOutlined,
  LogoutOutlined,
  MenuFoldOutlined,
  MessageOutlined,
  SearchOutlined,
  SettingOutlined,
  SoundOutlined,
  TeamOutlined,
  UserOutlined,
} from "@ant-design/icons";
import { clearSession, consoleApi, hasSession, login } from "./api/client";
import type { Actor, Catalog, Kind } from "./api/types";
import { emptyCatalog, roleLabels } from "./api/types";
import { ConsoleContext } from "./state";
import Cards from "./pages/Cards";
import CardEditor from "./pages/CardEditor";
import Entities from "./pages/Entities";
import Imports from "./pages/Imports";
import Dashboard from "./pages/Dashboard";
import Sources from "./pages/Sources";
import Operations, { operationNames } from "./pages/Operations";
import System from "./pages/System";
import AdminUsers from "./pages/AdminUsers";
import CatalogDetail from "./pages/CatalogDetail";
import CatalogWorkbench from "./pages/CatalogWorkbench";
import DigitalAlbums from "./pages/DigitalAlbums";
import FeedbackWorkbench from "./pages/FeedbackWorkbench";

function Login({ onLogin }: { onLogin: (actor: Actor) => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [form] = Form.useForm();
  const submit = async (values: { phone: string; code: string }) => {
    setBusy(true);
    setError("");
    try {
      onLogin(await login(values.phone, values.code));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="login-page">
      <div className="login-brand">
        <Link to="/">
          <span className="brand-icon">F</span>
          <strong>Fan OS</strong>
        </Link>
        <div className="login-copy">
          <div className="eyebrow">EVERY COLLECTION HAS A STORY</div>
          <h1>
            让热爱，
            <br />
            有迹可循。
          </h1>
          <p>
            从一张小卡，到每一份珍贵的收藏。
            <br />
            在这里，悉心维护属于粉丝的内容世界。
          </p>
          <div className="login-art">
            <div className="login-art-card one">
              <span>FAN OS</span>
              <b>✦</b>
              <small>COLLECT YOUR MOMENT</small>
            </div>
            <div className="login-art-card two">
              <span>PHOTOCARD</span>
              <b>✧</b>
              <small>EVERY LITTLE STORY</small>
            </div>
          </div>
        </div>
        <small className="login-copyright">FAN OS · ADMIN CONSOLE</small>
      </div>
      <div className="login-form">
        <div className="login-form-inner">
          <div className="eyebrow">ADMIN CONSOLE</div>
          <h2>登录运营工作台</h2>
          <p>使用管理员账号，继续今天的内容维护。</p>
          {error && (
            <Alert
              showIcon
              type="error"
              message={error}
              style={{ marginBottom: 20 }}
            />
          )}
          <Form form={form} layout="vertical" onFinish={submit}>
            <Form.Item
              name="phone"
              label="管理员手机号"
              rules={[
                { required: true, message: "请输入手机号" },
                { pattern: /^1\d{10}$/, message: "请输入 11 位手机号" },
              ]}
            >
              <Input
                size="large"
                prefix={<UserOutlined aria-hidden="true" />}
                placeholder="请输入管理员手机号"
                autoComplete="tel"
              />
            </Form.Item>
            <Form.Item
              name="code"
              label="登录验证码"
              rules={[{ required: true, message: "请输入验证码" }]}
            >
              <Input
                size="large"
                maxLength={6}
                placeholder="请输入验证码"
                autoComplete="one-time-code"
              />
            </Form.Item>
            <Button
              block
              size="large"
              type="primary"
              htmlType="submit"
              loading={busy}
            >
              进入工作台
            </Button>
          </Form>
          {import.meta.env.DEV && (
            <div className="dev-account">
              <span>本地开发账号</span>
              <b>13900000000 / 123456</b>
              <Button
                type="link"
                onClick={() =>
                  form.setFieldsValue({ phone: "13900000000", code: "123456" })
                }
              >
                填入账号
              </Button>
            </div>
          )}
          <div className="login-secure">
            <FileProtectOutlined aria-hidden="true" /> 仅限经授权的运营人员访问
          </div>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  const [actor, setActor] = useState<Actor>();
  const [checking, setChecking] = useState(true);
  const [catalog, setCatalog] = useState<Catalog>(emptyCatalog);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [collapsed, setCollapsed] = useState(false);
  const [search, setSearch] = useState("");
  const [quick, setQuick] = useState(false);
  const [quickSearch, setQuickSearch] = useState("");
  const navigate = useNavigate();
  const location = useLocation();
  const { modal } = AntApp.useApp();
  const reload = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = await consoleApi<Catalog>("/catalog");
      setCatalog(data);
    } catch (e) {
      setError((e as Error).message);
      throw e;
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    if (hasSession())
      consoleApi<Actor>("/me")
        .then(setActor)
        .catch(() => {})
        .finally(() => setChecking(false));
    else setChecking(false);
    const logout = () => setActor(undefined);
    window.addEventListener("fanos:logout", logout);
    return () => window.removeEventListener("fanos:logout", logout);
  }, []);
  useEffect(() => {
    if (actor) reload().catch(() => {});
  }, [actor, reload]);
  const blocker = useBlocker(
    ({ currentLocation, nextLocation }) =>
      currentLocation.pathname !== nextLocation.pathname &&
      (document.body.dataset.unsaved === "true" ||
        document.body.dataset.formUnsaved === "true"),
  );
  useEffect(() => {
    if (blocker.state !== "blocked") return;
    const confirmation = modal.confirm({
      title: "放弃未保存的修改？",
      content: "已填写的内容尚未保存，离开后需要重新填写。",
      okText: "放弃修改",
      cancelText: "继续编辑",
      onOk: () => {
        delete document.body.dataset.unsaved;
        delete document.body.dataset.formUnsaved;
        blocker.proceed();
      },
      onCancel: () => blocker.reset(),
    });
    return () => confirmation.destroy();
  }, [blocker.state, blocker.location?.key]);
  const go = (path: string) => navigate(path);
  if (checking)
    return (
      <div className="app-loading">
        <Spin size="large" />
        <span>正在连接 Fan OS 工作台…</span>
      </div>
    );
  if (!actor) return <Login onLogin={setActor} />;
  const contentRole = actor.role !== "operation_admin";
  const operationRole = actor.role !== "content_operator";
  const sections = [
    {
      label: "工作台",
      icon: <DashboardOutlined aria-hidden="true" />,
      path: "/dashboard",
    },
    {
      label: "图鉴内容管理",
      icon: <BookOutlined aria-hidden="true" />,
      path: "/catalog/cards",
      children: [
        { label: "小卡管理", path: "/catalog/cards" },
        { label: "组合管理", path: "/catalog/groups" },
        { label: "艺人管理", path: "/catalog/idols" },
        { label: "AI Scan 索引", path: "/catalog/scan" },
        { label: "公司管理", path: "/catalog/companies" },
        { label: "标签管理", path: "/catalog/tags" },
        {
          label: "专辑管理",
          path: "/catalog/albums",
        },
        { label: "活动管理", path: "/catalog/events" },
        { label: "其他来源", path: "/catalog/others" },
        ...(contentRole
          ? [{ label: "批量导入", path: "/catalog/import" }]
          : []),
        { label: "批次与批量编辑", path: "/catalog/workbench" },
        { label: "图鉴审核与质量", path: "/catalog/review" },
        { label: "小卡缺失收录", path: "/catalog/missing-cards" },
        { label: "图鉴问题纠错", path: "/catalog/corrections" },
      ],
    },
    ...(contentRole
      ? [
          {
            label: "明星动态管理",
            icon: <CommentOutlined aria-hidden="true" />,
            path: "/operations/social",
            children: [
              { label: "动态列表", path: "/operations/social" },
              { label: "社交数据源", path: "/operations/accounts" },
            ],
          },
        ]
      : []),
    ...(operationRole
      ? [
          {
            label: "每日翻卡管理",
            icon: <GiftOutlined aria-hidden="true" />,
            path: "/operations/daily",
            children: [
              { label: "卡池与概率", path: "/operations/daily" },
              { label: "翻卡记录", path: "/operations/draws" },
            ],
          },
          {
            label: "消息中心",
            icon: <MessageOutlined aria-hidden="true" />,
            path: "/operations/notifications",
          },
          {
            label: "首页运营",
            icon: <SoundOutlined aria-hidden="true" />,
            path: "/operations/announcements",
          },
          {
            label: "用户管理",
            icon: <TeamOutlined aria-hidden="true" />,
            path: "/operations/users",
          },
          {
            label: "数字相册",
            icon: <BookOutlined aria-hidden="true" />,
            path: "/digital-albums",
          },
        ]
      : []),
    {
      label: "审核与来源",
      icon: <AuditOutlined aria-hidden="true" />,
      path: contentRole ? "/reviews/sources" : "/operations/reports",
      children: [
        ...(contentRole
          ? [
              { label: "来源审核", path: "/reviews/sources" },
              { label: "小卡审核", path: "/catalog/cards?status=PENDING" },
            ]
          : []),
        ...(operationRole
          ? [
              { label: "举报管理", path: "/operations/reports" },
              { label: "评论管理", path: "/operations/comments" },
            ]
          : []),
      ],
    },
    {
      label: "系统管理",
      icon: <SettingOutlined aria-hidden="true" />,
      path: "/system/roles",
      children: [
        ...(actor.role === "admin"
          ? [{ label: "管理员账号", path: "/system/admins" }]
          : []),
        { label: "角色与权限", path: "/system/roles" },
        ...(actor.role === "admin"
          ? [{ label: "操作日志", path: "/system/logs" }]
          : []),
      ],
    },
  ];
  const current = location.pathname.startsWith("/catalog/")
    ? "图鉴内容管理"
    : location.pathname.startsWith("/reviews")
      ? "审核与来源"
      : location.pathname.startsWith("/system")
        ? "系统管理"
        : location.pathname === "/digital-albums"
          ? "数字相册"
          : operationNames[location.pathname.split("/").pop() || ""] ||
            "工作台";
  return (
    <ConsoleContext.Provider value={{ actor, catalog, reload, loading }}>
      <div className={`app-shell ${collapsed ? "sidebar-collapsed" : ""}`}>
        <aside className="sidebar">
          <button className="brand" onClick={() => go("/dashboard")}>
            <span className="brand-icon">
              F<span>✦</span>
            </span>
            <span className="brand-wordmark">
              <strong>Fan OS</strong>
              <small>ADMIN CONSOLE</small>
            </span>
          </button>
          <nav>
            {sections.map((s) => {
              const active =
                location.pathname === s.path ||
                s.children?.some(
                  (c) =>
                    (c.path.includes("?")
                      ? location.pathname + location.search === c.path
                      : location.pathname.startsWith(c.path)) ||
                    (c as any).match?.includes(location.pathname),
                );
              return (
                <div key={s.label} className="nav-group">
                  <button
                    className={`nav-parent ${active ? "active-parent" : ""}`}
                    title={s.label}
                    onClick={() => go(s.path)}
                  >
                    {s.icon}
                    <span>{s.label}</span>
                    {s.children && (
                      <DownOutlined
                        aria-hidden="true"
                        className="nav-arrow"
                        rotate={active ? 0 : -90}
                      />
                    )}
                  </button>
                  {s.children && active && !collapsed && (
                    <div className="nav-children">
                      {s.children.map((c) => (
                        <button
                          key={c.path}
                          className={
                            location.pathname === c.path ||
                            (c.path === "/catalog/cards" &&
                              /^\/catalog\/cards\//.test(location.pathname)) ||
                            ([
                              "/catalog/missing-cards",
                              "/catalog/corrections",
                            ].includes(c.path) &&
                              location.pathname.startsWith(c.path + "/")) ||
                            (c as any).match?.includes(location.pathname)
                              ? "active"
                              : ""
                          }
                          onClick={() => go(c.path)}
                        >
                          <span className="nav-child-dot" />
                          {c.label}
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </nav>
          <div className="sidebar-bottom">
            <button
              className="collapse-button"
              onClick={() => setCollapsed(!collapsed)}
              aria-label="收起或展开侧栏"
            >
              <MenuFoldOutlined
                aria-hidden="true"
                rotate={collapsed ? 180 : 0}
              />
              <span>收起导航</span>
            </button>
          </div>
        </aside>
        <div className="main-shell">
          <header className="topbar">
            <div className="topbar-breadcrumb">
              <span>工作空间</span>
              <b>/</b>
              <strong>{current}</strong>
            </div>
            <div className="global-search">
              <SearchOutlined aria-hidden="true" />
              <input
                aria-label="全局搜索"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="搜索组合、艺人、小卡…"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && search.trim()) {
                    go(`/catalog/cards?q=${encodeURIComponent(search)}`);
                    setSearch("");
                  }
                }}
              />
              <kbd>↵</kbd>
            </div>
            <div className="topbar-right">
              {contentRole && (
                <Button
                  onClick={() => {
                    setQuickSearch("");
                    setQuick(true);
                  }}
                >
                  快速创建
                </Button>
              )}
              <Dropdown
                trigger={["click"]}
                menu={{
                  items: [
                    {
                      key: "pending",
                      label: `待审核小卡 · ${catalog.cards.filter((c) => c.status === "PENDING").length}`,
                    },
                    { key: "sources", label: "查看来源审核任务" },
                  ],
                  onClick: ({ key }) =>
                    go(
                      key === "pending"
                        ? "/catalog/cards?status=PENDING"
                        : "/reviews/sources",
                    ),
                }}
              >
                <button className="top-icon-button" aria-label="查看待处理事项">
                  <Badge
                    dot={catalog.cards.some((c) => c.status === "PENDING")}
                  >
                    <BellOutlined aria-hidden="true" />
                  </Badge>
                </button>
              </Dropdown>
              <span className="topbar-separator" />
              <Dropdown
                trigger={["click"]}
                menu={{
                  items: [
                    {
                      key: "role",
                      label: roleLabels[actor.role],
                      disabled: true,
                    },
                    {
                      key: "logout",
                      icon: <LogoutOutlined aria-hidden="true" />,
                      label: "退出登录",
                    },
                  ],
                  onClick: ({ key }) => {
                    if (key === "logout") clearSession();
                  },
                }}
              >
                <button className="user-menu">
                  <Avatar
                    size={32}
                    style={{ background: "#eee7fb", color: "#8660dc" }}
                  >
                    {actor.name.slice(0, 1)}
                  </Avatar>
                  <span>
                    {actor.name}
                    <small>{roleLabels[actor.role]}</small>
                  </span>
                  <DownOutlined aria-hidden="true" />
                </button>
              </Dropdown>
            </div>
          </header>
          <main className="page-body">
            {error && (
              <Alert
                showIcon
                type="error"
                message={error}
                action={
                  <Button onClick={() => reload().catch(() => {})}>
                    重新连接
                  </Button>
                }
                style={{ marginBottom: 20 }}
              />
            )}
            {loading && !catalog.cards.length ? (
              <Skeleton active paragraph={{ rows: 14 }} />
            ) : (
              <Routes>
                <Route
                  path="/catalog/:kind/:id/detail"
                  element={<CatalogDetail />}
                />
                <Route
                  path="/catalog/workbench"
                  element={<CatalogWorkbench mode="workbench" />}
                />
                <Route
                  path="/catalog/review"
                  element={<CatalogWorkbench mode="review" />}
                />
                <Route
                  path="/catalog/scan"
                  element={<CatalogWorkbench mode="scan" />}
                />
                <Route
                  path="/catalog/companies"
                  element={<CatalogWorkbench mode="companies" />}
                />
                <Route
                  path="/"
                  element={<Navigate to="/catalog/cards" replace />}
                />
                <Route path="/dashboard" element={<Dashboard />} />
                <Route
                  path="/catalog/cards"
                  element={<Cards key={location.search} />}
                />
                <Route
                  path="/catalog/cards/:id"
                  element={<CardEditor key={location.pathname} />}
                />
                {(
                  ["groups", "idols", "albums", "events", "others"] as Kind[]
                ).map((kind) => (
                  <Route
                    key={kind}
                    path={`/catalog/${kind}`}
                    element={<Entities kind={kind} key={kind} />}
                  />
                ))}
                <Route path="/catalog/tags" element={<Tags />} />
                <Route path="/catalog/import" element={<Imports />} />
                <Route
                  path="/catalog/missing-cards/:feedbackId?"
                  element={
                    <FeedbackWorkbench key="missing" kind="MISSING_CARD" />
                  }
                />
                <Route
                  path="/catalog/corrections/:feedbackId?"
                  element={
                    <FeedbackWorkbench key="corrections" kind="CORRECTION" />
                  }
                />
                <Route path="/reviews/sources" element={<Sources />} />
                <Route path="/digital-albums" element={<DigitalAlbums />} />
                {Object.keys(operationNames).map((kind) => (
                  <Route
                    key={kind}
                    path={`/operations/${kind}`}
                    element={<Operations kind={kind} key={kind} />}
                  />
                ))}
                <Route path="/system/admins" element={<AdminUsers />} />
                <Route path="/system/roles" element={<System tab="roles" />} />
                <Route path="/system/logs" element={<System tab="logs" />} />
                <Route
                  path="*"
                  element={
                    <Result
                      status="404"
                      title="页面不存在"
                      extra={
                        <Button onClick={() => go("/catalog/cards")}>
                          返回图鉴管理
                        </Button>
                      }
                    />
                  }
                />
              </Routes>
            )}
          </main>
        </div>
      </div>
      <Modal
        title="快速创建"
        open={quick}
        onCancel={() => setQuick(false)}
        footer={null}
      >
        <Input
          placeholder="搜索小卡、专辑等"
          value={quickSearch}
          onChange={(e) => setQuickSearch(e.target.value)}
        />
        <div className="quick-create-grid">
          {[
            { label: "新增组合", path: "/catalog/groups?create=true" },
            { label: "新增艺人", path: "/catalog/idols?create=true" },
            { label: "新增专辑", path: "/catalog/albums?create=true" },
            { label: "新增活动", path: "/catalog/events?create=true" },
            {
              label: "新增其他来源",
              path: "/catalog/others?create=true",
            },
            { label: "新增小卡", path: "/catalog/cards/new" },
            {
              label: "小卡批次",
              path: "/catalog/workbench?tab=batches",
            },
            { label: "导入文件", path: "/catalog/import" },
            {
              label: "上传图片",
              path: "/catalog/workbench?tab=images",
            },
          ]
            .filter((i) =>
              i.label.toLowerCase().includes(quickSearch.toLowerCase()),
            )
            .map((i) => (
              <Button
                key={i.label}
                onClick={() => {
                  setQuick(false);
                  go(i.path);
                }}
              >
                {i.label}
              </Button>
            ))}
        </div>
      </Modal>
    </ConsoleContext.Provider>
  );
}

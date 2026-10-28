import { useEffect, useState } from "react";
import { Alert, App, Button, Checkbox, Spin } from "antd";
import {
  Table,
  TableToolbar,
  useFormGuard,
  useSingleSubmit,
} from "../components/admin";
import { consoleApi, send } from "../api/client";
import { roleLabels, type Role } from "../api/types";
import { useConsole } from "../state";

const permissionDependencies: Record<string, string> = {
  "auth.users.manage": "auth.users.view",
  "auth.users.sensitive": "auth.users.view",
  "auth.identities.unbind": "auth.users.view",
  "auth.test_code.manage": "auth.whitelist.manage",
};

type Capability = { key: string; label: string; admin_only: boolean };
type Matrix = {
  version: number;
  roles: Record<Role, string[]>;
  capabilities: Capability[];
};
export default function RolePermissions() {
  const { message } = App.useApp();
  const { reload } = useConsole();
  const [value, setValue] = useState<Matrix>();
  const [original, setOriginal] = useState<Matrix>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const guard = useFormGuard(true, busy);
  const changed =
    JSON.stringify(value?.roles) !== JSON.stringify(original?.roles);
  const load = async () => {
    setLoading(true);
    try {
      const next = await consoleApi<Matrix>("/roles");
      setValue(next);
      setOriginal(next);
      setError("");
      guard.reset();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => {
    void load();
  }, []);
  const toggle = (role: Role, key: string, checked: boolean) => {
    guard.mark();
    setValue((current) => {
      if (!current) return current;
      const keys = new Set(current.roles[role]);
      if (checked) {
        keys.add(key);
        if (permissionDependencies[key]) keys.add(permissionDependencies[key]);
        if (key.startsWith("catalog.")) keys.add("catalog.view");
      } else {
        keys.delete(key);
        for (const [dependent, required] of Object.entries(
          permissionDependencies,
        ))
          if (required === key) keys.delete(dependent);
        if (key === "catalog.view")
          for (const item of keys)
            if (item.startsWith("catalog.")) keys.delete(item);
      }
      return {
        ...current,
        roles: { ...current.roles, [role]: [...keys].sort() },
      };
    });
  };
  const save = useSingleSubmit(async () => {
    if (!value || !changed) return;
    setBusy(true);
    setError("");
    try {
      const saved = await consoleApi<Matrix>(
        "/roles",
        send({ version: value.version, roles: value.roles }, "PUT"),
      );
      setValue(saved);
      setOriginal(saved);
      guard.reset();
      message.success("角色权限已保存，相关账号下次操作即生效");
      void reload().catch(() =>
        message.warning("权限已保存，页面资料暂未刷新"),
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  });
  return (
    <>
      {error && (
        <Alert
          type="error"
          showIcon
          message={error}
          description="未保存的勾选仍保留。"
          action={
            <Button onClick={() => guard.close(() => void load())}>
              刷新权限
            </Button>
          }
        />
      )}
      <section className="panel table-panel">
        <TableToolbar
          actions={
            <Button
              disabled={busy}
              onClick={() => guard.close(() => void load())}
            >
              刷新
            </Button>
          }
        >
          权限配置
        </TableToolbar>
        <Spin spinning={loading}>
          <Table
            rowKey="key"
            pagination={false}
            dataSource={value?.capabilities ?? []}
            columns={[
              { title: "功能", dataIndex: "label" },
              ...Object.entries(roleLabels).map(([role, label]) => ({
                title: label,
                width: 180,
                render: (_: unknown, row: Capability) => (
                  <Checkbox
                    aria-label={`${label}：${row.label}`}
                    checked={value?.roles[role as Role]?.includes(row.key)}
                    disabled={role === "admin" || row.admin_only || busy}
                    onChange={(e) =>
                      toggle(role as Role, row.key, e.target.checked)
                    }
                  />
                ),
              })),
            ]}
          />
        </Spin>
        <div className="form-actions">
          <span className="muted">
            超级管理员保留完整权限；权限配置与后台管理员管理仅限超级管理员。
          </span>
          <Button
            disabled={!changed || busy}
            onClick={() =>
              guard.close(() => {
                setValue(original);
                setError("");
              })
            }
          >
            取消
          </Button>
          <Button
            type="primary"
            loading={busy}
            disabled={!changed || loading}
            onClick={() => void save()}
          >
            保存
          </Button>
        </div>
      </section>
    </>
  );
}

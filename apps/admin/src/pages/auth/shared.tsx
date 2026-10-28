import { useEffect, useState } from "react";
import { Alert, Button } from "antd";
import { api } from "../../api/client";

export const authApi = <T = any,>(path: string, init?: RequestInit) =>
  api<T>(`/admin/auth${path}`, init);
export interface AuthMeta {
  environment: string;
  permissions: string[];
}
export function useAuthMeta() {
  const [meta, setMeta] = useState<AuthMeta>();
  const [error, setError] = useState("");
  const load = () => {
    setError("");
    authApi<AuthMeta>("/meta")
      .then(setMeta)
      .catch((e) => setError(e.message));
  };
  useEffect(load, []);
  return {
    meta,
    can: (permission: string) => !!meta?.permissions.includes(permission),
    error,
    retry: load,
  };
}
export function LoadError({
  error,
  retry,
}: {
  error: string;
  retry?: () => void;
}) {
  return error ? (
    <Alert
      showIcon
      type="error"
      message={error}
      action={retry && <Button onClick={retry}>重试</Button>}
      style={{ marginBottom: 16 }}
    />
  ) : null;
}
export const truth = (v: string) => [
  { value: "", label: `全部${v}` },
  { value: "true", label: `${v}` },
  { value: "false", label: `未${v.replace(/^已/, "")}` },
];
export const channelLabel = (v?: string) =>
  ({
    phone: "手机号",
    sms: "短信",
    test_code: "测试验证码",
    whitelist: "测试白名单",
    wechat: "微信",
    weibo: "微博",
    qq: "QQ",
    password: "密码",
  })[v || ""] ||
  v ||
  "—";
export const authorizationLabel = (v?: string) =>
  ({
    valid: "授权有效",
    active: "授权有效",
    expired: "已知授权过期",
    revoked: "授权已撤销",
    unknown: "授权状态未知",
  })[(v || "unknown").toLowerCase()] || "授权状态未知";
export function filtersQuery(values: Record<string, unknown>) {
  return new URLSearchParams(
    Object.entries(values)
      .filter(([, v]) => v !== undefined && v !== null && v !== "")
      .map(([k, v]) => [k, String(v)]),
  ).toString();
}

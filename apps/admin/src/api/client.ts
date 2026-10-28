import type { Actor, FieldError } from "./types";
import { createRequestKey } from "./requestKey";
const base = import.meta.env.VITE_API_BASE_URL || "/api/v1";
const sessionKey = "fanos-admin-session";
const refreshRequestKey = "fanos-admin-refresh-request";
export class ApiError extends Error {
  constructor(
    message: string,
    public status = 0,
    public fields: FieldError[] = [],
  ) {
    super(message);
  }
}
export function clearSession() {
  sessionStorage.removeItem(sessionKey);
  sessionStorage.removeItem(refreshRequestKey);
  window.dispatchEvent(new Event("fanos:logout"));
}
function session(): { access_token?: string; refresh_token?: string } {
  try {
    return JSON.parse(sessionStorage.getItem(sessionKey) || "{}");
  } catch {
    return {};
  }
}
export const hasSession = () => !!session().access_token;
let refreshPromise: Promise<boolean | "unavailable"> | undefined;
async function refresh() {
  if (!refreshPromise)
    refreshPromise = (async () => {
      const token = session().refresh_token;
      if (!token) return false;
      try {
        const requestId =
          sessionStorage.getItem(refreshRequestKey) || createRequestKey();
        sessionStorage.setItem(refreshRequestKey, requestId);
        const res = await fetch(base + "/admin/auth/refresh", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Idempotency-Key": requestId,
          },
          body: JSON.stringify({ refresh_token: token }),
          signal: AbortSignal.timeout(15000),
        });
        if (!res.ok)
          return res.status === 401 || res.status === 403
            ? false
            : "unavailable";
        const json = await res.json();
        sessionStorage.setItem(sessionKey, JSON.stringify(json.data));
        sessionStorage.removeItem(refreshRequestKey);
        return true;
      } catch {
        return "unavailable";
      }
    })().finally(() => {
      refreshPromise = undefined;
    });
  return refreshPromise;
}
export async function api<T = any>(
  path: string,
  init: RequestInit = {},
  retry = true,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(base + path, {
      ...init,
      signal: init.signal || AbortSignal.timeout(30000),
      headers: {
        ...(init.body instanceof FormData
          ? {}
          : { "Content-Type": "application/json" }),
        ...(session().access_token
          ? { Authorization: `Bearer ${session().access_token}` }
          : {}),
        ...init.headers,
      },
    });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") throw e;
    throw new ApiError("无法连接服务，请检查后台 API 是否已启动");
  }
  if (
    response.status === 401 &&
    !path.startsWith("/admin/auth/login") &&
    !path.startsWith("/admin/auth/refresh")
  ) {
    if (retry) {
      const refreshed = await refresh();
      if (refreshed === true) return api<T>(path, init, false);
      if (refreshed === "unavailable")
        throw new ApiError("暂时无法恢复后台会话，请重试；已保留本地登录信息");
    }
    clearSession();
  }
  if (
    response.ok &&
    !response.headers.get("content-type")?.includes("application/json")
  ) {
    return (await response.blob()) as T;
  }
  const json = await response.json().catch(() => ({}));
  if (!response.ok || json.code !== 0) {
    const fields = (json.data?.details || []).map((e: any) => ({
      field:
        e.field || (e.loc || []).filter((s: string) => s !== "body").join("."),
      message: e.message || e.msg,
    }));
    throw new ApiError(
      json.message || "操作失败，请稍后重试",
      response.status,
      fields,
    );
  }
  return json.data as T;
}
export const consoleApi = <T = any>(path: string, init?: RequestInit) =>
  api<T>("/admin/console" + path, init);
export const send = (data: unknown, method = "POST"): RequestInit => ({
  method,
  body: JSON.stringify(data),
});
export async function login(account: string, password: string): Promise<Actor> {
  const data = await api("/admin/auth/login", send({ account, password }));
  sessionStorage.removeItem(refreshRequestKey);
  sessionStorage.setItem(sessionKey, JSON.stringify(data));
  try {
    return await consoleApi<Actor>("/me");
  } catch (e) {
    clearSession();
    throw e;
  }
}
export async function logout() {
  await api(
    "/admin/auth/logout",
    send({ refresh_token: session().refresh_token }),
  );
  clearSession();
}
export async function uploadImage(
  file: File,
  crop?: { points: { x: number; y: number }[] },
) {
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type))
    throw new ApiError("请选择 JPG、PNG 或 WebP 图片");
  if (file.size > 10 * 1024 * 1024) throw new ApiError("图片不能超过 10 MB");
  const data = new FormData();
  data.append("file", file);
  if (crop) data.append("crop", JSON.stringify(crop));
  return consoleApi<{ url: string }>("/uploads", {
    method: "POST",
    body: data,
  });
}

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, login, logout } from "../src/api/client";
import { authorizationLabel, filtersQuery } from "../src/pages/auth/shared";
import { webcrypto } from "node:crypto";

const stored = new Map<string, string>();
const response = (data: unknown, status = 200) =>
  new Response(
    JSON.stringify({ code: status === 200 ? 0 : "UNAUTHORIZED", data }),
    { status, headers: { "content-type": "application/json" } },
  );
beforeEach(() => {
  stored.clear();
  vi.stubGlobal("sessionStorage", {
    getItem: (k: string) => stored.get(k) || null,
    setItem: (k: string, v: string) => stored.set(k, v),
    removeItem: (k: string) => stored.delete(k),
  });
  vi.stubGlobal("window", { dispatchEvent: vi.fn() });
});
afterEach(() => vi.unstubAllGlobals());

describe("independent admin authentication", () => {
  it("uses admin credentials and never App challenge endpoints", async () => {
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(
        response({
          access_token: "admin-token",
          refresh_token: "admin-refresh",
        }),
      )
      .mockResolvedValueOnce(
        response({ id: "admin-1", role: "admin", name: "Operator" }),
      );
    vi.stubGlobal("fetch", fetch);
    await login("operator", "test-only-password");
    expect(fetch.mock.calls[0][0]).toBe("/api/v1/admin/auth/login");
    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({
      account: "operator",
      password: "test-only-password",
    });
    expect(stored.get("fanos-admin-session")).not.toContain(
      "test-only-password",
    );
  });
  it("refreshes only the admin audience", async () => {
    stored.set(
      "fanos-admin-session",
      JSON.stringify({
        access_token: "expired",
        refresh_token: "admin-refresh",
      }),
    );
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(response({}, 401))
      .mockResolvedValueOnce(
        response({ access_token: "new", refresh_token: "new-refresh" }),
      )
      .mockResolvedValueOnce(response({ items: [] }));
    vi.stubGlobal("fetch", fetch);
    await api("/admin/auth/users");
    expect(fetch.mock.calls[1][0]).toBe("/api/v1/admin/auth/refresh");
    expect(fetch.mock.calls[2][1].headers.Authorization).toBe("Bearer new");
  });
  it("retains local session during temporary refresh outage", async () => {
    stored.set(
      "fanos-admin-session",
      JSON.stringify({
        access_token: "expired",
        refresh_token: "admin-refresh",
      }),
    );
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValueOnce(response({}, 401))
        .mockRejectedValueOnce(new TypeError("network unavailable")),
    );
    await expect(api("/admin/auth/users")).rejects.toThrow(
      "已保留本地登录信息",
    );
    expect(stored.has("fanos-admin-session")).toBe(true);
  });
  it("refreshes on HTTP and reuses the refresh key after a temporary outage", async () => {
    vi.stubGlobal("crypto", {
      getRandomValues: webcrypto.getRandomValues.bind(webcrypto),
    });
    stored.set(
      "fanos-admin-session",
      JSON.stringify({
        access_token: "expired",
        refresh_token: "admin-refresh",
      }),
    );
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(response({}, 401))
      .mockRejectedValueOnce(new TypeError("temporary network failure"))
      .mockResolvedValueOnce(response({}, 401))
      .mockResolvedValueOnce(
        response({ access_token: "new", refresh_token: "new-refresh" }),
      )
      .mockResolvedValueOnce(response({ items: [] }));
    vi.stubGlobal("fetch", fetch);
    await expect(api("/admin/auth/users")).rejects.toThrow(
      "已保留本地登录信息",
    );
    const key = stored.get("fanos-admin-refresh-request");
    expect(key).toMatch(/^[0-9a-f-]{36}$/);
    await expect(api("/admin/auth/users")).resolves.toEqual({ items: [] });
    expect(fetch.mock.calls[1][1].headers["Idempotency-Key"]).toBe(key);
    expect(fetch.mock.calls[3][1].headers["Idempotency-Key"]).toBe(key);
    expect(stored.has("fanos-admin-refresh-request")).toBe(false);
  });
  it("preserves the session and permits retry after key generation fails", async () => {
    vi.stubGlobal("crypto", {});
    stored.set(
      "fanos-admin-session",
      JSON.stringify({
        access_token: "expired",
        refresh_token: "admin-refresh",
      }),
    );
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(response({}, 401))
      .mockResolvedValueOnce(response({}, 401))
      .mockResolvedValueOnce(
        response({ access_token: "new", refresh_token: "new-refresh" }),
      )
      .mockResolvedValueOnce(response({ items: [] }));
    vi.stubGlobal("fetch", fetch);
    await expect(api("/admin/auth/users")).rejects.toThrow(
      "已保留本地登录信息",
    );
    expect(fetch).toHaveBeenCalledOnce();
    expect(stored.has("fanos-admin-session")).toBe(true);
    vi.stubGlobal("crypto", {
      getRandomValues: webcrypto.getRandomValues.bind(webcrypto),
    });
    await expect(api("/admin/auth/users")).resolves.toEqual({ items: [] });
  });
  it("revokes the server session before clearing local credentials", async () => {
    stored.set(
      "fanos-admin-session",
      JSON.stringify({
        access_token: "admin-token",
        refresh_token: "admin-refresh",
      }),
    );
    const fetch = vi.fn().mockResolvedValue(response({}));
    vi.stubGlobal("fetch", fetch);
    await logout();
    expect(fetch.mock.calls[0][0]).toBe("/api/v1/admin/auth/logout");
    expect(stored.has("fanos-admin-session")).toBe(false);
  });
  it("unknown authorization never claims valid and filters preserve false values", () => {
    expect(authorizationLabel()).toBe("授权状态未知");
    expect(authorizationLabel("some-new-value")).toBe("授权状态未知");
    expect(filtersQuery({ q: "", whitelist: false, page: 2 })).toBe(
      "whitelist=false&page=2",
    );
  });
});

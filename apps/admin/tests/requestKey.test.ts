import { webcrypto } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createRequestKey } from "../src/api/requestKey";

const uuidV4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
afterEach(() => vi.unstubAllGlobals());

describe("request keys on secure and HTTP origins", () => {
  it("prefers the browser's native UUID implementation", () => {
    const randomUUID = vi.fn(() => "88e470b8-251e-4eab-bb6e-bbd892c9e42f");
    const getRandomValues = vi.fn();
    vi.stubGlobal("crypto", { randomUUID, getRandomValues });
    expect(createRequestKey()).toBe("88e470b8-251e-4eab-bb6e-bbd892c9e42f");
    expect(randomUUID).toHaveBeenCalledOnce();
    expect(getRandomValues).not.toHaveBeenCalled();
  });

  it("produces distinct UUID v4 keys using secure entropy when randomUUID is unavailable", () => {
    vi.stubGlobal("crypto", {
      getRandomValues: webcrypto.getRandomValues.bind(webcrypto),
    });
    const keys = Array.from({ length: 100 }, () => createRequestKey());
    expect(new Set(keys).size).toBe(100);
    for (const key of keys) expect(key).toMatch(uuidV4);
  });

  it.each([undefined, {}])(
    "fails explicitly without a secure entropy source",
    (crypto) => {
      vi.stubGlobal("crypto", crypto);
      expect(() => createRequestKey()).toThrow("无法生成安全请求编号");
    },
  );
});

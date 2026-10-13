import { describe, expect, it } from "vitest";
import { displayValue, formatTime, actionLabel } from "../src/design/format";
describe("business presentation boundary cases", () => {
  it("uses Beijing time across UTC date boundaries and accepts naive API UTC timestamps", () => {
    expect(formatTime("2026-10-13T18:30:45Z")).toBe("2026-10-14 02:30");
    expect(formatTime("2026-10-13T18:30:45")).toBe("2026-10-14 02:30");
    expect(formatTime("2026-10-14T02:30:45+08:00")).toBe("2026-10-14 02:30");
    expect(formatTime("invalid")).toBe("—");
  });
  it("preserves false and zero while distinguishing unset values", () => {
    expect(displayValue(false)).toBe("否");
    expect(displayValue(0)).toBe("0");
    expect(displayValue(null)).toBe("—");
    expect(displayValue([])).toBe("—");
    expect(displayValue("PUBLISHED")).toBe("已发布");
  });
  it("presents audit actions without leaking implementation namespaces", () => {
    expect(actionLabel("catalog.card.delete")).toBe("小卡 · 删除");
    expect(actionLabel("catalog.entity.archive")).toBe("图鉴内容 · 归档");
  });
});

import { describe, expect, it } from "vitest";
import type { CatalogEntity } from "../src/api/types";
import { groupMembers, memberLabel } from "../src/pages/memberOptions";

const idols = [
  { id: "current", name: "Current", group_id: "a", status: "PUBLISHED" },
  {
    id: "former",
    name: "Former",
    group_id: "b",
    status: "PUBLISHED",
    membership_history: [
      { group_id: "a", status: "former", end_date: "2020-12-31" },
    ],
  },
  { id: "other", name: "Other", group_id: "b", status: "PUBLISHED" },
  { id: "archived", name: "Archived", group_id: "a", status: "ARCHIVED" },
  { id: "solo", name: "Solo", group_id: "", status: "DRAFT" },
] as CatalogEntity[];

describe("group member selection", () => {
  it("includes current and former members and excludes unrelated groups", () => {
    expect(groupMembers(idols, "a").map((i) => i.id)).toEqual([
      "current",
      "former",
    ]);
    expect(memberLabel(idols[1], "a")).toBe("Former（历史成员）");
  });
  it("retains an existing card identity even with missing legacy membership", () => {
    expect(groupMembers(idols, "a", "other").map((i) => i.id)).toEqual([
      "current",
      "former",
      "other",
    ]);
  });
  it("allows solo releases by group members and independent idols", () => {
    expect(groupMembers(idols, "").map((i) => i.id)).toEqual([
      "current",
      "former",
      "other",
      "solo",
    ]);
    expect(groupMembers(idols, "nonexistent")).toEqual([]);
  });
});

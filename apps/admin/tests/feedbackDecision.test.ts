import { describe, expect, it } from "vitest";
import { initialReviewResult } from "../src/pages/feedback/ReviewDecisionFields";
import type { FeedbackRecord } from "../src/pages/feedback/types";

const record = (values: Partial<FeedbackRecord>) =>
  ({ review: {}, public_note: "旧处理说明", ...values }) as FeedbackRecord;
describe("feedback decision prefill compatibility", () => {
  it.each([
    ["INCLUDED", "ACCEPTED"],
    ["NOT_INCLUDED", "REJECTED"],
    ["NEEDS_INFO", "NEEDS_INFO"],
  ])(
    "shows the existing %s outcome without requiring data migration",
    (result, decision) => {
      expect(initialReviewResult(record({ result }))).toEqual({
        decision,
        note: "旧处理说明",
      });
    },
  );
  it("keeps the internally proposed decision and note until they are submitted", () => {
    expect(
      initialReviewResult(
        record({
          result: "PENDING",
          review_decision: "ACCEPTED",
          review: {
            review_decision_draft: "NEEDS_INFO",
            public_note_draft: "请补充背面图片",
          },
        }),
      ),
    ).toEqual({ decision: "NEEDS_INFO", note: "请补充背面图片" });
  });
});

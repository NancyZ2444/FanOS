import { Input, Radio } from "antd";
import { ReviewField } from "./FeedbackValues";
import type { FeedbackRecord, ReviewDecision } from "./types";

export const acceptedPublicNote = "已采纳，待发布后更新图鉴。";
export const reviewDecisionLabels: Record<ReviewDecision, string> = {
  ACCEPTED: "已采纳",
  REJECTED: "未采纳",
  NEEDS_INFO: "信息缺失待补充",
};
export type ReviewResult = {
  decision?: ReviewDecision;
  note: string;
};
export function initialReviewResult(item: FeedbackRecord): ReviewResult {
  const legacyDecision: ReviewDecision | undefined =
    item.result === "INCLUDED"
      ? "ACCEPTED"
      : item.result === "NOT_INCLUDED"
        ? "REJECTED"
        : item.result === "NEEDS_INFO"
          ? "NEEDS_INFO"
          : undefined;
  return {
    decision:
      item.review.review_decision_draft ??
      item.review_decision ??
      legacyDecision,
    note: item.review.public_note_draft ?? item.public_note ?? "",
  };
}

/** Shared by missing-card, missing-catalog and correction workbenches. */
export default function ReviewDecisionFields({
  value,
  onChange,
  editing,
  idPrefix = "feedback",
  decisionError,
  noteError,
}: {
  value: ReviewResult;
  onChange: (value: ReviewResult) => void;
  editing: boolean;
  idPrefix?: string;
  decisionError?: string;
  noteError?: string;
}) {
  return (
    <>
      <ReviewField
        id={`${idPrefix}-review-decision`}
        label="处理结果"
        required={editing}
        error={decisionError}
      >
        {editing ? (
          <Radio.Group
            id={`${idPrefix}-review-decision`}
            aria-label="处理结果"
            className="feedback-result-options"
            value={value.decision}
            onChange={(event) =>
              onChange({
                decision: event.target.value,
                note:
                  event.target.value === "ACCEPTED" ? acceptedPublicNote : "",
              })
            }
          >
            {Object.entries(reviewDecisionLabels).map(([key, label]) => (
              <Radio.Button key={key} value={key}>
                {label}
              </Radio.Button>
            ))}
          </Radio.Group>
        ) : (
          <div className="feedback-read-value">
            {value.decision ? reviewDecisionLabels[value.decision] : "待确认"}
          </div>
        )}
      </ReviewField>
      <ReviewField
        id={`${idPrefix}-public-note`}
        label="公开处理说明"
        required={editing}
        error={noteError}
        extra={
          editing
            ? "提交处理结果后同步用户；保存草稿仅供内部处理。已采纳后需单独发布，才会更新正式图鉴。"
            : undefined
        }
      >
        {editing ? (
          <Input.TextArea
            id={`${idPrefix}-public-note`}
            aria-label="公开处理说明"
            value={value.note}
            maxLength={2000}
            showCount
            autoSize={{ minRows: 3, maxRows: 6 }}
            onChange={(event) =>
              onChange({ ...value, note: event.target.value })
            }
          />
        ) : (
          <div className="feedback-read-value feedback-value">
            {value.note || "—"}
          </div>
        )}
      </ReviewField>
    </>
  );
}

export type Values = Record<string, any>;
export type FeedbackKind = "MISSING_CARD" | "MISSING_CATALOG" | "CORRECTION";
export type ReviewDecision = "ACCEPTED" | "REJECTED" | "NEEDS_INFO";
export type Field = {
  key: string;
  label: string;
  type: string;
  current: any;
  suggested: any;
  mode: string;
  reason: string;
  reference?: string;
  parent_id?: string | null;
  section?: string;
  max_length?: number;
  entity_type?: string;
  entity_id?: string;
  options?: string[];
};
export type Decision = {
  key: string;
  decision: string;
  value?: any;
  reason?: string;
};
export type FeedbackRecord = {
  id: string;
  revision: number;
  kind: FeedbackKind;
  name: string;
  status: string;
  result: string;
  review_decision?: ReviewDecision | null;
  can_publish?: boolean;
  status_label: string;
  user: { name: string; id: string };
  created_at: string;
  updated_at?: string;
  public_note: string;
  internal_note: string;
  handler_id?: string;
  entity_type: string;
  entity_id: string;
  submission: Values;
  review: Values;
  latest?: Values;
  draft?: Values;
  history: Values[];
};
export const kinds = [
  { value: "groups", label: "组合" },
  { value: "idols", label: "艺人" },
  { value: "cards", label: "小卡" },
  { value: "albums", label: "专辑" },
  { value: "events", label: "活动" },
  { value: "others", label: "其他来源" },
  { value: "versions", label: "版本" },
  { value: "companies", label: "公司" },
];
export const statusLabels: Record<string, string> = {
  PENDING: "待处理",
  PROCESSING: "处理中",
  PROCESSED: "已处理",
};
export const sourceLabels: Record<string, string> = {
  ALBUM: "专辑",
  EVENT: "活动",
  OTHER: "其他来源",
};
export function resultLabel(
  result: string,
  kind: FeedbackKind,
  decision?: ReviewDecision | null,
) {
  void kind;
  if (result === "PENDING" && decision === "ACCEPTED") return "已采纳，待发布";
  return result === "INCLUDED"
    ? "已采纳并发布"
    : result === "NOT_INCLUDED"
      ? "未采纳"
      : result === "NEEDS_INFO"
        ? "信息缺失待补充"
        : "待确认";
}
export const copyrightOptions = [
  { value: "UNKNOWN", label: "尚未核实" },
  { value: "AUTHORIZED", label: "已确认获得使用授权" },
  { value: "OFFICIAL_SOURCE", label: "已核实官方来源使用条件" },
];

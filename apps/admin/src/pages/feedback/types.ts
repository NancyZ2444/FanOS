export type Values = Record<string, any>;
export type FeedbackKind = "MISSING_CARD" | "CORRECTION";
export type Field = {
  key: string;
  label: string;
  type: string;
  current: any;
  suggested: any;
  mode: string;
  reason: string;
  reference?: string;
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
export function resultLabel(result: string, kind: FeedbackKind) {
  return result === "INCLUDED"
    ? "已收录"
    : result === "NOT_INCLUDED"
      ? kind === "MISSING_CARD"
        ? "未收录"
        : "未采纳"
      : "待确认";
}
export const copyrightOptions = [
  { value: "UNKNOWN", label: "尚未核实" },
  { value: "AUTHORIZED", label: "已确认获得使用授权" },
  { value: "OFFICIAL_SOURCE", label: "已核实官方来源使用条件" },
];

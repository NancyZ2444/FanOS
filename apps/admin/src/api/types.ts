export type Status =
  | "DRAFT"
  | "PENDING"
  | "PUBLISHED"
  | "OFFLINE"
  | "ARCHIVED"
  | "REJECTED";
export type Kind = "groups" | "idols" | "albums" | "events" | "others";
export type Role = "admin" | "content_operator" | "operation_admin";
export type ImportKind = Kind | "cards" | "groups_idols" | "companies";
export const importLabels: Record<ImportKind, string> = {
  companies: "公司",
  groups_idols: "组合 + 艺人",
  cards: "小卡",
  groups: "组合",
  idols: "艺人",
  albums: "专辑",
  events: "活动",
  others: "其他来源",
};
export interface Actor {
  id: string;
  name: string;
  role: Role;
}
export interface SourceInfo {
  source_type: string;
  source_url: string;
  copyright_status: string;
  source_platform?: string;
  copyright_note?: string;
  source_account?: string;
}
export interface CatalogEntity {
  id: string;
  name: string;
  name_en?: string;
  name_ko?: string;
  name_translated?: string;
  group_id?: string;
  company?: string;
  company_ids?: string[];
  membership_history?: {
    group_id: string;
    status: string;
    start_date?: string;
    end_date?: string | null;
  }[];
  description?: string;
  bio?: string;
  release_date?: string;
  image_url?: string;
  status: Status;
  updated_at: string;
  member_count?: number;
  card_count: number;
  tags?: string[];
  source_info?: SourceInfo;
  [key: string]: any;
}
export interface Card {
  id: string;
  title: string;
  title_en?: string;
  title_ko?: string;
  title_translated?: string;
  group_id: string;
  group_name: string;
  idol_id: string | null;
  idol_name: string;
  source: string;
  source_entity_type: string;
  source_entity_id: string;
  entity_version_id?: string | null;
  card_type: string;
  version: string;
  edition?: string;
  card_number?: string;
  rarity: string;
  release_date: string;
  region: string;
  tags: string[];
  status: Status;
  image_url?: string;
  back_image_url?: string;
  is_group_pc: boolean;
  is_double_sided: boolean;
  is_official: boolean;
  is_limited: boolean;
  is_random: boolean;
  has_ar: boolean;
  ar_type: string;
  ar_resource: string;
  source_info: SourceInfo;
  front_source: SourceInfo;
  back_source: SourceInfo;
  updated_at: string;
  created_at: string;
  operator?: string;
  review_note?: string;
  [key: string]: any;
}
export type Catalog = Record<Kind, CatalogEntity[]> & { cards: Card[] };
export interface ImportTask {
  id: string;
  kind: ImportKind;
  filename: string;
  status: string;
  created_at: string;
  imported_count: number;
  rows: { row: number; data: Record<string, unknown>; created_id?: string }[];
  errors: {
    row: number;
    field: string;
    message: string;
    suggestion: string;
    can_skip: boolean;
  }[];
}
export interface FieldError {
  field: string;
  message: string;
}
export const emptyCatalog: Catalog = {
  groups: [],
  idols: [],
  albums: [],
  events: [],
  others: [],
  cards: [],
};
export const emptySource = (): SourceInfo => ({
  source_type: "ADMIN_UPLOAD",
  source_url: "",
  copyright_status: "UNKNOWN",
});
export const emptyCard = (): Partial<Card> => ({
  title: "",
  group_id: "",
  idol_id: null,
  source_entity_type: "ALBUM",
  source_entity_id: "",
  card_type: "Regular",
  version: "",
  release_date: "",
  rarity: "R",
  region: "",
  tags: [],
  is_group_pc: false,
  is_double_sided: false,
  is_official: true,
  is_limited: false,
  is_random: false,
  has_ar: false,
  ar_type: "IMAGE",
  ar_resource: "",
  source_info: emptySource(),
  front_source: emptySource(),
  back_source: emptySource(),
});
export const names: Record<Kind, string> = {
  groups: "组合管理",
  idols: "艺人管理",
  albums: "专辑管理",
  events: "活动管理",
  others: "Other 管理",
};
export const sourceKinds: Record<string, Kind> = {
  ALBUM: "albums",
  EVENT: "events",
  OTHER: "others",
};
export const sourceLabels: Record<string, string> = {
  ALBUM: "专辑 Album",
  EVENT: "活动 Event",
  OTHER: "其他 Other",
};
export const statusLabels: Record<string, string> = {
  DRAFT: "草稿",
  PENDING: "待审核",
  PUBLISHED: "已发布",
  OFFLINE: "已下架",
  ARCHIVED: "已归档",
  REJECTED: "已驳回",
  APPROVED: "已通过",
  SENT: "已发送",
  CANCELLED: "已取消",
  NORMAL: "正常",
  BANNED: "已封禁",
  VISIBLE: "正常展示",
  HIDDEN: "已隐藏",
  DELETED: "已删除",
  RESOLVED: "已处理",
  VALIDATED: "校验通过",
  HAS_ERRORS: "待修复",
  COMPLETED: "已完成",
};
export const roleLabels: Record<Role, string> = {
  admin: "超级管理员",
  content_operator: "内容运营",
  operation_admin: "运营管理员",
};

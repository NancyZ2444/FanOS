export type Background = {
  type?: "SOLID" | "GRADIENT" | "IMAGE";
  colors?: string[];
  angle?: number;
  image_url?: string;
  resource_id?: string;
  resource_snapshot?: Resource;
};
export type CanvasElement = {
  id: string;
  type: "TEXT" | "EMOJI" | "STICKER" | "CARD" | "STROKE";
  content: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  z_index: number;
  points?: number[][];
  resource_snapshot?: Resource;
  style?: {
    color?: string;
    font_size?: number;
    font_family?: string;
    bold?: boolean;
    stroke_width?: number;
    opacity?: number;
  };
};
export type CanvasConfig = {
  background?: Background;
  elements?: CanvasElement[];
};
export type Slot = { id: string; card_id: string | null };
export type Album = {
  work_mode?: "BOOK" | "CARDS" | "REVIEW";
  card_instances?: Slot[];
  id: string;
  user_id: string;
  author_name: string;
  name: string;
  description: string;
  visibility: string;
  status: string;
  page_count: number;
  card_count: number;
  report_count: number;
  is_moderated: boolean;
  moderation_status?: string;
  publication_blocked?: boolean;
  review_status?: string;
  created_at: string;
  updated_at: string;
  published_at?: string;
  display_type?: string;
  visual_style?: string;
  cover?: CanvasConfig;
  cover_slots?: Slot[];
  card_view?: {
    background?: Background;
    default_mode?: string;
    cover_style?: string;
    card_order?: string[];
    display_fields?: string[];
  };
  pages: {
    id: string;
    grid_count?: number;
    slots: Slot[];
    config?: CanvasConfig;
  }[];
  cards: Record<
    string,
    {
      title: string;
      image_url?: string;
      back_image_url?: string;
      available?: boolean;
      idol_name?: string;
      group_name?: string;
      source?: string;
      card_type?: string;
      version?: string;
      release_date?: string;
      region?: string;
      size?: string;
    }
  >;
};
export type Resource = {
  id: string;
  name: string;
  kind: "SHELF" | "STICKER" | "BACKGROUND" | "COLOR";
  status: "DRAFT" | "PUBLISHED" | "OFFLINE";
  sort_order: number;
  scene?: "SHELF" | "ALBUM_COVER" | "ALBUM_PAGE" | "CARD_BACKGROUND";
  membership?: "ALL" | "PRO";
  locked_preview?: boolean;
  ever_published?: boolean;
  can_delete?: boolean;
  published_once?: boolean;
  used_once?: boolean;
  config: {
    type?: "SOLID" | "GRADIENT" | "IMAGE";
    symbol?: string;
    image_url?: string;
    colors?: string[];
    angle?: number;
    ledge?: string;
  };
};
export type Limits = {
  normal_cards: number;
  pro_cards: number;
  normal_albums: number;
  pro_albums: number;
  normal_pages: number;
  pro_pages: number;
  normal_color_daily: number;
  pro_color_daily: number;
  normal_color_monthly: number;
  pro_color_monthly: number;
  max_card_per_page: number;
  blocked_terms: string[];
};
export type AlbumReport = {
  id: string;
  reason: string;
  status: string;
  user_id?: string;
  created_at: string;
};
export type AlbumLog = {
  id: string;
  action: string;
  reason?: string;
  reason_code?: string;
  note?: string;
  actor_id?: string;
  actor_name?: string;
  before?: Record<string, unknown>;
  after?: Record<string, unknown>;
  created_at: string;
};
export type AlbumDetail = Album & {
  preview_version?: string;
  resources?: Resource[];
  reports?: AlbumReport[];
  logs?: AlbumLog[];
  review_snapshot?: Album | null;
  shelf_snapshot?: Resource;
  review_request?: {
    id: string;
    revision: number;
    status: string;
    created_at: string;
  } | null;
  moderation_reason?: string;
  moderation_note?: string;
};
export const resourceKinds = [
  { value: "SHELF", label: "书架" },
  { value: "BACKGROUND", label: "背景" },
  { value: "COLOR", label: "推荐颜色" },
  { value: "STICKER", label: "贴纸" },
];
export const resourceStatuses = [
  { value: "DRAFT", label: "草稿" },
  { value: "PUBLISHED", label: "已上架" },
  { value: "OFFLINE", label: "已下架" },
];
export const moderationReasons = [
  { value: "PORNOGRAPHY", label: "色情低俗" },
  { value: "ILLEGAL", label: "违法违规" },
  { value: "PRIVACY", label: "侵犯隐私" },
  { value: "COPYRIGHT", label: "版权问题" },
  { value: "MALICIOUS", label: "恶意内容" },
  { value: "SPAM", label: "广告垃圾" },
  { value: "TEXT", label: "不当文字" },
  { value: "IMAGE", label: "不当图片" },
  { value: "OTHER", label: "其他" },
];
export const moderationLabels: Record<string, string> = {
  NORMAL: "正常",
  NONE: "正常",
  RESTRICTED: "限制公开",
  OFFLINE: "已下架",
  PENDING: "待复核",
  PENDING_REVIEW: "待复核",
  RESTRICT: "限制公开",
  RESTORE: "恢复作品",
  REJECT: "驳回复核",
  REVIEW_REQUESTED: "提交复核",
};
export const moderationStatus = (album: Album) =>
  album.moderation_status || (album.is_moderated ? "RESTRICTED" : "NORMAL");

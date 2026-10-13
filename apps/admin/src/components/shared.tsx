import { useRef, useState } from "react";
import { App, Button, Empty, Modal, Tag, Tooltip } from "antd";
import {
  CheckCircleOutlined,
  CloudUploadOutlined,
  InfoCircleOutlined,
  PictureOutlined,
  SwapOutlined,
} from "@ant-design/icons";
import type { Card, CatalogEntity, Status } from "../api/types";
import { statusLabels } from "../api/types";
import { uploadImage } from "../api/client";
import CardImageCrop from "./CardImageCrop";
import type { CardCrop } from "./CardImageCrop";

export function EntityAvatar({
  entity,
  circle = false,
  small = false,
}: {
  entity?: CatalogEntity;
  circle?: boolean;
  small?: boolean;
}) {
  const [broken, setBroken] = useState<string>();
  const url = entity?.image_url || entity?.cover_image || entity?.avatar_url;
  return (
    <span
      className={`entity-avatar${circle ? " circle" : ""}`}
      style={
        small
          ? {
              width: 24,
              height: 24,
              minWidth: 24,
              fontSize: 12,
              display: "inline-flex",
              verticalAlign: "middle",
              marginRight: 8,
            }
          : undefined
      }
    >
      {url && broken !== url ? (
        <img
          src={url}
          alt={`${entity?.name || "档案"}图片`}
          aria-hidden="true"
          onError={() => setBroken(url)}
        />
      ) : (
        entity?.name?.slice(0, 1) || "?"
      )}
    </span>
  );
}

export function StatusTag({ status }: { status: string }) {
  const colors: Record<string, string> = {
    PUBLISHED: "success",
    PENDING: "warning",
    DRAFT: "default",
    OFFLINE: "default",
    REJECTED: "error",
    ARCHIVED: "default",
    APPROVED: "success",
    SENT: "success",
    NORMAL: "success",
    BANNED: "error",
    VISIBLE: "success",
    HIDDEN: "warning",
    HAS_ERRORS: "error",
    COMPLETED: "success",
    VALIDATED: "success",
  };
  return (
    <Tag className="status-tag" color={colors[status] || "default"}>
      <span className="status-dot" />
      {statusLabels[status] || status}
    </Tag>
  );
}
export function CardArt({
  card,
  back = false,
  small = false,
}: {
  card: Partial<Card>;
  back?: boolean;
  small?: boolean;
}) {
  const [brokenUrl, setBrokenUrl] = useState<string>();
  const url = back ? card.back_image_url : card.image_url;
  if (url && url !== brokenUrl)
    return (
      <img
        key={url}
        className={`card-art ${small ? "small" : ""}`}
        src={url}
        onError={() => setBrokenUrl(url)}
        alt={`${card.title || "小卡"}${back ? "背面" : "正面"}`}
      />
    );
  return (
    <div
      className={`card-art art-placeholder ${small ? "small" : ""} ${back ? "back" : ""}`}
    >
      <span className="art-group">{card.group_name || "FAN OS"}</span>
      <div className="art-orbit">
        <span>✦</span>
      </div>
      <div className="art-name">
        {back
          ? "COLLECT YOUR MOMENT"
          : card.idol_name || (card.is_group_pc ? "GROUP" : "PHOTOCARD")}
      </div>
      {!small && (
        <span className="art-caption">
          {url ? "图片暂时无法加载" : "图片待上传"}
        </span>
      )}
    </div>
  );
}
export function ImageUpload({
  value,
  onChange,
  label,
  disabled = false,
  cropCard = false,
}: {
  value?: string;
  onChange?: (value: string) => void;
  label: string;
  disabled?: boolean;
  cropCard?: boolean;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [cropFile, setCropFile] = useState<File>();
  const { message } = App.useApp();
  const handle = async (file?: File, crop?: CardCrop) => {
    if (!file || disabled || busy) return;
    if (input.current) input.current.value = "";
    if (cropCard && !crop) {
      if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
        message.error("请选择 JPG、PNG 或 WebP 图片");
        return;
      }
      if (file.size > 10 * 1024 * 1024) {
        message.error("图片不能超过 10 MB");
        return;
      }
      setCropFile(file);
      return;
    }
    setBusy(true);
    try {
      const result = await uploadImage(file, crop);
      setCropFile(undefined);
      onChange?.(result.url);
      message.success("图片上传成功");
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  };
  return (
    <div className="image-upload">
      {cropFile && (
        <CardImageCrop
          file={cropFile}
          busy={busy}
          confirmLabel="确认裁剪并上传"
          onCancel={() => setCropFile(undefined)}
          onConfirm={(crop) => handle(cropFile, crop)}
        />
      )}
      <input
        ref={input}
        hidden
        disabled={disabled || busy}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        aria-label={`上传${label}`}
        onChange={(e) => handle(e.target.files?.[0])}
      />
      {value ? (
        <div className="uploaded-image">
          <img src={value} alt={label} />
          <Button
            size="small"
            disabled={disabled}
            loading={busy}
            icon={<SwapOutlined aria-hidden="true" />}
            onClick={() => input.current?.click()}
          >
            更换图片
          </Button>
        </div>
      ) : (
        <button
          type="button"
          className="upload-zone"
          onClick={() => input.current?.click()}
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            handle(e.dataTransfer.files[0]);
          }}
          disabled={busy || disabled}
        >
          <CloudUploadOutlined aria-hidden="true" />
          <b>{busy ? "正在上传…" : `上传${label}`}</b>
          <span>点击上传或拖拽图片至此</span>
          <small>JPG / PNG / WebP · 最大 10 MB</small>
        </button>
      )}
    </div>
  );
}
export function AppPreview({
  card,
  onClose,
}: {
  card: Partial<Card>;
  onClose?: () => void;
}) {
  const [back, setBack] = useState(false);
  const body = (
    <div className="preview-layout">
      <div className="phone-frame">
        <div className="phone-top">
          <b>9:41</b>
          <span>● ▰</span>
        </div>
        <div className="phone-header">
          <span>‹</span>
          <b>小卡详情</b>
          <span>···</span>
        </div>
        <button
          className="phone-card"
          onClick={() => setBack(!back)}
          aria-label="翻转小卡"
        >
          <CardArt card={card} back={back} />
        </button>
        <span className="flip-hint">
          <SwapOutlined aria-hidden="true" /> 点击翻转查看
          {back ? "正面" : "背面"}
        </span>
        <div className="phone-body">
          <small>
            {card.group_name || "组合"} · {card.idol_name || "团卡"}
          </small>
          <h3>{card.title || "小卡名称"}</h3>
          <p>
            {card.source || "关联来源"} · {card.version || "版本"}
          </p>
          <div>
            {(card.tags || []).map((t) => (
              <Tag key={t}>{t}</Tag>
            ))}
          </div>
          <div className="phone-meta">
            <span>
              卡片类型<b>{card.card_type}</b>
            </span>
            <span>
              发行日期<b>{card.release_date || "—"}</b>
            </span>
          </div>
          <div className="phone-actions">
            <span>♡ 心愿单</span>
            <strong>＋ 加入收藏</strong>
          </div>
        </div>
        <div className="home-indicator" />
      </div>
      <div className="preview-note">
        <CheckCircleOutlined aria-hidden="true" />
        <h3>检查每一个收藏细节</h3>
        <p>
          预览小卡正反面、名称、来源与标签。发布后，小卡将出现在 App 图鉴中。
        </p>
        <span>
          <InfoCircleOutlined aria-hidden="true" />{" "}
          此处为后台预览，不会写入个人收藏。
        </span>
      </div>
    </div>
  );
  return onClose ? (
    <Modal
      open
      title="App 展示预览"
      width={780}
      footer={<Button onClick={onClose}>关闭预览</Button>}
      onCancel={onClose}
    >
      {body}
    </Modal>
  ) : (
    body
  );
}
export function Panel({
  title,
  subtitle,
  extra,
  children,
  className = "",
}: {
  title?: string;
  subtitle?: string;
  extra?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={`panel ${className}`}>
      {title && (
        <div className="panel-heading">
          <div>
            <h3>{title}</h3>
            {subtitle && <p>{subtitle}</p>}
          </div>
          {extra}
        </div>
      )}
      {children}
    </section>
  );
}
export function EmptyState({
  description = "暂无符合条件的内容",
}: {
  description?: string;
}) {
  return (
    <Empty
      image={
        <PictureOutlined
          aria-hidden="true"
          style={{ fontSize: 40, color: "#b7afd0" }}
        />
      }
      description={description}
    />
  );
}
export function Help({ text }: { text: string }) {
  return (
    <Tooltip title={text}>
      <InfoCircleOutlined aria-hidden="true" className="help-icon" />
    </Tooltip>
  );
}
export const editable = (status: Status) =>
  ["DRAFT", "REJECTED", "OFFLINE"].includes(status);

import { useState, type CSSProperties, type ReactNode } from "react";
import { Button, Select, Tag } from "antd";
import {
  LeftOutlined,
  RightOutlined,
  ZoomInOutlined,
  ZoomOutOutlined,
} from "@ant-design/icons";
import type {
  Album,
  Background,
  CanvasConfig,
  CanvasElement,
  Resource,
  Slot,
} from "./types";

export function backgroundStyle(background?: Background): CSSProperties {
  const value = background?.resource_snapshot?.config || background;
  const colors = value?.colors?.length ? value.colors : ["#E8EBE3"];
  if (value?.image_url) {
    return {
      backgroundColor: colors[0],
      backgroundImage: `url("${value.image_url.replace(/["\\\n\r]/g, "")}")`,
      backgroundSize: "cover",
      backgroundPosition: "center",
    };
  }
  return value?.type === "GRADIENT" && colors.length > 1
    ? {
        background: `linear-gradient(${90 + (value.angle ?? 45)}deg, ${colors.join(",")})`,
      }
    : { background: colors[0] };
}
function CardImage({
  album,
  id,
  back = false,
}: {
  album: Album;
  id: string | null;
  back?: boolean;
}) {
  if (!id) return <span className="album-card-unavailable">空卡位</span>;
  const card = album.cards?.[id];
  const url = back ? card?.back_image_url : card?.image_url;
  return card && card.available !== false && url ? (
    <img src={url} alt={`${card.title}${back ? "背面" : ""}`} loading="lazy" />
  ) : (
    <span className="album-card-unavailable">
      {back && card?.available !== false ? "暂无背面" : "小卡暂不可用"}
    </span>
  );
}
function Element({
  element: e,
  album,
  resources,
}: {
  element: CanvasElement;
  album: Album;
  resources: Resource[];
}) {
  const style = e.style || {};
  const sticker =
    e.resource_snapshot || resources.find((r) => r.id === e.content);
  const base: CSSProperties = {
    left: `${e.x * 100}%`,
    top: `${e.y * 100}%`,
    width: `${e.width * 100}%`,
    height: `${e.height * 100}%`,
    transform: `rotate(${e.rotation}deg)`,
    zIndex: e.z_index + 1,
    color: style.color || "#342A56",
    opacity: e.type === "STROKE" ? (style.opacity ?? 1) : 1,
    fontFamily:
      style.font_family === "serif"
        ? "Georgia, serif"
        : style.font_family === "monospace"
          ? "Courier, monospace"
          : "inherit",
    fontWeight: style.bold ? 800 : 500,
  };
  let body: ReactNode;
  if (e.type === "CARD") body = <CardImage album={album} id={e.content} />;
  else if (e.type === "STROKE")
    body = (
      <svg
        viewBox="0 0 300 300"
        preserveAspectRatio="none"
        role="img"
        aria-label="画笔轨迹"
      >
        <polyline
          points={(e.points || [])
            .map(([x, y]) => `${x * 300},${y * 300}`)
            .join(" ")}
          fill="none"
          stroke={style.color || "#6D5DD3"}
          strokeWidth={style.stroke_width || 3}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    );
  else if (e.type === "STICKER" && sticker?.config.image_url)
    body = <img src={sticker.config.image_url} alt={sticker.name || "贴纸"} />;
  else {
    const text =
      e.type === "STICKER"
        ? sticker?.config.symbol ||
          ({ star: "✦", heart: "♡", bow: "🎀", flower: "✿", stay: "STAY" }[
            e.content
          ] ??
            "素材暂不可用")
        : e.content;
    const fontSize = style.font_size || 24;
    const naturalWidth =
      [...text].reduce(
        (sum, char) => sum + (/[\u0020-\u007E]/.test(char) ? 0.6 : 1),
        0,
      ) * fontSize;
    body = (
      <svg
        viewBox={`0 0 ${Math.max(fontSize, naturalWidth)} ${fontSize * 1.25}`}
        preserveAspectRatio="xMidYMid meet"
        role="img"
        aria-label={text}
      >
        <text
          x="50%"
          y="50%"
          dominantBaseline="central"
          textAnchor="middle"
          fill="currentColor"
          fontSize={fontSize}
        >
          {text}
        </text>
      </svg>
    );
  }
  return (
    <div className="album-canvas-element" style={base}>
      {body}
    </div>
  );
}
function Canvas({
  config,
  album,
  resources,
  children,
}: {
  config?: CanvasConfig;
  album: Album;
  resources: Resource[];
  children?: ReactNode;
}) {
  return (
    <div className="album-canvas" style={backgroundStyle(config?.background)}>
      {children}
      {[...(config?.elements || [])]
        .sort((a, b) => a.z_index - b.z_index)
        .map((e) => (
          <Element key={e.id} element={e} album={album} resources={resources} />
        ))}
    </div>
  );
}
function StackCover({ album }: { album: Album }) {
  const poses = [
    [0, -0.025, -3, 1],
    [-0.21, 0.025, -12, 0.87],
    [0.21, 0.015, 12, 0.87],
    [-0.3, -0.05, -15, 0.78],
    [0.3, -0.06, 15, 0.78],
  ];
  const slots = (album.cover_slots || []).slice(0, 5);
  return (
    <div
      className="album-canvas"
      style={backgroundStyle(
        album.card_view?.background || album.cover?.background,
      )}
    >
      {slots.length === 0 && (
        <span className="album-cover-empty">暂无封面</span>
      )}
      {slots.map((slot, index) => {
        const [x, y, rotation, scale] = poses[index];
        const width = (slots.length === 1 ? (166 / 128) * 47 : 53) * scale;
        return (
          <div
            key={slot.id}
            className="album-stack-card"
            style={{
              left: `${50 + x * 100}%`,
              top: `${50 + y * 100}%`,
              width: `${width}%`,
              aspectRatio: "1 / 1.55",
              transform: `translate(-50%, -50%) rotate(${rotation}deg)`,
              zIndex: 5 - index,
            }}
          >
            <CardImage album={album} id={slot.card_id} />
          </div>
        );
      })}
    </div>
  );
}
function Cover({ album, resources }: { album: Album; resources: Resource[] }) {
  if (
    album.work_mode === "CARDS" || (!album.work_mode && (
    album.card_view?.cover_style === "STACK_V1" ||
    (album.card_view?.cover_style !== "CUSTOM" &&
      !album.cover?.elements?.length &&
      !!album.cover_slots?.length)))
  )
    return <StackCover album={album} />;
  const empty = !album.cover?.elements?.length;
  return (
    <Canvas config={album.cover} album={album} resources={resources}>
      {empty && album.cover_slots?.length ? (
        <>
          <div className="album-auto-cover">
            <CardImage album={album} id={album.cover_slots[0].card_id} />
          </div>
          <span className="album-cover-title">{album.name}</span>
        </>
      ) : empty ? (
        <span className="album-cover-empty">暂无封面</span>
      ) : !album.cover?.elements?.some((e) => e.type === "TEXT") ? (
        <span className="album-cover-title">{album.name}</span>
      ) : null}
    </Canvas>
  );
}
function Page({
  page,
  album,
  resources,
}: {
  page: Album["pages"][number];
  album: Album;
  resources: Resource[];
}) {
  const count = page.slots.length;
  const columns = count <= 3 ? count : count === 4 ? 2 : 3;
  const rows = Math.ceil(count / Math.max(1, columns));
  // Match App's fixed 55:85 card pockets without stretching sparse layouts.
  const width = Math.min(
    (300 - 12 - 7 * (columns - 1)) / Math.max(1, columns),
    (((420 - 12 - 7 * (rows - 1)) / Math.max(1, rows)) * 55) / 85,
  );
  return (
    <div
      className={`album-binder ${album.visual_style === "REALISTIC" ? "is-realistic" : ""}`}
    >
      <Canvas config={page.config} album={album} resources={resources}>
        <div
          className="album-card-grid"
          style={{
            gridTemplateColumns: `repeat(${columns}, ${width / 3}%)`,
            gridAutoRows: `${(width * 85) / 55 / 4.2}%`,
          }}
        >
          {page.slots.map((slot) => (
            <div className="album-card-pocket" key={slot.id}>
              <CardImage album={album} id={slot.card_id} />
            </div>
          ))}
        </div>
      </Canvas>
    </div>
  );
}
export function ResourcePreview({ resource }: { resource: Resource }) {
  const config = resource.config;
  return (
    <div
      className={`album-resource-sample is-${resource.kind.toLowerCase()}`}
      style={
        resource.kind === "STICKER"
          ? undefined
          : backgroundStyle({ ...config, type: config.type || "GRADIENT" })
      }
    >
      {resource.kind === "STICKER" ? (
        config.image_url ? (
          <img src={config.image_url} alt={resource.name} />
        ) : (
          <span>{config.symbol || "✦"}</span>
        )
      ) : resource.kind === "SHELF" ? (
        <>
          <div className="album-sample-books">
            <span />
            <span />
            <span />
          </div>
          <div
            className="album-sample-ledge"
            style={{ background: config.ledge || "#B9B0A2" }}
          />
        </>
      ) : null}
    </div>
  );
}
export default function AlbumPreview({
  album,
  resources = [],
  shelf,
}: {
  album: Album;
  resources?: Resource[];
  shelf?: Resource;
}) {
  const [page, setPage] = useState(0);
  const [zoom, setZoom] = useState(1);
  const mode = album.work_mode || album.card_view?.default_mode || "BOOK";
  const [back, setBack] = useState(false);
  const slots = mode === "CARDS" ? (album.card_instances || []) : (album.pages || [])
    .flatMap((p) => p.slots)
    .filter((s) => !!s.card_id);
  const byId = new Map(slots.map((s) => [s.id, s]));
  const ordered = (album.card_view?.card_order || [])
    .map((id) => byId.get(id))
    .filter((s): s is Slot => !!s);
  const cardSlots = [
    ...ordered,
    ...slots.filter((s) => !ordered.some((item) => item.id === s.id)),
  ];
  const requestedPage = Math.min(
    page,
    mode === "CARDS" ? Math.max(0, cardSlots.length - 1) : album.pages.length,
  );
  const double = mode === "BOOK" && album.display_type === "DOUBLE";
  const currentPage =
    double && requestedPage > 0
      ? Math.floor((requestedPage - 1) / 2) * 2 + 1
      : requestedPage;
  const maximum =
    mode === "CARDS"
      ? Math.max(0, cardSlots.length - 1)
      : double
        ? Math.max(0, Math.ceil(album.pages.length / 2) * 2 - 1)
        : album.pages.length;
  const pageStep = double && currentPage > 0 ? 2 : 1;
  const sheetWidth =
    mode === "BOOK" && currentPage === 0 ? (420 * 128) / 166 : 340;
  const card = album.cards[cardSlots[currentPage]?.card_id || ""];
  const cardFields: Record<string, [string, string | undefined]> = {
    idol: ["艺人", card?.idol_name],
    group: ["组合", card?.group_name],
    source: ["来源", card?.source],
    type: ["卡种", card?.card_type],
    version: ["版本", card?.version],
    release: ["发行日期", card?.release_date],
    region: ["地区", card?.region],
    size: ["尺寸", card?.size],
  };
  return (
    <section className="album-preview" aria-label="完整作品预览">
      <div className="album-preview-toolbar">
        <Tag>{mode === "CARDS" ? "卡片作品" : "相册作品"} · 固定类型</Tag>
        <div className="toolbar-actions">
          {mode === "CARDS" && (
            <Button onClick={() => setBack(!back)}>
              {back ? "查看正面" : "查看背面"}
            </Button>
          )}
          <Button
            icon={<ZoomOutOutlined />}
            aria-label="缩小预览"
            disabled={zoom <= 0.75}
            onClick={() => setZoom(Math.max(0.75, zoom - 0.25))}
          />
          <span className="album-zoom">{Math.round(zoom * 100)}%</span>
          <Button
            icon={<ZoomInOutlined />}
            aria-label="放大预览"
            disabled={zoom >= 2}
            onClick={() => setZoom(Math.min(2, zoom + 0.25))}
          />
        </div>
      </div>
      {mode === "CARDS" && card && (
        <div className="album-card-metadata">
          <strong>{card.title}</strong>
          {(album.card_view?.display_fields || ["idol", "group", "source"]).map(
            (key) =>
              cardFields[key]?.[1] ? (
                <span key={key}>
                  {cardFields[key][0]}：{cardFields[key][1]}
                </span>
              ) : null,
          )}
        </div>
      )}
      <div
        className="album-preview-stage"
        style={
          shelf
            ? backgroundStyle({
                ...shelf.config,
                type: shelf.config.type || "GRADIENT",
              })
            : undefined
        }
      >
        {shelf && <Tag className="album-shelf-label">书架：{shelf.name}</Tag>}
        <div
          className="album-preview-sheet"
          style={{ width: sheetWidth * zoom, height: 420 * zoom }}
        >
          {mode === "CARDS" ? (
            <div
              className="album-preview-single-card"
              style={backgroundStyle(album.card_view?.background)}
            >
              <CardImage
                album={album}
                id={cardSlots[currentPage]?.card_id || null}
                back={back}
              />
            </div>
          ) : currentPage === 0 ? (
            <Cover album={album} resources={resources} />
          ) : (
            <Page
              page={album.pages[currentPage - 1]}
              album={album}
              resources={resources}
            />
          )}
        </div>
        {mode === "BOOK" &&
          album.display_type === "DOUBLE" &&
          currentPage > 0 &&
          album.pages[currentPage] && (
            <div
              className="album-preview-sheet"
              style={{ width: 340 * zoom, height: 420 * zoom }}
            >
              <Page
                page={album.pages[currentPage]}
                album={album}
                resources={resources}
              />
            </div>
          )}
      </div>
      <div className="album-preview-navigation">
        <Button
          icon={<LeftOutlined />}
          disabled={currentPage === 0}
          onClick={() => setPage(Math.max(0, currentPage - pageStep))}
        >
          上一页
        </Button>
        <Select
          aria-label="预览页码"
          value={currentPage}
          onChange={setPage}
          options={
            mode === "CARDS"
              ? (cardSlots.length
                  ? cardSlots
                  : [{ id: "empty", card_id: null }]
                ).map((s, i) => ({
                  value: i,
                  label: s.card_id
                    ? `第 ${i + 1} 张 · ${album.cards[s.card_id]?.title || "小卡"}`
                    : "暂无小卡",
                }))
              : [
                  { value: 0, label: "封面" },
                  ...album.pages.flatMap((_, i) =>
                    double && i % 2
                      ? []
                      : [
                          {
                            value: i + 1,
                            label:
                              double && i + 1 < album.pages.length
                                ? `第 ${i + 1}–${i + 2} 页`
                                : `第 ${i + 1} 页`,
                          },
                        ],
                  ),
                ]
          }
        />
        <Button
          icon={<RightOutlined />}
          disabled={currentPage >= maximum}
          onClick={() => setPage(Math.min(maximum, currentPage + pageStep))}
        >
          下一页
        </Button>
      </div>
      {mode === "BOOK" && (
        <div className="album-preview-thumbnails" aria-label="相册缩略图">
          <button
            className={currentPage === 0 ? "selected" : ""}
            onClick={() => setPage(0)}
            aria-label="查看封面"
          >
            <div>
              <Cover album={album} resources={resources} />
            </div>
            <span>封面</span>
          </button>
          {album.pages.map((item, i) => (
            <button
              key={item.id}
              className={
                currentPage === i + 1 ||
                (double && currentPage > 0 && currentPage === i)
                  ? "selected"
                  : ""
              }
              onClick={() => setPage(i + 1)}
              aria-label={`查看第 ${i + 1} 页`}
            >
              <div>
                <Page page={item} album={album} resources={resources} />
              </div>
              <span>第 {i + 1} 页</span>
            </button>
          ))}
        </div>
      )}
    </section>
  );
}

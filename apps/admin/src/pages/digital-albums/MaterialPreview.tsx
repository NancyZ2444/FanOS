import { useState } from "react";
import { Button, Segmented } from "antd";
import { backgroundStyle, ResourcePreview } from "./AlbumPreview";
import type { Resource } from "./types";

/** Read-only scene demonstration, never submits or changes work data. */
export default function MaterialPreview({ resource }: { resource: Resource }) {
  const [grid, setGrid] = useState(4),
    [columns, setColumns] = useState(2);
  const [double, setDouble] = useState(false),
    [minimal, setMinimal] = useState(false);
  const [focus, setFocus] = useState(1),
    [expanded, setExpanded] = useState(false);
  const swatch = backgroundStyle({
    ...resource.config,
    type: resource.config.type || "GRADIENT",
  });
  const sample = (i: number) => (
    <div key={i} className="material-sample-card">
      示例 {i + 1}
    </div>
  );
  if (resource.kind === "STICKER")
    return (
      <div>
        <p>封面贴纸 · 保留透明区域</p>
        <ResourcePreview resource={resource} />
      </div>
    );
  return (
    <div className="material-scene-preview">
      <p>场景示例 · 不保存作品</p>
      {resource.scene === "SHELF" ? (
        <>
          <Segmented
            value={columns}
            onChange={setColumns}
            options={[
              { value: 2, label: "每层 2 本" },
              { value: 3, label: "每层 3 本" },
            ]}
          />
          <div style={{ ...swatch, padding: 16 }}>
            {[0, 1].map((row) => (
              <div
                key={row}
                style={{
                  display: "grid",
                  gridTemplateColumns: `repeat(${columns}, 1fr)`,
                  gap: 12,
                  padding: "12px 0",
                  borderBottom: `6px solid ${resource.config.ledge || "#B9B0A2"}`,
                }}
              >
                {Array.from({ length: columns }, (_, i) =>
                  sample(row * columns + i),
                )}
              </div>
            ))}
          </div>
        </>
      ) : resource.scene === "CARD_BACKGROUND" ? (
        <>
          <div className="material-card-stage" style={swatch}>
            {[0, 1, 2].map((i) => (
              <button
                key={i}
                aria-label={`预览示例卡 ${i + 1}`}
                className="material-sample-card"
                onClick={() =>
                  i === focus
                    ? setExpanded(!expanded)
                    : (setFocus(i), setExpanded(false))
                }
                style={{
                  position: "absolute",
                  width: expanded && focus === i ? "54%" : "39%",
                  left: `${50 + (i - focus) * 24}%`,
                  top: "50%",
                  zIndex: i === focus ? 3 : 1,
                  transform: `translate(-50%, -50%) rotate(${i === focus ? 0 : (i - focus) * 9}deg)`,
                }}
              >
                示例 {i + 1}
              </button>
            ))}
          </div>
          <p>点侧卡聚焦，点居中卡放大或收回</p>
        </>
      ) : resource.scene === "ALBUM_PAGE" ? (
        <>
          <Segmented value={grid} onChange={setGrid} options={[1, 4, 9]} />
          <div className="toolbar-actions">
            <Button onClick={() => setDouble(!double)}>
              {double ? "双面" : "单面"}
            </Button>
            <Button onClick={() => setMinimal(!minimal)}>
              {minimal ? "极简" : "真实"}
            </Button>
          </div>
          <div style={{ display: "flex", gap: 6 }}>
            {Array.from({ length: double ? 2 : 1 }, (_, n) => (
              <div
                key={n}
                className={`material-page ${minimal ? "" : "is-paper"}`}
                style={{
                  ...swatch,
                  gridTemplateColumns: `repeat(${Math.sqrt(grid)}, 1fr)`,
                }}
              >
                {Array.from({ length: grid }, (_, i) => sample(i))}
              </div>
            ))}
          </div>
        </>
      ) : (
        <div className="material-cover is-paper" style={swatch}>
          {sample(0)}
          <span>封面示例</span>
        </div>
      )}
    </div>
  );
}

import { useEffect, useRef, useState } from "react";
import type { PointerEvent as ReactPointerEvent } from "react";
import { Alert, Button, InputNumber, Modal, Select, Space, Spin } from "antd";
import { consoleApi } from "../api/client";

type Point = { x: number; y: number };
export type CardCrop = { points: Point[] };
type Preview = {
  preview_url: string;
  width: number;
  height: number;
  regions: CardCrop[];
};
const fullImage: CardCrop = {
  points: [
    { x: 0, y: 0 },
    { x: 1, y: 0 },
    { x: 1, y: 1 },
    { x: 0, y: 1 },
  ],
};
const labels = ["左上", "右上", "右下", "左下"];
const clamp = (n: number) => Math.min(1, Math.max(0, n));

function validCrop({ points: p }: CardCrop) {
  const area =
    p.reduce(
      (sum, a, i) => sum + a.x * p[(i + 1) % 4].y - p[(i + 1) % 4].x * a.y,
      0,
    ) / 2;
  return (
    area >= 0.0001 &&
    p.every((a, i) => {
      const b = p[(i + 1) % 4],
        c = p[(i + 2) % 4];
      return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) > 1e-8;
    })
  );
}

// Mounted once per selected file. Keep the original for the confirmed request;
// preview detection does not persist media or create catalog records.
export default function CardImageCrop({
  file,
  busy,
  confirmLabel,
  onCancel,
  onConfirm,
}: {
  file: File;
  busy: boolean;
  confirmLabel: string;
  onCancel: () => void;
  onConfirm: (crop: CardCrop) => void;
}) {
  const [preview, setPreview] = useState<Preview>();
  const [crop, setCrop] = useState<CardCrop>(fullImage);
  const [error, setError] = useState("");
  const [attempt, setAttempt] = useState(0);
  const [region, setRegion] = useState(0);
  const surface = useRef<SVGSVGElement>(null);
  const drag = useRef<
    { index: number; start: Point; points: Point[] } | undefined
  >(undefined);
  useEffect(() => {
    const abort = new AbortController();
    const form = new FormData();
    form.append("file", file);
    consoleApi<Preview>("/cards/crop-preview", {
      method: "POST",
      body: form,
      signal: abort.signal,
    })
      .then((data) => {
        if (abort.signal.aborted) return;
        setPreview(data);
        setCrop(data.regions[0] || fullImage);
      })
      .catch((e: Error) => {
        if (!abort.signal.aborted) setError(e.message);
      });
    return () => abort.abort();
  }, [file, attempt]);
  const update = (index: number, point: Partial<Point>) => {
    if (busy) return;
    setCrop((current) => ({
      points: current.points.map((p, i) =>
        i === index ? { ...p, ...point } : p,
      ),
    }));
  };
  const position = (e: ReactPointerEvent): Point => {
    const rect = surface.current!.getBoundingClientRect();
    return {
      x: (e.clientX - rect.left) / rect.width,
      y: (e.clientY - rect.top) / rect.height,
    };
  };
  const start = (e: ReactPointerEvent<SVGElement>, index: number) => {
    if (busy) return;
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = { index, start: position(e), points: crop.points };
  };
  const move = (e: ReactPointerEvent<SVGElement>) => {
    if (!drag.current || busy) return;
    const next = position(e),
      original = drag.current;
    if (original.index >= 0)
      update(original.index, { x: clamp(next.x), y: clamp(next.y) });
    else {
      const xs = original.points.map((p) => p.x),
        ys = original.points.map((p) => p.y);
      const dx = Math.max(
        -Math.min(...xs),
        Math.min(1 - Math.max(...xs), next.x - original.start.x),
      );
      const dy = Math.max(
        -Math.min(...ys),
        Math.min(1 - Math.max(...ys), next.y - original.start.y),
      );
      setCrop({
        points: original.points.map((p) => ({ x: p.x + dx, y: p.y + dy })),
      });
    }
  };
  const valid = validCrop(crop);
  // Keep the viewBox proportional to the photograph, so handles remain round.
  const width = 1000,
    height = preview ? (1000 * preview.height) / preview.width : 1000;
  const points = crop.points
    .map((p) => `${p.x * width},${p.y * height}`)
    .join(" ");
  return (
    <Modal
      title="裁剪小卡图片"
      open
      width={960}
      onCancel={onCancel}
      closable={!busy}
      maskClosable={false}
      keyboard={!busy}
      footer={
        <Space>
          <Button disabled={busy} onClick={onCancel}>
            取消
          </Button>
          <Button
            type="primary"
            disabled={!preview || !valid}
            loading={busy}
            onClick={() => onConfirm(crop)}
          >
            {confirmLabel}
          </Button>
        </Space>
      }
    >
      {error ? (
        <Alert
          type="error"
          showIcon
          message={error}
          action={
            <Button
              onClick={() => {
                setError("");
                setAttempt((n) => n + 1);
              }}
            >
              重试
            </Button>
          }
        />
      ) : !preview ? (
        <div className="card-crop-loading">
          <Spin />
          <p>正在检测小卡边缘…</p>
        </div>
      ) : (
        <>
          <Alert
            type={preview.regions.length ? "info" : "warning"}
            showIcon
            message={
              preview.regions.length > 1
                ? `检测到 ${preview.regions.length} 张小卡，请选择本次保留的一张。`
                : preview.regions.length
                  ? "已自动框选小卡，请确认完整保留卡片边缘。"
                  : "未检测到清晰边缘，已保留整张图片，请手动调整。"
            }
            description="拖动四个角贴合小卡边缘，也可拖动框内移动范围。确认后会裁去背景并校正透视。"
          />
          <div className="card-crop-layout">
            <div className="card-crop-stage">
              <svg
                ref={surface}
                className="card-crop-surface"
                viewBox={`0 0 ${width} ${height}`}
                style={{
                  aspectRatio: `${preview.width} / ${preview.height}`,
                  maxWidth: `${(520 * preview.width) / preview.height}px`,
                }}
                aria-label="小卡裁剪范围"
                onPointerMove={move}
                onPointerUp={() => {
                  drag.current = undefined;
                }}
                onPointerCancel={() => {
                  drag.current = undefined;
                }}
              >
                <image
                  href={preview.preview_url}
                  width={width}
                  height={height}
                  preserveAspectRatio="none"
                />
                <path
                  d={`M0,0 H${width} V${height} H0 Z M${crop.points.map((p) => `${p.x * width},${p.y * height}`).join(" L")} Z`}
                  fill="rgba(15,23,42,.64)"
                  fillRule="evenodd"
                  pointerEvents="none"
                />
                <polygon
                  points={points}
                  fill="transparent"
                  stroke={valid ? "#ad8cff" : "#ff7875"}
                  strokeWidth={3}
                  vectorEffect="non-scaling-stroke"
                  onPointerDown={(e) => start(e, -1)}
                  style={{ cursor: "move" }}
                />
                {crop.points.map((p, i) => (
                  <circle
                    key={i}
                    cx={p.x * width}
                    cy={p.y * height}
                    r={Math.max(width, height) * 0.018}
                    fill="#fff"
                    stroke="#8762da"
                    strokeWidth={3}
                    vectorEffect="non-scaling-stroke"
                    role="button"
                    tabIndex={busy ? -1 : 0}
                    aria-label={`调整${labels[i]}角`}
                    style={{ cursor: "grab" }}
                    onPointerDown={(e) => start(e, i)}
                    onKeyDown={(e) => {
                      if (!e.key.startsWith("Arrow")) return;
                      e.preventDefault();
                      const amount = e.shiftKey ? 0.01 : 0.001;
                      update(i, {
                        x: clamp(
                          p.x +
                            (e.key === "ArrowLeft"
                              ? -amount
                              : e.key === "ArrowRight"
                                ? amount
                                : 0),
                        ),
                        y: clamp(
                          p.y +
                            (e.key === "ArrowUp"
                              ? -amount
                              : e.key === "ArrowDown"
                                ? amount
                                : 0),
                        ),
                      });
                    }}
                  />
                ))}
              </svg>
            </div>
            <div className="card-crop-controls">
              <b>裁剪范围</b>
              {preview.regions.length > 1 && (
                <Select
                  aria-label="选择检测到的小卡"
                  value={region}
                  disabled={busy}
                  options={preview.regions.map((_, i) => ({
                    value: i,
                    label: `小卡 ${i + 1}`,
                  }))}
                  onChange={(i) => {
                    setRegion(i);
                    setCrop(preview.regions[i]);
                  }}
                />
              )}
              <Space wrap>
                <Button
                  disabled={busy || !preview.regions.length}
                  onClick={() => setCrop(preview.regions[region])}
                >
                  恢复自动框选
                </Button>
                <Button disabled={busy} onClick={() => setCrop(fullImage)}>
                  保留整张图片
                </Button>
              </Space>
              <p className="subtle-note">
                位置为图片宽高的百分比。选中圆点后也可用方向键微调。
              </p>
              {crop.points.map((p, i) => (
                <div className="card-crop-coordinate" key={i}>
                  <span>{labels[i]}角</span>
                  {(["x", "y"] as const).map((axis) => (
                    <label key={axis}>
                      {axis === "x" ? "横向 %" : "纵向 %"}
                      <InputNumber
                        aria-label={`${labels[i]}角${axis === "x" ? "横向" : "纵向"}百分比`}
                        min={0}
                        max={100}
                        step={0.1}
                        precision={2}
                        value={p[axis] * 100}
                        disabled={busy}
                        onChange={(n) =>
                          n !== null && update(i, { [axis]: clamp(n / 100) })
                        }
                      />
                    </label>
                  ))}
                </div>
              ))}
              {!valid && (
                <Alert
                  type="error"
                  message="四角不能交叉或重合，请调整裁剪范围。"
                />
              )}
              <small>确认前可以取消，本次照片不会写入图鉴。</small>
            </div>
          </div>
        </>
      )}
    </Modal>
  );
}

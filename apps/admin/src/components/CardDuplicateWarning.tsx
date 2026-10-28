import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, App, Button, Space, Spin } from "antd";
import type { Card } from "../api/types";
import { consoleApi, send } from "../api/client";
import { CardArt, StatusTag } from "./shared";
import "./card-duplicate-warning.css";

export type Similarity = {
  candidates: { score: number; card: Card }[];
  indexed_count: number;
  unavailable_count: number;
};
type Check = {
  key: string;
  result?: Similarity;
  error?: string;
  loading?: boolean;
};
async function requestCheck(
  imageUrl: string,
  excludeId?: string,
): Promise<Check> {
  const key = `${imageUrl}\n${excludeId || ""}`;
  try {
    const result = await consoleApi<Similarity>(
      "/cards/similar",
      send({ image_url: imageUrl, exclude_card_id: excludeId }),
    );
    if (!Array.isArray(result.candidates))
      throw new Error("检查结果暂不可用，请重试");
    return { key, result };
  } catch (error) {
    return { key, error: (error as Error).message || "相似小卡检查失败" };
  }
}
function confirmCheck(
  modal: ReturnType<typeof App.useApp>["modal"],
  current: Check,
  stillCurrent: () => boolean,
  subject?: string,
): Promise<boolean> {
  if (!stillCurrent()) return Promise.resolve(false);
  const count = current.result?.candidates.length || 0;
  const incomplete = current.result?.unavailable_count || 0;
  if (!current.error && !count && !incomplete) return Promise.resolve(true);
  return new Promise<boolean>((resolve) => {
    modal.confirm({
      title: count
        ? `发现 ${count} 张相似小卡，请先核对`
        : "相似小卡检查未完整完成",
      content: (
        <Space direction="vertical">
          {subject && <strong>待发布：{subject}</strong>}
          <span>
            {current.error ||
              (count
                ? "相似度仅作核对参考。同一艺人、不同版本也可能相似，请确认不是重复图鉴。"
                : `有 ${incomplete} 张现有记录缺少可用图片，无法完成比对。`)}
          </span>
          <CandidateList result={current.result} />
          <span>
            如已存在，请取消新增并查看已有记录；确认属于新卡后可继续。
          </span>
        </Space>
      ),
      width: 640,
      okText: "已核对，继续",
      cancelText: "返回核对",
      onOk: () => {
        resolve(stillCurrent());
      },
      onCancel: () => {
        resolve(false);
      },
    });
  });
}
export function useCardsDuplicateApproval() {
  const { modal } = App.useApp();
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  return async (cards: Card[]) => {
    for (const card of cards) {
      if (!mounted.current) return false;
      if (!card.image_url) continue; // Publication validates the required image.
      const current = await requestCheck(card.image_url, card.id);
      if (
        !(await confirmCheck(modal, current, () => mounted.current, card.title))
      )
        return false;
    }
    return mounted.current;
  };
}
export function useCardDuplicateCheck(
  imageUrl?: string,
  excludeId?: string,
  enabled = true,
) {
  const { modal } = App.useApp();
  const key = enabled && imageUrl ? `${imageUrl}\n${excludeId || ""}` : "";
  const [state, setState] = useState<Check>({ key: "" });
  const pending = useRef<{ key: string; promise: Promise<Check> } | undefined>(
    undefined,
  );
  const cache = useRef<Check | undefined>(undefined);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  const activeKey = useRef(key);
  activeKey.current = key;
  const check = useCallback(
    async (force = false): Promise<Check> => {
      if (!key) return { key };
      if (pending.current?.key === key) return pending.current.promise;
      if (!force && cache.current?.key === key) return cache.current;
      setState({ key, loading: true });
      const promise = requestCheck(imageUrl!, excludeId).then((outcome) => {
        if (activeKey.current === key) {
          cache.current = outcome;
          setState(outcome);
        }
        if (pending.current?.key === key) pending.current = undefined;
        return outcome;
      });
      pending.current = { key, promise };
      return promise;
    },
    [key, imageUrl, excludeId],
  );
  useEffect(() => {
    if (key) void check();
  }, [key, check]);
  const confirm = async (): Promise<boolean> => {
    // Refresh before writing: another operator may have added a card since upload.
    const current = await check(true);
    if (activeKey.current !== current.key) return false;
    return confirmCheck(
      modal,
      current,
      () => mounted.current && activeKey.current === current.key,
    );
  };
  return {
    state: key
      ? state.key === key
        ? state
        : { key, loading: true }
      : undefined,
    retry: () => check(true),
    confirm,
  };
}
function CandidateList({ result }: { result?: Similarity }) {
  if (!result?.candidates.length) return null;
  return (
    <div className="card-duplicate-candidates">
      {result.candidates.map(({ card, score }) => (
        <a
          key={card.id}
          href={`/catalog/cards/${card.id}/detail`}
          target="_blank"
          rel="noreferrer"
          className="card-duplicate-candidate"
          title={`查看 ${card.title} 详情`}
        >
          <CardArt card={card} small />
          <strong>{Math.round(score * 100)}% 相似</strong>
          <span title={card.title}>{card.title || "未命名小卡"}</span>
          <StatusTag status={card.status} />
        </a>
      ))}
    </div>
  );
}
export default function CardDuplicateWarning({
  check,
}: {
  check: ReturnType<typeof useCardDuplicateCheck>;
}) {
  const { state } = check;
  if (!state) return null;
  if (state.loading)
    return (
      <Alert
        className="card-duplicate-warning"
        type="info"
        message={
          <Space>
            <Spin size="small" />
            正在检查相似小卡…
          </Space>
        }
      />
    );
  const count = state.result?.candidates.length || 0;
  const unavailable = state.result?.unavailable_count || 0;
  return (
    <Alert
      className="card-duplicate-warning"
      showIcon
      type={state.error || count || unavailable ? "warning" : "success"}
      message={
        state.error
          ? "暂未完成相似小卡检查"
          : count
            ? `发现 ${count} 张相似小卡，新增前请核对`
            : unavailable
              ? "部分现有图片无法比对，请人工核对"
              : "当前未发现相似小卡"
      }
      description={
        <>
          <p>
            {state.error ||
              `已比对 ${state.result?.indexed_count || 0} 张图鉴${unavailable ? `；${unavailable} 张缺少可用图片，无法比对` : ""}。相似度仅供核对，不代表同一张小卡。`}
          </p>
          <CandidateList result={state.result} />
        </>
      }
      action={
        <Button size="small" onClick={() => void check.retry()}>
          重新检查
        </Button>
      }
    />
  );
}

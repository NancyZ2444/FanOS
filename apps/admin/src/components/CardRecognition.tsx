import { Modal, Table } from "./admin";
import { useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Alert, App, Button, Image, Space } from "antd";
import { ScanOutlined } from "@ant-design/icons";
import { consoleApi } from "../api/client";
import type { Card } from "../api/types";
import { CardArt, StatusTag } from "./shared";
import CardImageCrop from "./CardImageCrop";
import type { CardCrop } from "./CardImageCrop";

type Recognition = {
  status: "matched" | "candidates" | "incomplete" | "unrecognized";
  image_url: string;
  indexed_count: number;
  unavailable_count: number;
  candidates: { score: number; card: Card }[];
};
export default function CardRecognition() {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [file, setFile] = useState<File>();
  const [result, setResult] = useState<Recognition>();
  const navigate = useNavigate();
  const { message } = App.useApp();
  const create = (data: Recognition) => {
    setResult(undefined);
    navigate(
      `/catalog/cards/new?image_url=${encodeURIComponent(data.image_url)}`,
      {
        state: {
          scanNotice:
            "已带入上传的小卡正面，请选择组合、艺人和来源，补充信息后保存草稿。",
          scanCoverageNotice: data.unavailable_count
            ? `暂未匹配到记录；另有 ${data.unavailable_count} 张现有小卡缺少可用卡图，保存前请核对，避免重复新增。`
            : "",
        },
      },
    );
  };
  const maintain = (card: Card) => {
    setResult(undefined);
    navigate(`/catalog/cards/${card.id}`, {
      state: {
        scanNotice: `已识别到「${card.title}」，请核对并维护资料。已发布或审核中的记录按原流程下架或驳回后编辑。`,
      },
    });
  };
  const choose = (selected?: File) => {
    if (input.current) input.current.value = "";
    if (!selected || busy) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(selected.type)) {
      message.error("请选择 JPG、PNG 或 WebP 图片");
      return;
    }
    if (selected.size > 10 * 1024 * 1024) {
      message.error("图片不能超过 10 MB");
      return;
    }
    setFile(selected);
  };
  const recognize = async (crop: CardCrop) => {
    if (!file || busy) return;
    if (file.size > 10 * 1024 * 1024) {
      message.error("图片不能超过 10 MB");
      return;
    }
    setBusy(true);
    try {
      const form = new FormData();
      form.append("file", file);
      form.append("crop", JSON.stringify(crop));
      const data = await consoleApi<Recognition>("/cards/recognize", {
        method: "POST",
        body: form,
      });
      setFile(undefined);
      if (data.status === "matched") maintain(data.candidates[0].card);
      else if (data.status === "unrecognized" || data.status === "incomplete")
        create(data);
      else setResult(data);
    } catch (e) {
      message.error((e as Error).message);
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  };
  return (
    <>
      <input
        ref={input}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        hidden
        aria-label="上传小卡识别图片"
        disabled={busy || !!file}
        onChange={(e) => choose(e.target.files?.[0])}
      />
      <Button
        icon={<ScanOutlined />}
        loading={busy}
        disabled={!!file}
        onClick={() => input.current?.click()}
      >
        {busy ? "正在识别小卡…" : "上传识别"}
      </Button>
      {file && (
        <CardImageCrop
          file={file}
          mode="recognition"
          busy={busy}
          confirmLabel="确认裁剪并识别"
          onCancel={() => setFile(undefined)}
          onConfirm={recognize}
        />
      )}
      <Modal
        title="小卡识别结果"
        open={!!result}
        onCancel={() => setResult(undefined)}
        width={760}
        footer={
          <Space>
            <Button onClick={() => setResult(undefined)}>返回列表</Button>
            <Button onClick={() => result && create(result)}>
              未找到，手动新增
            </Button>
          </Space>
        }
      >
        {result && (
          <>
            <Image width={100} src={result.image_url} alt="本次上传的小卡" />
            <Alert
              style={{ marginBlock: 16 }}
              type="info"
              message={
                result.status === "incomplete"
                  ? "暂未匹配到记录，请先核对现有小卡，或手动新增。"
                  : "找到相似记录，请选择需要维护的小卡。"
              }
              description={`已比对 ${result.indexed_count} 张小卡${result.unavailable_count ? `；另有 ${result.unavailable_count} 张缺少可用卡图，无法参与比对。` : "。"}`}
            />
            <Table
              rowKey={(r) => r.card.id}
              dataSource={result.candidates}
              pagination={false}
              columns={[
                {
                  title: "卡图",
                  render: (_, r) => <CardArt card={r.card} small />,
                },
                {
                  title: "小卡",
                  render: (_, r) => (
                    <>
                      <b>{r.card.title}</b>
                      <div>
                        {r.card.group_name} · {r.card.idol_name}
                      </div>
                      <small>{r.card.id}</small>
                    </>
                  ),
                },
                {
                  title: "相似度",
                  render: (_, r) => `${Math.round(r.score * 100)}%`,
                },
                {
                  title: "状态",
                  render: (_, r) => <StatusTag status={r.card.status} />,
                },
                {
                  title: "操作",
                  render: (_, r) => (
                    <Button onClick={() => maintain(r.card)}>维护记录</Button>
                  ),
                },
              ]}
            />
          </>
        )}
      </Modal>
    </>
  );
}

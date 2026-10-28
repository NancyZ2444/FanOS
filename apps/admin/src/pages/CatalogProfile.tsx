import { useEffect, useRef, useState } from "react";
import { Alert, App, Button, Collapse, Input, Modal, Spin, Tabs } from "antd";
import { consoleApi } from "../api/client";
import { canPermission } from "../api/permissions";
import { useConsole } from "../state";
import { Form, useFormGuard } from "../components/admin";
import { ImageUpload } from "../components/shared";
import { formatTime } from "../design/format";
import "./catalog-editorial.css";
import { ValueEditor, ValueView } from "./feedback/FeedbackValues";
import type { Field, Values } from "./feedback/types";

const sections: Record<string, string> = {
  intro: "简介",
  basic: "基本资料",
  career: "从艺历程",
  honors: "荣誉记录",
};
export default function CatalogProfile({
  kind,
  entityId,
}: {
  kind: string;
  entityId: string;
}) {
  const { actor, reload } = useConsole();
  const canEdit = canPermission(actor, "catalog.edit");
  const canPublish = canPermission(actor, "catalog.publish");
  const canModify = canEdit || canPublish;
  const { message } = App.useApp();
  const [data, setData] = useState<Values>();
  const [changes, setChanges] = useState<Values>({});
  const [summary, setSummary] = useState("");
  const [section, setSection] = useState("intro");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const guard = useFormGuard(true, busy);
  const [preview, setPreview] = useState(false);
  const [validation, setValidation] = useState("");
  const [history, setHistory] = useState<Values[]>([]);
  const [next, setNext] = useState<number | null>(0);
  const [version, setVersion] = useState<Values>();
  const request = useRef<{ signature: string; key: string } | undefined>(
    undefined,
  );
  useEffect(() => {
    if (!data) return;
    if (
      JSON.stringify(changes) !== JSON.stringify(data.draft?.values || {}) ||
      summary !== (data.draft?.summary || "")
    )
      guard.mark();
    else guard.reset();
  }, [data, changes, summary]);
  const path = `/profiles/${kind}/${entityId}`;
  const load = async () => {
    setBusy(true);
    setError("");
    try {
      const value = await consoleApi(path);
      setData(value);
      setChanges(value.draft?.values || {});
      setSummary(value.draft?.summary || "");
      setValidation("");
      guard.reset();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, [kind, entityId]);
  const submit = async (publish: boolean) => {
    if (!data || busy || !(publish ? canPublish : canEdit)) return;
    if (!Object.keys(changes).length) {
      setValidation("请修改至少一个资料字段");
      return;
    }
    const payload = {
      values: changes,
      summary,
      expected: data.version,
      draft_version: data.draft_version,
    };
    const signature = JSON.stringify(payload);
    if (request.current?.signature !== signature)
      request.current = { signature, key: crypto.randomUUID() };
    setBusy(true);
    setError("");
    setValidation("");
    try {
      const response = await consoleApi(
        path + (publish ? "/publish" : "/draft"),
        {
          method: publish ? "POST" : "PUT",
          body: JSON.stringify({
            ...payload,
            request_key: request.current.key,
          }),
        },
      );
      if (publish) {
        setPreview(false);
        setHistory([]);
        setNext(0);
        await reload();
        await load();
      } else setData(response);
      message.success(
        publish
          ? "正式资料已发布，修订历史已记录"
          : "处理草稿已保存，公开资料未改变",
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const loadHistory = async () => {
    setBusy(true);
    try {
      const r = await consoleApi(`${path}/history?offset=${next ?? 0}`);
      setHistory((v) => [...v, ...r.items]);
      setNext(r.next_offset);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  if (!data)
    return (
      <section className="panel">
        {busy ? (
          <Spin />
        ) : (
          <Alert
            type="error"
            message={error}
            action={<Button onClick={load}>重试</Button>}
          />
        )}
      </section>
    );
  return (
    <section className="panel editorial-panel">
      <div className="editorial-heading">
        <div>
          <h2>公开资料</h2>
          <p className="subtle-note">
            草稿仅后台可见，发布后同步 App。当前版本 V{data.profile_revision}
          </p>
        </div>
        <span className="editorial-change-count">
          已修改 {Object.keys(changes).length} 项
        </span>
      </div>
      {error && (
        <Alert
          type="error"
          showIcon
          message={error}
          description="填写内容已保留，可修正后重试。"
          action={
            <Button onClick={() => guard.close(() => void load())}>
              重新载入
            </Button>
          }
        />
      )}
      <Tabs
        activeKey={section}
        onChange={setSection}
        items={Object.entries(sections).map(([key, label]) => ({ key, label }))}
      />
      <Form className="editorial-form" disabled={busy || !canModify}>
        <div className="form-grid">
          {(data.fields as Field[])
            .filter((f) => f.section === section)
            .map((f) => {
              const modified = f.key in changes;
              const value = modified
                ? changes[f.key]
                : f.type === "relations"
                  ? []
                  : f.current;
              const update = (nextValue: any) => {
                setValidation("");
                setChanges((previous) => {
                  const next = { ...previous };
                  if (
                    JSON.stringify(nextValue ?? "") ===
                      JSON.stringify(f.current ?? "") ||
                    (f.type === "relations" && !nextValue?.length)
                  )
                    delete next[f.key];
                  else next[f.key] = nextValue;
                  return next;
                });
              };
              return (
                <Form.Item
                  key={f.key}
                  className={
                    ["long_text", "relations", "list"].includes(f.type)
                      ? "editorial-full-width"
                      : undefined
                  }
                  label={
                    <span className="editorial-field-label">
                      {f.label}
                      {modified && (
                        <span className="editorial-modified">已修改</span>
                      )}
                    </span>
                  }
                  htmlFor={`profile-${f.key}`}
                  required={f.key === "name"}
                >
                  {f.type === "image" ? (
                    <div className="editorial-image-field">
                      <ImageUpload
                        value={value || undefined}
                        onChange={update}
                        label={f.label}
                        disabled={busy || !canModify}
                      />
                      {!!value && (
                        <Button
                          disabled={busy || !canModify}
                          onClick={() => update("")}
                        >
                          移除图片
                        </Button>
                      )}
                    </div>
                  ) : ["text", "url", "date"].includes(f.type) ? (
                    <Input
                      id={`profile-${f.key}`}
                      aria-label={f.label}
                      type={f.type === "date" ? "date" : "text"}
                      value={value ?? ""}
                      maxLength={f.max_length ?? 2000}
                      placeholder={
                        f.type === "url" ? "https://" : `请输入${f.label}`
                      }
                      onChange={(e) => update(e.target.value)}
                    />
                  ) : ["long_text", "list"].includes(f.type) ? (
                    <Input.TextArea
                      id={`profile-${f.key}`}
                      aria-label={f.label}
                      value={
                        Array.isArray(value) ? value.join("\n") : (value ?? "")
                      }
                      autoSize={{ minRows: 4, maxRows: 18 }}
                      maxLength={f.max_length ?? 2000}
                      showCount
                      placeholder={
                        f.type === "list" ? "每行一项" : `请输入${f.label}`
                      }
                      onChange={(e) =>
                        update(
                          f.type === "list"
                            ? e.target.value.split("\n").filter(Boolean)
                            : e.target.value,
                        )
                      }
                    />
                  ) : (
                    <>
                      {f.type === "relations" && !!f.current?.length && (
                        <details className="optional-fields">
                          <summary>
                            查看已有{f.label}（{f.current.length}）
                          </summary>
                          <ValueView field={f} value={f.current} />
                        </details>
                      )}
                      <ValueEditor
                        field={f}
                        id={`profile-${f.key}`}
                        value={value}
                        onChange={update}
                        disabled={busy || !canModify}
                      />
                    </>
                  )}
                </Form.Item>
              );
            })}
        </div>
        <Form.Item
          label="内部备注（选填）"
          htmlFor="profile-summary"
          validateStatus={validation ? "error" : undefined}
          help={validation || "仅后台存档，不展示给用户。"}
        >
          <Input.TextArea
            id="profile-summary"
            value={summary}
            onChange={(e) => {
              setSummary(e.target.value);
              setValidation("");
            }}
            rows={2}
            maxLength={2000}
            showCount
            placeholder="可补充本次维护说明，仅后台可见"
          />
        </Form.Item>
      </Form>
      <footer className="form-actions">
        <Button disabled={busy} onClick={() => guard.close(() => void load())}>
          取消
        </Button>
        <Button
          disabled={busy || !canEdit}
          onClick={() => void submit(false)}
          loading={busy}
        >
          保存草稿
        </Button>
        <Button
          type="primary"
          disabled={!canPublish || busy}
          onClick={() => {
            if (!Object.keys(changes).length) {
              setValidation("请修改至少一个资料字段");
              return;
            }
            setPreview(true);
          }}
        >
          预览并发布
        </Button>
      </footer>
      <Collapse
        className="editorial-history"
        items={[
          {
            key: "history",
            label: "资料修订存档",
            children: (
              <>
                {history.map((v) => (
                  <p key={v.id}>
                    <Button
                      type="link"
                      onClick={async () => {
                        try {
                          setVersion(
                            await consoleApi(`${path}/history/${v.id}`),
                          );
                        } catch (e) {
                          setError((e as Error).message);
                        }
                      }}
                    >
                      V{v.version} · {v.summary || "内部资料更新"}
                    </Button>
                    {v.visibility === "PUBLIC" ? "用户反馈 · 公开" : "内部存档"}{" "}
                    · {v.author.name} · {formatTime(v.published_at)}
                  </p>
                ))}
                {next !== null && (
                  <Button loading={busy} onClick={loadHistory}>
                    加载修订记录
                  </Button>
                )}
              </>
            ),
          },
        ]}
      />
      <Modal
        title="确认资料发布"
        open={preview}
        onCancel={() => setPreview(false)}
        onOk={() => void submit(true)}
        confirmLoading={busy}
        okText="确认发布"
        width={900}
      >
        {summary && <p>内部备注：{summary}</p>}
        {(data.fields as Field[])
          .filter((f) => f.key in changes)
          .map((f) => (
            <section key={f.key}>
              <h3>{f.label}</h3>
              <div className="editorial-comparison">
                <div>
                  <p className="subtle-note">当前公开资料</p>
                  <ValueView field={f} value={f.current} />
                </div>
                <div>
                  <p className="subtle-note">本次发布内容</p>
                  <ValueView field={f} value={changes[f.key]} />
                </div>
              </div>
            </section>
          ))}
      </Modal>
      <Modal
        title={`修订记录 V${version?.version ?? ""}`}
        open={!!version}
        onCancel={() => setVersion(undefined)}
        footer={null}
        width={1000}
      >
        <p>
          {version?.author?.name} · {formatTime(version?.published_at)}
        </p>
        {version?.changes?.map((c: Values) => (
          <section key={c.key}>
            <h3>{c.label}</h3>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                gap: 24,
              }}
            >
              <div>
                <p>修改前</p>
                <ValueView field={c as Field} value={c.before} />
              </div>
              <div>
                <p>修改后</p>
                <ValueView field={c as Field} value={c.after} />
              </div>
            </div>
          </section>
        ))}
      </Modal>
    </section>
  );
}

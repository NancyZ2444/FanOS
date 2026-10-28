import { useEffect, useState } from "react";
import { App, Button, Input, Select, Skeleton, Switch, Tag } from "antd";
import { Form, PageHeader, useFormGuard } from "../../components/admin";
import { send } from "../../api/client";
import { authApi, LoadError, useAuthMeta } from "./shared";
import "../catalog-editorial.css";

export default function SupportEntry() {
  const [form] = Form.useForm();
  const [config, setConfig] = useState<any>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const { can, error: metaError, retry: retryMeta } = useAuthMeta();
  const { message } = App.useApp();
  const guard = useFormGuard(!!config, busy);
  const values = Form.useWatch([], form) || config || {};
  const type = values.type;
  const reset = (value = config) => {
    form.resetFields();
    form.setFieldsValue({ ...value, reason: "" });
    guard.reset();
  };
  const load = () => {
    setError("");
    authApi("/support-entry")
      .then((d) => {
        setConfig(d);
        reset(d);
      })
      .catch((e) => setError(e.message));
  };
  useEffect(load, []);
  const save = async () => {
    if (busy || !config || !can("auth.support.manage")) return;
    try {
      const v = await form.validateFields();
      setBusy(true);
      setError("");
      const result = await authApi(
        "/support-entry",
        send(
          {
            ...v,
            url: v.type === "external" ? v.url : null,
            expected_version: config.version,
          },
          "PATCH",
        ),
      );
      setConfig(result);
      reset(result);
      message.success("客服入口已保存");
    } catch (e) {
      if (e instanceof Error) setError(e.message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <PageHeader
        title="App 登录客服入口"
        description="配置用户在登录页与账号受限时可查看的帮助信息。"
      />
      <LoadError error={metaError} retry={retryMeta} />
      <LoadError error={error} retry={() => guard.close(load)} />
      {!config && !error ? (
        <section className="panel editorial-panel">
          <Skeleton active />
        </section>
      ) : (
        <div className="settings-workspace">
          <section className="panel editorial-panel">
            <Form
              form={form}
              onValuesChange={guard.mark}
              disabled={!can("auth.support.manage") || !config || busy}
            >
              <section className="detail-section">
                <h2>入口设置</h2>
                <Form.Item
                  name="enabled"
                  label="开启客服入口"
                  valuePropName="checked"
                  extra="关闭后，App 不展示该入口；已填写内容会保留。"
                >
                  <Switch checkedChildren="开启" unCheckedChildren="关闭" />
                </Form.Item>
                <div className="form-grid">
                  <Form.Item
                    name="type"
                    label="入口类型"
                    rules={[{ required: true, message: "请选择入口类型" }]}
                  >
                    <Select
                      options={[
                        { value: "help_page", label: "公开帮助页" },
                        { value: "external", label: "外部链接" },
                      ]}
                    />
                  </Form.Item>
                  <Form.Item
                    name="display_name"
                    label="展示名称"
                    rules={[
                      {
                        required: true,
                        whitespace: true,
                        message: "请输入展示名称",
                      },
                    ]}
                  >
                    <Input maxLength={40} placeholder="例如：登录帮助" />
                  </Form.Item>
                </div>
                {type === "external" && (
                  <Form.Item
                    name="url"
                    label="外部链接"
                    extra="使用已配置可访问域名的 HTTPS 链接。"
                    rules={[
                      { required: true, message: "请输入外部链接" },
                      { type: "url", message: "请输入有效链接" },
                      {
                        validator: (_, v) =>
                          !v || /^https:\/\//.test(v)
                            ? Promise.resolve()
                            : Promise.reject(new Error("仅允许 HTTPS 链接")),
                      },
                    ]}
                  >
                    <Input placeholder="https://" />
                  </Form.Item>
                )}
              </section>
              <section className="detail-section">
                <h2>公开帮助信息</h2>
                <Form.Item
                  name="contact"
                  label="公开联系渠道"
                  rules={[
                    {
                      required: true,
                      whitespace: true,
                      message: "请输入公开联系渠道",
                    },
                  ]}
                >
                  <Input.TextArea
                    rows={3}
                    maxLength={500}
                    showCount
                    placeholder="例如：客服邮箱、工作时间"
                  />
                </Form.Item>
                <Form.Item
                  name="backup"
                  label="备用联系说明"
                  rules={[
                    {
                      required: true,
                      whitespace: true,
                      message: "请输入备用联系说明",
                    },
                  ]}
                >
                  <Input.TextArea
                    rows={2}
                    maxLength={500}
                    showCount
                    placeholder="主要渠道暂不可用时的帮助说明"
                  />
                </Form.Item>
                <p className="subtle-note">
                  以上内容对用户公开，请勿填写账号凭证或内部处理信息。账号申诉结果由审核处理。
                </p>
              </section>
              <Form.Item
                name="reason"
                label="修改原因"
                extra="仅记录在后台操作日志中。"
                rules={[
                  {
                    required: true,
                    whitespace: true,
                    message: "请填写修改原因",
                  },
                ]}
              >
                <Input.TextArea
                  rows={2}
                  maxLength={300}
                  showCount
                  placeholder="说明本次设置调整"
                />
              </Form.Item>
              <footer className="form-actions">
                <Button
                  onClick={() => guard.close(() => reset())}
                  disabled={busy || !config}
                >
                  取消
                </Button>
                <Button
                  type="primary"
                  loading={busy}
                  onClick={() => void save()}
                >
                  保存
                </Button>
              </footer>
            </Form>
          </section>
          <aside className="panel settings-preview" aria-label="客服入口预览">
            <div className="editorial-heading">
              <h2>App 展示预览</h2>
              <Tag color={values.enabled ? "success" : "default"}>
                {values.enabled ? "开启" : "关闭"}
              </Tag>
            </div>
            <p className="subtle-note">预览当前填写内容，保存后生效。</p>
            <div className="settings-preview-content">
              <h3>{values.display_name || "登录帮助"}</h3>
              <p>{values.contact || "公开联系渠道"}</p>
              <p className="subtle-note">{values.backup || "备用联系说明"}</p>
              {type === "external" && (
                <div className="settings-preview-link">
                  {values.url || "尚未填写链接"}
                </div>
              )}
            </div>
            {!values.enabled && (
              <p className="subtle-note">当前关闭，用户不会看到此入口。</p>
            )}
          </aside>
        </div>
      )}
    </>
  );
}

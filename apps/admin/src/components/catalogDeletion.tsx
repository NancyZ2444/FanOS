import { Button } from "antd";
import { consoleApi, send } from "../api/client";

export async function confirmCatalogDeletion(
  kind: string,
  id: string,
  name: string,
  modal: any,
  message: any,
  reload: () => Promise<void>,
) {
  try {
    const check = await consoleApi(`/deletion-check/${kind}/${id}`);
    if (!check.allowed) {
      modal.warning({
        title: `无法删除「${name}」`,
        content: (
          <div>
            <p>
              {check.blockers
                .map((b: any) => `${b.label} ${b.count} 条`)
                .join("；") || "当前状态不允许删除"}
            </p>
            {!["groups", "idols"].includes(kind) &&
              ["OFFLINE", "ARCHIVED"].includes(check.status) && (
                <Button
                  danger
                  onClick={() =>
                    modal.confirm({
                      title: "解除上游归属以准备删除？",
                      content:
                        "仅当没有下游业务引用时执行。发行时归属会保存在审计中，记录保持下架 / 归档；解除后不能直接重新发布。",
                      okButtonProps: { danger: true },
                      onOk: async () => {
                        try {
                          await consoleApi(`/detach/${kind}/${id}`, send({}));
                          await reload();
                          message.success("已解除归属，请重新执行删除检查");
                        } catch (e) {
                          message.error((e as Error).message);
                        }
                      },
                    })
                  }
                >
                  检查并解除上游归属
                </Button>
              )}
          </div>
        ),
        okText: "关闭",
      });
      return;
    }
    modal.confirm({
      title: `永久删除「${name}」？`,
      content: check.ever_published
        ? "已核实全部上下游关联解除。删除不可恢复，保留操作审计。"
        : "该记录未上架，删除草稿不可恢复；已有下游引用会阻止删除。",
      okText: "永久删除",
      cancelText: "取消",
      okButtonProps: { danger: true },
      onOk: async () => {
        try {
          await consoleApi(
            kind === "cards" ? `/cards/${id}` : `/entities/${kind}/${id}`,
            { method: "DELETE" },
          );
          await reload();
          message.success("已永久删除");
        } catch (e) {
          message.error((e as Error).message);
        }
      },
    });
  } catch (e) {
    message.error((e as Error).message);
  }
}

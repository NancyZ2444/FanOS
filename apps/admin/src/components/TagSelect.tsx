import { useEffect, useState } from "react";
import { App, Select } from "antd";
import { consoleApi } from "../api/client";

export type TagType = "ALBUM" | "EVENT" | "OTHER" | "CARD";
export type CatalogTag = {
  id: string;
  name: string;
  entity_type: TagType;
  status: "ACTIVE" | "DISABLED";
  source: "INTERNAL" | "USER_SUBMITTED";
  usage_count: number;
  created_at: string;
};
export default function TagSelect({
  entityType,
  value = [],
  onChange,
  disabled,
}: {
  entityType: TagType;
  value?: string[];
  onChange?: (values: string[]) => void;
  disabled?: boolean;
}) {
  const [items, setItems] = useState<CatalogTag[]>([]);
  const { message } = App.useApp();
  const load = () =>
    consoleApi<{ items: CatalogTag[] }>(`/tags?entity_type=${entityType}`)
      .then((r) => setItems(r.items))
      .catch((e) => message.error(e.message));
  useEffect(() => {
    load();
  }, [entityType]);
  return (
    <Select
      mode="tags"
      showSearch
      value={value}
      disabled={disabled}
      onOpenChange={(open) => open && load()}
      tokenSeparators={[",", "，"]}
      placeholder="搜索并多选标签，不存在时输入后回车"
      maxCount={30}
      options={items
        .filter((t) => t.status === "ACTIVE" || value.includes(t.name))
        .map((t) => ({
          value: t.name,
          label:
            t.name + (t.status === "DISABLED" ? "（已停用，历史关联）" : ""),
          disabled: t.status === "DISABLED",
        }))}
      onChange={(values) =>
        onChange?.([
          ...new Map(
            values.map((v: string) => {
              const name = v.normalize("NFKC").trim().replace(/\s+/g, " ");
              return [name.toLocaleLowerCase(), name];
            }),
          ).values(),
        ] as string[])
      }
    />
  );
}

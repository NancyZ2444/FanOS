import { useEffect, useState } from "react";
import { Alert, Button } from "antd";
import { useParams } from "react-router-dom";
import { canPermission } from "../../api/permissions";
import { consoleApi } from "../../api/client";
import { PageHeader } from "../../components/admin";
import { useConsole } from "../../state";
import ResourceManager from "./ResourceManager";
import type { Resource } from "./types";
import "./digital-albums.css";

export const materialScenes = {
  SHELF: "书架主题",
  ALBUM_COVER: "相册封面",
  ALBUM_PAGE: "相册内页",
  CARD_BACKGROUND: "卡片背景",
};
export default function MaterialScene() {
  const { scene = "" } = useParams();
  const { actor } = useConsole();
  const [items, setItems] = useState<Resource[]>([]);
  const [error, setError] = useState("");
  const refresh = async () => {
    try {
      const result = await consoleApi<{ items: Resource[] }>(
        `/album-materials/${scene}`,
      );
      setItems(result.items);
      setError("");
    } catch (e) {
      setError((e as Error).message);
    }
  };
  useEffect(() => {
    setItems([]);
    void refresh();
  }, [scene]);
  if (!(scene in materialScenes))
    return <Alert type="error" message="素材场景不存在" />;
  return (
    <div className="digital-albums-page">
      <PageHeader
        title={materialScenes[scene as keyof typeof materialScenes]}
      />
      {error && (
        <Alert
          type="error"
          message={error}
          action={<Button onClick={refresh}>重试</Button>}
        />
      )}
      <ResourceManager
        key={scene}
        scene={scene as keyof typeof materialScenes}
        resources={items}
        canEdit={canPermission(actor, "albums.manage")}
        onSaved={refresh}
      />
    </div>
  );
}

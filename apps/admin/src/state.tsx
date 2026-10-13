import { createContext, useContext } from "react";
import type { Actor, Catalog } from "./api/types";
import { emptyCatalog } from "./api/types";
export const ConsoleContext = createContext<{
  actor: Actor;
  catalog: Catalog;
  reload: () => Promise<void>;
  loading: boolean;
}>({
  actor: { id: "", name: "", role: "admin" },
  catalog: emptyCatalog,
  reload: async () => {},
  loading: false,
});
export const useConsole = () => useContext(ConsoleContext);

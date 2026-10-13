import React from "react";
import "@ant-design/v5-patch-for-react-19";
import ReactDOM from "react-dom/client";
import { App as AntApp, ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import App from "./App";
import "./styles.css";
import "./design/tokens.css";
import "./design/components.css";
import { adminTheme } from "./design/theme";
const router = createBrowserRouter([{ path: "*", element: <App /> }]);
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ConfigProvider
      locale={zhCN}
      theme={adminTheme}
      form={{ validateMessages: { required: "请填写${label}" } }}
      button={{ autoInsertSpace: false }}
    >
      <AntApp>
        <RouterProvider router={router} />
      </AntApp>
    </ConfigProvider>
  </React.StrictMode>,
);

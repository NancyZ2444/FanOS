import React from "react";
import "@ant-design/v5-patch-for-react-19";
import ReactDOM from "react-dom/client";
import { App as AntApp, ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import { BrowserRouter } from "react-router-dom";
import App from "./App";
import "./styles.css";
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ConfigProvider
      locale={zhCN}
      theme={{
        token: {
          colorPrimary: "#8660dc",
          colorInfo: "#8660dc",
          colorText: "#273650",
          colorTextSecondary: "#8b93a5",
          colorBorder: "#e1e5ee",
          borderRadius: 6,
          fontSize: 13,
          controlHeight: 36,
          fontFamily:
            'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif',
        },
        components: {
          Table: {
            headerBg: "#f8f9fc",
            headerColor: "#858da0",
            rowHoverBg: "#faf8ff",
            cellPaddingBlock: 15,
          },
          Tabs: { horizontalItemGutter: 30 },
          Button: { primaryShadow: "0 3px 8px rgba(134,96,220,.16)" },
          Input: { activeShadow: "0 0 0 2px rgba(134,96,220,.08)" },
          Select: { optionSelectedBg: "#f0eafb" },
        },
      }}
    >
      <AntApp>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </AntApp>
    </ConfigProvider>
  </React.StrictMode>,
);

import type { ThemeConfig } from "antd";
/** Admin UI contract. Keep CSS variables in tokens.css aligned with these values. */
export const adminTheme: ThemeConfig = {
  token: {
    colorPrimary: "#8660dc",
    colorInfo: "#8660dc",
    colorText: "#29364e",
    colorTextSecondary: "#737e91",
    colorBorder: "#e1e5ee",
    colorBgLayout: "#f6f7fb",
    colorError: "#c73746",
    borderRadius: 6,
    borderRadiusLG: 8,
    fontSize: 14,
    fontSizeSM: 12,
    fontSizeLG: 16,
    fontSizeHeading1: 24,
    controlHeight: 36,
    controlHeightSM: 28,
    controlHeightLG: 36,
    padding: 16,
    paddingSM: 12,
    paddingXS: 8,
    paddingXXS: 4,
    fontFamily:
      'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif',
  },
  components: {
    Button: {
      paddingInline: 16,
      paddingInlineSM: 8,
      iconGap: 8,
      primaryShadow: "none",
    },
    Table: {
      headerBg: "#f8f9fc",
      headerColor: "#63708b",
      rowHoverBg: "#faf8ff",
      cellPaddingBlock: 16,
      cellPaddingInline: 16,
      cellPaddingBlockSM: 16,
      cellPaddingInlineSM: 16,
    },
    Tabs: { horizontalItemGutter: 24 },
    Form: {
      itemMarginBottom: 16,
      labelFontSize: 14,
      verticalLabelPadding: "0 0 8px",
    },
    Modal: { borderRadiusLG: 8 },
    Input: { activeShadow: "0 0 0 2px rgba(134,96,220,.12)" },
    Select: { optionSelectedBg: "#f3eefc" },
  },
};

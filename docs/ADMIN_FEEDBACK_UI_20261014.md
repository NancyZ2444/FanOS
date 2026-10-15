# 图鉴补全后台 UI 本地整改

开始日期：2026-10-14；验收日期：2026-10-15（Asia/Shanghai）。

本次范围是新增的「小卡缺失收录」「图鉴问题纠错」两个模块，按现有 Fan OS 后台公共 UI 规范整理列表、查看、编辑及处理确认。仅修改本地前端；没有提交或推送 Git，没有部署后台服务器，没有修改 API、数据库结构或 App。工作区内原有的其他前后端改动不属于本次整改。

## 页面清单

| 页面 | 路由 | 本次变化 |
| --- | --- | --- |
| 小卡缺失收录列表 | `/catalog/missing-cards` | 公共标题、筛选、状态工具栏、表格、空状态、上一页/下一页；移除嵌套页面留白 |
| 小卡缺失收录详情 | `/catalog/missing-cards/:feedbackId` | 独立查看页；基本信息、关联内容、小卡信息、发布信息、处理记录、系统信息分组；右上角编辑 |
| 小卡缺失收录编辑 | 同一详情路由，点击「编辑」 | 垂直表单、行内必填提示、图片预览、关联已有卡、底部保存与发布；低频状态动作放入更多 |
| 图鉴问题纠错列表 | `/catalog/corrections` | 与缺失收录复用相同列表结构；增加对象类型筛选，高级条件折叠 |
| 图鉴问题纠错详情 | `/catalog/corrections/:feedbackId` | 分组查看；提交时值、建议值、平台最新值、处理结果并列核对；未审核字段显示待核对；缺失小卡详情采用紧凑标签和值布局，空内部备注折叠 |
| 图鉴问题纠错编辑 | 同一详情路由，点击「编辑」 | 共用字段编辑器；采纳、修改后采纳、未采纳及原因；保存审核意见与发布区分 |

## 公共规范及交互

- 直接复用 `src/design/tokens.css` 的 24px 页面间距、20px 卡片内边距、16px 字段间距、36px 控件高度、28px 紧凑按钮、24/16/14/12px 字级及现有紫色主题。
- 复用 `PageHeader`、`FilterBar`、`TableToolbar`、`Table`、`RowActions`、`EmptyState`、`Form`、`RecordId`、`useFormGuard`、`useSingleSubmit`；新增公共 `CursorPagination` 适配现有分页响应。
- 两模块共用 `feedback/FeedbackReview.tsx`、`FeedbackValues.tsx` 和同一份局部组合样式。没有更改其他页面的尺寸或主题规则。
- 模块入口保留在侧栏；列表 Tab 只切换处理状态。详情有明确的查看/编辑状态；不再打开后即可直接改写。
- 基础筛选即时生效；高级筛选包括处理人和提交日期，重置统一清除全部条件并回到第一页。没有为不支持关键词查询的接口增加无效搜索框。
- API 没有返回总量，因此只显示「第 N 页 · 本页 N 条」，不把当前页数量当成总数。
- 时间复用公共格式 `YYYY-MM-DD HH:mm`，详情明确标注北京时间；编号弱化、截断并可复制；布尔值和状态中文展示；扫描信息用中文业务项取代原始 JSON。
- 新增/处理字段共用原有控件与顺序；多组字段的复杂审核使用独立页面。仅存在运营编辑，不新增运营代替用户提交反馈的入口。
- 保存期间禁止重复提交；失败保留输入；相同内容重试复用请求编号。编辑离开、取消或刷新时提示未保存内容；版本冲突时要求明确刷新并重新核对，不自动覆盖新版本。
- 发布、关联完成、不予采纳有对象名称、数量和影响说明。必填公开说明及未采纳原因先校验再确认。完成的反馈恢复只读。
- 删除、归档、批量处理不在现有反馈 API 能力中，本次不新增这些入口，也不把「不予采纳」等同于删除。原有图鉴页面的删除约束保持原样。

## 接口与数据边界

保持原有接口及字段结构：

- `GET /api/v1/admin/console/feedback`：`kind/status/result/entity_type/handler_id/date_from/date_to/offset/limit`。
- `GET /api/v1/admin/console/feedback/{id}`。
- `POST /api/v1/admin/console/feedback/{id}/actions`：保留 `action/revision/public_note/internal_note/card_id/changes/decisions/object_version/sources/request_key`。
- `GET /api/v1/feedback/objects` 与单对象查询继续用于引用选择和版本核对。
- 处理动作仍为 `start/draft/review/publish/reject/match/already_fixed`，权限仍由原后端校验；前端相应隐藏无权限的发布操作。
- 来源类型、Tag、成员归属、版权、正式发布和贡献计算均使用现有后端规则，没有迁移或清洗已有数据。

## 本地验证与截图

截图使用 Playwright 独立测试数据库、独立上传目录和本地图像检测生成的演示反馈；不向运营数据库写入测试记录。端口为 API 8011、前端 5174，测试后自动关闭。常规本地预览使用已有 API 8000 与前端 5173。

验收记录见同目录输出文件：`output/feedback-ui-20261014/`。三种宽度 1280、1440、1920 均包含两模块的列表、查看和编辑截图。整改前 12 张、整改后 18 张。

[打开前后截图对比页](../output/feedback-ui-20261014/index.html)

| 模块 | 整改前（1440） | 整改后（1440） | 编辑（1440） |
| --- | --- | --- | --- |
| 小卡缺失收录列表 | [截图](../output/feedback-ui-20261014/before/1440/missing-cards-list.png) | [截图](../output/feedback-ui-20261014/after/1440/missing-cards-list.png) | — |
| 小卡缺失收录详情 | [原抽屉](../output/feedback-ui-20261014/before/1440/missing-cards-detail.png) | [详情](../output/feedback-ui-20261014/after/1440/missing-cards-detail.png) | [编辑](../output/feedback-ui-20261014/after/1440/missing-cards-edit.png) |
| 图鉴问题纠错列表 | [截图](../output/feedback-ui-20261014/before/1440/corrections-list.png) | [截图](../output/feedback-ui-20261014/after/1440/corrections-list.png) | — |
| 图鉴问题纠错详情 | [原抽屉](../output/feedback-ui-20261014/before/1440/corrections-detail.png) | [详情](../output/feedback-ui-20261014/after/1440/corrections-detail.png) | [编辑](../output/feedback-ui-20261014/after/1440/corrections-edit.png) |

### 验收场景

- 缺失小卡：必填提示、取消继续编辑、保存失败保留内容、相同请求重试、防止双击重复保存、草稿回填、同一草稿正式发布。
- 逐字段纠错：保存意见、回填、未采纳原因校验、部分采纳并发布。
- 多人处理：版本冲突、输入保留、明确刷新提示；返回与取消的未保存保护。
- 不予采纳：确认对象及影响、取消不执行、完成后只读、返回列表显示新状态。
- 已有卡匹配、已由其他修改修正：保持原完成及不重复计入收录的规则。
- 筛选、重置、游标分页、尚无数据、无匹配结果；空列表无横向溢出。
- 1280/1440/1920 布局，控制高度、工具栏和页面溢出；其他已有后台页面回归。

### 验证结果

- TypeScript 类型检查、ESLint、生产构建通过。Vite 仍提示既有主包体积大于 500 kB；本次没有扩大到全站拆包优化。
- Vitest：3 个文件、12 项通过。
- Playwright 全量回归：38 项通过（4.7 分钟），含本次 7 项与原有 31 项。覆盖全站 29 个列表/详情/编辑入口的 1280、1440、1920 宽度巡检，以及新增、回填保存、取消、校验、删除确认、关联删除受阻、批量操作与空状态。
- 本次截图验收对列表、详情、编辑检查页面横向溢出、28/36px 按钮高度、操作按钮重叠及每区主按钮数量；未发现异常。
- 最终只读布局收尾后，三宽度截图复验另通过 1 项（11.4 秒）。
- 最终日志：[三宽度复验](../output/feedback-ui-20261014/visual-final.log)、[全量端到端验收](../output/feedback-ui-20261014/e2e-all.log)、[单元测试](../output/feedback-ui-20261014/unit.log)、[构建](../output/feedback-ui-20261014/build.log)、[ESLint](../output/feedback-ui-20261014/lint.log)。
- 本地预览：[小卡缺失收录](http://127.0.0.1:5173/catalog/missing-cards)、[图鉴问题纠错](http://127.0.0.1:5173/catalog/corrections)。常规预览显示已有本地数据，演示反馈仅存在于隔离验收库中。

### 本次实现文件

- `apps/admin/src/pages/FeedbackWorkbench.tsx`：两个列表、路由详情加载及列表状态。
- `apps/admin/src/pages/feedback/FeedbackReview.tsx`：共用查看/编辑与审核操作。
- `apps/admin/src/pages/feedback/FeedbackValues.tsx`、`types.ts`、`feedback.css`：公共字段组合、展示映射和局部布局。
- `apps/admin/src/components/admin.tsx`、`src/design/components.css`：新增游标分页组件及其样式；其他公共组件规则保持原样。
- `apps/admin/src/App.tsx`：在已有模块入口上支持详情子路由及侧栏选中状态。
- `apps/admin/tests/e2e/feedback-fixtures.ts`、`feedback-interactions.spec.ts`、`feedback-ui.spec.ts`：隔离反馈数据、流程和视觉验收。

本次交付停留在本地验证阶段，没有执行 Git 提交、推送或服务端部署。

# Verification record · 2026-09-16

## 2026-10-13 · 后台 UI 与操作规范统一

- 新增公共设计变量、Ant Design 主题、标题/筛选/工具栏/表格/空状态/详情/表单组件，统一导航、尺寸、中文状态与日志、时间、编号复制及快捷创建。
- 新增编辑复用表单，增加保存防重、失败保留、取消与离开保护；删除通过原服务端关联检查，保留图鉴历史关系规则和批量事务语义。
- ESLint / TypeScript / 生产构建通过，Vitest **11 项通过**，完整 Playwright **31 项通过**；公共表单异常与重试场景连续 3 次通过。
- **29 个页面入口 × 1280 / 1440 / 1920** 的页面溢出、工具栏重叠、按钮高度及浏览器运行错误检查通过，提供修改前后截图与交互截图。
- 所有写入验证使用隔离数据库；本次不迁移或修改运营数据。生产构建仍有主包体积提示，未做拆包性能改造。
- [页面清单、公共规范与验收说明](ADMIN_UI_STANDARDIZATION_20261013.md) · [截图对照](../output/admin-ui-20261013/index.html)


## 2026-10-12 · 头像缓存与双端更新

- App 增加网络图片首帧占位、成员缩略图和磁盘缓存，保留详情原图；API 旧 localhost 上传地址按包内真实后端地址解析，支持 Android 真机访问。
- 后端 196 项全量测试通过；追加「外部来源暂缓时保留原图、不发起下载」后，头像相关 5 项复测通过。App 97 项通过、2 项按配置跳过；相关 Dart 分析及后端 Ruff 通过。
- 真实服务的 24 张缓存头像全部请求成功，共 347,802 字节，本机响应中位数 1.63 ms；局域网健康检查 200。其余 29 张外部头像按用户要求暂不处理来源限制，继续保留原地址，不宣称全量加载速度问题已消除。
- 1.0.2（2026101201）iOS Simulator 通用包构建、双架构、签名、ZIP 完整性、覆盖安装及启动通过。没有卸载或清空应用数据；没有数据库迁移。
- 同版本 Android 通用 Release APK 已完成：v2 签名、ZIP CRC、16 KB ZIP 对齐、三架构原生库、MainActivity 和 API 地址验证通过；最低 Android 7，使用开发签名，连接 `192.168.0.112:8000` 真实开发 API。无 Android 设备连接，因此未声明真机相机／相册验收完成。
- 双端安装包、后端连接方式、校验记录与验收边界见 [移动端交付说明](MOBILE_RELEASE_20261012.md)。

## 2026-10-11 · 来源收敛、统一 Tag 与用户补充

- 来源统一为 Album / Event / Other，后台增加 Tag 管理；四种实体独立 Tag、标准化去重、历史停用关系保留；用户资料与新 Tag 一次提交并在同一事务审核发布。App 显示 Tag，并按当前结果动态计算筛选项。
- 后端全量 pytest 通过（含新增 7 个场景）；App 92 项通过、2 项需独立 API 的用例跳过；最后的补充表单修正复测 13 项通过。Flutter analyze、后端 Ruff、后台 TypeScript / ESLint / Vitest 8 项 / build 通过。
- 浏览器测试：Other 六字段表单、Tag 创建/关联数/详情跳转/停用保留历史，以及小卡专辑版本保存两项通过。后台截图为隔离测试数据，不写本机业务库。
- 实际迁移 `d611_catalog_taxonomy` 完成：3 条旧 Merchandise 保留 ID 转为 Other，原状态保留，无已有 Tag 待回填。49 张原有表摘要不变；数据库完整性正常、外键错误为 0。快照、只读验证报告与回退步骤见 [来源与 Tag 更新](CATALOG_TAXONOMY_TAGS_20261011.md)。
- 新版真实 API 模式 iOS Simulator App 已构建、安装并启动；后台和 API 本机服务正常，未发布远程生产或应用商店。


## 2026-10-11 · 活动必填项、小卡编号与本命名称设置

- 活动：线下城市必填，线上新增 `platform` 且必填；后台管理、快捷新建来源、CSV / XLSX 导入、审核发布统一校验。App 线上活动展示平台，线下展示城市 / 场馆。
- 小卡：移除后台手填名称、英文 / 韩文名称以及手填编号；新增小卡不需要 `title`，服务端生成兼容旧客户端的来源 / 版本 / 类型标签。`card_number` 由服务端生成 `FOS-` + UUID，数据库唯一约束保证唯一，编辑不变，忽略客户端自填编号。导入模板不再要求名称 / 编号；旧模板仍兼容。App 详情和后台列表显示新编号，支持编号搜索。
- 本命：`primary_idol_id` 独立持久化，可为空，保存 / 重读不再自动选第一位。点击星星设置或取消；有星标时沿用大图重点展示，无星标时平等展示；用户界面移除“主本命”称谓。
- 私人备注：艺人 / 组合详情可设置备注，“我的 → 编辑资料 → 名称与备注”以及本命管理页可集中维护；提供官方名、仅备注名、官方名（备注名）三种模式，没有备注始终回退官方名。备注只保存于当前账户，官方名称、关联 ID、公开图鉴及分享数据不被改写。
- 接口新增 `GET/PATCH /me/name-preferences`、`PUT /me/name-preferences/{groups|idols}/{id}`，备注限 40 字，清空删除，OpenAPI 已更新。
- 数据迁移 `c611_catalog_preferences`：既有重点展示选择迁移一次，后续支持取消；旧手填编号留在 `admin_data.legacy_card_number`，卡片 ID、图片、收藏和扫描关联保留。开发库已备份至 `apps/api/data/backups/fan_os_before_catalog_preferences_20261011.db`；副本演练及实际升级均通过完整性 / 外键检查，10 张小卡均有不同编号。
- 验证：后端全量 191 项、Flutter 全量 88 项（2 项需独立运行服务的契约测试跳过）、后台 8 项通过；Dart 分析、TypeScript、相关 Ruff 及后台生产构建通过。该轮为代码与本地数据库更新，未生成新的 iOS 安装包。

## 2026-10-11 · 扫描批量处理与官方来源反馈

- 完成紧凑结果列表、批量收藏／喜欢和拥有标记、详情返回保留扫描状态；官方来源与专辑版本选择、其他／不确定、缺失版本／活动反馈及图鉴入口已接入。
- 后端全量 **186 项 pytest**、Flutter 全量 **83 项测试**、iPhone 16 Pro / iOS 18.6 原生 Mock UI 操作回归通过。Dart 与本次后端代码 Ruff 检查通过；OpenAPI 已更新。
- 原生 UI 验证布局和导航，真实 API 使用隔离 TestClient 验证，不写真实收藏。无需数据库迁移，旧客户端反馈兼容。
- 操作定义、接口与验证边界见 [扫描交互更新](SCAN_INTERACTIONS_20261011.md)。
- 已重新编译、安装并启动普通 iOS Simulator 版 **1.0.1（2026101103）**，连接 API 8000，保留原 App 数据。三份原生框架均含 arm64／x86_64；签名及 ZIP 完整性检查通过。

## 2026-10-11 · 后台小卡自动裁剪与手动调整

- 后端全量 **170 项 pytest**、**7 项 Vitest**、TypeScript、ESLint、Ruff 和生产 build 通过。既有 TestClient 弃用与构建包体积提示保留。OpenAPI 已同步。
- 11 项裁剪 API 用例覆盖背景边界检测、倾斜透视、EXIF 方向、确认范围不重复检测、手动裁剪输出、无边缘回退、权限、坏图片及越界 / 交叉 / NaN / 过小选区；专门验证补建索引时不会把上传图替换成已有参考图。
- 浏览器 7 个相关场景完成：首次 4 项通过，识别图变量问题及两个「取消」按钮的测试定位修正后，剩余 3 项复跑全部通过。覆盖上传带背景照片识别原记录、未知图携图新增、取消不调用识别 / 持久化上传、拖动四角、方向键 / 数值微调、恢复自动框选、保留全图、裁剪后保存，以及既有审核发布 / 公司流程。截图已人工检查。
- 本地 API 8000 已以 `AUTO_SEED=false` 重启；后台 5173、API 健康检查成功；运行中 OpenAPI 确認裁剪预览路由和 `crop` 字段生效。重启前后 **53 张表的行数与内容 SHA-256 一致**，无迁移、无历史图片批量改写。
- 测试使用隔离库与媒体目录；公开 App 扫描响应格式和页面未修改。操作说明及截图见 [小卡裁剪说明](CATALOG_CARD_CROPPING_20261011.md)。

## 2026-10-11 · 图片选择、后台识别与公司导入

- 后端全量 **159 项 pytest**、前端 **7 项 Vitest**、TypeScript、ESLint、Ruff（排除既有第三方 vendor）与生产 build 通过。OpenAPI 同步；既有依赖弃用及构建包大小提示保留。
- 识别专项使用真实合成卡图特征匹配，覆盖草稿未建公开索引仍可匹配、无结果、相似结果歧义、图片不可用、权限与坏图片；确认原小卡和用户收藏没有被识别改写。
- 公司导入覆盖 CSV / XLSX、模板、预检不写数据、确认与重复确认、导入后关联、归一化查重、逐行修正 / 跳过、确认时冲突整批回滚。
- 图鉴 Playwright 16 场景运行：15 项通过，原审核发布场景因增加版本下拉后旧测试的无名称 combobox 定位产生歧义；已改为明确的「来源对象」定位，后续 4 项定向复跑全部通过（包含三项新增场景和审核发布流程）。新增场景覆盖公司导入后在组合选择、组合 / 艺人图片及下拉回显、上传识别打开既有草稿与携图新增。测试使用隔离库及 8011 / 5174 端口。
- 后台开发 API 8000 已包含新识别路由和公司导入枚举。无本次运营数据迁移或批量改写。功能与资料补齐策略见 [说明](CATALOG_RECOGNITION_COMPANIES_20261011.md)。

## 2026-10-11 · 透明卡册九卡分割

- 用户真实原图在隔离库的完整扫描服务验证：修复前 1 个整页对象，修复后 **9 张独立裁剪、9 个独立 ID**。不是强制九等分；空中格为八张，2×3 为六张，邻页截断卡不计入主页面。
- 后端全量 **152 项 pytest**、Flutter 全量 **62 项测试**通过，Dart 静态检查通过；本次检测、测试和验证脚本 Ruff 通过。全仓 Ruff 存在其他正在更新的后台文件行长提示，未在本任务修改。
- 保留逐张候选／未知状态和用户确认，未改 API 契约、数据库或 iOS 代码；现有 App 不需重打包，重新上传原照片可获取新结果。旧扫描历史不会自动重算。图鉴参考不足仍可能逐张未匹配。
- 原图裁剪、验证脚本与边界说明见 [九卡分割修复](SCAN_NINE_CARD_FIX_20261011.md)。

## 2026-10-11 · 小卡专辑版本搜索选择

- 31 项相关 API 测试、7 项 Vitest、TypeScript、ESLint、Ruff 与生产 build 通过。既有构建包大小和依赖弃用提示保留。
- 新增 Playwright 场景通过：新建小卡选择专辑→按版本编码搜索→切换专辑清空旧版本→按版本名称选择→保存具体版本 ID→重新打开回显。测试使用独立库与 8011 / 5174 端口。
- 原有小卡数据未迁移；保存接口校验版本的实体类型/所属 ID，拒绝新增归档版本关联，并以所选版本记录名称保存版本文本。

## 2026-10-11 · 专辑版本与多艺人导入

- 后端全量 **145 项 pytest**、前端 **7 项 Vitest**、TypeScript、ESLint、生产 build 和 Ruff 项目检查通过。OpenAPI 已更新，既有依赖弃用及包大小提示保留。
- 完整 Playwright 共 13 项：专辑与原图鉴运营 **12 项通过**；数字相册场景使用独立 API 18001，与默认 8011 测试配置不一致：完整运行查询超时，单独复跑时 18001 连接拒绝。本次未改数字相册或其专用测试配置。测试使用隔离数据库及 8011 / 5174 端口。
- 运营库备份后单事务归并 14 条 Draft 为 4 个父专辑、14 个版本，10 个旧 ID 保留归档映射；补齐 7 个明确旧版本。物理专辑仍 71 行，已有版本资料及其他 49 张表在应用事务中不变；副本重复执行 53 张表无变化。
- API 明确禁用 AUTO_SEED 后启动，8000 健康与后台 5173 检查均 200。App 页面逻辑与数字相册未改动。数据映射、备份及策略见 [专辑版本说明](CATALOG_ALBUM_VERSIONS_20261011.md)。

## 2026-10-11 · 封面文字保存红屏修复

- 用户路径「新建相册 → 添加封面文字 → 保存」复现输入控制器提前释放及 `_dependents.isEmpty` 连带断言。改为弹层 State 管理控制器，覆盖文字、背景、设置、重命名与举报输入；未修改 API 或数据库。
- Flutter 全量 **60 项测试通过**，Dart 静态检查通过。新增保存／再次编辑、取消／遮罩／系统返回和其他输入弹层回归。具体原因和设备验证见 [红屏修复说明](BUGFIX_ALBUM_TEXT_20261011.md)。
- iPhone 16 Pro / iOS 18.6 原生回归通过，文字新增和修改均写入真实测试 API，选卡／发布／阅读流程正常。测试在隔离数据库执行。
- 普通模拟器版 **1.0.1（2026101102）** 已重新编译、安装、启动；连接开发 API 8000，保留原 App 数据。Runner／App.framework／Flutter.framework 均为 arm64 + x86_64；签名、ZIP 完整性检查通过。

## 2026-10-11 · 数字相册与 iOS 模拟器更新

- 完成数字相册的 Flutter、独立 API、数据迁移和后台管理。后端全量 **117 项 pytest**、Flutter 全量 **56 项测试**、真实 API 相册契约、后台 **7 项 Vitest** 及新增 Playwright 相册管理流程通过；Dart、ESLint、TypeScript、Ruff、Alembic check 通过。
- **iPhone 16 Pro / iOS 18.6 原生操作回归通过**：新建、封面选卡、内页选卡、保存发布、翻页、预览关闭保留位置、卡片轮播。测试隔离在 18001 API / 临时数据库，清除本次测试作品；正常包连接开发 API 8000，不包含测试启动入口。
- 旧数据库先备份再升级，既有组合、艺人、小卡、卡册数量保持不变，没有重置上传图片和收藏。实际迁移 head 为 `a611_digital_albums`。
- 相册范围、版权处理、草稿／发布快照机制、Figma 辅助页面额度限制及 PRO 支付等未接入项见 [数字相册说明](DIGITAL_ALBUM_2026_10_11.md)。iOS Simulator 版本为 **1.0.1 (2026101101)**，非实体 iPhone IPA / TestFlight 包。

## 2026-10-11 · 组合成员与公司选择修复

- 后端全量 **105 项 pytest**、前端 **7 项 Vitest** 通过；TypeScript、生产 build、ESLint、Ruff 项目代码检查通过（排除既有第三方 `card_matcher/vendor`）。既有依赖弃用和构建包体积提示保留。
- **10 个 Playwright 场景完整运行全部通过**，使用隔离库与 8011 / 5174 端口。新增组合过滤 / 历史成员和新建公司在组合 / 艺人表单选择的浏览器验证；既有批次、反馈、Solo、发布下架、导入和布局场景继续通过。
- 后续补充「日期未知的公司经历可编辑备注且保留来源」验证，修正测试详情路径后复跑通过；最后的公司经历界面修改及批次场景也分别复核通过。
- 公司补齐：只读预览 → 副本演练 → 副本重复执行零新增 → 运营库一致性备份 → 单事务补齐 → 启动后零候选复核。新增 9 家公司、9 条组合关联和 18 条审计，其余 44 张表完整内容不变；启动后 46 张表与补齐结束时一致。
- 直接读取实际运营数据，确认 IVE 对应 STARSHIP Entertainment 的公司 ID，艺人候选为其 6 名成员。公司关系起止日期待核实，没有按组合为艺人推断公司。
- 后台 5173、API 8000、索引 Worker 已启动，健康检查 200，新版 OpenAPI 包含 `company_ids` / `company_effective_date`。资料和实际映射见 [修复说明](CATALOG_FIXES_20261011.md)。

## 2026-10-10 · 图鉴运营功能与历史关系

- 后端全量 **98 项 pytest 通过**；新增场景覆盖 Solo / 合作发行、历史成员与缺失经历兼容、Draft 删除和发布历史保护、来源链 / 版本、批量预览 / 冲突、批次生成与解除、联合导入修正 / 幂等、同名个人发行查重、反馈审核和人工合并。
- 下架卡实际图片匹配、确认收藏和历史访问通过测试；未登录及无本人历史关系用户仍不能读取下架详情，归档卡不进入识别。
- 前端 TypeScript、生产 build、ESLint、4 项 Vitest 通过。Ruff 全量检查通过。现有 TestClient 弃用提醒和约 1.47 MB 的构建包提示保留。
- 浏览器共 8 个场景：完整运行 7 个通过；新增批次场景因点击 Ant Design 占位文字超时，改为有名称的 combobox 后单独复跑通过。覆盖批次 / 批量字段、反馈比较接受、个人发行 / 版本 / 关联创建，以及原创建发布下架、六类导入批量操作、页面布局和删除。使用隔离库及端口 8011 / 5174，未写入运营数据库。
- SQLite 全新升级至工程 head `b610_profile_background`、结构比较、回退至 `e2a10b8f4c63`、再次升级及比较通过；包含 `f310_catalog_operations`。回退演练只对空测试库执行。
- 现有运营库已具备所需结构，备份后复核 head / `alembic check`，重启前后 45 张业务表行数及内容 SHA-256 一致。27 项语义补齐候选未改写，策略见 [图鉴更新与数据升级](CATALOG_UPGRADE_20261010.md)。
- 后台 5173、API 8000、索引 Worker 已启动；OpenAPI JSON / YAML 更新。未进行生产部署、万级目录 / PostgreSQL 并发压测，也未重新构建移动端。

## 2026-10-09 · 归档记录永久删除

- 后端原有 69 项与新增 9 项删除测试全量通过；补充小卡上游检查测试后，删除专项 10 项通过（合计 79 项）。覆盖归档前置条件、上游归属、已归档下游、JSON 对象键引用、整批回滚、审计保留与权限。
- 前端 build、ESLint、TypeScript 和 4 项 Vitest 测试通过。
- 原有 4 项 Playwright 场景通过；新增永久删除场景修正确认按钮空格定位后单独复跑通过。使用隔离数据库，不删除现有运营记录。
- 本地后台 5173、API 8000 已启动，健康检查通过；OpenAPI 已重新导出。规则与必填归属限制见 [CATALOG_DELETION.md](CATALOG_DELETION.md)。
- PostgreSQL 并发及大数据量检查未专项验证；已有前端包体积提示仍存在。

For the newer admin delivery, see the 2026-09-18 section below. Earlier counts describe the
previous build and are preserved as history.

Completed on the local Apple Silicon development machine:

- Flutter `dart format`, `flutter analyze`: no issues.
- Flutter unit/widget/contract tests: 33 passed; the opt-in live contract test is skipped in the normal run.
- Flutter live backend contract: passed against the updated API on
  `http://127.0.0.1:8001/api/v1`.
- API Ruff checks (excluding the unchanged vendored card-matcher source) and pytest: 10 passed.
- Reserved Phase 2/3 architecture tests confirm Community and Chat do not register Phase 1 routes,
  the transactional Outbox persists versioned events, and backend/Flutter share stable entity refs.
- Catalog API now persists and returns groups, Idols, albums, events, cards, and merchandise,
  including paginated filters, details, cross-entity search, and user-state hydration.
- Catalog entities now expose English, Korean, and translated names; group region filtering is
  removed, and albums support optional front/back artwork.
- AI Scan readiness reports the official-card index and extractor requirements through
  `GET /api/v1/scan/status`; the current local index is empty, so production recognition remains
  unavailable until authorized official card images are imported.
- Alembic fresh upgrade through `a8e42c19f5d0`, downgrade to the previous head, re-upgrade,
  and `alembic check`: passed.
- Existing OpenAPI remains at 57 paths; no Community or Chat endpoints are exposed yet.
- iOS Simulator `1.0.0 (3)` API build: ad-hoc signature, ZIP integrity, arm64 and x86_64 passed.
- The build installed and launched successfully as `com.fanos.app` on an iPhone 16 Pro Max
  simulator running iOS 18.6.
- Crawler Worker Ruff checks and pytest: 1 passed.
- Alembic fresh SQLite upgrade, `alembic check`, downgrade: passed.
- OpenAPI JSON/YAML regenerated from the running FastAPI application.
- Docker Compose YAML and all six required services validated structurally.
- Supplied OSNet, FER+, and YOLO Pose models loaded through ONNX Runtime; OSNet returned
  512 dimensions and FER+ returned 8 dimensions. YOLO Pose correctly returned no person
  for a solid-color image.
- Copied ONNX hashes match the user-supplied files exactly.
- Original card-matcher tests: 27 passed, 2 skipped. One additional test could not run
  because its external `biasroom-cards/...png` fixture is absent from the supplied folder.

The machine does not have a Docker CLI, so image builds were not executed locally. The
same API and Flutter contract were exercised directly, and CI definitions cover API,
Worker, migrations, Flutter analysis, tests, and Android debug compilation.

## Admin Console · 2026-09-18

- API Ruff checks: passed. Pytest: **23 passed**, including 13 new admin scenarios. Two dependency
  deprecation warnings remain in the FastAPI/Starlette test client stack.
- Frontend ESLint, TypeScript and Vite production build: passed. Four field-validation tests passed.
- Playwright: **2 passed**. Covered create → incomplete-field feedback → real file upload →
  preview → submit → publish → offline, with public API visibility assertions, and all 21 module
  routes plus editor overflow checks at widths 1440 and 1024. Uses a separate test database,
  storage directory and ports 8011/5174. This is smoke coverage for secondary modules, not full
  branch coverage of every operational action.
- Alembic fresh SQLite upgrade to `d1f09a7c3e22`, schema comparison, downgrade to
  `a8e42c19f5d0`, re-upgrade and comparison: passed. Existing local database migrated after backup.
- Source-image tests verify actual image decoding, WebP upload, version history, worker index
  generation and rejection of arbitrary external storage reads.
- Permission tests include direct endpoint access, legacy endpoint restrictions, admin account
  protection, disabled sessions and rejection of development login in production mode.
- Notification tests verify test-only delivery, review gating, inbox ownership, send idempotency
  and invalid/unpublished target handling. Card-pool weights affect actual daily draw results.
- Updated Flutter card-detail file: `dart format` and targeted `dart analyze` passed.
  No fresh mobile release build was produced in this admin task.
- OpenAPI JSON/YAML regenerated. Frontend `npm audit` reports zero vulnerabilities.
- Build has a JavaScript chunk-size warning (about 1.4 MB before gzip); splitting remains a
  performance task. AI model accuracy and external provider delivery were not measured here.
- Docker/Nginx/Compose and Admin CI definitions supplied; local Docker image execution and
  PostgreSQL migration validation were not possible because Docker is not installed.

Scope and remaining requirements: [Admin project status](ADMIN_PHASE1_STATUS.md).

## AI Scan · 2026-10-08

- API pytest: **41 passed**; Ruff format/check passed. Two existing TestClient dependency
  deprecation warnings remain. Tests now exercise real artwork features, not fallback matches.
- Flutter local unit/widget tests: **38 passed** (including **9 Scan tests**) using a socket-free
  Flutter engine harness, excluding the opt-in live backend contract.
  Dart analysis of all `lib` and `test` files passed. Standard test-runner socket creation is
  denied in this environment, so this is not a fresh standard `flutter test`/device E2E run.
- Existing uploaded artwork: **5 in-process API scenarios passed** (original, rotation,
  cropped/darkened, two copies plus one unknown, all unknown). A copied temporary database
  isolated confirmation writes from the user's real collection. Results are in
  `output/scan-verification/report.json`; they are not a field-accuracy measurement.
- Local usable index: **1 published card**, `sift-homography-v1`; no fabricated matches for
  missing or legacy indices. `production_ready=false` deliberately marks unvalidated field
  accuracy/scale, independently of `available=true` for local matching.
- Alembic fresh SQLite upgrade to `e22a811c4b03`, downgrade to `d1f09a7c3e22`, re-upgrade and
  schema checks passed. Local database at head; OpenAPI JSON/YAML refreshed.
- API TCP listen and CoreSimulator IPC are restricted here. No new iOS package, simulator
  launch, real-camera capture, live network contract, Docker or PostgreSQL validation is claimed.

Activation, scope, test details and remaining device checks:
[AI Scan verification](AI_SCAN_VERIFICATION.md).

## Catalog bulk operations and typed imports · 2026-10-09

- API Ruff passed; pytest **69 passed** (28 new bulk/import cases, preserving the prior 41).
  Covers all six upstream entity models in CSV and XLSX, preview-only behavior, persisted IDs,
  duplicates, invalid relations, confirmation revalidation/idempotency, all batch transitions,
  rollback, permissions and both template formats for all seven catalog types.
- Frontend lint, TypeScript, production build and **4** Vitest checks passed. Existing large-chunk
  build warning remains; no dependency changes were made in this update.
- **4 browser scenarios passed** across the regression run and targeted rerun: the original
  two scenarios, six entity tabs/imports/batch archive/restore with group publish/offline,
  and import type isolation with CSV/XLSX downloads. The first new test selector initially
  matched both sidebar and main-area import buttons; scoping it to `main` resolved the test.
- New migration `e2a10b8f4c63` follows the existing scan migration `e22a811c4b03`. Fresh SQLite
  upgrade/check/downgrade/re-upgrade/check passed. The local database was backed up before
  upgrading; schema comparison passed. Existing import tasks default to kind `cards`.
- OpenAPI exported; live API and admin restarted/refreshed for the updated feature.
- PostgreSQL/Docker execution was not performed in this update.

Usage, precise import semantics and migration notes: [Catalog bulk operations](CATALOG_BULK_OPERATIONS.md).

## iOS Simulator package · 2026-10-09

- Produced `FanOS-iOS-Simulator-1.0.0-build4-UNIVERSAL.zip`, version **1.0.0 (4)**,
  bundle ID `com.fanos.app`, minimum iOS 15 and real-API configuration pointing to
  `http://127.0.0.1:8000/api/v1`.
- Runner, App.framework and Flutter.framework all contain **arm64 + x86_64**, supporting
  Apple Silicon and Intel Mac simulators. Flutter engine revision matches the native shell.
- Ad-hoc signature verification, ZIP integrity check, re-extraction, bundle metadata and all
  three Mach-O architecture checks passed. SHA-256:
  `c1f5b489da007912f3777a7f153a52a8384cd22ad8aa01cfea311213308b5af4`.
- Updated Dart code was assembled successfully. The standard Xcode wrapper could not access
  CoreSimulatorService/SwiftPM temporary paths in this restricted execution environment, so the
  previously verified universal native shell (unchanged plugin set and identical Flutter engine)
  was combined with the newly assembled App.framework and re-signed.
- CoreSimulatorService remains unavailable in this execution context; installation and launch
  were not claimed. Run the documented `simctl install` and `simctl launch` commands in a normal
  macOS user session for the final simulator smoke test.

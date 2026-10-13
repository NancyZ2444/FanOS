# Fan OS 运营后台

2026-10-11 新增「数字相册」管理：作品与页面查看、公开限制／恢复、额度与 PRO 权益、主题／背景／系统贴纸。完整交付及验证见 [数字相册说明](../../docs/DIGITAL_ALBUM_2026_10_11.md)。

2026-10-11 修复组合成员筛选，支持从公司管理选择组合 / 艺人所属公司；已有 9 个组合的公司已备份后建立主数据及关联，历史日期保持待核实。使用方式与数据报告见 [修复说明](../../docs/CATALOG_FIXES_20261011.md)。

从未发布的 Draft 支持删除；曾发布后下架及归档记录须解除全部上下游关联。先预检再确认，无下游引用的下架内容可明确解除上游；历史成员关系受保护。详见 [删除说明](../../docs/CATALOG_DELETION.md)。

2026-10-10 增加个人 / 合作发行、历史经历、详情、来源版本、批次与批量编辑、图片上传、联合导入修正、反馈审核、人工合并和索引管理。功能范围与 27 项旧数据补齐候选见 [图鉴更新与数据升级策略](../../docs/CATALOG_UPGRADE_20261010.md)。

React + TypeScript + Ant Design 的 Phase 1 后台，连接项目现有 FastAPI 与数据库。当前交付以图鉴管理为主：组合、艺人、发行来源、小卡录入、审核、图片来源追溯、批量导入及 App 可见性已打通。其他运营模块提供可操作的基础版本。

完整范围、已验证事项和待办见 [项目情况说明](../../docs/ADMIN_PHASE1_STATUS.md)。本目录包含实际应用代码，不是静态页面或 localStorage 数据演示。

2026-10-09 新增全部图鉴类型的表格导入，以及六类上游内容的列表勾选、批量提交／发布／下架／归档／恢复。详见 [批量管理使用说明](../../docs/CATALOG_BULK_OPERATIONS.md)。

## 本地启动

要求：Node.js 22、npm、Python 3.11 及以上；当前验证环境为 Node.js 22.15、Python 3.12、macOS。索引 Worker 使用文件锁，适用于 macOS / Linux。

首次在项目根目录安装依赖：

```bash
python3.12 -m venv apps/api/.venv
apps/api/.venv/bin/pip install -e './apps/api[dev]'
npm ci --prefix apps/admin
```

运行：

```bash
bash scripts/dev-admin.sh
```

脚本先运行 Alembic 迁移，再启动 API、图片索引 Worker 和 Vite。启动前请释放 8000、5173 端口；Ctrl+C 停止本次脚本启动的服务。已有数据库升级前应备份，脚本不会自动创建备份。

入口：

- 后台：<http://127.0.0.1:5173>
- API 文档：<http://127.0.0.1:8000/docs>
- 健康检查：<http://127.0.0.1:8000/health>
- 开发管理员手机号：`13900000000`；验证码：`123456`。登录页可点击「填入账号」。

脚本默认 `AUTO_SEED=false`，保护已有数据。只有全新演示库需要运行 `AUTO_SEED=true bash scripts/dev-admin.sh` 初始化虚构账号与资料；不要对真实运营库开启演示初始化。账号和固定验证码仅适用于开发，生产需接入身份服务。

已有 API 时，可单独启动前端：

```bash
cd apps/admin
npm run dev
```

前端默认把 `/api`、`/media` 代理到 `http://127.0.0.1:8000`。参考 [环境变量示例](.env.example)，通过 `API_PROXY_TARGET` 更换开发 API；`VITE_API_BASE_URL` 用于显式指定 API 根路径，默认 `/api/v1`。部署配置不要加入密钥，Vite 环境变量会进入浏览器代码。

API 与 Worker 需要相同的数据库、存储地址和索引位置。可在两个终端分别运行：

```bash
cd apps/api
.venv/bin/alembic upgrade head
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

```bash
cd apps/api
.venv/bin/python -m app.modules.admin.catalog_jobs
```

## 图鉴操作

1. 在组合、艺人、专辑／活动／系列／周边页面维护上游资料，提交审核后由超级管理员发布。
2. 新建小卡，按八步向导选择组合、艺人和来源，补充基础信息、正反面图片、标签属性。
3. 可以先保存不完整草稿。提交审核时检查个人卡艺人、团卡标记、双面图片、AR 资源、来源归属、上游发布状态、图片来源链接与版权。
4. 超级管理员审核发布或填写原因驳回；已发布内容需要下架后编辑、重新审核。归档可恢复为草稿。
5. App 公开图鉴仅展示已发布小卡；下架小卡仍可参与已建立索引的扫描匹配，并返回 `OFFLINE`。

正反面各自保存来源与版权信息。替换图片或修改对应来源会记录版本；来源异常列表可跳回编辑页。现有历史数据可能缺少授权资料，重新审核发布时需补齐。

上传支持 JPEG / PNG / WebP，单张最多 10 MB，解码上限 4,000 万像素。服务端移除 EXIF，输出 WebP 原图（最长边不超过 5,000）、1,200 中图和 360 缩略图。没有提供授权照片的示例卡片会显示「图片待上传」。

## 批量导入

从每个图鉴列表点击「批量导入」，或在统一导入页选择小卡、组合、艺人、专辑、活动、合集、周边。下载该类型的 CSV 或 Excel 模板。支持 UTF-8 CSV、`.xlsx`，最多 5 MB / 2,000 行；首行为字段名，错误行号包含表头。标签以 `|` 分隔，布尔值填写 `true` / `false`。

非小卡以 `name` 为必填列。艺人可独立 Solo；发行来源至少关联组合或艺人，也可通过 `artists` JSON 数组表达合作。组合 + 艺人联合导入使用独立模板。检查文件与数据库重复，不覆盖已有记录；日期支持 `YYYY-MM-DD` 和 Excel 日期。预览可逐行修正、跳过，确认后写入草稿。

`group_id`、`idol_id`、`source_entity_id` 使用后台真实 ID。来源类型支持 `ALBUM`、`EVENT`、`COLLECTION`、`MERCHANDISE`、`OTHER`。上传文件只校验；确认后才保存草稿。有错误时必须明确勾选跳过错误行；再次确认同一任务不会重复导入。导入记录仍需提交审核。

当前不是图片 ZIP 批量导入工具。图片需先上传或使用有效 HTTP(S) 地址；外部 URL 不会自动抓取并建 AI 索引，需将图片导入当前配置的存储。

## 代码结构

```text
src/api/                  API 调用、会话、类型
src/components/           状态、图片上传、App 预览、通用容器
src/pages/Cards.tsx        小卡列表、批量操作
src/pages/CardEditor.tsx   八步编辑向导
src/pages/Entities.tsx     组合、艺人及来源对象
src/pages/CatalogDetail.tsx 实体档案、关联、素材与历史
src/pages/RecordManager.tsx 版本、来源、经历、公司与批次
src/pages/CatalogWorkbench.tsx 批量编辑、图片、审核、合并与索引
src/pages/Imports.tsx      导入预检与确认
src/pages/Sources.tsx      来源异常
src/pages/Operations.tsx   动态、翻卡、消息、用户运营
src/pages/DigitalAlbums.tsx 数字相册、公开限制、额度与系统素材
src/pages/AdminUsers.tsx   管理员账号
src/pages/System.tsx       权限说明、审计日志
tests/                    字段校验与浏览器流程
```

后台 API 位于 `apps/api/app/modules/admin/`；新增表定义位于 `apps/api/app/admin_models.py`。API 路径前缀为 `/api/v1/admin/console`，契约见根目录 `contracts/openapi/`。

## 检查与构建

在 `apps/admin` 中执行：

```bash
npm run lint
npm run test
npm run build
npx playwright install chromium
npm run test:e2e
```

浏览器测试每次使用独立目录 `.test-data/run-*/admin-e2e.db`，API 8011、前端 5174，不写入日常开发数据库，也不复用旧测试库结构。默认使用 `../api/.venv/bin/python`，可通过 `API_PYTHON` 指定。已有兼容 Chromium 时可指定 `PLAYWRIGHT_EXECUTABLE_PATH`。测试会保留独立演示数据，失败时保存截图和 Trace。

后端检查在 `apps/api` 执行：

```bash
.venv/bin/ruff check app tests migrations --exclude vendor
.venv/bin/pytest
.venv/bin/alembic check
```

构建输出 `apps/admin/dist`。根目录 Compose 已包含 Nginx 后台和索引 Worker，启动命令为 `docker compose up --build`；Nginx 转发 API 并支持前端路由刷新。本机没有 Docker，镜像运行尚未实测。Compose 含演示凭据，不能直接作为生产配置。


专辑新版模板使用 `name` 填作品名称，`versions` 填版本名称、`artist_names` 填多个组合或个人名称，多个值以 `|` 分隔。同名且参与艺人集合一致的版本行归入一个父专辑；追加导入保留原父专辑资料，重复版本报错。已确认旧数据归并及完整映射见 [专辑版本更新](../../docs/CATALOG_ALBUM_VERSIONS_20261011.md)。App 展示逻辑留待后续。


小卡管理的「上传识别」可上传单张正面卡图，匹配后进入原记录，未匹配自动携图进入新增表单；资料与版权手动补充后保存。公司管理新增「批量导入公司」，CSV / XLSX 模板为 `name,description`，导入公司可在组合 / 艺人资料关联。详情及数据补齐策略见 [说明](../../docs/CATALOG_RECOGNITION_COMPANIES_20261011.md)。


小卡「上传识别」及编辑器的正反面上传会先自动框选小卡，支持拖动四角、移动选区、数值 / 键盘微调、恢复自动范围与保留整图；确认后裁掉背景并校正透视，再识别或上传。现有卡图不批量改写，无数据迁移。详见 [裁剪说明](../../docs/CATALOG_CARD_CROPPING_20261011.md)。

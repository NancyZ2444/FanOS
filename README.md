# Fan OS · Phase 1

Fan OS 已形成可独立运行的 Flutter + FastAPI 完整项目。移动端继续支持 Mock
演示，也可通过标准 REST/OpenAPI 切换真实后端；后端默认使用虚构组合、艺人、小卡、
用户和本命动态 Seed，不包含未授权真人素材。

现已新增 Phase 1 运营后台，优先打通图鉴录入、图片来源管理、审核发布和批量导入。
后台连接真实 API 与数据库。交付范围和待办见 [后台项目情况说明](docs/ADMIN_PHASE1_STATUS.md)，
安装与使用见 [后台 README](apps/admin/README.md)。

最新移动端版本为 **1.0.2（2026101201）**。头像优化、iOS 模拟器与 Android 测试包、真实后端连接方式见 [双端交付说明](docs/MOBILE_RELEASE_20261012.md)。

已安装依赖时，可在项目根目录执行 `bash scripts/dev-admin.sh`，然后打开
[后台管理界面](http://127.0.0.1:5173)。开发管理员为 `13900000000`，验证码 `123456`。

## 项目结构

```text
apps/mobile/             Flutter iOS / Android App
apps/admin/              React / TypeScript / Ant Design 运营后台
apps/api/                FastAPI、SQLAlchemy、Alembic、AI Scan
apps/crawler-worker/     第三方公开动态定时同步 Worker
assets/import/cards/     官方小卡照片手动导入目录
contracts/openapi/       OpenAPI 3 契约（JSON / YAML）
contracts/events/        Phase 2/3 版本化领域事件契约
database/docs/           数据字典
deploy/docker/           API / Worker / Admin 镜像
deploy/nginx/            后台静态站点与同源 API 代理
docs/architecture/       后端架构说明
docker-compose.yml       PostgreSQL、Redis、MinIO、API、后台及两个 Worker
```

## 一键启动完整后端

已安装 Docker 的环境，在项目根目录执行：

```bash
docker compose up --build
```

服务入口：

- API：`http://localhost:8000/api/v1`
- Admin：`http://localhost:5173`
- Swagger：`http://localhost:8000/docs`
- Health：`http://localhost:8000/health`
- MinIO Console：`http://localhost:9001`

开发手机号验证码固定为 `123456`。普通演示账号为 `13800000000`，管理员账号为
`13900000000`。这些值只用于本地开发。生产模式拒绝开发登录，需接入真实短信／OAuth，
并更换密钥、关闭自动演示数据。当前机器未安装 Docker，镜像配置尚未实机验证。

没有 Docker 时，API 可使用 SQLite 独立启动：

```bash
cd apps/api
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev,ai]'
alembic upgrade head
python -m app.seed_cli
uvicorn app.main:app --reload
```

## Flutter 连接后端

```bash
cd apps/mobile
flutter run \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

iOS 模拟器可使用 `127.0.0.1`。Android Emulator 应把地址改为
`http://10.0.2.2:8000/api/v1`。不传 `USE_MOCK_API=false` 时，App 继续使用内置
Mock 数据。

## AI Scan 与素材

AI Scan 当前通过真实卡面特征与几何校验（OpenCV SIFT + RANSAC）识别图鉴中已建库
的小卡，支持单卡、多卡、独立未知结果、手动选卡、批量收藏与防重复提交。无索引
不会返回模拟匹配。用户提供的 `card-matcher` 和 ONNX 文件仍隔离保留在
`apps/api/app/integrations/card_matcher/vendor/`，不使用人物/表情相似度冒充具体卡版匹配。

已获授权的小卡正面照片请放到 `assets/import/cards/`。目录结构、当前虚构 Card ID
以及导入命令见该目录的 README；导入会同步更新对象存储、数据库图片地址和 AI
卡面特征索引。旧安装升级需运行数据库迁移，并重建已有卡图索引。启用步骤、已测
范围和真机测试限制见 [AI Scan 验证与使用](docs/AI_SCAN_VERIFICATION.md)。

## 主要文档

- [来源收敛、Tag 管理、用户补充与数据升级](docs/CATALOG_TAXONOMY_TAGS_20261011.md)

- [数字相册功能、API、数据兼容与验证](docs/DIGITAL_ALBUM_2026_10_11.md)
- [后台项目情况、交付范围与待办](docs/ADMIN_PHASE1_STATUS.md)
- [后台启动与使用](apps/admin/README.md)
- [图鉴批量操作与表格导入](docs/CATALOG_BULK_OPERATIONS.md)
- [验证记录](docs/VERIFICATION.md)
- [AI Scan 验证与使用](docs/AI_SCAN_VERIFICATION.md)
- [API 使用说明](apps/api/README.md)
- [后端架构](docs/architecture/BACKEND.md)
- [Phase 2/3 社区与实时聊天演进](docs/architecture/PHASE2_PHASE3_EVOLUTION.md)
- [数据字典](database/docs/DATA_DICTIONARY.md)
- [小卡素材导入](assets/import/cards/README.md)
- [OpenAPI YAML](contracts/openapi/fan-os-v1.yaml)

最新 iOS Simulator 测试包位于
`output/releases/FanOS-iOS-Simulator-1.0.1-2026101103.zip`。该包包含扫描批量处理、官方来源反馈及封面文字红屏修复，使用真实 API
模式，默认连接 `http://127.0.0.1:8000/api/v1`，运行前请先启动本地后端。
修复原因与回归结果见 [封面文字保存修复](docs/BUGFIX_ALBUM_TEXT_20261011.md)。
新版扫描交互与操作定义见 [扫描结果批量处理和反馈来源](docs/SCAN_INTERACTIONS_20261011.md)。

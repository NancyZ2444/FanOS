# 数字相册交付与验证 · 2026-10-11

本次实现以《Fan OS 相册功能 PRD V1.0》及 Figma「Photo Album」为依据，延续 Fan OS 的浅色、雾紫、简约风格。数字相册引用官方图鉴的小卡，不是上传私人照片的相册，也不会增加或减少 Owned / Wishlist。原个人主页照片功能保留，标签明确区分为「照片」与「卡册」。

## 已实现的用户流程

- 从收藏／个人主页「卡册」进入书架；支持书架／列表、搜索、排序、刷新、分页、我创建的／我收藏的、五种书架主题。
- 创建默认私密草稿，选择单面／双面翻页、真实卡册／极简数字风格。正常用户默认最多 10 本、每本 10 个实际内页；PRO 默认 30 本、20 个实际内页。双面展示不额外消耗页数，封面不计内页。
- 封面允许一张官方小卡，支持文字、Emoji、系统符号贴纸、背景、图层、移动、缩放、旋转、复制、撤销和重做。页面支持 1–9 个固定卡位，小卡完整显示、不按容器裁切。
- 官方选卡支持搜索、组合、艺人、来源类型、来源、已拥有、仅本命筛选；默认本命优先。允许未拥有小卡与重复卡；每个放置实例有独立 Slot ID。
- 页面管理支持新增、复制、删除、清空和拖动排序；缩减布局要求确认，移出的卡进入本地待放置区，避免静默丢失。
- 编辑时自动保存；断网保留账号隔离的磁盘草稿，可重试。版本冲突不覆盖服务器内容，选择重新加载时先保存本地备份。
- 阅读支持封面、单面／双面翻页、目录、真实／极简风格。点小卡打开正反面预览，再进入官方详情；关闭预览保留阅读位置。
- 卡片模式支持立体轮播、自定义 Slot 顺序、关键卡面和独立背景，不改变内页顺序。
- 「完成」发布当前快照，私密／公开可调整。之后编辑自动保存的版本不会立刻替换访客看到的已发布快照。
- 公开作品支持赞、收藏引用、取消、举报、访问作者、分享链接；私密／删除后收藏显示不可访问，仍可取消。作者不能赞或收藏自己的作品。
- `fanos://app/digital-albums/{id}` 已注册 iOS／Android Scheme；实际内容读取仍通过 API 权限校验。

## 后端、后台与数据兼容

新增 `app/modules/albums/`，与图鉴、收藏、用户关系模块分离。迁移 `a611_digital_albums` 在既有 `card_albums` 上增加草稿／发布快照、revision 与展示配置，并新增页面、卡位、互动、偏好、权益、配置和系统素材表。

旧卡册兼容读取；旧关系首次写入时转换为稳定的页面／卡位实例。替换官方小卡、人工合并和删除预检同时检查卡位、封面与发布快照引用。后台版权下架后 API 会重新过滤小卡正反面，不依赖客户端缓存继续展示。恢复本地草稿时重新获取素材可用性；无法联网校验时保留布局，暂不显示缓存的官方照片。

写入均携带 `revision`，冲突返回 409；容量由服务端校验。PRO 到期保留已有作品与超额页，允许编辑／排序／删除，但不允许继续增加超额容量。互动具备唯一约束与幂等性。公开切换／发布检查文字规则与运营限制。

后台新增「数字相册」，支持按作品／作者／日期／状态查询、查看页面和卡位、限制／恢复公开、维护额度与拦截词、手动授予 PRO、维护系统主题／背景／贴纸；操作记录审计。配置与权益需要管理员权限。管理列表最多查询最近 200 本，可通过条件缩小范围。

主要接口（根路径 `/api/v1`）：

| 用途 | 路径 |
| --- | --- |
| 列表、创建、详情、更新、删除 | `/albums`、`/albums/{id}` |
| 额度、系统素材、素材版权校验、偏好 | `/albums/quota`、`/albums/resources`、`/albums/card-assets`、`/albums/preferences` |
| 发布、复制、预览 | `/albums/{id}/publish`、`/duplicate`、`/preview` |
| 页面、顺序、卡位 | `/albums/{id}/pages`、`/pages/reorder`、`/pages/{page_id}/slots` |
| 封面、展示、卡片模式、权限 | `/albums/{id}/cover`、`/display`、`/card-view`、`/visibility` |
| 赞、收藏、举报 | `/albums/{id}/like`、`/favorite`、`/report` |
| 他人作品、收藏引用 | `/users/{id}/albums`、`/users/me/favorite-albums` |
| 管理、配置、系统素材、权益 | `/admin/console/digital-albums`、`/album-settings`、`/album-resources/{id}`、`/album-entitlements/{user_id}` |

完整请求／响应见 `contracts/openapi/fan-os-v1.yaml`。相册编辑 UI 采用整体 PATCH 原子保存，细粒度页面接口保留给其他客户端。

## 现有数据保护

实际开发数据库升级前备份：`apps/api/data/backups/fan_os_before_digital_albums_20261011.db`。升级前后 9 个组合、53 位艺人、8 张小卡、3 本旧卡册数量一致；没有重置数据库、重新 Seed 或替换已上传照片。Alembic 已到新 head，结构检查无待生成迁移。

本地草稿位于 App Application Support 下的 `digital-albums/account-{用户ID}/`，包含草稿及发生冲突后保留的备份，不包含登录令牌。草稿写入采用 flush、临时文件与原子替换，防止界面退出后只剩内存状态。

## 验证记录

- 后端全量 117 项 pytest 通过，新增 12 项数字相册测试；覆盖配额／会员到期、重复实例、版本冲突、页面编辑、发布快照、公开权限、版权隐藏、互动幂等、运营限制和卡片合并。Ruff、Alembic check 通过；OpenAPI 已导出。
- Flutter 全量 56 项单元／组件测试通过，两个需主动开启的网络契约测试在普通运行中跳过；包含 11 项数字相册测试，覆盖 1–9 布局、主要手机画面、磁盘草稿、账号隔离、断网重试、保存中继续修改、冲突备份、撤销／重做、返回与关闭预览。Dart 静态检查通过。
- Flutter Repository 对真实 FastAPI 的独立契约测试通过。测试 API 使用 `output/album-qa/contract.db`、端口 18001，不写入端口 8000 的开发数据库。
- 后台 ESLint、TypeScript、生产构建、7 项 Vitest 通过；新增 Playwright 相册管理流程通过，覆盖公开限制／恢复、详情、额度、系统素材。既有约 1.60 MB JS chunk 警告仍在，不等同于构建失败。
- iPhone 16 Pro / iOS 18.6 原生操作回归通过：UI 新建相册 → 封面选卡 → 新增内页 → 内页官方选卡 → 完成保存／发布 → 翻页 → 小卡预览／关闭后位置保留 → 卡片轮播。验证服务器实际保存一页、一张小卡，状态已发布且仍为私密。测试结束清除本次作品；没有修改原开发数据库。
- UI 截图保存在 `output/album-qa/`。Figma 成功读取 15 个主画面的上下文和截图；另外 5 个辅助画面受连接额度限制，使用 PRD 与已读设计组件补齐，未宣称完整逐像素核对整个文件。

复跑模拟器端测试（先启动仅用于测试的 18001 API）：

```bash
cd apps/mobile
flutter drive --no-pub \
  --driver=test_driver/album_driver.dart \
  --target=integration_test/digital_album_flow_test.dart \
  -d E91E6A61-DFDE-448D-940B-2B7EFDC9E1E8 \
  --dart-define=RUN_ALBUM_NATIVE_E2E=true \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:18001/api/v1 \
  --dart-define=INITIAL_ROUTE=/digital-albums/new
```

该测试明确拒绝写入其他 API 地址，使用独立草稿目录，结束时删除自己的测试作品。普通 `flutter test` 不运行此设备测试。测试版本与普通 App 是同一 Bundle ID，测试后必须重新编译／安装连接 8000 的正常版本，不能将测试 bundle 作为交付。

## 明确未接入的范围

PRO 支付／订阅尚未接入，目前由后台维护权益；封面在客户端实时绘制矢量配置，尚未增加 Worker 生成静态封面缩略图。公开内容审核为后台复核和可配置拦截词，不是外部版权／内容识别平台。未增加用户上传小卡、贴纸、音乐、海报等 PRD 外功能，也未宣称完成 PostgreSQL 并发压测、生产部署、真机／TestFlight 验证。

## iOS 模拟器交付

最新修复版为 **1.0.1（2026101102）**，包含封面文字保存红屏修复，已替换本机安装。新安装包为 `output/releases/FanOS-iOS-Simulator-1.0.1-2026101102.zip`；详细回归结果见 [修复说明](BUGFIX_ALBUM_TEXT_20261011.md)。以下保留首轮相册交付包的校验记录。

已重新编译并安装普通版至本机 **iPhone 16 Pro / iOS 18.6**，版本 **1.0.1 (2026101101)**，Bundle ID `com.fanos.app`。保留 App 数据，没有卸载／重置模拟器。最后启动截图为 `output/album-qa/ios-final-installed.png`。

安装包：`output/releases/FanOS-iOS-Simulator-1.0.1-2026101101.zip`，内含 `Runner.app`。Runner、App.framework、Flutter.framework 均为 **arm64 + x86_64**；代码签名和 ZIP 完整性校验通过。SHA-256：

```text
e704351efe752404f1bdc406de41e36c07290db8a047d57cc6180873c5f33554
```

普通版使用真实 API `http://127.0.0.1:8000/api/v1`，不包含测试的 `INITIAL_ROUTE`／18001 地址。API 8000 和后台 5173 已保留运行，临时测试 API 18001 已停止。登录本地开发账号 `13800000000`、验证码 `123456`，从「我的／收藏 → 卡册」体验；该验证码不适用于生产。

其他模拟器使用方式：解压安装包，启动目标模拟器后执行以下命令（替换 `.app` 的实际位置）：

```bash
xcrun simctl install booted /absolute/path/Runner.app
xcrun simctl launch booted com.fanos.app
```

这是本机调试用 Simulator Debug 包，不可安装到实体 iPhone。实体机／TestFlight 需要另外的签名与打包流程。

## 主要代码

- `apps/mobile/lib/features/albums/`：数据接口、模型、草稿存储、编辑状态、书架、编辑器、选卡与阅读器。
- `apps/api/app/modules/albums/`、`apps/api/app/album_models.py`：独立相册业务与数据模型。
- `apps/api/migrations/versions/a611_digital_albums.py`：向前兼容数据迁移。
- `apps/admin/src/pages/DigitalAlbums.tsx`：后台作品、额度与系统素材管理。
- `apps/mobile/assets/album/icons/`：设计图中使用的 SVG 图标；官方照片始终来自现有图鉴 API。
- `apps/mobile/integration_test/digital_album_flow_test.dart`：隔离数据库的 iOS 操作回归测试。

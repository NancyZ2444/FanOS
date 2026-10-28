# 数字相册 P0 本地交付说明

日期：2026-10-20。范围：用户确认的 Q1–Q7，以及《后台管理—数字相册运营管理 PRD》的 P0。后台、API、App 已联动更新；本次只在本地运行，未提交 Git、推送、更新云服务器或发布商店版本。

实施前对照与决策依据见 [差异确认记录](ADMIN_DIGITAL_ALBUMS_P0_GAPS_20261020.md)。附件仅作为产品资料；实施范围由用户确认确定。

## 1. 本地验证入口

| 对象 | 入口 / 状态 |
| --- | --- |
| 后台构建版本 | http://127.0.0.1:5173/digital-albums |
| API | http://127.0.0.1:8000/api/v1 |
| 接口文档 | http://127.0.0.1:8000/docs |
| 健康检查 | http://127.0.0.1:8000/health |
| 后台本地管理员 | `13900000000`，本次运行验证码 `666666` |
| App 本地普通账号 | `13800000000`，验证码 `666666` |
| iOS 模拟器 | iPhone 16 Pro / iOS 18.6，已安装并启动 |
| App 构建 | `1.0.14 (2026102002)`，真实 API 模式，连接 `127.0.0.1:8000/api/v1`；含下方登录启动修复 |

后台使用 `npm run preview` 运行已通过生产构建的产物，不显示开发模式的“填入账号”按钮。该机器 API 配置使用 `666666`；旧 README 中的 Docker 示例验证码 `123456` 不适用于本次运行。

模拟器包：`apps/mobile/build/ios/iphonesimulator/Runner.app`。安装保留原 App 数据；没有卸载应用，没有生成 Android 包，也没有替换远端版本。

服务退出后的启动方式（当前数据库已升级，无需再次 stamp）：

```bash
# 终端一，项目根目录
cd apps/api
AUTO_SEED=false .venv/bin/python -m alembic upgrade head
AUTO_SEED=false .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

# 终端二，项目根目录
cd apps/admin
npm run build
npm run preview -- --host 127.0.0.1 --port 5173 --strictPort
```

## 2. 已完成的业务能力

| 页面 / 模块 | 本次更新 |
| --- | --- |
| 后台 → 数字相册 → 作品管理 | 保留筛选与列表，统一查看 / 更多操作、中文状态、时间和空状态 |
| 作品详情 | 重新获取详情；已发布作品默认预览发布快照，未发布作品预览编辑内容；显示书架、封面、内页、文字、图片 / 符号贴纸、画笔、背景、卡位、单双页、缩略图、缩放及小卡正背面 |
| 作品处理 | 区分限制公开、下架、恢复；原因分类与备注；查看关联举报，明确选择要结案的举报；按业务名称展示日志 |
| 复核 | 作者修改并保存后提交不可变复核快照；后台查看待复核内容、恢复或驳回；避免处理尚未加载的复核内容 |
| 额度与会员 | 保留现有普通 / PRO 相册数、页数及授权；增加日 / 月取色配置；降低额度先展示影响及前后值，取消不改配置 |
| 主题与系统素材 | 书架、背景、颜色、贴纸；可视化新增 / 编辑、图片上传和预览、场景、排序、会员范围、锁定预览、草稿 / 上架 / 下架 |
| 素材删除 | 新增 ID 重复报错；只允许删除从未上架且从未使用的草稿，内置素材不可删除；有历史使用的素材通过下架停止新增 |
| App 编辑器与书架 | 接入上架素材、图片渲染、场景过滤、PRO 锁定预览；贴纸继续仅用于封面，保留已有颜色 / 渐变 / 符号 |
| App 图片取色 | 从本机照片或可用官方小卡提取颜色，展示日 / 月余额，选择结果应用到颜色；失败不扣次，重试复用请求 ID |
| App 作品状态 | 显示限制、下架、复核及待重新发布提示；受限仍可保存修改；复核后由作者主动发布 |

后台复用已有设计变量和 Ant Design 公共组件，新增相册内部的 `AlbumPreview`、`AlbumDetail`、`AlbumSettings`、`ResourceManager` 模块。没有逐个页面添加不同尺寸标准。

### 发布与复核规则

- 正常、限制公开、下架与作者自己的草稿 / 已发布、公开 / 私密状态分别保存。
- 限制公开和下架均阻止他人访问及分享；作者可以继续编辑和保存完整表单。
- 复核请求保存提交当时的快照，后续编辑不会替换已经提交的内容。
- 运营恢复后标记为“待作者重新发布”，不会自动展示旧违规快照，也不替作者发布最新编辑。
- 作者主动发布后，公开访问恢复；恢复不会把私密作品变公开，不会复活已删除作品。
- 受限作品不能通过复制绕过处理。公开列表、详情、收藏和搜索均遵循限制。

### 素材与历史规则

- 类型为 `SHELF / BACKGROUND / COLOR / STICKER`，会员范围为 `ALL / PRO`。
- 背景支持封面 / 内页 / 两者。封面专用背景不会被同步到卡片轮播展示。
- 历史实例保存必要的渲染快照；素材下架、替换文件或会员到期，不直接改变已保存的视觉。
- 已有不可用素材可以保留和调整原实例；不能新增同款实例，删除保存后不能重新添加。
- 整本及内页复制视为新增使用：含下架或无权使用的 PRO 素材时阻止复制，并返回原因。
- 图片上传至受管理存储并保留透明度。贴纸接受 PNG / WebP，书架和背景另支持 JPG；上传上限 10 MB。
- 非会员按配置看到 PRO 锁定预览，点击提示会员要求；本次没有增加支付购买流程。

### 取色规则

| 权益 | 普通 | PRO |
| --- | ---: | ---: |
| 每日初始额度 | 3 | 30 |
| 每月初始额度 | 20 | 300 |

按 `Asia/Shanghai` 的日历日、自然月计算。只记录成功结果；无效图片、透明空图片和接口失败不扣次。相同用户与请求 ID 重试返回原结果；数据库锁防止并发超扣。应用已获得的颜色不重复分析。

本机照片只用于分析，不保存为图鉴图片。官方小卡必须当前可用且图片已经进入受管理存储；未入库的远程图片返回具体提示，可改用本机照片，失败不扣次。照片最大 15 MB / 2400 万像素。

## 3. 本地数据升级

原数据库：`apps/api/data/fan_os.db`。先创建一致性备份，再在副本演练，最后才升级真实本地库。

- 备份：[fan_os-before-20261020-190952.db](../output/digital-albums-p0-20261020/backups/fan_os-before-20261020-190952.db)。备份权限为仅当前用户可读写。
- 新迁移：[h620_album_operations.py](../apps/api/migrations/versions/h620_album_operations.py)。
- 结果：[本地迁移核验](../output/digital-albums-p0-20261020/local-migration-result.json)。
- 原有 **10 本相册保留**；逐条对照 ID、作者 ID、名称、说明、状态、公开设置、revision、创建时间和发布时间均一致。
- 旧 `is_moderated=true` 映射为限制公开，原日志继续保留。
- 增加复核、取色记录和必要字段；补齐历史素材 / 默认书架快照，不重置相册 / 页数额度，不删除现有内容。
- 外键检查无违规，SQLite `integrity_check=ok`。本次未发现需要人工恢复的缺失素材。
- 本地真实 API 的健康、管理员登录、10 本相册列表、额度配置读取均返回 200。

### 本机既有迁移历史修正

该库升级前的 Alembic 版本为 `e612_color_bigint`，但此前启动时已通过 ORM 创建了 `f614` / `g614` 的六张表。直接重放会报表已存在。

本次先将六张表的列、类型、非空、主键、外键、唯一约束和索引与全新迁移至 `g614_feedback_workflow` 的参考库逐项比较，全部一致后才把历史标记对齐到 `g614`，然后执行 `h620`。校验记录：[schema 核验](../output/digital-albums-p0-20261020/local-schema-check.json)。

此修正仅适用于已核验的本地库；不得在其他环境盲目执行 `alembic stamp`。未来升级其他环境，应先备份并检查实际迁移版本，再按正常迁移链升级。

### 回退

需要回退时先停止本地 API，另行保存升级后新录入的数据，再恢复升级前备份并配套使用升级前代码。新代码依赖新增列，不能只把数据库换回旧版而继续运行新 API。新增上传文件不被本次迁移删除。

## 4. 验证结果

| 验证 | 结果 / 覆盖 |
| --- | --- |
| API | 46 项通过：P0、取色、原数字相册、收藏分组、结构规范化；含并发、幂等、额度边界、历史素材、复核和发布限制 |
| App | 37 项通过：24 项已有回归、11 项 P0 单元 / 交互、2 项真实本地 API 契约 |
| 后台浏览器 | 新 P0 6 项通过，原综合回归 1 项通过；新增 / 校验 / 上传 / 编辑回填与保存 / 取消 / 删除确认 / 限制 / 复核 / 额度降低 / 空状态 |
| 后台布局 | 1280 / 1440 / 1920，三个 Tab 均无页面级横向溢出；主要操作控件 36px |
| 静态与构建 | API Ruff、后台 TypeScript / 相关 ESLint / 生产构建、Flutter analyze 均通过；iOS 模拟器构建安装及启动成功 |
| 数据 | 副本与真实本地库升级、原相册字段对照、外键与完整性检查通过 |

浏览器测试最初命中了 Ant Design 隐藏的辅助输入 / option，已改为点击可见选择器和下拉项；最后分别复验新 6 项和旧 1 项均通过。失败尝试保留在日志，不作为通过证据。没有用实际本地业务库执行新增 / 删除验收；测试采用隔离数据库。

测试入口：

```bash
# apps/api
.venv/bin/python -m pytest tests/test_album_color_extraction.py \
  tests/test_album_p0_backend.py tests/test_digital_albums.py \
  tests/test_album_favorite_groups.py tests/test_album_normalization.py \
  --override-ini addopts='' -q

# apps/admin；自动启动隔离 API 和 Vite
npx playwright test --config playwright.albums-p0.config.ts
```

App 测试命令如下。真实契约须连接独立、已初始化的 `18001` 测试 API，验证码 `666666`；不得对本地业务库或生产库运行。两个契约串行执行，避免共享会员状态干扰。

```bash
# apps/mobile
flutter test --no-pub --concurrency=1 \
  --dart-define=RUN_ALBUM_API_CONTRACT=true \
  test/album_api_contract_test.dart test/album_p0_api_contract_test.dart \
  test/album_p0_test.dart test/digital_album_test.dart \
  test/album_card_scene_test.dart test/album_favorite_groups_test.dart
flutter analyze --no-pub
```

App 结果为 `37: All tests passed!`，分析为 `No issues found!`；未额外保存独立日志文件。验收后已关闭隔离测试 API，保留用户验证所用的 `8000` / `5173` 服务。

证据：[API JUnit](../output/digital-albums-p0-20261020/api-junit.xml)、[新浏览器 6 项结果](../output/digital-albums-p0-20261020/admin-e2e-final.log)、[旧浏览器 1 项复验](../output/digital-albums-p0-20261020/admin-legacy-e2e-final.log)、[本地 API 检查](../output/digital-albums-p0-20261020/local-api-smoke.json)。

原生系统照片选择器的人工点击尚未验收：当前电脑控制权限未开放。照片上传分析接口、客户端请求、失败重试及颜色选择交互已经测试；模拟器正常包已安装启动，用户可继续实际选择照片验证。未将此描述为已完成真机全流程验收。

## 5. 页面及前后截图

截图使用隔离演示数据，保存在本地忽略目录 `output/digital-albums-p0-20261020`，不包含真实本地用户作品。

| 页面 | 修改前 | 修改后 |
| --- | --- | --- |
| 作品列表 | [1440](../output/digital-albums-p0-20261020/before/works-1440.png) | [1440](../output/digital-albums-p0-20261020/after/works-1440.png) |
| 作品详情 | [1440](../output/digital-albums-p0-20261020/before/detail-1440.png) | [完整预览](../output/digital-albums-p0-20261020/after/work-preview-1440.png)、[内页](../output/digital-albums-p0-20261020/after/work-pages-1440.png)、[复核](../output/digital-albums-p0-20261020/after/review-1440.png) |
| 额度与会员 | [1440](../output/digital-albums-p0-20261020/before/benefits-1440.png) | [矩阵](../output/digital-albums-p0-20261020/after/benefits-1440.png)、[降低确认](../output/digital-albums-p0-20261020/after/quota-impact-1440.png) |
| 素材管理 | [1440](../output/digital-albums-p0-20261020/before/materials-1440.png) | [列表](../output/digital-albums-p0-20261020/after/materials-1440.png)、[图片表单](../output/digital-albums-p0-20261020/after/material-form-1440.png)、[空状态](../output/digital-albums-p0-20261020/after/material-empty-1440.png) |
| 1280 宽度 | — | [作品](../output/digital-albums-p0-20261020/after/works-1280.png)、[额度](../output/digital-albums-p0-20261020/after/benefits-1280.png)、[素材](../output/digital-albums-p0-20261020/after/materials-1280.png) |
| 1920 宽度 | — | [作品](../output/digital-albums-p0-20261020/after/works-1920.png)、[额度](../output/digital-albums-p0-20261020/after/benefits-1920.png)、[素材](../output/digital-albums-p0-20261020/after/materials-1920.png) |

## 6. 建议的本地验收顺序

1. 后台打开现有作品，查看完整封面 / 内页、预览版本、缩略图和小卡。
2. 新建一个草稿图片素材，预览、保存、编辑，再上架；App 打开对应选择器检查显示。贴纸从封面选择，背景按场景筛选。
3. App 从一张照片取色，确认成功后余额减一，应用颜色不再扣次。
4. 用测试作品验证限制公开 → 作者编辑并保存 → 申请复核 → 后台查看提交内容 → 恢复 → 作者重新发布。
5. 对测试素材下架，检查已有实例保持原视觉、新增选择不再提供；包含不可用素材的复制应被阻止。
6. 调低权益时检查影响确认，先取消核对配置不变，再按需要确认。

## 7. 本次边界

保留普通 / PRO 两级和现有角色边界；不增加付款、会员等级管理、内页自由贴纸编辑、P1 通用编辑 / 发布双版本对比、独立用量查询、素材 Tag、定时上下架、运营通知、版权管理或 P2 Dashboard / 素材版本界面。

相册列表沿用现有服务端最近 200 条上限并展示提示；本次未宣称完成全量运营报表。字体、表情和画笔的浏览器 / 系统渲染可能存在细微差异，后台预览使用相同数据与布局规则。

## 8. 模拟器“无法连接”修复

首次交付的 `2026102001` 包使用 `--no-codesign` 构建。虽然进程已启动、本地 API 健康，App 在恢复登录之前读取 Keychain 就返回 `-34018 / A required entitlement isn't present`，请求未到达 API。启动页把全部异常统一显示成网络错误；游客入口也未捕获凭据清理异常。

修复措施：

- 使用正常签名流程重新构建 `2026102002`，保留 Xcode 对模拟器的应用身份及 Keychain 权限处理；不删除用户凭据，不改为明文存储，不修改服务端数据。
- 启动页区分安全存储、网络、服务及未知错误，给出相应提示；游客入口捕获异常并阻止重复操作。
- 新增原生测试，使用单独 Keychain 键验证读写删除，并对默认凭据键只读检查；随后验证真实 API 及实际 App 启动流程。

补充验证：

- 登录错误提示与凭据持久化 **12 项通过**。
- iPhone 16 Pro 原生 Keychain / API / 正常启动 **2 项通过**；启动不再卡在“重新连接”。
- Flutter 静态检查通过。
- 证据：[原生测试](../output/digital-albums-p0-20261020/native-connection-smoke.log)、[登录回归](../output/digital-albums-p0-20261020/login-recovery-tests.log)、[静态检查](../output/digital-albums-p0-20261020/login-fix-analyze.log)、[修复包构建](../output/digital-albums-p0-20261020/ios-login-fix-build.log)。

复现构建命令见 [App README](../apps/mobile/README.md)。此前“进程正常”仅是进程检查，不等于本轮新增的原生登录启动验收。

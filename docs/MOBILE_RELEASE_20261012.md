# Fan OS 1.0.2（2026101201）头像优化与双端安装包

## 本次范围

- 修复「选择你的本命」头像首次解码前出现空白的问题，加载中和失败时始终保留成员首字母占位。
- 公开成员新增独立 `thumbnail_url`，头像优先使用缩略图；详情原图 `image_url` 保留，不降低详情图清晰度。
- 后端生成最长边 384 px 的 WebP 缩略图。相同原图的请求复用缓存，替换上传图片后按新版本生成；只允许查询已公开的组合／成员。
- App 对这些缩略图使用磁盘缓存，7 天有效，最多 200 个文件；同一地址并发请求合并，下载失败可在重新进入页面时重试，损坏缓存会清理。
- API 返回的旧 `localhost/127.0.0.1` 上传图片地址按本次配置的服务器地址解析，Android 真机不再误连自己的 localhost。
- 两端均使用全部现有 Flutter 功能和真实 API（`USE_MOCK_API=false`），包含图鉴、Tag、收藏、扫描、数字相册、用户资料等当前已实现模块。

**用户已明确暂不处理第三方图片源限制。** 当前公开头像中 24 张已具备服务器缓存，另外 29 张继续保留原外部地址，不会被替换为不可用的缩略图。后者仍受图片源速度／限流影响；本次不宣称所有外部头像都能即时加载。

## 安装与后端

版本均为 **1.0.2（2026101201）**，应用 ID 为 `com.fanos.app`。

### iOS

安装包：`output/releases/FanOS-iOS-Simulator-1.0.2-2026101201.zip`。

这是 **Mac 上的 iOS 模拟器包**，支持 arm64 和 x86_64，延续此前交付方式；不能安装到实体 iPhone，也不是 TestFlight／IPA。API 为 `http://127.0.0.1:8000/api/v1`。

解压后安装到已启动的模拟器：

```sh
xcrun simctl install booted /完整路径/Runner.app
xcrun simctl launch booted com.fanos.app
```

本机已在 iPhone 16 Pro（iOS 18.6）模拟器覆盖安装并启动，未卸载旧应用。

### Android

安装包：`output/releases/FanOS-Android-1.0.2-2026101201.apk`（65,735,416 字节）。

已生成通用 Release APK，支持 armeabi-v7a、arm64-v8a、x86_64，Android 7.0（API 24）及以上，Target API 36。使用项目现有开发签名，供测试安装，不作为商店正式发布签名。将 APK 传到 Android 手机后安装；应用名为「Fan OS」。

连接地址：`http://192.168.0.112:8000/api/v1`。手机需与这台 Mac 在同一局域网，Mac 的开发 API 需保持运行。手机浏览器打开 `http://192.168.0.112:8000/health` 应看到正常响应。该包不是离线后端，也没有将真实服务替换为演示数据。

本机 API 已使用 `AUTO_SEED=false` 启动，监听 `0.0.0.0:8000`，保留当前数据库。若 Mac 的局域网地址变更，需使用新地址重新构建 APK。当前测试包允许 HTTP 连接；正式环境应使用 HTTPS 和正式签名。

```sh
cd apps/api
AUTO_SEED=false .venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## 数据与缓存

不需要数据库迁移；没有更改艺人／组合关系、原图地址、收藏或相册数据。新增文件只位于 `apps/api/data/uploads/catalog-thumbnails/`，属于可重新生成的缓存。

`apps/api/scripts/warm_catalog_portraits.py` 可预热已发布头像，不写数据库。远程预热默认关闭（`CATALOG_REMOTE_PORTRAITS_ENABLED=false`），已缓存远程图片仍可使用；未缓存的外部头像继续用原地址。未来处理外部来源时，再配置允许域名、符合来源规则的 `CATALOG_IMAGE_USER_AGENT` 并启用远程预热。来源要求参考 [Wikimedia User-Agent Policy](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy) 和 [标准缩略图尺寸](https://www.mediawiki.org/wiki/Common_thumbnail_sizes/en)。

## 验证记录

- 后端全量：196 项通过；新增缩略图尺寸、原图保留、缓存复用、ETag、取消公开后拒绝访问、路径安全与失败重试检查。随后追加外部来源暂缓用例，头像相关 5 项复测通过。
- App 全量：97 项通过、2 项按配置跳过；新增缓存并发合并、跨实例复用、版本变更、失败重试、占位及局域网图片地址解析检查。
- 实际服务：24 个缓存头像请求全部 200，本机响应中位数 1.63 ms；这是服务器本机测量，不代表手机端完整首屏加载时间。局域网 `/health` 返回 200。
- iOS：模拟器构建成功，Runner／App.framework／Flutter.framework 均包含 arm64 + x86_64，覆盖安装与启动成功。
- Android：Release 构建成功；APK v2 签名、ZIP CRC、16 KB ZIP 对齐、版本号、MainActivity 启动入口检查通过。三种架构均含 Flutter、App、JNI 和相机原生库，并验证各架构 App 二进制内的 API 地址正确。网络、相机、媒体访问权限已合入最终 Manifest。
- 当前没有已连接的 Android 真机；真机相机、相册权限和实际扫描体验需安装后验收。桌面 UI 自动化权限未开放，未声称完成全流程人工视觉验收。

实测明细：`output/avatar-20261012/live-verification.json`。安装包校验信息已记录在同目录的 `release-manifest.json`，Android 签名和 Manifest 信息分别见 `android-signature.txt` 与 `android-package.txt`。

SHA-256：

- iOS ZIP：`eee4e3ce14e69281aa9b7c05994aafa37ac10e3c7a3081f329f68fa730754be6`
- Android APK：`b8815826fccda4687b594268513bdd59a33e0d067fb4ee715cd7cf0b06eff6d4`

## 后续重打包

使用 Flutter 3.47.4／Dart 3.13.3；Android 使用 JDK 17、Android SDK 35 与 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1。iOS 使用 Xcode 16.4。

```sh
cd apps/mobile
flutter build ios --simulator --debug \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

flutter build apk --release \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://192.168.0.112:8000/api/v1
```

Android Release 构建保留 Flutter 的插件刷新步骤，不添加 `--no-pub`：本机在 Debug／iOS 构建后跳过刷新，会留下仅供测试使用的 `integration_test` 注册项，导致 Release 编译失败。应用的正常相机、选图、JNI 等插件均已打包。

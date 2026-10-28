# Fan OS Flutter App

Android/iOS 双端移动应用。项目采用 Feature First 页面组织，使用 Riverpod 管理状态、GoRouter 管理路由、Dio 作为服务端访问层。

2026-10-28 本地测试版 **1.0.14（2026102806）** 已覆盖安装并启动于 iPhone 16 Plus（iOS 18.6）。包含固定 55:85 裁剪、点图更换、横向相似推荐、默认卡背和公告/通知/反馈结果分类。使用 `http://127.0.0.1:8000/api/v1` 真实 API；验证及截图见 [本地交付说明](../../docs/ADMIN_APP_POLISH_LOCAL_20261028.md)。

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

默认运行本地 Mock Repository。真实 API 的切换方式和当前预留端点见 [`docs/API_INTEGRATION.md`](docs/API_INTEGRATION.md)。

## 本地 iOS 模拟器打包

```bash
flutter build ios --simulator \
  --target=lib/main.dart \
  --build-number=<本次构建号> \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

构建成功不代表当前打开的模拟器已更新。不同型号/UDID 的模拟器拥有独立的安装包和数据；2026-10-28 曾出现最新包安装在 iPhone 16 Pro Max，但打开的 iPhone 16 Plus 仍为 build 4 的情况。每次交付须确认目标设备并覆盖安装，不能只复用上次的 UDID：

```bash
# 先确认正在使用的设备（Booted），并检查本地服务已启动。
xcrun simctl list devices booted
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8000/api/v1/auth/capabilities

# <目标 UDID> 必须是本次确认的设备；不要使用 uninstall 或 erase。
xcrun simctl terminate <目标UDID> com.fanos.app
xcrun simctl install <目标UDID> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <目标UDID> com.fanos.app
xcrun simctl get_app_container <目标UDID> com.fanos.app app

# 使用上一步返回的已安装 App 路径，而不是工作区构建产物路径。
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '<已安装App路径>/Info.plist'
```

如果 App 未运行，`terminate` 返回未找到进程是正常情况，可继续安装。验收记录同时写明设备名称、UDID、已安装构建号和 API 地址。必须显式传入真实 API 参数；不带参数的默认 Mock 构建不是本地联调包。保留正常 `lib/main.dart` 入口，不把集成测试包或临时 `INITIAL_ROUTE` 构建作为交付版本。覆盖安装保留数据，不为解决版本问题清空登录凭证或重建数据库。

此 App 使用 Keychain 保存登录凭证，模拟器构建也应保留 Xcode 的正常签名流程。不要为可安装使用的包添加 `--no-codesign`：这会关闭签名及相关模拟器权限注入，可能导致 Keychain 返回 `-34018`，连尚未保存凭证的启动读取也会失败。只检查 App 进程与 API 健康不能证明登录恢复可用。

原生验证（本地 API 8000 已启动，将 `<device-id>` 换为目标模拟器 UDID）：

```bash
flutter test --no-pub --no-uninstall -d <device-id> \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 \
  --dart-define=RUN_LOCAL_CONNECTION_SMOKE=true \
  integration_test/local_connection_smoke_test.dart
```

测试使用独立 Keychain 键，不覆盖用户凭证；验证原生读写删除、真实 API 请求及正常启动页面。必须保留 `--no-uninstall`：Flutter 默认在集成测试结束后卸载应用，会删除模拟器 App 的本地数据容器，即使 Keychain 凭据仍可恢复。对已有用户数据的模拟器执行测试前，先备份 `xcrun simctl get_app_container <device-id> com.fanos.app data` 返回的整个目录。运行后应重新构建并覆盖安装正常 `lib/main.dart` 包，不能把测试入口包作为交付版本，也不要卸载旧 App 或清空模拟器。

## Platform baseline

- Android API 24+
- iOS 15+
- Bundle/Application ID: `com.fanos.app`

演示数据和卡面均为虚构的代码生成占位内容，不包含参考原型中的艺人照片。

个人主页 V1.1 已覆盖等级与成长值、关注/粉丝关系、他人主页、四类资产
Tab（收藏、喜欢、卡册、相册）、图库/列表切换、筛选记忆和细粒度隐私设置。
当前头像与相册使用系统图片选择器保存在本机演示状态，服务端接口仍通过标准
Repository 层预留。

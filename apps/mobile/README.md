# Fan OS Flutter App

Android/iOS 双端移动应用。项目采用 Feature First 页面组织，使用 Riverpod 管理状态、GoRouter 管理路由、Dio 作为服务端访问层。

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

默认运行本地 Mock Repository。真实 API 的切换方式和当前预留端点见 [`docs/API_INTEGRATION.md`](docs/API_INTEGRATION.md)。

## Platform baseline

- Android API 24+
- iOS 15+
- Bundle/Application ID: `com.fanos.app`

演示数据和卡面均为虚构的代码生成占位内容，不包含参考原型中的艺人照片。

个人主页 V1.1 已覆盖等级与成长值、关注/粉丝关系、他人主页、四类资产
Tab（收藏、喜欢、卡册、相册）、图库/列表切换、筛选记忆和细粒度隐私设置。
当前头像与相册使用系统图片选择器保存在本机演示状态，服务端接口仍通过标准
Repository 层预留。

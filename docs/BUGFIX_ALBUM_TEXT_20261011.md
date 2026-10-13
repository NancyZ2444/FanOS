# 封面文字保存红屏修复 · 2026-10-11

## 问题与原因

复现路径：新建相册 → 编辑封面 → 添加文字 → 输入内容（输入框仍有焦点）→ 确定／保存。

回归测试复现了同一串错误：先出现 `A TextEditingController was used after being disposed`，继而出现截图中的 `framework.dart:6281 '_dependents.isEmpty'`。后者是组件树清理时的连带断言，不是相册 API／数据错误。

原代码在 `await showDialog` 或 `await showModalBottomSheet` 返回后立刻释放输入控制器。但 `Navigator.pop` 此时只完成了结果 Future；关闭动画期间 TextField 仍在组件树中，键盘焦点变化会触发重建并再次读取已释放控制器。

## 修复

新增 `AlbumInputScope`，由弹窗内的 StatefulWidget 创建并拥有输入控制器，在弹窗真正退出组件树时统一 dispose。没有使用任意时长的延迟，也没有隐藏 Flutter 错误或关闭断言。

已应用到封面／内页文字编辑、相册名称和简介设置、背景颜色设置、书架重命名与举报输入。相册创建页自身的控制器原本就由页面 State 管理，保留原行为。

本次只修改 Flutter 输入弹层生命周期与测试；没有改 API、数据库、Owned／Wishlist、发布快照或保存格式。文字仍以原有自动保存机制持久化，取消不会覆盖已有文字。

## 验证

- 修改前，文字保存、背景保存的最小回归均复现已释放控制器及相同的 `_dependents.isEmpty` 断言。
- 修改后 Flutter 全量 **60 项测试通过**；两个需要单独开启的 API 契约测试在普通运行中跳过。新增覆盖文字保存／再次编辑、取消／点击遮罩／系统返回、背景保存、设置退出与重命名。
- Dart 静态检查通过。
- iPhone 16 Pro / iOS 18.6 原生回归通过：新建 → 新增封面文字 → 保存 → 修改文字 → 保存 → 官方选卡 → 发布 → 翻页 → 关闭小卡预览 → 卡片轮播。服务器实际保存了修改后的封面文字。
- 设备测试使用隔离 API 18001 与独立草稿目录，结束时移除自己的测试作品，没有修改真实开发库中的相册。保存及再次编辑截图位于 `output/album-qa/ios-album-text-saved.png`、`ios-album-text-updated.png`。

## 模拟器安装

修复版 **1.0.1（2026101102）** 已安装并启动于本机 iPhone 16 Pro / iOS 18.6，没有卸载 App 或重置数据。普通包连接 `http://127.0.0.1:8000/api/v1`，不包含测试入口；本次临时 API 18001 已停止，开发 API 8000 和后台 5173 保持运行。

安装包：`output/releases/FanOS-iOS-Simulator-1.0.1-2026101102.zip`。Runner、App.framework 和 Flutter.framework 均包含 arm64／x86_64；签名与 ZIP 完整性检查通过。该包仅用于 Mac 上的 iOS 模拟器，不是实体 iPhone IPA。

SHA-256：`7aedfb15f703c6414e737378726c80be5c2c525f3fd1ad08b0f58f521f44e5d8`。

## 相关代码

`apps/mobile/lib/features/albums/presentation/album_input_scope.dart` 与相册编辑／书架／阅读页面；回归位于 `apps/mobile/test/digital_album_test.dart` 和 `integration_test/digital_album_flow_test.dart`。

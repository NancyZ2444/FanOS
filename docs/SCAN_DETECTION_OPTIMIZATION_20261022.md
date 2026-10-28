# 小卡区域检测优化与验证（2026-10-22）

首轮（2026-10-22）更新扫描中的小卡定位、裁剪及人物存在性判断。当时用户确认样本卡片未收录，因此首轮未调整图鉴匹配、SIFT/RANSAC 打分或索引内容。后续按用户要求增加匹配修复，见各日期记录；实现和验证均在本地，未部署线上。

## 2026-10-26：R.jpeg 第 9 张匹配与相似候选

输入 `/Users/nancy/Downloads/测试数据/R.jpeg`（1080×1487）。原检测已完整返回 9 张，第 9 张有 437 个 SIFT 特征，但对应已发布图鉴卡 `card_36a4179ebc894f91aa16c87601b0d0c8` 没有索引。图片 URL 使用 `127.0.0.1:8000`，本地存储配置为 `localhost:8000`；原 worker 按字符串前缀判断归属，拒绝读取实际存在的图片，累计 5 次失败后停止。完整卡图内存比对已达约 0.988，故本次未放宽严格同卡匹配阈值。

修复内容：

- 本地存储仅在协议、有效端口和媒体路径均相同的情况下兼容 `localhost`、`127.0.0.1`、`[::1]`。索引 worker 统一使用存储读取器。外部地址、不同端口、用户凭据、路径穿越和符号链接逃逸继续拒绝；S3 不启用别名。图鉴图片 URL 保留原值。
- 严格匹配无结果时，增加独立的卡面近似候选路径：双向 SIFT 对应、独立空间位置、尺度/旋转/平移一致性、双图覆盖和合理投影均须成立。严格匹配优先，近似分数上限 0.85，带 `scores.approximate=1`。后端无论数值分数多高都不将此标记自动提升为 `recommended`；无充分证据仍不返回候选。
- 客户端明确显示“相似候选，需手动确认”，不默认选择，不被“全选推荐”自动确认；主动选择后才可保存喜欢或拥有。旧响应继续兼容。
- 两条扫描接口都以 PNG 无损保存裁片，避免“先检测、后选择匹配”比直接识别多一次 JPEG 压缩，改变弱特征支持集。原图归档仍为 JPEG。本图 9 张裁片合计由约 165KB 增至 838KB。旧历史记录不自动重算。

真实 HTTP“检测→选择全部→匹配”结果：

| 对象 | 结果 | 评分 |
| --- | --- | --- |
| 2 | 原有同卡推荐保持 | 0.985 |
| 3 | 新增相似候选，需手动确认 | 0.724 |
| 5 | 原有同卡推荐保持 | 0.989 |
| 8 | 新增相似候选，需手动确认 | 0.722 |
| 9 | 恢复正确同卡推荐，243 个有效对应 | 0.988 |
| 1、4、6、7 | 暂无充分图像证据，仍未识别 | — |

这些分数不是准确率或身份概率。验证覆盖本图、此前低清版本和合成回归样本，不代表所有场景；近似候选可能是不同卡，须对照卡面确认。

验证：138 项存储、匹配、建库、后台、反馈和媒体回归通过；最终 PNG/状态改动后 29 项相关流程再次通过，累计 144 个不同后端用例。初次媒体测试因脚本导入路径未设置而收集失败，改用 `.venv/bin/python -m pytest` 后通过。客户端目标交互测试 18 项通过（含 4 项新增近似候选用例），相关三文件 Dart 分析无问题，Ruff 与空白检查通过。

本地 API 与索引 worker 已启动加载修复，通过管理员接口只重试第 9 张卡，一次成功。原有 7 条索引逐条相同，新增后共 8 条；6 张已发布卡片现在均有可用索引，另有 2 条非公开/旧索引不会进入公开候选。临时接口验证的会话、9 条检测结果、候选及 10 个媒体文件已精确清理，未提交收藏。

按用户确认，更新当前 iPhone 16 Pro Max / iOS 18.6 模拟器，正常 `lib/main.dart` 包 **1.0.14（2026102601）**，连接 `http://127.0.0.1:8000/api/v1`。覆盖安装前已完整备份数据目录和旧安装包。本次没有执行卸载或原生集成测试。模拟器在覆盖安装时迁移了数据目录 UUID；启动前逐项比对，6 个非缓存文件与备份完全一致，变化仅为系统启动截图和图形缓存。备份保留于下方部署目录。

- [第 9 张根因](../output/scan-matching-20261026/baseline/query-09-diagnosis.json)
- [真实接口结果与清理记录](../output/scan-matching-20261026/live-verification.json)
- [近似候选验证](../output/scan-matching-20261026/approximate-study.json)
- [裁片持久化比较](../output/scan-matching-20261026/crop-persistence-study.json)
- [App 安装及数据核对](../output/scan-matching-20261026/deployment/installation.json)
- [启动画面](../output/scan-matching-20261026/deployment/app-launch.png)

## 2026-10-23：424 图片框超出卡面

用户指出上轮 424 图片仍包含卡套和背景。上轮的 21/21 验收证明了数量和大致位置，没有证明裁片贴合卡面。该图既有真实裁片过大，也有水平外包矩形在倾斜卡片周围多显示背景的问题。

修复内容：

- 照片外框按触及的照片边数判断；一个顶点同时触及左、上边时，不再误计为仅触及一边。
- 同一张卡的相近候选比较四边两侧的连续对比度，优先真实卡边，防止背景纹理或卡面局部装饰线胜出。
- 最终只有一张大卡时，依据两侧以上独立的内外边精修边缘；每条收紧的边都需要自身的透明条带证据，不能借用其他边的证据裁掉白色印刷边。局部反光可使用同边连续清晰段，或连续的亮度、色度及局部饱和证据复核。单边内收最多 9%，整体保留至少 85% 面积。证据不足原样返回，多卡网格不使用此精修。
- API 返回可选的真实四角坐标，客户端按相同多边形绘制和响应点击。实际裁片也使用这组四角。旧记录缺失或不合法的四角仍回退矩形；后台建库的坐标约定保持不变。

以人工标注的 424 卡面四角为参照，最终裁片中额外背景约 **1.01%**，未覆盖卡面约 **0.021%**，最大角点偏差约为卡宽的 **1.175%**。这是四边形标注的几何测量，存在人工标注误差，圆角及强反光仍可能留下少量边缘。其余 7 张图验证数量及位置，未逐张声称像素级边界准确。

8 张原图重新检测仍为 **21/21**，无新增输出框；90 项后端回归通过，包括新增的边界质量、透明套边、印刷白边、混合边框、局部反光、重复调用和 API 四角持久化测试。客户端的 22 项扫描选择/多边形测试通过，相关 Dart 静态分析通过。后续按用户要求更新了本地后端和客户端，见下文；未发布云端。

- [424 修正前后与实际裁片](../output/scan-boundaries-20261023/424-before-after.jpg)
- [本轮全部检测框](../output/scan-boundaries-20261023/final/contact-sheet.jpg)
- [带四角的人工标注](../output/scan-boundaries-20261023/annotations.json)
- [本轮逐图测量结果](../output/scan-boundaries-20261023/final/report.json)

复测命令：

```bash
apps/api/.venv/bin/python apps/api/scripts/verify_card_detection.py \
  --images '/Users/nancy/Downloads/测试数据/优化图片' \
  --manifest output/scan-boundaries-20261023/annotations.json \
  --output output/scan-boundaries-20261023/final
```

后端回归使用下文首轮命令，并追加：

```text
tests/test_scan_polygon_payload.py
tests/test_scan_boundary_quality.py
tests/test_scan_boundary_refinement.py
```

## 本地启用（2026-10-23）

- API 已按原地址 `http://127.0.0.1:8000` 重启，`AUTO_SEED=false`，未进行数据库迁移或重建匹配索引。
- 真实 HTTP 请求 `POST /api/v1/scan/detect` 对 424 原图返回 200、1 张小卡、4 个角点，结果与上方离线验收完全一致。只调用检测，没有调用匹配或收藏；本次创建的临时扫描记录和临时图已精确清理。[接口证据](../output/scan-boundaries-20261023/deployment/api-smoke.json)
- iPhone 16 Pro / iOS 18.6 已安装并启动 **1.0.14（2026102301）**，正常 `lib/main.dart` 入口、正常签名、真实本地 API。Keychain、API、正常启动的原生验证 2 项通过。[构建日志](../output/scan-deployment-20261023/ios-client-build.log)、[原生验证](../output/scan-deployment-20261023/native-connection-smoke.log)、[启动截图](../output/scan-deployment-20261023/app-launch.png)
- 已保存的历史检测记录不会自动重新计算四角，需要重新发起扫描。

### 本次执行失误及影响

原生测试沿用了缺少 `--no-uninstall` 的命令。Flutter 的 `test` 命令默认在测试结束后卸载应用，导致旧 App 数据容器被删除；随后安装正常包时创建了新容器。本次未提前备份旧容器，不能宣称本地文件完整保留。

原 Keychain 登录及服务器资料已恢复。服务器保存的相册、收藏、本命、反馈和上传图片未因卸载而删除；图库原图也不在 App 数据容器。若旧容器中存在尚未同步、冲突或待放置卡片的相册草稿，其 `Library/Application Support/digital-albums/account-*/draft-*.json` 和同目录 `backup-*.json` 可能已丢失。头像缩略图缓存和选图临时副本也被清除。未读取或暴露用户凭据。

系统未配置 Time Machine；本机只有系统更新快照，不能作为这些用户文件的可用备份。限定检查项目 `output`、`/private/tmp` 和目标模拟器目录后，未找到旧容器或相册草稿副本。已修正 [App README](../apps/mobile/README.md) 的原生测试命令，明确加入 `--no-uninstall`，并要求在已有用户数据的模拟器上测试前备份数据容器。此后未再执行安装、卸载或清空操作。

## 匹配修复及本地启用（2026-10-23）

用户随后明确要求优化匹配：九宫格原图的第 2 张小卡已在图鉴发布，但客户端显示未找到匹配。目标为 `I've Mine · Either Way Version · Regular`（`card_0ed207e42903425a8b2169cd54d9f2c5`）。

### 原因与修复

- 该卡的 211×335 正面图已经裁好，但原建库检测把卡面头发、手臂的两处细长轮廓当作两张卡。索引任务以“建库照片需仅包含一张小卡，请先裁剪正面图片”失败 5 次后停止重试；目标卡从未进入匹配索引。完整卡图直接与查询裁片比对已有 55 个有效对应、评分约 0.980，因此主要问题是参考图建库失败。
- 建库新增独立的四角几何检查。紧凑、卡片比例的输入若只检测到面积受限的非矩形印刷碎片，保留完整图；正常单卡仍按轮廓裁切。存在可靠主卡时，其他小碎片须完全位于其真实四边形内才能忽略；外部倾斜卡、多张可靠卡和大面积不确定轮廓继续要求人工裁切。公共检测和后台编辑预览不受此检查影响。
- 小尺寸裁片的 RANSAC 重投影容差由固定 4 像素改为短边的 1.2%，限制在 1–4 像素之间。目标裁片仍高分命中，邻近第 3 张卡原先约 0.698 的局部弱候选被拒绝。SIFT 描述子及 `sift-homography-v1` 索引格式保持兼容。

### 验证范围

97 项相关 API 回归全部通过；审查补充卡外倾斜卡保护后，12 项建库几何与失败重试测试再次通过，累计覆盖 99 项不同用例。包含真实轮廓提取、旋转、桌面单卡、多卡拒绝、低分辨率同图、旋转/曝光/JPEG 干扰、索引失败重试和原有后台/扫描流程。Ruff 与改动空白检查通过。测试仍有两条现有 Starlette/httpx 弃用提示。

离线比较 9 个真实裁片与 6 条原索引及目标完整卡图，共 63 组：保留 2 个正确匹配，移除 1 个弱误候选。30 个已有参考图降采样正例保持 29 个命中；原先失败的 1 个样本仍失败。该小样本验证不代表整体准确率。

真实 HTTP 验证使用客户端的“检测→选择→匹配”流程，包含实际 JPEG 90 裁片持久化：

| 对象 | 接口结果 | 匹配评分 | 有效特征对应 |
| --- | --- | --- | --- |
| 2，用户指出的目标 | 推荐 `Either Way Version · Regular` | 0.965 | 49 |
| 3，相邻卡 | 未识别，无候选 | — | — |
| 5，原已可匹配卡 | 推荐 `Baddie Version · Regular` | 0.980 | 77 |

评分是几何匹配分数，不是准确率或概率。

### 启用状态

本地 API `http://127.0.0.1:8000` 与 catalog 索引进程已重启加载新代码，`AUTO_SEED=false`。通过现有管理员重试接口只补建目标卡索引，新任务一次成功；原失败记录及操作审计保留。索引由 6 条变为 7 条，原有 6 条逐项验证完全相同。没有修改图鉴图片、执行数据库迁移或整体重建索引。

验证临时扫描的 1 条会话、9 条检测结果、对应候选及 10 个媒体文件已精确清理，没有确认收藏。现有客户端可直接使用更新后的接口；本轮未执行客户端安装、卸载或原生测试。旧扫描历史不会自动重算，需要重新选择原图扫描。

- [根因记录](../output/scan-matching-20261023/diagnosis.json)
- [63 组比对及降采样验证](../output/scan-matching-20261023/precision-study.json)
- [真实接口验证结果](../output/scan-matching-20261023/live-verification.json)
- [修复前索引快照](../output/scan-matching-20261023/index-before-repair.json)

回归命令：

```bash
cd apps/api
.venv/bin/pytest tests/test_scan_reference_geometry.py \
  tests/test_scan_index_recovery.py tests/test_scan_matching_precision.py \
  tests/test_scan_real_matching.py tests/test_scan_detection_selection.py \
  tests/test_admin_card_cropping.py tests/test_admin_console.py \
  tests/test_admin_recognition_company_import.py tests/test_catalog_operations.py
```

## 首轮原图结果（2026-10-22）

输入目录：`/Users/nancy/Downloads/测试数据/优化图片`。肉眼标注 8 张照片中的 21 张完整小卡，不计照片边缘的残缺卡片。

| 图片 | 优化前输出框 | 优化后独立小卡 |
| --- | --- | --- |
| 1280.jpeg | 1，含较多背景 | 1 |
| 3卡，斜拍.jpg | 1 | 3 |
| 微信图片尾号 422 | 0 | 1 |
| 微信图片尾号 423 | 0 | 1 |
| 微信图片尾号 424 | 1 | 1 |
| 微信图片尾号 425 | 1 个四卡整体框 | 4 |
| Xnip2026-10-22_23-33-47.jpg | 1 个整图框 | 1 个小卡框 |
| 多卡.jpg | 3 | 9 |

以人工标注框 IoU ≥ 0.7 且一对一匹配为验收条件：优化前 6/21 个目标正确定位，优化后 21/21，8 张图均无多余输出框。最终匹配框 IoU 为 0.782–0.980。这里的“匹配框”仅指评估检测位置，不涉及图鉴卡片匹配。

- [原算法框图](../output/scan-diagnosis-20261022/contact-sheet.jpg)
- [优化后框图](../output/scan-diagnosis-20261022/optimized/contact-sheet.jpg)
- [21 张实际裁片](../output/scan-diagnosis-20261022/optimized/all-crops.jpg)
- [原图标注](../output/scan-diagnosis-20261022/annotations.json)
- [最终逐图结果及文件哈希](../output/scan-diagnosis-20261022/optimized/report.json)

这些结果只覆盖本次 8 张原图及下面的回归测试，不代表所有拍摄场景的准确率。三卡斜拍顶部的强反光卡片仍接近人物置信阈值，轻微重采样或不同裁边可能再次漏检；部分框会保留卡套边缘。

## 首轮实现

1. 在公共扫描中增加有界多尺度闭合轮廓检测，处理圆角、桌面纹理连接和弱边缘。候选仍须满足面积、比例、凸性和角度约束；大面积单卡另用矩形前景轮廓收紧边界。
2. 在人物推理前合并近重复候选，优先保留图内完整轮廓；丢弃包含真实小卡的照片外框。按相对卡高聚行再按横坐标排序，避免固定像素分桶造成行内顺序跳变。
3. 保留已经确认的卡套网格。普通轮廓可补充网格证据；缺失格必须有独立边缘及纹理。已有至少四个观测格时允许一条部分遮挡边，但其他三边须有至少 85% 支持；不按固定数量等分照片。
4. YuNet 接受阈值保持 0.88。弱响应仅触发最可信方向的多尺度、留白、灰度、局部对比度、倾斜和细亮纹抑制复核。最多 12 次推理，无弱人脸响应时仅 4 次；添加的留白不计入人脸可见范围。
5. 公共扫描的新增候选不进入无需人物验证的后台建库路径，避免将衣饰局部当作建库图片。保留原有整张紧卡的回退条件。

原图片、业务库和图鉴索引没有写入；图片标注和裁片仅保存于忽略提交的 `output/` 目录。算法不读取样本文件名、标注坐标或预期张数。

## 首轮回归

76 项通过，覆盖真实人物、旋转、键盘/空槽/自然纹理负例、人物复核上限、合框、照片外框、斜放卡、卡套遮挡、空格不补卡、极窄图片、整张紧卡回退、扫描选择流程和后台建库。Ruff 与改动空白检查通过。测试中有两条现有 Starlette/httpx 弃用提示。

```bash
cd apps/api
.venv/bin/pytest tests/test_scan_card_geometry.py \
  tests/test_scan_portrait_detection.py tests/test_portrait_gate_retries.py \
  tests/test_scan_sleeve_detection.py tests/test_scan_sleeve_partial_boundaries.py \
  tests/test_scan_detection_selection.py tests/test_scan_real_matching.py \
  tests/test_admin_recognition_company_import.py
```

从项目根目录重跑本次真实图评估（仅读图，不调用匹配，不写业务库）：

```bash
apps/api/.venv/bin/python apps/api/scripts/verify_card_detection.py \
  --images '/Users/nancy/Downloads/测试数据/优化图片' \
  --manifest output/scan-diagnosis-20261022/annotations.json \
  --output output/scan-diagnosis-20261022/optimized
```

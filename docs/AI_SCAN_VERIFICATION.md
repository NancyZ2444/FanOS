# AI Scan：實作、啟用與驗證

2026-10-11 新增透明卡套多卡分割：用户原图现可切出九张独立卡面，不强制九等分，空格不补卡。原因、真实原图验证及重新扫描方式见 [九卡分割修复](SCAN_NINE_CARD_FIX_20261011.md)。原有扫描历史不自动重算，本次无需 iOS 重打包。

更新：2026-10-08。本次修改 App/API/索引 Worker 與測試，未重新製作 iOS 安裝包。

## 已完成的流程

- 拍照／相簿選圖 → 檢測與透視裁剪 → 每張獨立匹配 → 統一結果列表。
- 展示實際掃描裁剪圖與官方卡圖，而非一律使用佔位圖；支援本機檔案及 API 圖片。
- 高分推薦仍需用戶確認；相近候選需手動選擇，不自動加入收藏。
- 無匹配可搜尋圖鑑、選擇正確卡片，或提交帶有原圖／裁剪／候選的回饋。
- 批量收藏由服務端返回最終数量。相同 Card 的兩個實體區域各 +1；同一區域重送不再 +1。
- 收藏保存失敗保留選擇；已加入的區域禁止重新選卡，避免重複寫入。
- 加入喜歡獨立於 Owned，等待 API 成功才更新 UI；失敗可重試。
- 歷史 API 保留 `owned_added`、手動選卡及圖片；未公開卡片不再作為候選返回。
- 修正相機恢復、初始化競態與圖片框線比例；真實 API 模式不再顯示無圖片的「多卡演示」按鈕。
- 同步 API 完成後顯示「識別完成」，不模擬逐卡推理進度；目前不是串流識別 API。

## 識別方式與限制

採用 OpenCV SIFT 卡面局部特徵 + RANSAC 幾何驗證，索引版本為
`sift-homography-v1`。建庫前也裁剪卡片，避免把桌面背景當作卡面特徵。
只搜尋**已發布、圖片地址與索引一致**的卡片；更換照片後舊索引立即不可用。
空索引／舊 Mock 索引返回 `503 SCAN_INDEX_UNAVAILABLE`，不製造模擬命中。
純色、特徵不足或包含多張卡的參考照片不接受建庫。

用戶提供的 `card-matcher` 與 ONNX 模型完整保留在 vendor。原先人物、姿態、表情
特徵不能單獨確認具體印刷卡版，因此目前掃描不依賴這些特徵，也不需要新增下載
InsightFace 模型或提供第三方密鑰。API／登入／可用卡圖索引仍是必要條件。

一次最多 10 張，單張照片最多 15 MB／24 百萬像素。卡片需完整、清晰，避免重疊、
強反光或遮擋。沒有可靠輪廓時，整張照片作為一個待識別區域；數量不保證等於真實卡數。
同一照片印在不同卡版、只有邊框不同、反面或嚴重遮擋，仍可能無法可靠區分。
相似度是幾何評分，**不是識別準確率**。

目前採用小型 JSON 索引與逐卡匹配。大型卡庫、並發效能、PostgreSQL 多用戶壓力測試、
真機拍攝準確率與營運部署尚未驗證。因此 `/scan/status` 中
`available=true` 表示可以匹配已建庫卡片，而 `production_ready=false` 刻意保留。

## 本機現況與啟動

本次檢查有 8 張已發布卡片，其中 1 張有真實已上傳圖片並已重建索引；其他 7 張 Seed
無卡圖，不會假裝識別成功。現有照片 ID：`card_d5ced7bd6536434eacc043792cf693c3`。

在一般終端中執行（不是受限制的測試執行環境）：

```bash
cd /Users/nancy/Documents/ChatGPT/FanOS/apps/api
.venv/bin/alembic upgrade head
.venv/bin/python scripts/import_card_assets.py --rebuild-existing
cd ../..
bash scripts/dev-admin.sh
```

`dev-admin.sh` 啟動 API、索引 Worker 與后台。檢查
`http://127.0.0.1:8000/api/v1/scan/status` 的 `available` 與 `indexed_card_count`。
若有新照片，後台上傳後由 Worker 建庫；卡片還需要審核發布。
手動素材目錄與詳細命令見 [卡圖導入說明](../assets/import/cards/README.md)。

App 開發執行：

```bash
cd /Users/nancy/Documents/ChatGPT/FanOS/apps/mobile
flutter run --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

此地址供同機 iOS 模擬器使用。實體手機需可訪問的 API 地址，API 要監聽 LAN 介面，
且 `PUBLIC_MEDIA_BASE_URL` 也必須是手機可訪問的地址（正式環境使用 HTTPS）。
不能只改 App API 地址而繼續返回 `localhost` 圖片地址。不要對外開放開發登入。
API 模式目前要求登入；未登入會先引導登入，尚未實作匿名掃描每日配額。

## 已執行的驗證

- API pytest：41 項通過。包含單卡旋轉／縮放／曝光、透視多卡、未知混合、區域故障隔離、
  相近候選需確認、重複卡與重送、手動選卡、Wishlist、權限、批次回滾、下架與失效索引、
  檔案大小／張數限制、回饋驗證及原有後台功能。
- Ruff 格式與靜態檢查通過；Dart 對 `lib`、`test` 的靜態分析無問題。
- Flutter 本地單元／元件測試 38 項通過（不含 live backend contract），其中 AI Scan
  9 項覆蓋搜尋手動選卡、Wishlist 失敗與重試、服務端數量覆蓋本機、批量保存失敗重試、
  歷史模型、Mock 隔離、回饋與批量確認。其餘為首頁、圖鑑、個人頁與動態等回歸測試。
- SQLite 全新遷移 → 回退到前版 → 再升級 → 結構比較通過；本機資料庫已在
  `e22a811c4b03`。遷移新增 `detected_cards.owned_added_at`，不改卡片或收藏數量。
- OpenAPI JSON/YAML 已重新導出。
- 現有真實卡圖另做 5 組進程內 API 驗證：原圖、90°旋轉、裁剪變暗、兩張相同卡混合
  一張未知卡、全部未知。全部通過；混合照片檢出 3 個區域、命中 2 個，確認後 +2，重送 +0。
  驗證使用本機資料庫的**臨時副本**，未把測試結果加到用戶原收藏。

[照片驗證報告](../output/scan-verification/report.json) 與
[混合輸入圖](../output/scan-verification/multi-card-input.jpg) 可直接查看。
這些是現有圖片及合成變換，不是新拍攝的真機樣本；5/5 不代表實際識別準確率。

## 重跑測試

```bash
cd apps/api
.venv/bin/pytest
.venv/bin/python scripts/verify_scan_local.py
cd ../mobile
flutter test test/scan_session_test.dart
flutter analyze
```

`verify_scan_local.py` 適用本機 SQLite + 本機媒體，先執行遷移與建庫。
可選的 Flutter live contract 測試增加 `SCAN_TEST_IMAGE_PATH`：

```bash
flutter test test/backend_contract_test.dart \
  --dart-define=RUN_BACKEND_INTEGRATION=true \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 \
  --dart-define=SCAN_TEST_IMAGE_PATH=/absolute/path/to/indexed-card-photo.jpg
```

Live contract 會修改開發帳號（包括收藏），只對隔離測試服務執行。
未提供圖片時只驗證空白圖不會誤命中，不視為真圖匹配通過。

本次執行環境禁止本機 TCP listen，且無法連接 CoreSimulator；一般 `flutter test`
及 App→網路→API 的端到端執行受阻。已改用 Flutter engine 的無 socket headless 執行器
執行元件測試，與 FastAPI TestClient 的進程內 API 測試分開驗證。
這**不等於**真機 E2E、相機／相簿系統權限、閃光燈或 iOS 安裝包驗證。
輔助執行器見 [headless_flutter_runner.dart](../output/scan-verification/headless_flutter_runner.dart)，
僅為當前已鎖定測試依賴的驗證產物，不進入 App。

本機 macOS 無 socket 重跑方式（需已有 `flutter pub get` 與 `build/unit_test_assets`，
以下 SDK 路徑為本次臨時唯讀 SDK 副本；換環境請使用自己的 SDK 路徑）：

```bash
cd apps/mobile
/tmp/fanos-flutter-sdk/bin/cache/dart-sdk/bin/dartaotruntime \
  /tmp/fanos-flutter-sdk/bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot \
  --sdk-root /tmp/fanos-flutter-sdk/bin/cache/artifacts/engine/common/flutter_patched_sdk/ \
  --target=flutter --no-print-incremental-dependencies \
  --packages .dart_tool/package_config.json --output-dill /tmp/fanos_flutter_tests.dill \
  ../../output/scan-verification/headless_flutter_runner.dart
FLUTTER_TEST=true /tmp/fanos-flutter-sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester \
  --non-interactive --disable-vm-service --enable-software-rendering --use-test-fonts \
  --flutter-assets-dir=build/unit_test_assets /tmp/fanos_flutter_tests.dill
```

真機驗收仍需：拍攝不同卡版和真實反光／遮擋／重疊樣本，確認相簿授權、閃光燈、
切後台恢復、上傳中斷、圖片地址可訪問及收藏跨頁同步。正式上線前需補完整卡圖庫及
帶標記的評測集，再決定匹配門檻與是否更換檢測／檢索模型。

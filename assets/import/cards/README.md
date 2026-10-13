# 官方小卡照片手动导入目录

将已获授权的卡面正面照片按下面结构放入本目录：

```text
assets/import/cards/
├── card-aria-01/
│   └── front.jpg
├── card-lin-01/
│   └── front.png
└── card-yuna-01/
    └── front.webp
```

文件夹名称必须等于数据库中的 Card ID。也可以把照片直接放在本目录，并把
文件名设为 `<card-id>.jpg`。支持 JPG、JPEG、PNG、WebP；以下内容会自动跳过：

- 文件名以 `_` 开头的界面截图；
- 文件名包含 `back` 的卡背；
- 数据库中不存在对应 Card ID 的照片。

在 `apps/api` 目录执行：

```bash
python scripts/import_card_assets.py --dry-run
python scripts/import_card_assets.py
```

导入会完成三件事：上传/复制图片到对象存储、更新 `cards.image_url`、通过与后台
上传相同的 Outbox Worker 建立 `sift-homography-v1` 卡面特征索引。文件夹支持
任意数据库 Card ID（包括后台生成的 `card_...`），卡面文件命名为 `front.*`。

每张建库照片仅放一张小卡，优先使用清晰、完整、无反光的正面图。允许带少量桌面
背景，系统会先检测裁剪；纯色、模糊到缺少特征或包含多张卡的参考照片不能建索引。
卡背不会导入正面检索索引。导入并不自动发布草稿，只有已发布卡片能被 App 匹配。

已有后台图片或旧版 embedding 索引时，在 `apps/api` 执行：

```bash
python scripts/import_card_assets.py --rebuild-existing
```

默认索引文件为 `apps/api/data/card_matcher/cards.json`，可通过
`CARD_MATCHER_INDEX_PATH` 配置。旧 Mock/人物特征索引不会被当作真实卡面索引。
后台新上传的图片会自动排队，需运行 `python -m app.modules.admin.catalog_jobs`。
用 `GET /api/v1/scan/status` 检查实际可用数量，不以“上传成功”代替“已建库”。
`production_ready=false` 代表尚未完成真实拍摄准确率评测，不代表不能本地试用。

当前演示 Card ID 清单见同目录的 `manifest.csv`。本目录只接收拥有使用权的素材。

# 专辑双面素材手动导入目录

每张专辑可只提供正面、只提供背面，或同时提供两面；均不是必填字段。

```text
assets/import/albums/
├── album-starlit/
│   ├── front.jpg
│   └── back.jpg
└── album-bloom/
    └── front.png
```

文件夹名必须等于数据库中的 Album ID，图片支持 JPG、JPEG、PNG、WebP。在
`apps/api` 目录执行：

```bash
python scripts/import_album_assets.py --dry-run
python scripts/import_album_assets.py
```

缺少某一面不会阻止专辑发布；App 仅在已录入素材时显示正面/背面切换。

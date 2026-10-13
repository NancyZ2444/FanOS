# Fan OS Crawler Worker

独立于 API 的本命动态同步进程。每个平台拥有独立 Provider 和 Redis 游标；单个平台
失败只记录错误，不阻断其他平台。同步结果通过带 `X-Worker-Token` 的内部 API 幂等
写入 `social_posts`。

当前默认启用微博、Instagram、X、小红书、抖音五个 Mock Provider，用于本地闭环。
接入真实平台时必须使用官方/获授权 API，并保持 `Original Post ID`、原帖地址、抓取
时间和删除状态字段，不读取用户私信、私人关注 Feed 或非公开内容。

```bash
cd apps/crawler-worker
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
python -m worker.main
```

`python -m worker.main` 会立即同步一次，然后按 `SYNC_INTERVAL_MINUTES` 调度。完整
Docker 环境建议直接在项目根目录运行 `docker compose up --build`。

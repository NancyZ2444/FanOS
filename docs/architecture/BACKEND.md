# Fan OS 后端架构

Phase 1 使用“模块化单体 API + 独立定时 Worker”。该结构能在当前规模下保持事务
一致性，也为后续把动态聚合、AI Scan 拆为独立服务保留清晰边界。Router 负责 HTTP
校验，Service 承载业务规则，SQLAlchemy 负责持久化，`integrations/` 隔离对象存储和
模型推理。

```text
Flutter -> REST/OpenAPI -> FastAPI modules -> PostgreSQL
                              |       |
                              |       +-> S3/MinIO media
                              +-> card-matcher ONNX

Scheduler -> Crawler Worker -> worker ingestion API -> PostgreSQL
                    |
                    +-> Redis cursor / retry state
```

本地无基础设施模式使用 SQLite 和 Worker 内存替身；Docker 模式使用 PostgreSQL 16、
Redis 7、MinIO，并保持同一份 HTTP 契约。

## 模块边界

- `auth`：验证码/OAuth 占位登录、Access/Refresh Token、用户状态校验。
- `catalog`：组合、成员、官方小卡目录和搜索。
- `users`：个人主页、隐私、本命关系、关注关系。
- `collections`：Owned 数量、Wishlist、卡册、主页照片。
- `daily_cards`：每日最多三次、请求幂等、本命权重。
- `scan`：多区域检测、逐卡候选、批量确认、历史和未识别反馈。
- `social_feed`：平台/本命筛选、分页、已读、点赞、两级评论和举报。
- `notifications`：本命动态聚合通知偏好。
- `admin`：小卡补录、未识别队列、举报、用户状态和操作审计。
- `crawler-worker`：五个平台适配器、独立游标、重试与单平台故障隔离。

## Phase 2/3 预留边界

当前代码已为社区和实时聊天预留独立边界，但没有注册 Community/Chat
路由，因此不会改变 Phase 1 App 行为。用户社区使用独立的 `community_*` 模型，
不会复用第三方本命动态的 `social_posts` 或评论；实时聊天只保留版本化契约，后续由
独立 Realtime Service 通过 WebSocket 提供。

跨模块副作用使用 `outbox_events` 作为事务边界；通知箱和设备 Token 独立存储；Redis
通过适配器和版本化 KeySpace 接入。详细演进方案见
[`PHASE2_PHASE3_EVOLUTION.md`](PHASE2_PHASE3_EVOLUTION.md)。

## Phase 1 Admin Console 扩展（2026-09-18）

React 后台通过 `/api/v1/admin/console` 调用已有 FastAPI。`catalog_service.py` 集中实现
图鉴关系、审核状态、权限、来源版本和审计；`console_router.py` 提供录入、导入与上传接口；
`operations.py` 承载基础运营管理，`admin_users.py` 管理后台人员。前端不绕过 API 写数据库。

`cards.status` 控制公开目录可见性，`admin_data` 保存新增小卡字段。其余既有图鉴对象通过
`admin_content_metadata` 扩展状态与资料；来源系列由 `catalog_collections` 单独持久化。
多对象批量状态变更和确认导入使用事务，图片来源独立记录版本。

图片上传先保存到配置存储。小卡正面图片更换在同一数据库事务内写入 Outbox，独立
`catalog_jobs` Worker 读取这些事件，更新现有 JSON 检索索引。Worker 只读取自身存储，
最多自动重试 5 次；未使用通用远程 URL 抓取器，也没有把其他事件当作已投递处理。
该 Worker 是单索引文件部署方案，后续生产规模需扩展。

通知现在已使用此前预留的通知箱表；新增用户自己的通知列表与已读接口。运营发送在校验
审核状态、受众和跳转目标后写入通知箱。APNs／FCM、定时发送与送达统计仍待接入。
公告时间窗在读取首页时判断，卡池权重用于既有每日抽卡服务。详见
[后台项目情况](../ADMIN_PHASE1_STATUS.md)。

## 数据与一致性

- 外部公开动态以 `(platform, original_post_id)` 唯一，Worker 重试不会重复写入。
- 每日翻卡以 `(user_id, request_id)` 保证幂等，并由服务端记录当日次数。
- 收藏以 `(user_id, card_id)` 唯一，重复扫描自然增加 `quantity`。
- 一次 Scan Session 下的每个 Detected Card 独立存储，部分识别失败不回滚其他卡。
- 图片进入本地对象存储或 S3/MinIO，数据库只保存 URL；AI embedding 保存在可重建索引。

## 生产切换清单

1. 使用强随机 `JWT_SECRET`、`WORKER_TOKEN`，关闭开发验证码与自动 Seed。
2. 把 `DATABASE_URL`、Redis、S3 指向托管服务并配置备份、生命周期和监控。
3. 为微博、Instagram、X、小红书、抖音实现经授权的 Provider，不采集私人 Feed。
4. 配置 HTTPS、受限 CORS、API 限流、图片大小/类型检测和内容审核策略。
5. 使用获授权的小卡图片重建索引；所有查询实例必须与建库时使用相同模型模式。
6. 接入 APNs/FCM、短信和真实 OAuth AppID/回调地址。
7. Phase 2 启用 Outbox Publisher 与消息队列后，再开放 Community 路由；Phase 3
   单独部署 Realtime Service，不在 FastAPI Worker 内维持长连接群聊。

# Fan OS Phase 2/3 演进边界

## 结论

Phase 1 保持 Python + FastAPI 模块化单体。Phase 2 的用户社区先作为独立模块落在
业务 API 内；Phase 3 的群聊、私聊、在线状态和消息漫游由独立 Realtime Service
承担。此次仅增加表、契约与基础适配器，未注册新路由，现有 App 行为不变。

```text
Flutter App
  ├─ REST/OpenAPI ──> FastAPI Business API
  │                    ├─ Identity / Catalog / Collection
  │                    ├─ External Idol Feed（现有）
  │                    └─ Community（Phase 2）
  └─ WebSocket ─────> Realtime Service（Phase 3）
                         ├─ Room / Member / Message / Read Cursor
                         └─ Presence / Fan-out / Reconnect

FastAPI ── Outbox ──> Message Broker ──> Notification Worker / Realtime Service
          PostgreSQL                    └─ APNs / FCM
Redis: feed cache、rate limit、presence、unread；不作为唯一业务数据源
```

## 必须保持分离的领域

| 领域 | 数据所有者 | 当前/未来存储 | 说明 |
| --- | --- | --- | --- |
| 外部本命动态 | `social_feed` | `social_posts`、现有评论 | 第三方公开内容，受原帖删除状态约束 |
| 用户社区 | `community` | `community_*` | 用户原创内容、独立审核与可见性策略 |
| 实时聊天 | Realtime Service | 独立 Room/Member/Message 存储 | 不复用社区评论，不写业务 API 的评论表 |
| 通知 | Notification Worker | `notifications`、`device_tokens` | Feed、社区和聊天统一进入用户通知箱 |
| 跨域事件 | 事件总线 | `outbox_events` + Broker | 版本化契约，至少一次投递，消费端幂等 |

社区帖子不能写入 `social_posts`，社区评论不能写入现有 `comments`，聊天消息不能写入
任一评论表。这样后续可在不迁移三种不同生命周期数据的前提下独立扩容。

## 当前已预留

- 数据表：`community_posts`、`community_post_media`、`community_comments`、
  `community_reactions`、`community_bookmarks`、`community_moderation_cases`、
  `user_blocks`、`outbox_events`、`notifications`、`device_tokens`。
- API 内部契约：`app/modules/community/schemas.py` 与
  `app/modules/chat_contract/schemas.py`。聊天模块只放共享契约，不放 WebSocket 实现。
- Flutter 契约：社区发布草稿、消息发送、分享对象引用与已读游标。
- Redis：统一版本化 KeySpace，未来替换部署方式不侵入业务代码。
- 事件：公共 JSON Schema 和 `chat.message.created.v1` 示例。

## 分阶段落地

### Phase 2：社区

1. 在 `community` 模块新增 Router/Service/Repository，采用游标分页。
2. 发布、评论、互动与审核状态变更和 Outbox 写入同一事务。
3. Outbox Publisher 投递 `community.post.*`、`community.comment.*` 等事件。
4. Notification Worker 聚合关注对象动态并写通知箱、发送 APNs/FCM。
5. Feed 缓存在 Redis，PostgreSQL 保持事实来源；缓存丢失可重建。

### Phase 3：群聊/私聊

1. 新建独立 `apps/realtime-service`，通过 OAuth/JWT 验证同一 Fan OS User ID。
2. 房间模型使用 Room、Member、Message、Read Cursor；房间主题使用
   `subject_type = group | idol | custom`。
3. 消息按 `room_sequence` 排序，`client_message_id` 保证重试幂等；断线以最后序号续传。
4. 卡片、帖子、收藏分享只传稳定 `type + target_id + version`，展示数据由业务 API 获取。
5. Redis 只保存在线状态、临时 Fan-out 和未读缓存；消息历史进入持久化存储。

## 提取条件

社区暂不因为“未来可能增长”提前拆服务。当独立发布节奏、审核隔离、数据库负载或
团队归属成为真实约束时，再把 `community_*` 表迁移到 Community Service；由于当前
已采用独立命名空间和事件契约，提取不需要改变 Flutter 的领域模型。

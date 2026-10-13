# Fan OS 领域事件契约

此目录预留 Phase 2 社区、通知与 Phase 3 实时聊天之间的异步契约。事件使用
`event_type + event_version` 作为稳定标识；消费者必须忽略未知字段，并按版本升级，
不能直接读取其他服务的数据表。

- `event-envelope.schema.json`：所有跨进程事件的公共信封。
- `chat-message.created.v1.example.json`：实时服务发布聊天消息后的示例事件。

当前 Phase 1 不启动消息队列，也不发布这些事件。业务 API 可先在同一数据库事务中
写入 `outbox_events`；Phase 2 再由 Outbox Publisher 投递至消息队列，避免数据库提交
成功而消息发送失败。

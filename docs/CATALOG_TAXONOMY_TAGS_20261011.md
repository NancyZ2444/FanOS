# 图鉴来源、Tag 与用户补充更新

日期：2026-10-11。范围：FastAPI、React 运营后台、Flutter App。本次规则优先于旧文档中 Collection / Merchandise、自由 Tag 字符串和“接受后仅创建草稿”的描述。

## 已实现

- 图鉴来源统一为 `ALBUM / EVENT / OTHER`。后台导航、来源选择、小卡关联、导入模板、App 图鉴与扫描反馈使用同一组类型。旧来源查询地址保留只读兼容入口，返回 Other 数据。
- Other 业务表单和导入仅使用 `name / original_name / start_date / end_date / description / tags`。日期为 `YYYY-MM-DD`，结束日期不能早于开始日期。ID、状态、操作人、创建/更新时间仍保留。
- Album、Event、Other、Card 使用独立的平级 Tag 库和多对多关联；不增加 Tag Group。唯一约束是 `(entity_type, normalized_name)`。名称执行 Unicode NFKC、去首尾空白、压缩连续空白、casefold 去重；同实体内复用原 Tag ID，跨实体允许同名。
- 后台新增「图鉴内容管理 → Tag 管理」：按类型、名称、状态筛选，查看来源和关联数量，创建、改名、停用/启用、查看关联内容。内容运营可创建和编辑名称，管理员可变更状态；操作写入审计记录。
- 后台表单支持搜索已有 Tag、多选和输入新 Tag；后台创建的 Tag 来源为 `INTERNAL`。改名通过稳定 ID 更新展示，历史对象无需重新绑定。
- 停用后不再出现在新录入候选中，服务端禁止新增关联；原有绑定保留，历史内容继续显示。历史结果集中的停用 Tag 仍可用于浏览筛选，与“新增录入候选”分开处理。
- 用户补充表单优先选择已有组合、艺人、Album / Event / Other、专辑版本、小卡和 Tag。缺失信息可以补充名称；缺失上游名称作为审核线索保存，不自动创建正式上游对象。Other 不要求组合和商品属性。保留历史成员候选，不把当前成员身份当成历史卡的唯一有效归属。
- 用户新增 Tag 只保存于本次待审主体的建议数据中。通过同一审核时，主体发布、新 Tag 进入正式库并绑定，来源为 `USER_SUBMITTED`，记录提交单与审核人；驳回或发布校验失败不会产生正式新 Tag。并发同名依赖数据库唯一约束复用。已存在 Tag 保留原来源。
- 审核页展示缺失上游线索，可补充关联、图片、来源版权等发布必需字段。资料不完整时接受会返回校验错误，整笔事务回滚，仍保留待审。新增专辑版本向既有专辑追加，不覆盖原版本和原 Tag。
- App 小卡列表、详情和 Album / Event / Other 页面显示 Tag；组合/艺人页的 Other 来源通过真实小卡关联定位。小卡来源详情优先使用来源类型和 ID 跳转。
- App 筛选从当前已加载图鉴结果集聚合实际 Tag，组合、艺人、年份、来源类型、来源对象等条件变化后重算；非 Tag 条件改变会清理失效候选。API 同样在完整结果集过滤后、分页前返回 `available_tags`。多个 Tag 使用 AND；不同实体的同名 Tag 不混用。
- 现有图鉴搜索实时读取正式 Tag 关联，Tag 改名后搜索立即生效，无独立缓存索引重建步骤。AI 卡面图片识别索引保持独立。

## 接口与存储

新增表：`catalog_others`、`catalog_tags`、`catalog_tag_bindings`。

主要接口：

| 路径（统一前缀 `/api/v1`） | 用途 |
| --- | --- |
| `GET /catalog/tags?entity_type=OTHER&q=...` | 新录入可选的启用 Tag |
| `GET /admin/console/tags` | Tag 管理列表，含 usage_count |
| `POST /admin/console/tags`、`PUT /admin/console/tags/{id}` | 创建、改名、状态管理 |
| `GET /admin/console/tags/{id}/contents` | 查看关联主体 |
| `GET /catalog/cards`、`/albums`、`/events`、`/others` | 支持 `tag_ids` 多值参数，返回当前结果中的 `available_tags` |
| `POST /catalog/feedback` | 用户主体与 Tag 一次提交 |
| `POST /admin/console/review-queue/contribution/{id}/actions` | 同一次审核发布主体和 Tag |

实体返回 `tags`（规范展示名）、`tag_ids`、`tag_details`（类型、状态、来源）。写入使用名称数组，由服务端匹配稳定 ID。OpenAPI JSON / YAML 已同步生成。

## 已有数据升级结果

迁移：`c611_catalog_preferences → d611_catalog_taxonomy`。

先使用 SQLite backup API 制作一致性副本，完成副本迁移和校验，再停止本地 API、制作最终快照并升级当前数据库。API 重启时使用 `AUTO_SEED=false`。

- 原 Collection：0 条。原 Merchandise：3 条，均按原 ID 建立 Other。
- 原状态逐条保留，3 条均非公开状态，没有因迁移自动上架。
- 当前原库没有需要转为正式 Tag 的已有标签数组，因此 Tag 库初始 0 条；不凭空生成分类标签。
- 小卡共 10 条，原库没有需要从 Collection / Merchandise 改写的已绑定小卡来源。本次小卡表内容完全不变。
- 141 条内容元数据数量不变；其中 3 条来源元数据类型改为 `others`。
- 原始来源行及完整历史字段保留。旧归属保存到 Other 与 `legacy_data` 快照；旧归档行不再持有活动外键，避免旧只读表阻碍后续正常解除关联和删除。
- 49 张原有表的内容摘要完全不变，包括组合、艺人、专辑、活动、小卡、收藏、用户相册等业务数据。
- 增加一条已完成的迁移标记，防止重复执行重新创建已删除的 Other，或把 Tag 旧名称重新导入。
- `PRAGMA integrity_check = ok`，外键错误为 0。

备份与报告（仅本机保留，数据库快照已加入 Git 忽略规则）：

- `output/taxonomy-20261011/pre-upgrade.db`：实际升级前快照。
- `output/taxonomy-20261011/before.db`、`rehearsal.db`：首次演练副本。
- `output/taxonomy-20261011/applied-verification.json`：实际升级检查结果。
- `scripts/verify_catalog_taxonomy.py`：只读检查工具。

可重复验证：

```bash
python3 scripts/verify_catalog_taxonomy.py \
  output/taxonomy-20261011/pre-upgrade.db apps/api/data/fan_os.db
```

## 其他环境的升级与回退策略

1. 先部署兼容本次迁移的代码到预发布环境，备份数据库；停止业务写入后再取最终快照。
2. 在副本执行 `AUTO_SEED=false alembic upgrade head`，验证旧来源 ID、状态、卡片来源 ID、Tag 去重结果及用户关系。
3. 同 ID 发生跨旧类型冲突时迁移会停止，不覆盖记录；先核实并制定 ID 映射。历史名称、日期、归属不足时保留原快照并交由运营确认，不猜测补齐。
4. 当前库没有此类缺失阻塞项。后续若给旧 Other 增加 Tag，在后台按真实来源选择/创建，历史状态不变；需要发布时使用正常审核流程。
5. 在实际库执行迁移，启动 API，再同步更新 App。旧 App 依赖旧 bootstrap 字段的版本需同步升级；旧列表/详情 URL 的兼容不等于完整旧客户端协议兼容。
6. 回退需要停止写入，恢复已核验的完整备份及匹配的旧代码，再启动服务。本迁移禁止破坏性降级删除新表。升级后若已有新提交，先导出增量再人工合并，不能直接覆盖丢弃新数据。

## 验证

- 后端全量 pytest 通过；新增测试覆盖实体隔离、Unicode/空格/大小写去重、停用与历史关联、审核通过/拒绝、发布失败回滚、上下文筛选、字段校验和迁移幂等。
- Flutter analyze 通过；App 测试 92 项通过、2 项真实后端联调用例按默认条件跳过。新增 4 项覆盖 Tag 读取、上下文筛选、用户新增 Tag 去重和 Other 六字段提交。
- 后台 TypeScript、ESLint、Vitest 8 项及生产构建通过；构建保留已有的主包体积提示。
- 两项浏览器流程通过（Tag 治理与小卡专辑版本保存）。Tag 流程覆盖：创建 Tag、复用、Other 六字段表单、Usage Count、关联详情跳转、停用后候选移除且关系保留。
- 本机升级后的 API `/health` 与后台首页返回 200。新版 iOS Simulator App 已构建、安装到已启动的 iPhone 16 Pro（iOS 18.6）并正常启动，使用 `USE_MOCK_API=false` 连接本机 API 8000。安装保留 App 数据，启动截图位于 `output/taxonomy-20261011/app-launch.png`。

本次为本地开发环境升级；没有发布到远程生产服务或应用商店。App 的实体筛选使用当前 bootstrap 快照，在图鉴首页下拉刷新获取最新服务端数据；分页 API 可供后续改为服务端分页时直接复用。

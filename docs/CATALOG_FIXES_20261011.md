# 图鉴成员筛选与公司关联修复

更新日期：2026-10-11。范围以用户本次 Bug 修复与现有组合公司数据补齐请求为准。

## 已修复行为

- 小卡向导选择组合后，艺人网格与基础信息下拉只显示该组合的当前或历史成员；历史成员有明确标记。切换组合会清除原艺人选择。无组合 Solo 发行仍可选择独立艺人或有组合身份的艺人。
- 艺人列表接口新增 `membership_history`，成员筛选依据完整成员经历。历史卡已有归属缺少经历时，原艺人仍保留用于编辑；不会把其他组合艺人整体放入候选列表。发行日期与历史归属的后端校验继续生效。
- 批次生成、批量属性编辑的成员选项同步按所选组合筛选；批量编辑切换组合会清除艺人选项。
- 组合、艺人新建及编辑的「所属公司」改为公司管理记录选择，支持多家公司。每次打开表单重新读取公司列表，新建公司可立即选择。
- 选择公司写入 `company_relations`，使用公司 ID，保留兼容显示字段。重复保存相同选择不会重复建关系。未操作公司选择的旧客户端或旧表单保留原公司文本。
- 已有公司经历变更须提供生效日期：原关系保留，结束日期为新关系生效前一天；新关系独立建立。开始日期未知的首次关系标记「日期待核实」，不推测签约日期。同日纠错和未来排期在公司经历中维护。
- 公司名称按 Unicode 规范化、空白整理及大小写检查重复；有关联的公司不能删除。编辑公司或公司经历保留补齐来源等扩展信息。

## 本次运营数据处理

已从现有组合公司的明确文本建立 **9 家公司和 9 条组合关联**，新增 **18 条操作审计**。没有新增、删除或重建组合、艺人和小卡。

| 组合 | 公司 |
| --- | --- |
| LUMINA | North Star Studio |
| ASTER | Orbit Entertainment |
| NOVA | Blue Hour Records |
| IVE | STARSHIP Entertainment |
| ATEEZ | KQ Entertainment |
| SEVENTEEN | PLEDIS Entertainment |
| Stray Kids | JYP Entertainment |
| BTS | BIGHIT MUSIC |
| i-dle | CUBE Entertainment |

关联保存 `original_company`、`source=legacy_group_company_backfill`、`date_unknown=true`。开始 / 结束日期为空，表示缺乏史料依据；这些关系作为现有公司归属用于选择与展示，不作为历史期间已核实的证据。组合原公司字段和原 ID 保持原样，艺人的公司不按组合公司推断。

补齐过程只增加 `catalog_operational_records` 和 `operation_logs`。其余 **44 张表**的行数及完整内容 SHA-256 一致，包括原组合、艺人、卡、用户收藏、心愿单、卡册和成员经历。启动后全部 **46 张表**与补齐完成时的指纹一致。当前仍为 9 个组合、53 个艺人、8 张小卡；IVE 的成员候选为 Gaeul、Yujin、Rei、Wonyoung、Liz、Leeseo。

已先执行只读预览，再在数据库副本上演练和重复执行，最后对运营库备份及补齐。演练第二次新增数为 0；运营库启动后只读复核新增候选为 0。已有公司经历优先保留；同名多公司、归档公司或不明公司文本会跳过并写入报告。

证据文件位于 `output/catalog-upgrade/`：

- `company-preview-20261011.json`：只读预览及表指纹。
- `company-rehearsal-20261011.json`、`company-rehearsal-repeat-20261011.json`：副本演练及幂等性。
- `company-applied-20261011.json`：实际映射、前后指纹、备份路径。
- `company-after-restart-20261011.json`：启动后只读复核。
- 运营库备份：`company-backup-20261011-011716-084419.db`，文件名时间为 UTC；数据库备份已加入 Git 忽略。

此前 [2026-10-10 数据升级策略](CATALOG_UPGRADE_20261010.md) 中的 27 项发行艺人、卡来源与版本补齐候选维持原状态。这次只处理明确授权的公司数据，不推断缺失发行关系或历史有效期。

## 后续补齐和重复运行

在项目根目录运行。默认只读；每次使用新的输出文件名，防止覆盖历史报告：

```bash
apps/api/.venv/bin/python scripts/backfill_group_companies.py apps/api/data/fan_os.db \
  --output output/catalog-upgrade/company-preview-next.json
```

明确需要对新导入的组合再次补齐时，使用 `--apply`：

```bash
apps/api/.venv/bin/python scripts/backfill_group_companies.py apps/api/data/fan_os.db \
  --apply --output output/catalog-upgrade/company-applied-next.json
```

脚本自动创建 SQLite 一致性备份，在事务提交前确认原表不变；发现异常会回滚。已有关系不会重复补齐，也不会因旧文本覆盖后续人工维护的公司经历。执行时避免同时修改图鉴或其他数据，以保证指纹比对。

待核实日期需根据证据在「公司经历」中补充；未知日期可保留。若映射错误，优先在操作审计支持下纠正指定关系。只有确认备份之后没有新的有效业务写入时，才考虑停服后恢复整个备份，以免覆盖后续运营数据。

## 验证和运行

- 后端全量 105 项 pytest 通过；前端 7 项 Vitest 通过。
- 10 个 Playwright 场景全部通过，包含组合切换、历史成员筛选、公司新建后在组合 / 艺人选择，以及原图鉴创建、审核、下架、导入、批量处理及页面布局。
- 补充验证公司经历在开始日期待核实时可以编辑备注，保留关系 ID、数据来源和待核实标记；最终公司与批次界面改动复核通过。
- TypeScript、生产构建、ESLint、Ruff 项目代码检查通过（排除既有第三方 `card_matcher/vendor`）；OpenAPI 已更新。测试使用隔离数据库，未写入运营数据。
- 后台与 API 已启动，5173 / 8000 健康检查为 200；默认 `AUTO_SEED=false`。

后台入口：<http://127.0.0.1:5173>。已有浏览器页面刷新即可使用修复。

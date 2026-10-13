# 后台 UI 与关联 API 云端发布

发布日期：2026-10-14（北京时间）。代码提交和备份开始于 2026-10-13。

## 版本与范围

- 分支：`develop`，仓库：`NancyZ2444/FanOS`。
- 应用版本：`fe3697f8b0f78e558a72e42e1af3626b70bdb044`。
- `a5a3ddc`：将既有云端识别、人物检测、存储读取、头像与成员筛选补丁纳入 Git；同步 Other 艺人关联、导入与公开查询、登录返回字段及开发配置模板。
- `fe3697f`：后台公共设计变量、组件、导航、列表、详情、表单与新增/编辑/删除交互统一，包含测试与验收文档。
- 本次发布范围为管理后台与相关 API。工作区中的移动端改动仍由其开发任务维护，未混入本次提交。

后台入口：[Fan OS 管理后台](http://106.53.120.249:5173/)。页面结构、功能清单和修改前后截图见 [后台 UI 整改说明](ADMIN_UI_STANDARDIZATION_20261013.md)。

## 部署方式与数据保留

服务器代码目录 `/home/ubuntu/FanOS-code`，沿用 `docker-compose.cloud.yml`、项目名 `fanos` 与服务器 `.env.cloud`。固定到上述 Git 提交构建，并更新 `api`、`admin`、`catalog-index-worker` 三个应用容器；PostgreSQL、Redis 及原数据卷继续使用。

部署前核对了线上未提交补丁：识别补丁与本地一致，图鉴图片/成员补丁为本地版本的子集。已保存补丁、未跟踪模型、配置和 Git stash 后再快进更新。模型附带 MIT 许可及 SHA-256 校验。原模型目录的所有者差异已修正，未丢弃线上补丁。

没有重新生成服务器配置、执行演示数据清理或导入演示数据。`.env.cloud` 部署前后 SHA-256 一致；`AUTO_SEED` 保持关闭。开发验证码脚本已纳入 Git，但本次未执行该脚本，服务器现有登录配置保留。

数据库保持 `e612_color_bigint`。上线前后 PostgreSQL `alembic check` 均通过，本次没有新增数据库迁移。已有迁移文件的差异仅为导入顺序和字符串换行。

## 备份与回滚

私有备份目录：`/home/ubuntu/FanOS-backups/ui-20261013T155807Z`，目录权限 700，文件按 600 保存。备份只留在服务器，未提交到 Git。

- `database.dump`：PostgreSQL 自定义格式备份，约 448 KiB；已通过 `pg_restore --list` 读取归档目录。未执行覆盖恢复。
- `uploads.tar.gz`：约 7.6 MiB；`card-matcher.tar.gz`：约 492 KiB。已验证 gzip 完整性并生成 SHA-256 清单。
- `server-local-files.tar.gz`、`server-patches.diff`：服务器原始配置及补丁。
- `previous-images.txt`：原 API、后台和索引服务镜像 ID；均已额外打上 `before-ui-20261013T155807Z` 标签。
- `rollback.compose.yml`：保留原镜像和原 Nginx 配置的回滚覆盖文件。

如需回退应用，在服务器运行：

```sh
cd /home/ubuntu/FanOS-code
sudo docker compose -p fanos --env-file .env.cloud \
  -f docker-compose.cloud.yml \
  -f /home/ubuntu/FanOS-backups/ui-20261013T155807Z/rollback.compose.yml \
  up -d --no-build api admin catalog-index-worker
curl -fsS http://127.0.0.1:8000/health
```

该方式恢复的是发布前实际运行、包含历史线上补丁的镜像。回滚不删除数据卷，也不需要回退数据库结构。数据库备份仅用于另行确认后的数据恢复。

## 验证记录

- API：231 项 pytest 通过；Ruff 格式与静态检查通过。
- 后台：ESLint、类型检查、生产构建、11 项单元测试、31 项完整端到端测试通过；详见 UI 验收文档。
- 云端构建成功，三个应用容器运行中、重启次数为 0；API `/health` 返回 `ok`。
- 部署前后 **56 张表的行数一致、77 个上传文件 SHA-256 一致**，服务器配置不变。
- API 与索引容器各 **127 个源码/配置/模型文件** 与已部署 Git 工作区一致。
- 线上浏览器：现有管理员登录成功；29 个页面入口在 1440 宽度通过，另检查小卡页 1280 / 1920 宽度，共 31 个页面视图通过；没有页面运行错误、API 5xx 或页面级横向溢出。已人工查看云端组合与小卡列表截图。
- Other 导入模板的组合、多艺人及图片字段读取成功；公开图鉴 API 正常；人物检测可用，现有 2 张小卡索引保留。
- 线上浏览器验收结果及 8 张截图：`output/admin-ui-20261013/cloud/`，日志 `cloud-smoke.log`；验收使用现有管理员，只读取列表/详情及导入模板，不新增、编辑或删除运营记录。

复验中的已知限制：SQLite 空库迁移能完成，但 `alembic check` 仍报告既有颜色字段 `INTEGER / BigInteger` 差异，因为此前 `e612_color_bigint` 仅在 PostgreSQL 上执行类型转换。该问题不由本次发布引入；云端 PostgreSQL 检查通过。后台构建仍有主包超过 500 kB 的提示，未影响构建成功。

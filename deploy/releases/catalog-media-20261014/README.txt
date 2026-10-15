Fan OS 图片转存云端更新 · 2026-10-14

需要更新服务器，仅安装新版 APK 不会执行图片下载。
本包包含当前已测试的 API/管理后台代码快照、媒体 Worker 与 Compose 配置。
执行脚本会覆盖清单中的源代码；执行前自动备份源代码和数据库。
不会替换 .env.cloud，不会清空数据库、上传图片、收藏或 AI 索引。
默认仍使用服务器已有持久化媒体目录，不要求购买 COS。

一、在 Mac 终端上传（不是已经 SSH 登录的服务器终端）
scp -i /Users/nancy/.ssh/fanos_cloud -o IdentitiesOnly=yes "/Users/nancy/Documents/ChatGPT/FanOS/output/releases/FanOS-Cloud-Media-20261014.zip" ubuntu@106.53.120.249:/home/ubuntu/

二、SSH 登录后，在服务器执行
cd /home/ubuntu
unzip FanOS-Cloud-Media-20261014.zip -d fanos-media-20261014
sudo bash /home/ubuntu/fanos-media-20261014/deploy.sh

脚本固定项目名 fanos，目录 /home/ubuntu/FanOS-code；会核对现有数据库与媒体卷。
检查不通过时立即停止，不要改成 fanos-code，不要运行 down -v，不要重新 seed。
第一次运行若解压目录已存在，请先确认是不是同一更新包，避免覆盖另一次部署资料。
如果构建失败，旧容器仍在提供服务；保存输出以便排查。
若切换 API 后健康检查失败，应停止后续操作，保留脚本显示的备份目录。

三、部署内容
1. API：导入/编辑组合、艺人、专辑、活动、其他、小卡和版本封面时创建持久化任务。
2. catalog-media-worker：后台下载、验证、转存、生成 384px WebP 缩略图；大图最大边 2048px。
3. Admin：图鉴详情 > 素材 > 图片转存，可看状态、补下载、重试。
4. Nginx：转存图片的 UUID 地址允许缓存；不对私人用户照片添加公共缓存规则。
5. 历史图片：脚本自动执行一次 --backfill，仅加入任务队列，可重复运行。
6. 小卡：转存成功后自动提交 AI 索引更新，不需要用户再次上传。

四、查看进度
cd /home/ubuntu/FanOS-code
sudo docker compose -p fanos --env-file .env.cloud -f docker-compose.cloud.yml logs --tail=80 catalog-media-worker
sudo docker compose -p fanos --env-file .env.cloud -f docker-compose.cloud.yml ps

后台可查看每张图片的等待下载、下载中、待重试、已转存、失败等状态。
外链图片在转存成功前 App 展示占位图，不再将外链返回给 App。
历史图较多时需要等待队列完成；可以刷新图鉴或重新进入 App 获取最新地址。
首次无法访问的外链仍可能失败，最多自动尝试 5 次，之后需后台手动重试或上传本地图片。
本机测试不能证明服务器一定能访问 Wikimedia，请以云端任务状态为准。

五、下载来源限制
默认仅允许 https://upload.wikimedia.org，拒绝重定向、非图片、超 20MB、超 4000 万像素及内网来源。
如需新的合法图片来源，在 .env.cloud 加入 JSON 域名列表并重新创建 catalog-media-worker：
CATALOG_IMAGE_HOSTS=["upload.wikimedia.org","已审核的图片域名"]
不要改为允许任意域名。图片权利和授权要求仍需满足。
使用非白名单地址的导入资料会正常保存，但图片任务失败，后台显示原因。

六、数据存储
图片：现有 fan_os_uploads 卷中的 catalog-managed/ 与 catalog-managed/thumbs/。
数据库：原图地址、下载任务状态、重试次数、转存 URL 和缩略图 URL。
不是把图片二进制写入数据库。使用已有 Outbox 表，不新增专用媒体表。
脚本仍会执行项目已有 Alembic 迁移，已完成的迁移不会重复执行。

七、回滚注意
备份目录形如 /home/ubuntu/fanos-media-backup.XXXXXX：
source-before.tar.gz 是被覆盖前的代码；database.dump 是 PostgreSQL 自定义格式备份；
api-image.txt、admin-image.txt 记录旧镜像 ID；new-files.json 记录新增源码文件。
不要直接将数据库备份覆盖线上，因为这会抹掉部署后用户新操作；有异常请先保留日志和备份。
本次任务不执行生产部署、不执行 Git commit/push，也不更新 iOS。

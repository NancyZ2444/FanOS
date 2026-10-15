Fan OS 用户反馈闭环 · 2026-10-14

本包更新 API、后台管理页面和数据库迁移。没有 .env、数据库、密钥或用户上传图片。
新版 Android 仍使用 http://106.53.120.249:5173/api/v1，因此需要先部署本包。
iOS 模拟器包使用本机 http://127.0.0.1:8000/api/v1，不依赖云端部署。

在 Mac 终端上传（使用此前已有的 SSH 密钥，不要上传密钥本身）：
scp -i /Users/nancy/.ssh/fanos_cloud -o IdentitiesOnly=yes "/Users/nancy/Documents/ChatGPT/FanOS/output/releases/FanOS-Cloud-Feedback-20261014.zip" ubuntu@106.53.120.249:/home/ubuntu/

SSH 进入服务器后执行：
cd /home/ubuntu
unzip FanOS-Cloud-Feedback-20261014.zip -d fanos-feedback-20261014
sudo bash /home/ubuntu/fanos-feedback-20261014/deploy.sh

固定使用 /home/ubuntu/FanOS-code 和 Compose 项目 fanos。
脚本先核对现有数据库/上传卷，备份 PostgreSQL、源码和镜像 ID，再构建、迁移和更新 API/管理后台。
保留 .env.cloud、上传图片、数据库、索引，不执行 down -v，不启动另一个 fanos-code 项目。
数据库新增反馈、图片版本引用、贡献关系和通知重试表；同时包含上一轮卡册收藏分组迁移。
若预检、迁移或健康检查失败，停止并保留输出和备份路径，不要删除卷或强行 stamp 迁移。
回滚应使用备份源码/镜像；新增表可以保留，已经产生的用户反馈不能直接删除。

验证：
1. 管理后台出现“小卡缺失收录”“图鉴问题纠错”两个独立入口。
2. App 从专辑/艺人/组合/活动/其他/小卡详情提交字段纠错。
3. 运营保存意见不修改正式图鉴；确认发布后 App 刷新反馈结果和通知。
4. 扫描反馈：双面必填背面；单人必填艺人；缺失来源可暂存但发布前必须补建。
5. 用户图片免填来源链接，但发布仍必须单独核实版权状态。
6. 图片正式采用后，贡献来源和我的贡献出现；下架后隐藏贡献卡片，反馈历史保留。
7. 进入已收录图鉴内容时 App 会刷新图鉴数据；返回仍保留扫描列表。

站内消息已接通，失败记录会在后续处理和用户读取消息时重试。
系统 Push 仍依赖项目已有推送能力，本包不包含 APNs/厂商推送服务配置。
这不是生产部署确认；需由服务器部署结果和手机验收共同确认。

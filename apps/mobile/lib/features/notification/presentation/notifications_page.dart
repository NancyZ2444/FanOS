import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(socialFeedProvider);
    final settings = ref.watch(idolFeedNotificationProvider);
    final primaryId = ref.watch(favoritesProvider).primaryId;
    final catalog = ref.watch(catalogProvider).value;
    final primaryName = catalog?.idols
        .where((idol) => idol.id == primaryId)
        .firstOrNull
        ?.name;

    const items = <(IconData, Color, String, String)>[
      (
        Icons.auto_awesome_rounded,
        FanColors.lavender,
        '今日翻卡已开启',
        '3 次机会正在等待你 · 刚刚',
      ),
      (
        Icons.style_rounded,
        Color(0xFF4F73B7),
        '图鉴新增 12 张小卡',
        'LUMINA「Starlit」系列已更新 · 2 小时前',
      ),
      (
        Icons.campaign_outlined,
        FanColors.coral,
        'Fan OS 内测说明',
        '欢迎体验 Phase 1 移动端原型 · 昨天',
      ),
    ];
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('通知')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          if (settings.enabled && feed.newCount > 0) ...[
            Material(
              key: const Key('compact-feed-notice'),
              color: FanColors.lavenderSoft,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => context.push('/feed'),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.dynamic_feed_rounded,
                        size: 19,
                        color: FanColors.lavender,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${primaryName ?? '本命'}今天有 ${feed.newCount} 条新动态',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Text(
                        '去看看',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 17),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          const Text('本命动态通知', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dynamic_feed_outlined),
                  title: const Text('本命有新动态'),
                  subtitle: const Text('按天聚合公开内容更新'),
                  value: settings.enabled,
                  onChanged: ref
                      .read(idolFeedNotificationProvider.notifier)
                      .setEnabled,
                ),
                const Divider(height: 1, indent: 58),
                SwitchListTile(
                  secondary: const Icon(Icons.star_outline_rounded),
                  title: const Text('星标优先'),
                  value: settings.primaryIdolFirst,
                  onChanged: settings.enabled
                      ? ref
                            .read(idolFeedNotificationProvider.notifier)
                            .setPrimaryIdolFirst
                      : null,
                ),
                const Divider(height: 1, indent: 58),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('接收 Push'),
                  subtitle: const Text('正式服务接入后生效'),
                  value: settings.pushEnabled,
                  onChanged: settings.enabled
                      ? ref
                            .read(idolFeedNotificationProvider.notifier)
                            .setPushEnabled
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '本命内容通知与关注其他用户的社交通知相互独立。',
              style: TextStyle(fontSize: 11, color: FanColors.textSecondary),
            ),
          ),
          const SizedBox(height: 24),
          const Text('最近通知', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (var index = 0; index < items.length; index++) ...[
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: items[index].$2.withValues(alpha: .12),
                  ),
                  child: Icon(items[index].$1, color: items[index].$2),
                ),
                title: Text(
                  items[index].$3,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(items[index].$4),
                ),
              ),
            ),
            if (index != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/config/feature_flags.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum NoticeSection { announcements, notifications, feedback }

final noticeItemsProvider = FutureProvider.autoDispose
    .family<List<FeedbackJson>, NoticeSection>((ref, section) async {
      if (useMockApi) return [];
      if (section != NoticeSection.announcements &&
          !ref.watch(sessionProvider).isLoggedIn) {
        return [];
      }
      final data = await ref
          .watch(apiClientProvider)
          .getData(
            section == NoticeSection.announcements
                ? '/announcements'
                : '/notifications/inbox',
            query: section == NoticeSection.announcements
                ? null
                : {
                    'category': section == NoticeSection.feedback
                        ? 'FEEDBACK_RESULT'
                        : 'NOTIFICATION',
                  },
          );
      return feedbackItems(data['items']);
    });

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: 1,
  );
  @override
  void initState() {
    super.initState();
    _tabs.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_changed);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh(NoticeSection section) async {
    ref.invalidate(noticeItemsProvider(section));
    try {
      await ref.read(noticeItemsProvider(section).future);
    } catch (_) {
      // The selected list renders its own retryable error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = NoticeSection.values[_tabs.index];
    final loading = ref.watch(noticeItemsProvider(section)).isLoading;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('通知'),
        actions: [
          IconButton(
            key: const Key('notifications-refresh'),
            tooltip: '刷新',
            onPressed: loading ? null : () => _refresh(section),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '公告'),
            Tab(text: '通知'),
            Tab(text: '反馈结果'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final value in NoticeSection.values)
            _NoticeList(section: value, onRefresh: () => _refresh(value)),
        ],
      ),
    );
  }
}

class _NoticeList extends ConsumerWidget {
  const _NoticeList({required this.section, required this.onRefresh});
  final NoticeSection section;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(noticeItemsProvider(section));
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: PageStorageKey(section),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          if (section == NoticeSection.notifications)
            const _FeedNoticeSettings(),
          ...items.when(
            loading: () => [const LinearProgressIndicator()],
            error: (error, _) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(feedbackError(error), textAlign: TextAlign.center),
              ),
            ],
            data: (values) => values.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        switch (section) {
                          NoticeSection.announcements => '暂无公告',
                          NoticeSection.notifications => '暂无通知',
                          NoticeSection.feedback => '暂无反馈结果',
                        },
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: FanColors.textSecondary),
                      ),
                    ),
                  ]
                : [
                    for (final item in values)
                      _NoticeTile(item: item, section: section),
                  ],
          ),
        ],
      ),
    );
  }
}

class _NoticeTile extends ConsumerWidget {
  const _NoticeTile({required this.item, required this.section});
  final FeedbackJson item;
  final NoticeSection section;
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (section != NoticeSection.announcements && item['read_at'] == null) {
      try {
        await ref
            .read(apiClientProvider)
            .postData('/notifications/inbox/${item['id']}/read');
        ref.invalidate(noticeItemsProvider(section));
      } catch (_) {
        /* Reading must not block opening the message. */
      }
    }
    if (!context.mounted) return;
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? item);
    final feedbackId = payload['feedback_id'];
    if (section == NoticeSection.feedback && feedbackId != null) {
      await context.push('/feedback/$feedbackId');
      return;
    }
    final target = switch (payload['target_type']) {
      'CARD' => '/card/',
      'ALBUM' => '/album/',
      'GROUP' => '/group/',
      'IDOL' => '/idol/',
      _ => null,
    };
    if (target != null && payload['target_id'] != null) {
      await context.push('$target${payload['target_id']}');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['title'] ?? '消息',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(item['content'] ?? ''),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: Icon(
        section == NoticeSection.announcements
            ? Icons.campaign_outlined
            : item['read_at'] == null
            ? Icons.mark_email_unread_outlined
            : Icons.drafts_outlined,
      ),
      title: Text(item['title'] ?? '消息'),
      subtitle: Text(
        item['content'] ?? '',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _open(context, ref),
    ),
  );
}

class _FeedNoticeSettings extends ConsumerWidget {
  const _FeedNoticeSettings();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showFeed = ref.watch(idolFeedEnabledProvider);
    if (!showFeed) return const SizedBox.shrink();
    final feed = ref.watch(socialFeedProvider);
    final settings = ref.watch(idolFeedNotificationProvider);
    final primaryId = ref.watch(favoritesProvider).primaryId;
    final catalog = ref.watch(catalogProvider).value;
    final primaryName = catalog?.idols
        .where((idol) => idol.id == primaryId)
        .firstOrNull
        ?.name;
    return Column(
      children: [
        if (showFeed && settings.enabled && feed.newCount > 0) ...[
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
        if (showFeed) ...[
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
        ],
      ],
    );
  }
}

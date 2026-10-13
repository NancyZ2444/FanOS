import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(socialFeedProvider.notifier).ensureHomeLoaded(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final daily = ref.watch(dailyCardProvider);
    final favorites = ref.watch(favoritesProvider);
    final catalog = ref.watch(catalogProvider);
    final feed = ref.watch(socialFeedProvider);
    final feedNotifications = ref.watch(idolFeedNotificationProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.refresh(catalogProvider.future),
              ref.read(socialFeedProvider.notifier).refreshHome(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: FanContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FanWordmark(),
                      const Spacer(),
                      IconButton(
                        tooltip: '通知',
                        onPressed: () => context.push('/notifications'),
                        icon: feedNotifications.enabled && feed.newCount > 0
                            ? Badge.count(
                                count: feed.newCount,
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                ),
                              )
                            : const Icon(Icons.notifications_none_rounded),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => context.go('/profile'),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: FanColors.lavenderSoft,
                          child: ClipOval(
                            child: FanImage(
                              imageUrl: session.avatarPath,
                              fallback: Text(
                                session.isGuest ? '游' : '星',
                                style: const TextStyle(
                                  color: FanColors.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FanSearchButton(onTap: () => context.push('/search')),
                  const SizedBox(height: 16),
                  _HeroBanner(
                    album: catalog.asData?.value.albums.firstOrNull,
                    card: catalog.asData?.value.cards.firstOrNull,
                    onTap: () => context.go('/catalog'),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(
                    title: '今日翻卡',
                    subtitle: '每天 3 次，发现与你有关的小卡',
                  ),
                  const SizedBox(height: 10),
                  _DailyCardBanner(
                    daily: daily,
                    isGuest: session.isGuest,
                    onTap: () => _openProtected(
                      context,
                      ref,
                      () => context.push('/daily-card'),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SectionHeader(
                    title: session.isGuest ? '热门艺人' : '我的本命',
                    actionLabel: session.isGuest
                        ? '登录设置'
                        : favorites.selectedIds.isEmpty
                        ? '添加本命'
                        : '管理',
                    onAction: () => session.isGuest
                        ? context.push('/login')
                        : context.push('/onboarding/favorites'),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 92,
                    child: catalog.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => const Center(child: Text('暂时无法加载')),
                      data: (data) {
                        if (!session.isGuest && favorites.selectedIds.isEmpty) {
                          return _EmptyFavoritesPrompt(
                            onTap: () => context.push('/onboarding/favorites'),
                          );
                        }
                        final idols = session.isGuest
                            ? data.idols.take(5).toList()
                            : data.idols
                                  .where(
                                    (idol) =>
                                        favorites.selectedIds.contains(idol.id),
                                  )
                                  .toList();
                        if (idols.isEmpty && !session.isGuest) {
                          return _EmptyFavoritesPrompt(
                            onTap: () => context.push('/onboarding/favorites'),
                          );
                        }
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: idols.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 16),
                          itemBuilder: (context, index) =>
                              _IdolShortcut(idol: idols[index]),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: feed.newCount > 0
                        ? '本命动态 · ${feed.newCount} 条新动态'
                        : '本命动态',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/feed'),
                  ),
                  if (!session.isGuest && favorites.selectedIds.isEmpty) ...[
                    const SizedBox(height: 6),
                    _CompactFeedFavoriteHint(
                      onTap: () => context.push('/onboarding/favorites'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _HomeFeedPreview(
                    state: feed,
                    primaryIdolId: favorites.primaryId,
                    onOpen: () => context.push('/feed'),
                    onPostOpen: (post) {
                      ref.read(socialFeedProvider.notifier).markViewed(post.id);
                      ref.read(feedEngagementProvider.notifier).registerPosts([
                        post,
                      ]);
                      context.push('/feed/post/${post.id}', extra: post);
                    },
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(title: '快捷入口'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.document_scanner_outlined,
                          label: 'AI Scan',
                          color: FanColors.lavenderSoft,
                          onTap: () => context.go('/scan'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.auto_stories_outlined,
                          label: '官方图鉴',
                          color: FanColors.blueSoft,
                          onTap: () => context.go('/catalog'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.favorite_border_rounded,
                          label: '我的收藏',
                          color: const Color(0xFFFFECE8),
                          onTap: () => _openProtected(
                            context,
                            ref,
                            () => context.go('/collection'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openProtected(
    BuildContext context,
    WidgetRef ref,
    VoidCallback onAuthenticated,
  ) {
    if (ref.read(sessionProvider).isGuest) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 34),
              const SizedBox(height: 12),
              Text('登录后继续', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '登录后即可保存本命、收藏并参与每日翻卡。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/login');
                },
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    onAuthenticated();
  }
}

class _HomeFeedPreview extends StatelessWidget {
  const _HomeFeedPreview({
    required this.state,
    required this.primaryIdolId,
    required this.onOpen,
    required this.onPostOpen,
  });

  final SocialFeedState state;
  final String? primaryIdolId;
  final VoidCallback onOpen;
  final ValueChanged<SocialFeedPost> onPostOpen;

  @override
  Widget build(BuildContext context) {
    final posts = state.homePosts(primaryIdolId).take(3).toList();
    if (state.isHomeLoading && posts.isEmpty) {
      return const Card(
        child: SizedBox(
          height: 112,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (posts.isEmpty) {
      return InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.dynamic_feed_outlined,
                  color: Color(0xFF4F73B7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.errorMessage ?? '暂时还没有获取到近期动态',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < posts.length; index++) ...[
            _HomePostRow(
              post: posts[index],
              onTap: () => onPostOpen(posts[index]),
            ),
            if (index != posts.length - 1) const Divider(height: 1, indent: 72),
          ],
        ],
      ),
    );
  }
}

class _EmptyFavoritesPrompt extends StatelessWidget {
  const _EmptyFavoritesPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('empty-favorites-prompt'),
      color: FanColors.lavenderSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 21,
                backgroundColor: Colors.white,
                child: Icon(Icons.favorite_border_rounded, size: 21),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '还没有设置本命',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '添加后可在首页快速查看',
                      style: TextStyle(
                        color: FanColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                '去添加',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactFeedFavoriteHint extends StatelessWidget {
  const _CompactFeedFavoriteHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('home-feed-favorite-hint'),
      color: FanColors.blueSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  '当前展示默认动态，设置本命后可优先查看',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11),
                ),
              ),
              SizedBox(width: 6),
              Text(
                '设置',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              Icon(Icons.chevron_right_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePostRow extends ConsumerWidget {
  const _HomePostRow({required this.post, required this.onTap});

  final SocialFeedPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(namePreferencesProvider);
    final media = post.media.firstOrNull;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(post.idolColorStart),
                    Color(post.idolColorEnd),
                  ],
                ),
              ),
              child: ClipOval(
                child: FanImage(
                  imageUrl: post.idolImageUrl,
                  fallback: Text(
                    post.idolInitials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: names.display(
                            post.isGroupAuthor ? 'groups' : 'idols',
                            post.isGroupAuthor ? post.groupId : post.idolId,
                            post.idolName,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: '  ${post.platform.displayName}',
                          style: const TextStyle(
                            color: FanColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.isAvailable ? post.content : '原动态已删除或不可访问',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            if (media != null) ...[
              const SizedBox(width: 10),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [Color(media.colorStart), Color(media.colorEnd)],
                  ),
                ),
                child: Icon(
                  media.type == SocialMediaType.video
                      ? Icons.play_arrow_rounded
                      : Icons.photo_outlined,
                  color: Colors.white,
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 13),
                child: Icon(Icons.chevron_right_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onTap, this.album, this.card});
  final VoidCallback onTap;
  final CatalogAlbum? album;
  final CollectibleCard? card;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF171A32), Color(0xFF776DCB)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    album == null
                        ? 'FAN OS · DISCOVER'
                        : '${album!.artistName} · ${album!.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '把每一次心动\n收进你的宇宙',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 92,
              child: Transform.rotate(
                angle: .12,
                child: FanArtwork(
                  imageUrl: album?.frontImageUrl ?? card?.imageUrl,
                  startColor: Color(0xFFC9BBFF),
                  endColor: Color(0xFF555497),
                  label: 'AR',
                  borderRadius: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyCardBanner extends StatelessWidget {
  const _DailyCardBanner({
    required this.daily,
    required this.isGuest,
    required this.onTap,
  });

  final DailyCardState daily;
  final bool isGuest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = isGuest ? 3 : daily.remaining;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFF3E8FF), Color(0xFFE3E7FF)],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.style_rounded,
                color: FanColors.lavender,
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    daily.remaining == 0 && !isGuest
                        ? '今日翻卡已完成'
                        : '还有 $remaining 次机会',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isGuest ? '登录后开启今日惊喜' : '至少一张与你的本命相关',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: FanColors.ink,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                daily.remaining == 0 && !isGuest ? '查看' : '立即翻卡',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdolShortcut extends StatelessWidget {
  const _IdolShortcut({required this.idol});
  final IdolProfile idol;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: () => context.push('/idol/${idol.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            IdolAvatar(idol: idol, size: 58),
            const SizedBox(height: 7),
            Text(
              idol.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, size: 25),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

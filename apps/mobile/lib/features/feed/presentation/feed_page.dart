import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final _scrollController = ScrollController();
  final Set<String> _expandedPostIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future<void>.microtask(() async {
      await ref.read(socialFeedProvider.notifier).ensureLoaded();
      if (mounted) ref.read(socialFeedProvider.notifier).markFeedOpened();
    });
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 360) {
      ref.read(socialFeedProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final count = await ref.read(socialFeedProvider.notifier).refresh();
    if (!mounted) return;
    if (count == null) {
      showFanToast(context, '刷新失败，当前继续展示已缓存内容');
    } else if (count == 0) {
      showFanToast(context, '已经是最新了');
    } else {
      showFanToast(context, '更新了 $count 条动态');
    }
  }

  void _toggleExpanded(SocialFeedPost post) {
    setState(() {
      if (!_expandedPostIds.add(post.id)) _expandedPostIds.remove(post.id);
    });
    ref.read(socialFeedProvider.notifier).markViewed(post.id);
  }

  void _openPostDetail(SocialFeedPost post) {
    ref.read(socialFeedProvider.notifier).markViewed(post.id);
    ref.read(feedEngagementProvider.notifier).registerPosts([post]);
    context.push('/feed/post/${post.id}', extra: post);
  }

  Future<void> _openOriginal(SocialFeedPost post) async {
    ref.read(socialFeedProvider.notifier).markViewed(post.id);
    try {
      final deepLink = Uri.tryParse(post.deepLinkUrl ?? '');
      if (deepLink != null && await canLaunchUrl(deepLink)) {
        await launchUrl(deepLink, mode: LaunchMode.externalApplication);
        return;
      }
      final webUrl = Uri.parse(post.originalUrl);
      if (await launchUrl(webUrl, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The user still gets a clear in-app error when neither route works.
    }
    if (mounted) showFanToast(context, '暂时无法打开${post.platform.displayName}');
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(socialFeedProvider);
    final favorites = ref.watch(favoritesProvider);
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('本命动态'),
        actions: [
          IconButton(
            tooltip: '通知设置',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _FeedFilters(
            catalog: catalog,
            favoriteIds: favorites.selectedIds,
            selectedIdolId: feed.selectedIdolId,
            selectedPlatform: feed.selectedPlatform,
            unavailablePlatforms: feed.unavailablePlatforms,
            onIdolSelected: (idolId) =>
                ref.read(socialFeedProvider.notifier).selectIdol(idolId),
            onPlatformSelected: (platform) =>
                ref.read(socialFeedProvider.notifier).selectPlatform(platform),
          ),
          Expanded(child: _buildBody(feed)),
        ],
      ),
    );
  }

  Widget _buildBody(SocialFeedState feed) {
    if (feed.isInitialLoading && feed.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.errorMessage != null && feed.posts.isEmpty) {
      return FanEmptyState(
        icon: Icons.cloud_off_rounded,
        title: '动态暂时加载失败',
        message: '没有可用缓存，请检查网络后重新加载。',
        actionLabel: '重新加载',
        onAction: () => ref.read(socialFeedProvider.notifier).refresh(),
      );
    }
    if (feed.posts.isEmpty) {
      final idolName = _selectedIdolName(feed.selectedIdolId);
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: FanEmptyState(
                icon: Icons.dynamic_feed_outlined,
                title: idolName == null
                    ? '暂时还没有近期动态'
                    : '暂时还没有获取到 $idolName 的近期动态',
                message: '可以切换其他本命或平台后再试。',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        key: const Key('idol-feed-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        itemCount: feed.posts.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) return _FeedStatusBanner(feed: feed);
          if (index == feed.posts.length + 1) {
            return _PaginationFooter(
              state: feed,
              onRetry: () => ref.read(socialFeedProvider.notifier).loadMore(),
            );
          }
          final post = feed.posts[index - 1];
          return SocialFeedCard(
            post: post,
            expanded: _expandedPostIds.contains(post.id),
            viewed: feed.viewedPostIds.contains(post.id),
            onToggleExpanded: () => _toggleExpanded(post),
            onOpenOriginal: () => _openOriginal(post),
            onOpenAuthor: () => context.push(post.authorRoute),
            onOpenGroup: () => context.push(post.groupRoute),
            onOpenComments: () => _openPostDetail(post),
            onOpenRelation: post.relation == null
                ? null
                : () {
                    ref.read(socialFeedProvider.notifier).markViewed(post.id);
                    context.push(post.relation!.route);
                  },
          );
        },
      ),
    );
  }

  String? _selectedIdolName(String? idolId) {
    if (idolId == null) return null;
    final catalog = ref.read(catalogProvider).value;
    for (final idol in catalog?.idols ?? const <IdolProfile>[]) {
      if (idol.id == idolId) return idol.displayName;
    }
    return null;
  }
}

class _FeedFilters extends StatelessWidget {
  const _FeedFilters({
    required this.catalog,
    required this.favoriteIds,
    required this.selectedIdolId,
    required this.selectedPlatform,
    required this.unavailablePlatforms,
    required this.onIdolSelected,
    required this.onPlatformSelected,
  });

  final AsyncValue<CatalogBundle> catalog;
  final Set<String> favoriteIds;
  final String? selectedIdolId;
  final SocialPlatform? selectedPlatform;
  final Set<SocialPlatform> unavailablePlatforms;
  final ValueChanged<String?> onIdolSelected;
  final ValueChanged<SocialPlatform?> onPlatformSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: FanColors.canvas,
      padding: const EdgeInsets.fromLTRB(20, 2, 0, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: favoriteIds.isEmpty ? '全部动态' : '全部本命',
                  selected: selectedIdolId == null,
                  onTap: () => onIdolSelected(null),
                ),
                ...catalog.when(
                  loading: () => const <Widget>[],
                  error: (_, _) => const <Widget>[],
                  data: (data) {
                    final visibleIds = favoriteIds.isEmpty
                        ? data.groups.first.memberIds.toSet()
                        : favoriteIds;
                    return data.idols
                        .where((idol) => visibleIds.contains(idol.id))
                        .map(
                          (idol) => _IdolFilterChip(
                            idol: idol,
                            selected: selectedIdolId == idol.id,
                            onTap: () => onIdolSelected(idol.id),
                          ),
                        )
                        .toList();
                  },
                ),
                const SizedBox(width: 20),
              ],
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: '全部平台',
                  selected: selectedPlatform == null,
                  compact: true,
                  onTap: () => onPlatformSelected(null),
                ),
                for (final platform in SocialPlatform.values)
                  _FilterChip(
                    label:
                        '${platform.displayName}${unavailablePlatforms.contains(platform) ? ' · 暂停更新' : ''}',
                    selected: selectedPlatform == platform,
                    compact: true,
                    warning: unavailablePlatforms.contains(platform),
                    onTap: () => onPlatformSelected(platform),
                  ),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.warning = false,
  });

  final String label;
  final bool selected;
  final bool compact;
  final bool warning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: compact ? VisualDensity.compact : null,
        side: warning && !selected
            ? const BorderSide(color: FanColors.coral)
            : null,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _IdolFilterChip extends StatelessWidget {
  const _IdolFilterChip({
    required this.idol,
    required this.selected,
    required this.onTap,
  });

  final IdolProfile idol;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: IdolAvatar(idol: idol, size: 24),
        label: Text(idol.displayName),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _FeedStatusBanner extends StatelessWidget {
  const _FeedStatusBanner({required this.feed});

  final SocialFeedState feed;

  @override
  Widget build(BuildContext context) {
    final selectedUnavailable =
        feed.selectedPlatform != null &&
        feed.unavailablePlatforms.contains(feed.selectedPlatform);
    final message = selectedUnavailable
        ? '${feed.selectedPlatform!.displayName} 暂时无法更新，以下为历史缓存'
        : feed.isFromCache || feed.errorMessage != null
        ? '部分动态可能不是最新，当前继续展示历史缓存'
        : feed.unavailablePlatforms.isNotEmpty
        ? '${feed.unavailablePlatforms.map((item) => item.displayName).join('、')} 暂时无法更新，其他平台内容不受影响'
        : '仅聚合公开内容，不读取私信、私人关注 Feed 或非公开内容';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: selectedUnavailable || feed.isFromCache
            ? const Color(0xFFFFF0E9)
            : FanColors.blueSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            selectedUnavailable || feed.isFromCache
                ? Icons.info_outline_rounded
                : Icons.public_rounded,
            size: 18,
            color: selectedUnavailable || feed.isFromCache
                ? FanColors.coral
                : const Color(0xFF4F73B7),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class SocialFeedCard extends ConsumerWidget {
  const SocialFeedCard({
    required this.post,
    required this.expanded,
    required this.viewed,
    required this.onToggleExpanded,
    required this.onOpenOriginal,
    required this.onOpenRelation,
    required this.onOpenAuthor,
    required this.onOpenGroup,
    required this.onOpenComments,
    super.key,
  });

  final SocialFeedPost post;
  final bool expanded;
  final bool viewed;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenOriginal;
  final VoidCallback? onOpenRelation;
  final VoidCallback onOpenAuthor;
  final VoidCallback onOpenGroup;
  final VoidCallback onOpenComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engagement = ref.watch(feedEngagementProvider);
    final liked = engagement.likedPostIds.contains(post.id);
    return Card(
      color: viewed ? const Color(0xFFFCFCFD) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PostHeader(
              post: post,
              viewed: viewed,
              onOpenAuthor: onOpenAuthor,
              onOpenGroup: onOpenGroup,
            ),
            const SizedBox(height: 13),
            if (!post.isAvailable)
              const _UnavailablePost()
            else ...[
              Text(
                post.content,
                maxLines: expanded ? null : 5,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.52),
              ),
              if (post.content.length > 72)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onToggleExpanded,
                    child: Text(expanded ? '收起' : '展开'),
                  ),
                ),
              if (post.media.isNotEmpty) ...[
                const SizedBox(height: 9),
                SocialMediaGrid(media: post.media, onTap: onOpenOriginal),
              ],
              if (post.relation != null) ...[
                const SizedBox(height: 12),
                _RelatedContent(
                  relation: post.relation!,
                  onTap: onOpenRelation!,
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: Key('feed-like-${post.id}'),
                    onPressed: () => ref
                        .read(feedEngagementProvider.notifier)
                        .togglePostLike(post.id),
                    icon: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                      color: liked ? FanColors.coral : FanColors.ink,
                    ),
                    label: Text('${engagement.likeCount(post)}'),
                  ),
                  TextButton.icon(
                    key: Key('feed-comments-${post.id}'),
                    onPressed: onOpenComments,
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                    ),
                    label: Text('评论 ${engagement.commentCount(post)}'),
                  ),
                  TextButton.icon(
                    onPressed: onOpenOriginal,
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('原动态'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostHeader extends ConsumerWidget {
  const _PostHeader({
    required this.post,
    required this.viewed,
    required this.onOpenAuthor,
    required this.onOpenGroup,
  });

  final SocialFeedPost post;
  final bool viewed;
  final VoidCallback onOpenAuthor;
  final VoidCallback onOpenGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(namePreferencesProvider);
    return Row(
      children: [
        InkWell(
          onTap: onOpenAuthor,
          customBorder: const CircleBorder(),
          child: Container(
            width: 43,
            height: 43,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(post.idolColorStart), Color(post.idolColorEnd)],
              ),
            ),
            child: ClipOval(
              child: FanImage(
                imageUrl: post.idolImageUrl,
                fallback: Text(
                  post.idolInitials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
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
              Row(
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: onOpenAuthor,
                      child: Text(
                        names.display(
                          post.isGroupAuthor ? 'groups' : 'idols',
                          post.isGroupAuthor ? post.groupId : post.idolId,
                          post.idolName,
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _PlatformBadge(platform: post.platform),
                ],
              ),
              const SizedBox(height: 3),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!post.isGroupAuthor) ...[
                    InkWell(
                      onTap: onOpenGroup,
                      child: Text(
                        names.display('groups', post.groupId, post.groupName),
                        style: const TextStyle(
                          color: FanColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      ' · ',
                      style: TextStyle(color: FanColors.textSecondary),
                    ),
                  ],
                  Text(
                    _relativeTime(post.postedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!viewed)
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: FanColors.lavender,
            ),
          )
        else
          const Text(
            '已读',
            style: TextStyle(fontSize: 10, color: FanColors.textSecondary),
          ),
      ],
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});

  final SocialPlatform platform;

  @override
  Widget build(BuildContext context) {
    final icon = switch (platform) {
      SocialPlatform.weibo => Icons.rss_feed_rounded,
      SocialPlatform.instagram => Icons.camera_alt_outlined,
      SocialPlatform.x => Icons.close_rounded,
      SocialPlatform.xiaohongshu => Icons.menu_book_rounded,
      SocialPlatform.douyin => Icons.music_note_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(platform.displayName, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class SocialMediaGrid extends StatelessWidget {
  const SocialMediaGrid({required this.media, required this.onTap, super.key});

  final List<SocialPostMedia> media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (media.first.type == SocialMediaType.video) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: _MediaTile(media: media.first, onTap: onTap, showPlay: true),
      );
    }
    if (media.length == 1) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: _MediaTile(media: media.first, onTap: onTap),
      );
    }
    final visible = media.take(4).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) => _MediaTile(
        media: visible[index],
        onTap: onTap,
        moreCount: index == visible.length - 1 && media.length > 4
            ? media.length - 4
            : 0,
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.media,
    required this.onTap,
    this.showPlay = false,
    this.moreCount = 0,
  });

  final SocialPostMedia media;
  final VoidCallback onTap;
  final bool showPlay;
  final int moreCount;

  @override
  Widget build(BuildContext context) {
    final imageUrl = media.type == SocialMediaType.video
        ? media.coverUrl
        : media.url;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _MediaGradient(media: media),
              )
            else
              _MediaGradient(media: media),
            if (showPlay)
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: .5),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            if (moreCount > 0)
              ColoredBox(
                color: Colors.black.withValues(alpha: .42),
                child: Center(
                  child: Text(
                    '+$moreCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaGradient extends StatelessWidget {
  const _MediaGradient({required this.media});

  final SocialPostMedia media;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(media.colorStart), Color(media.colorEnd)],
        ),
      ),
      child: Center(
        child: Icon(
          media.type == SocialMediaType.video
              ? Icons.movie_creation_outlined
              : Icons.photo_outlined,
          color: Colors.white.withValues(alpha: .65),
          size: 30,
        ),
      ),
    );
  }
}

class _RelatedContent extends StatelessWidget {
  const _RelatedContent({required this.relation, required this.onTap});

  final FeedRelation relation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FanColors.lavenderSoft,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.auto_stories_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '相关${relation.typeLabel}：${relation.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailablePost extends StatelessWidget {
  const _UnavailablePost();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.link_off_rounded, color: FanColors.textSecondary),
          SizedBox(width: 10),
          Expanded(child: Text('原动态已删除或不可访问')),
        ],
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.state, required this.onRetry});

  final SocialFeedState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadMoreError != null) {
      return Center(
        child: TextButton(onPressed: onRetry, child: const Text('加载失败，点击重试')),
      );
    }
    if (!state.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(
          child: Text(
            '已经看到最近所有动态了',
            style: TextStyle(color: FanColors.textSecondary, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 52);
  }
}

String _relativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes}分钟前';
  if (difference.inDays < 1) return '${difference.inHours}小时前';
  if (difference.inDays < 7) return '${difference.inDays}天前';
  return '${time.month}月${time.day}日';
}

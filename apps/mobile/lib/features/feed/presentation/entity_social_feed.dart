import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feed/presentation/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class EntitySocialFeed extends ConsumerStatefulWidget {
  const EntitySocialFeed.group({
    required this.group,
    required this.members,
    super.key,
  }) : idol = null;

  const EntitySocialFeed.idol({required this.idol, super.key})
    : group = null,
      members = const [];

  final FanGroup? group;
  final IdolProfile? idol;
  final List<IdolProfile> members;

  bool get isGroup => group != null;

  @override
  ConsumerState<EntitySocialFeed> createState() => _EntitySocialFeedState();
}

class _EntitySocialFeedState extends ConsumerState<EntitySocialFeed> {
  static const _pageSize = 20;
  final _scrollController = ScrollController();
  final Set<String> _expandedPostIds = {};
  List<SocialFeedPost> _posts = const [];
  Set<SocialPlatform> _unavailablePlatforms = const {};
  SocialPlatform? _platform;
  String? _memberId;
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _fromCache = false;
  String? _error;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future<void>.microtask(_loadInitial);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  List<String> get _idolIds {
    if (widget.idol != null) return [widget.idol!.id];
    if (_memberId != null && _memberId != 'official') return [_memberId!];
    return widget.members.map((item) => item.id).toList();
  }

  bool _matchesEntity(SocialFeedPost post) {
    if (widget.idol != null) {
      return !post.isGroupAuthor && post.idolId == widget.idol!.id;
    }
    if (post.groupId != widget.group!.id) return false;
    if (_memberId == 'official') return post.isGroupAuthor;
    if (_memberId != null) {
      return !post.isGroupAuthor && post.idolId == _memberId;
    }
    return true;
  }

  Future<void> _loadInitial() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _loadMoreError = null;
      });
    }
    try {
      final page = await ref
          .read(socialFeedRepositoryProvider)
          .fetchFeed(idolIds: _idolIds, platform: _platform, limit: _pageSize);
      final posts = page.posts.where(_matchesEntity).toList();
      ref.read(feedEngagementProvider.notifier).registerPosts(posts);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _nextCursor = page.nextCursor;
        _unavailablePlatforms = page.unavailablePlatforms;
        _fromCache = page.isFromCache;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _posts.isEmpty ? '动态暂时加载失败' : '部分动态可能不是最新';
        _fromCache = _posts.isNotEmpty;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final result = await ref
          .read(socialFeedRepositoryProvider)
          .refreshFeed(
            idolIds: _idolIds,
            platform: _platform,
            limit: _pageSize,
          );
      final posts = result.page.posts.where(_matchesEntity).toList();
      ref.read(feedEngagementProvider.notifier).registerPosts(posts);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _nextCursor = result.page.nextCursor;
        _unavailablePlatforms = result.page.unavailablePlatforms;
        _fromCache = result.page.isFromCache;
        _error = null;
      });
      showFanToast(
        context,
        result.newCount == 0 ? '已经是最新了' : '更新了 ${result.newCount} 条动态',
      );
    } catch (_) {
      if (mounted) showFanToast(context, '刷新失败，当前继续展示已缓存内容');
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await ref
          .read(socialFeedRepositoryProvider)
          .fetchFeed(
            idolIds: _idolIds,
            platform: _platform,
            cursor: _nextCursor,
            limit: _pageSize,
          );
      final incoming = page.posts.where(_matchesEntity).toList();
      ref.read(feedEngagementProvider.notifier).registerPosts(incoming);
      if (!mounted) return;
      final known = _posts.map((item) => item.id).toSet();
      setState(() {
        _posts = [
          ..._posts,
          ...incoming.where((item) => !known.contains(item.id)),
        ];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = '加载失败，点击重试';
      });
    }
  }

  void _selectMember(String? id) {
    if (_memberId == id) return;
    setState(() => _memberId = id);
    _loadInitial();
  }

  void _selectPlatform(SocialPlatform? platform) {
    if (_platform == platform) return;
    setState(() => _platform = platform);
    _loadInitial();
  }

  void _toggleExpanded(SocialFeedPost post) {
    setState(() {
      if (!_expandedPostIds.add(post.id)) _expandedPostIds.remove(post.id);
    });
    ref.read(socialFeedProvider.notifier).markViewed(post.id);
  }

  Future<void> _openOriginal(SocialFeedPost post) async {
    ref.read(socialFeedProvider.notifier).markViewed(post.id);
    try {
      final deepLink = Uri.tryParse(post.deepLinkUrl ?? '');
      if (deepLink != null && await canLaunchUrl(deepLink)) {
        await launchUrl(deepLink, mode: LaunchMode.externalApplication);
        return;
      }
      if (await launchUrl(
        Uri.parse(post.originalUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // A visible in-app message is shown below when both routes fail.
    }
    if (mounted) showFanToast(context, '暂时无法打开${post.platform.displayName}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      color: FanColors.canvas,
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 10),
      child: Column(
        children: [
          if (widget.isGroup)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _EntityChoice(
                    label: '全部',
                    selected: _memberId == null,
                    onTap: () => _selectMember(null),
                  ),
                  _EntityChoice(
                    label: '官方',
                    selected: _memberId == 'official',
                    onTap: () => _selectMember('official'),
                  ),
                  for (final member in widget.members)
                    _EntityChoice(
                      label: member.displayName,
                      selected: _memberId == member.id,
                      onTap: () => _selectMember(member.id),
                    ),
                ],
              ),
            ),
          if (widget.isGroup) const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _EntityChoice(
                  label: '全部平台',
                  selected: _platform == null,
                  onTap: () => _selectPlatform(null),
                ),
                for (final platform in SocialPlatform.values)
                  _EntityChoice(
                    label:
                        '${platform.displayName}${_unavailablePlatforms.contains(platform) ? ' · 暂停更新' : ''}',
                    selected: _platform == platform,
                    warning: _unavailablePlatforms.contains(platform),
                    onTap: () => _selectPlatform(platform),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _posts.isEmpty) {
      return FanEmptyState(
        icon: Icons.cloud_off_rounded,
        title: '动态暂时加载失败',
        message: '没有可用缓存，请检查网络后重新加载。',
        actionLabel: '重新加载',
        onAction: _loadInitial,
      );
    }
    if (_posts.isEmpty) {
      final name = widget.group?.name ?? widget.idol!.name;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 380,
              child: FanEmptyState(
                icon: Icons.dynamic_feed_outlined,
                title: '暂时还没有获取到 $name 的近期动态',
                message: '可以切换其他成员或平台后再试。',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        key: Key(widget.isGroup ? 'group-social-feed' : 'idol-social-feed'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        itemCount: _posts.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            final message = _fromCache || _error != null
                ? '部分动态可能不是最新，当前继续展示历史缓存'
                : '按发布时间倒序 · 仅聚合公开内容';
            return _EntityStatus(message: message, warning: _fromCache);
          }
          if (index == _posts.length + 1) {
            if (_loadingMore) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_loadMoreError != null) {
              return TextButton(
                onPressed: _loadMore,
                child: Text(_loadMoreError!),
              );
            }
            if (_nextCursor == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '已经看到最近所有动态了',
                    style: TextStyle(
                      color: FanColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }
            return const SizedBox(height: 40);
          }
          final post = _posts[index - 1];
          final viewed = ref
              .watch(socialFeedProvider)
              .viewedPostIds
              .contains(post.id);
          return SocialFeedCard(
            post: post,
            expanded: _expandedPostIds.contains(post.id),
            viewed: viewed,
            onToggleExpanded: () => _toggleExpanded(post),
            onOpenOriginal: () => _openOriginal(post),
            onOpenAuthor: () => context.push(post.authorRoute),
            onOpenGroup: () => context.push(post.groupRoute),
            onOpenComments: () {
              ref.read(socialFeedProvider.notifier).markViewed(post.id);
              context.push('/feed/post/${post.id}', extra: post);
            },
            onOpenRelation: post.relation == null
                ? null
                : () => context.push(post.relation!.route),
          );
        },
      ),
    );
  }
}

class _EntityChoice extends StatelessWidget {
  const _EntityChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.warning = false,
  });

  final String label;
  final bool selected;
  final bool warning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        side: warning && !selected
            ? const BorderSide(color: FanColors.coral)
            : null,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _EntityStatus extends StatelessWidget {
  const _EntityStatus({required this.message, required this.warning});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF0E9) : FanColors.blueSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Icons.info_outline_rounded : Icons.schedule_rounded,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

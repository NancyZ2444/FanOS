import 'package:url_launcher/url_launcher.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:fan_os/features/profile/presentation/profile_backdrop.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _ProfileTab { collection, likes, albums, contributions }

enum _LibraryView { gallery, list }

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, this.userId});

  final String? userId;
  bool get isSelf => userId == null || userId == 'current-user';

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool get _isSelf =>
      widget.userId == null ||
      widget.userId == ref.read(sessionProvider).userId;
  _ProfileTab _activeTab = _ProfileTab.collection;
  late final PageController _pageController;
  final Map<_ProfileTab, _LibraryView> _viewModes = {
    for (final tab in _ProfileTab.values) tab: _LibraryView.gallery,
  };
  final Map<_ProfileTab, String> _filters = {
    _ProfileTab.collection: '全部',
    _ProfileTab.likes: '全部',
  };

  _LibraryView get _activeView =>
      _viewModes[_activeTab] ?? _LibraryView.gallery;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(_ProfileTab tab, List<_ProfileTab> tabs) {
    final index = tabs.indexOf(tab);
    if (index < 0) return;
    setState(() => _activeTab = tab);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _toggleView() {
    setState(() {
      _viewModes[_activeTab] = _activeView == _LibraryView.gallery
          ? _LibraryView.list
          : _LibraryView.gallery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (_isSelf && !session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: FanEmptyState(
          icon: Icons.person_outline_rounded,
          title: '登录后创建个人主页',
          message: '展示你的本命与公开卡册，收藏数据会跟随账号同步。',
          actionLabel: '登录 / 注册',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final publicProfile = _isSelf
        ? null
        : ref.watch(publicUserProfileProvider(widget.userId!));
    if (!_isSelf && publicProfile!.isLoading) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton(), title: const Text('个人主页')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final other = publicProfile?.asData?.value;
    if (!_isSelf && other == null) {
      final error = publicProfile?.error;
      final missing = error is ApiException && error.statusCode == 404;
      return Scaffold(
        appBar: AppBar(leading: const BackButton(), title: const Text('个人主页')),
        body: FanEmptyState(
          icon: missing ? Icons.person_off_outlined : Icons.cloud_off_outlined,
          title: missing ? '该用户不存在或已注销' : '个人主页加载失败',
          message: missing ? '你可以返回上一页继续浏览。' : '请检查网络后重试。',
          actionLabel: missing ? null : '重试',
          onAction: missing
              ? null
              : () => ref.invalidate(publicUserProfileProvider(widget.userId!)),
        ),
      );
    }

    final catalog = ref.watch(catalogProvider);
    final collection = ref.watch(collectionProvider);
    final favorites = ref.watch(favoritesProvider);
    final assets = ref.watch(profileAssetProvider);
    final relationships = ref.watch(profileRelationshipProvider);
    final privacy = _isSelf ? session.privacy : other!.privacy;
    final tabs = <_ProfileTab>[
      if (_isSelf || privacy.collectionVisible) _ProfileTab.collection,
      if (_isSelf || privacy.likesVisible) _ProfileTab.likes,
      if (_isSelf || privacy.albumsVisible) _ProfileTab.albums,
      _ProfileTab.contributions,
    ];
    if (tabs.isEmpty) tabs.add(_ProfileTab.collection);
    if (!tabs.contains(_activeTab)) _activeTab = tabs.first;

    final profile = _ProfileViewData(
      id: _isSelf ? session.userId : other!.id,
      displayName: _isSelf ? session.displayName : other!.displayName,
      initial: _isSelf ? session.displayName.characters.first : other!.initial,
      bio: _isSelf ? session.bio : other!.bio,
      avatarPath: _isSelf ? session.avatarPath : other!.avatarPath,
      backgroundPath: _isSelf ? session.backgroundPath : other!.backgroundPath,
      level: _isSelf ? session.level : other!.level,
      experience: _isSelf ? session.experience : other!.experience,
      nextLevelExperience: _isSelf
          ? session.nextLevelExperience
          : other!.nextLevelExperience,
      favoriteIds: _isSelf
          ? favorites.selectedIds.toList()
          : other!.favoriteIdolIds,
      primaryIdolId: _isSelf ? favorites.primaryId : other!.primaryIdolId,
      followingCount: _isSelf
          ? relationships.myFollowingCount
          : other!.followingCount,
      followersCount: _isSelf
          ? relationships.myFollowersCount
          : relationships.followerCountFor(other!),
      ownedIds: _isSelf ? collection.owned.keys.toSet() : other!.ownedCardIds,
      likedIds: _isSelf ? collection.wishlist : other!.likedCardIds,
      albumCount: _isSelf
          ? (ref.watch(albumQuotaProvider).value?.albumCount ??
                assets.albums.length)
          : other!.albumCount,
      weiboName: _isSelf
          ? (session.weiboVisible ? session.weiboName : null)
          : other!.weiboName,
      weiboUrl: _isSelf
          ? (session.weiboVisible ? session.weiboUrl : null)
          : other!.weiboUrl,
      privacy: privacy,
    );

    return Scaffold(
      body: SafeArea(
        top: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: FanContent(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ProfileHeader(
                  profile: profile,
                  isSelf: _isSelf,
                  catalog: catalog.value,
                  relationshipStatus: _isSelf
                      ? null
                      : relationships.statusFor(
                          profile.id,
                          fallback:
                              other?.relationStatus ?? UserRelationStatus.none,
                        ),
                  followBusy: relationships.busyUserIds.contains(profile.id),
                  onEdit: () => context.push('/profile/edit'),
                  onSettings: () => context.push('/profile/edit'),
                  onShare: () => showFanToast(context, '已生成仅含公开字段的分享链接'),
                  onFollow: () => _handleFollow(
                    profile.id,
                    relationships.statusFor(
                      profile.id,
                      fallback:
                          other?.relationStatus ?? UserRelationStatus.none,
                    ),
                  ),
                  onOpenLevel: () => context.push(
                    '/profile/level',
                    extra: <String, Object>{
                      'name': profile.displayName,
                      'level': profile.level,
                      'experience': profile.experience,
                      'next': profile.nextLevelExperience,
                    },
                  ),
                  onOpenFollowing: () => _openRelations(
                    type: 'following',
                    isPublic: _isSelf || privacy.followingListVisible,
                    userId: profile.id,
                  ),
                  onOpenFollowers: () => _openRelations(
                    type: 'followers',
                    isPublic: _isSelf || privacy.followersListVisible,
                    userId: profile.id,
                  ),
                  onOpenFavorite: (idolId) => context.push('/idol/$idolId'),
                  onManageFavorites: () =>
                      context.push('/onboarding/favorites'),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyProfileTabs(
                height: MediaQuery.textScalerOf(context).scale(14) * 1.5 + 30,
                child: _ProfileLibraryBar(
                  isSelf: _isSelf,
                  counts: {
                    _ProfileTab.collection: profile.ownedIds.length,
                    _ProfileTab.likes: profile.likedIds.length,
                    _ProfileTab.albums: profile.albumCount,
                    _ProfileTab.contributions: ref
                        .watch(
                          contributionCountProvider(
                            _isSelf ? 'me' : profile.id,
                          ),
                        )
                        .value,
                  },
                  tabs: tabs,
                  activeTab: _activeTab,
                  activeView: _activeView,
                  onTabChanged: (tab) => _selectTab(tab, tabs),
                  onViewChanged: _toggleView,
                ),
              ),
            ),
          ],
          body: catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const FanEmptyState(
              icon: Icons.cloud_off_rounded,
              title: '内容加载失败',
              message: '请稍后重试',
            ),
            data: (data) => PageView(
              key: const Key('profile-tab-pages'),
              controller: _pageController,
              onPageChanged: (index) =>
                  setState(() => _activeTab = tabs[index]),
              children: [
                for (final tab in tabs)
                  if (tab == _ProfileTab.albums)
                    AlbumShelfBody(
                      profileMode: true,
                      showTitle: false,
                      key: PageStorageKey(
                        'profile-${profile.id}-digital-albums',
                      ),
                      userId: _isSelf ? null : profile.id,
                    )
                  else if (tab == _ProfileTab.contributions)
                    ContributionShelf(userId: _isSelf ? 'me' : profile.id)
                  else
                    _ProfileLibraryPage(
                      key: PageStorageKey('profile-${profile.id}-${tab.name}'),
                      tab: tab,
                      view: _viewModes[tab] ?? _LibraryView.gallery,
                      selectedFilter: _filters[tab] ?? '全部',
                      isSelf: _isSelf,
                      cards: data.cards,
                      ownedIds: profile.ownedIds,
                      likedIds: profile.likedIds,
                      collection: collection,
                      albums: _isSelf
                          ? assets.albums
                          : (useMockApi
                                ? _demoAlbums(profile.albumCount)
                                : other!.albums),
                      onFilterChanged: (value) =>
                          setState(() => _filters[tab] = value),
                      onOpenCard: (card) => context.push('/card/${card.id}'),
                      onCreateAlbum: () {
                        ref.read(profileAssetProvider.notifier).createAlbum();
                        showFanToast(context, '已创建一本新卡册');
                      },
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRelations({
    required String type,
    required bool isPublic,
    required String userId,
  }) {
    if (!isPublic) {
      showFanToast(context, '对方暂未公开${type == 'following' ? '关注' : '粉丝'}列表');
      return;
    }
    context.push('/profile/relations?type=$type&user=$userId');
  }

  Future<void> _handleFollow(String userId, UserRelationStatus status) async {
    if (status == UserRelationStatus.following ||
        status == UserRelationStatus.mutual) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('取消关注？'),
          content: const Text('取消后仍可再次关注对方。'),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: const Text('取消关注'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await ref
          .read(profileRelationshipProvider.notifier)
          .toggleFollow(userId, currentStatus: status);
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('关注状态未更新'),
          content: const Text('网络或服务暂时不可用，原有关注状态未改变，请重试。'),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  List<DigitalCardAlbum> _demoAlbums(int count) => List.generate(
    count,
    (index) => DigitalCardAlbum(
      id: 'public-album-$index',
      name: index == 0 ? '最近收藏' : '舞台回忆 ${index + 1}',
      cardCount: 8 + index * 3,
      updatedLabel: '${index + 1} 天前更新',
      colorStart: index.isEven ? 0xFF8176CA : 0xFFF2A8BB,
      colorEnd: index.isEven ? 0xFF272B53 : 0xFF87415D,
    ),
  );
}

class _ProfileViewData {
  const _ProfileViewData({
    required this.id,
    required this.displayName,
    required this.initial,
    required this.bio,
    required this.avatarPath,
    required this.level,
    required this.experience,
    required this.nextLevelExperience,
    required this.favoriteIds,
    required this.primaryIdolId,
    required this.followingCount,
    required this.followersCount,
    required this.ownedIds,
    required this.likedIds,
    required this.albumCount,
    required this.privacy,
    this.weiboName,
    this.weiboUrl,
    this.backgroundPath,
  });

  final String id;
  final String displayName;
  final String initial;
  final String bio;
  final String? avatarPath;
  final String? backgroundPath;
  final int level;
  final int experience;
  final int nextLevelExperience;
  final List<String> favoriteIds;
  final String? primaryIdolId;
  final int followingCount;
  final int followersCount;
  final Set<String> ownedIds;
  final Set<String> likedIds;
  final int albumCount;
  final String? weiboName;
  final String? weiboUrl;
  final ProfilePrivacy privacy;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isSelf,
    required this.catalog,
    required this.relationshipStatus,
    required this.followBusy,
    required this.onEdit,
    required this.onSettings,
    required this.onShare,
    required this.onFollow,
    required this.onOpenLevel,
    required this.onOpenFollowing,
    required this.onOpenFollowers,
    required this.onOpenFavorite,
    required this.onManageFavorites,
  });

  final _ProfileViewData profile;
  final bool isSelf;
  final CatalogBundle? catalog;
  final UserRelationStatus? relationshipStatus;
  final bool followBusy;
  final VoidCallback onEdit;
  final VoidCallback onSettings;
  final VoidCallback onShare;
  final VoidCallback onFollow;
  final VoidCallback onOpenLevel;
  final VoidCallback onOpenFollowing;
  final VoidCallback onOpenFollowers;
  final ValueChanged<String> onOpenFavorite;
  final VoidCallback onManageFavorites;

  @override
  Widget build(BuildContext context) {
    final favoriteIdols =
        catalog?.idols
            .where((item) => profile.favoriteIds.contains(item.id))
            .toList() ??
        const <IdolProfile>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Stack(
            children: [
              if (profile.backgroundPath != null)
                Positioned.fill(
                  key: const Key('profile-background'),
                  child: ProfileBackdrop(imageUrl: profile.backgroundPath!),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 8,
                  20,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!isSelf) ...[
                          const BackButton(),
                          const Expanded(
                            child: Text(
                              '个人主页',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        IconButton(
                          tooltip: '分享主页',
                          onPressed: onShare,
                          icon: const Icon(Icons.ios_share_rounded),
                        ),
                        if (isSelf)
                          IconButton(
                            tooltip: '我的扫描反馈',
                            onPressed: () => context.push('/feedback'),
                            icon: const Icon(Icons.history_rounded),
                          ),
                        if (isSelf)
                          IconButton(
                            tooltip: '设置',
                            onPressed: onSettings,
                            icon: const Icon(Icons.settings_outlined),
                          )
                        else
                          IconButton(
                            tooltip: '更多',
                            onPressed: () =>
                                showFanToast(context, '举报与屏蔽功能将在后续开放'),
                            icon: const Icon(Icons.more_horiz_rounded),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFFBBA9FF), Color(0xFF5A58A4)],
                            ),
                          ),
                          child: profile.avatarPath == null
                              ? Text(
                                  profile.initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : ClipOval(
                                  child: FanImage(
                                    imageUrl: profile.avatarPath,
                                    fallback: Text(
                                      profile.initial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              InkWell(
                                key: const Key('profile-level-entry'),
                                onTap: onOpenLevel,
                                borderRadius: BorderRadius.circular(99),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: FanColors.lavenderSoft,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'Lv.${profile.level} · ${profile.experience} EXP',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelf)
                          SizedBox(
                            width: 82,
                            child: OutlinedButton(
                              onPressed: onEdit,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                backgroundColor: Colors.white.withValues(
                                  alpha: .6,
                                ),
                              ),
                              child: const Text(
                                '编辑资料',
                                maxLines: 1,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                        else
                          _FollowButton(
                            status: relationshipStatus!,
                            busy: followBusy,
                            onPressed: onFollow,
                          ),
                      ],
                    ),
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(profile.bio, style: const TextStyle(height: 1.45)),
                    ] else if (isSelf) ...[
                      const SizedBox(height: 10),
                      const Text(
                        '还没有填写简介',
                        style: TextStyle(
                          fontSize: 12,
                          color: FanColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 15),
                    if (profile.weiboName != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: profile.weiboUrl == null
                            ? null
                            : () async {
                                final uri = Uri.tryParse(profile.weiboUrl!);
                                if (uri == null ||
                                    uri.scheme != 'https' ||
                                    !{
                                      'weibo.com',
                                      'www.weibo.com',
                                      'm.weibo.cn',
                                      'weibo.cn',
                                    }.contains(uri.host)) {
                                  return;
                                }
                                try {
                                  if (!await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  )) {
                                    throw StateError('unavailable');
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    showDialog<void>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('暂时无法打开微博主页'),
                                        content: const Text('请稍后重试。'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('知道了'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Text(
                          '微博 · ${profile.weiboName!}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: FanColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        _RelationStat(
                          value: profile.followingCount,
                          label: '关注',
                          onTap: onOpenFollowing,
                        ),
                        _RelationStat(
                          value: profile.followersCount,
                          label: '粉丝',
                          onTap: onOpenFollowers,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if ((profile.privacy.favoritesVisible || isSelf) &&
            (isSelf || favoriteIdols.isNotEmpty)) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FavoriteIdolsShowcase(
              idols: favoriteIdols,
              primaryId: profile.primaryIdolId,
              onManage: isSelf ? onManageFavorites : null,
              onOpen: (idol) => onOpenFavorite(idol.id),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.status,
    required this.busy,
    required this.onPressed,
  });

  final UserRelationStatus status;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final following =
        status == UserRelationStatus.following ||
        status == UserRelationStatus.mutual;
    final label = switch (status) {
      UserRelationStatus.none => '关注',
      UserRelationStatus.followsYou => '回关',
      UserRelationStatus.following => '已关注',
      UserRelationStatus.mutual => '互相关注',
    };
    return SizedBox(
      width: 88,
      child: following
          ? OutlinedButton(
              onPressed: busy ? null : onPressed,
              child: Text(busy ? '处理中' : label),
            )
          : FilledButton(
              onPressed: busy ? null : onPressed,
              child: Text(busy ? '处理中' : label),
            ),
    );
  }
}

class _RelationStat extends StatelessWidget {
  const _RelationStat({
    required this.value,
    required this.label,
    required this.onTap,
  });
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(color: FanColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileLibraryBar extends StatelessWidget {
  const _ProfileLibraryBar({
    required this.tabs,
    required this.counts,
    this.isSelf = true,
    required this.activeTab,
    required this.activeView,
    required this.onTabChanged,
    required this.onViewChanged,
  });

  final List<_ProfileTab> tabs;
  final Map<_ProfileTab, int?> counts;
  final bool isSelf;
  final _ProfileTab activeTab;
  final _LibraryView activeView;
  final ValueChanged<_ProfileTab> onTabChanged;
  final VoidCallback onViewChanged;

  String _label(_ProfileTab tab) => switch (tab) {
    _ProfileTab.collection => '已拥有',
    _ProfileTab.likes => '心愿单',
    _ProfileTab.albums => '卡册',
    _ProfileTab.contributions => isSelf ? '我的贡献' : 'TA 的贡献',
  };

  @override
  Widget build(BuildContext context) {
    final showViewToggle =
        activeTab == _ProfileTab.collection || activeTab == _ProfileTab.likes;
    final isGallery = activeView == _LibraryView.gallery;
    return ColoredBox(
      color: FanColors.canvas,
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: FanColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tab in tabs)
                      InkWell(
                        key: ValueKey('profile-tab-${tab.name}'),
                        onTap: () => onTabChanged(tab),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: activeTab == tab
                                    ? FanColors.ink
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            '${_label(tab)}(${counts[tab] ?? '—'})',
                            maxLines: 1,
                            style: TextStyle(
                              color: activeTab == tab
                                  ? FanColors.ink
                                  : FanColors.textSecondary,
                              fontSize: 14,
                              fontWeight: activeTab == tab
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showViewToggle)
              IconButton(
                key: const Key('profile-view-toggle'),
                tooltip: isGallery ? '切换为列表' : '切换为图库',
                onPressed: onViewChanged,
                icon: Icon(
                  isGallery
                      ? Icons.view_agenda_outlined
                      : Icons.grid_view_rounded,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickyProfileTabs extends SliverPersistentHeaderDelegate {
  const _StickyProfileTabs({required this.child, required this.height});
  final Widget child;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(covariant _StickyProfileTabs oldDelegate) =>
      oldDelegate.child != child;
}

class _ProfileLibraryPage extends StatefulWidget {
  const _ProfileLibraryPage({
    required this.tab,
    required this.view,
    required this.selectedFilter,
    required this.isSelf,
    required this.cards,
    required this.ownedIds,
    required this.likedIds,
    required this.collection,
    required this.albums,
    required this.onFilterChanged,
    required this.onOpenCard,
    required this.onCreateAlbum,
    super.key,
  });

  final _ProfileTab tab;
  final _LibraryView view;
  final String selectedFilter;
  final bool isSelf;
  final List<CollectibleCard> cards;
  final Set<String> ownedIds;
  final Set<String> likedIds;
  final CollectionState collection;
  final List<DigitalCardAlbum> albums;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<CollectibleCard> onOpenCard;
  final VoidCallback onCreateAlbum;

  @override
  State<_ProfileLibraryPage> createState() => _ProfileLibraryPageState();
}

class _ProfileLibraryPageState extends State<_ProfileLibraryPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<CollectibleCard> get _baseCards => switch (widget.tab) {
    _ProfileTab.collection =>
      widget.cards.where((card) => widget.ownedIds.contains(card.id)).toList(),
    _ProfileTab.likes =>
      widget.cards.where((card) => widget.likedIds.contains(card.id)).toList(),
    _ => const [],
  };

  List<CollectibleCard> get _visibleCards {
    final filter = widget.selectedFilter;
    if (filter == '全部') return _baseCards;
    return _baseCards.where((card) {
      return card.idolName == filter ||
          card.groupName == filter ||
          card.cardType == filter ||
          card.releaseDate.startsWith(filter);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.tab == _ProfileTab.albums) return _buildAlbums(context);
    if (widget.tab == _ProfileTab.contributions) {
      return const FanEmptyState(
        icon: Icons.volunteer_activism_outlined,
        title: '贡献记录即将开放',
        message: '后续可在这里查看图鉴贡献，本版本暂不展示。',
      );
    }
    final cards = _visibleCards;
    return CustomScrollView(
      key: PageStorageKey('profile-scroll-${widget.tab.name}'),
      slivers: [
        SliverToBoxAdapter(child: _buildFilters()),
        if (cards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: FanEmptyState(
              icon: widget.tab == _ProfileTab.collection
                  ? Icons.style_outlined
                  : Icons.favorite_border_rounded,
              title: widget.isSelf
                  ? (widget.tab == _ProfileTab.collection
                        ? '还没有拥有的小卡'
                        : '心愿单还是空的')
                  : (widget.tab == _ProfileTab.collection
                        ? 'TA 还没有公开拥有的小卡'
                        : 'TA 的心愿单还是空的'),
              message: widget.isSelf ? '去逛图鉴或使用 AI Scan 发现喜欢的小卡。' : '稍后再来看看吧。',
            ),
          )
        else if (widget.view == _LibraryView.list)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
            sliver: SliverList.separated(
              key: ValueKey('profile-list-${widget.tab.name}'),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final card = cards[index];
                return _ProfileCardListTile(
                  card: card,
                  badge: _badge(card),
                  onTap: () => widget.onOpenCard(card),
                );
              },
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
            sliver: SliverGrid.builder(
              key: ValueKey('profile-gallery-${widget.tab.name}'),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
                childAspectRatio: .7,
              ),
              itemCount: cards.length,
              itemBuilder: (context, index) {
                final card = cards[index];
                return _CompactCardArtwork(
                  card: card,
                  badge: _badge(card),
                  onTap: () => widget.onOpenCard(card),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFilters() {
    final options = <String>{'全部'};
    for (final card in _baseCards) {
      options
        ..add(card.idolName)
        ..add(card.groupName)
        ..add(card.cardType)
        ..add(card.releaseDate.split('.').first);
    }
    options.removeWhere((value) => value.trim().isEmpty);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 5),
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final value = options.elementAt(index);
          return ChoiceChip(
            label: Text(value),
            selected: widget.selectedFilter == value,
            showCheckmark: false,
            onSelected: (_) => widget.onFilterChanged(value),
          );
        },
      ),
    );
  }

  Widget _buildAlbums(BuildContext context) {
    return CustomScrollView(
      key: const ValueKey('profile-gallery-albums'),
      slivers: [
        if (widget.isSelf)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: widget.onCreateAlbum,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建卡册'),
                ),
              ),
            ),
          ),
        if (widget.albums.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: FanEmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: widget.isSelf ? '把你的收藏整理成一本专属卡册' : 'TA 还没有公开卡册',
              message: widget.isSelf ? '可以按组合、活动或回忆创建主题卡册。' : '稍后再来看看吧。',
              actionLabel: widget.isSelf ? '创建第一本卡册' : null,
              onAction: widget.isSelf ? widget.onCreateAlbum : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: .82,
              ),
              itemCount: widget.albums.length,
              itemBuilder: (context, index) =>
                  _AlbumCover(album: widget.albums[index]),
            ),
          ),
      ],
    );
  }

  Widget? _badge(CollectibleCard card) {
    if (widget.tab == _ProfileTab.likes) {
      return null;
    }
    final quantity = widget.isSelf ? widget.collection.quantity(card.id) : 1;
    return StatusBadge(label: '×$quantity', dark: true);
  }
}

class _CompactCardArtwork extends StatelessWidget {
  const _CompactCardArtwork({
    required this.card,
    required this.badge,
    required this.onTap,
  });
  final CollectibleCard card;
  final Widget? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FanArtwork(
            imageUrl: card.imageUrl,
            startColor: Color(card.colorStart),
            endColor: Color(card.colorEnd),
            label: card.idolName.characters.take(2).toString().toUpperCase(),
            borderRadius: 11,
          ),
          if (badge != null) Positioned(right: 5, bottom: 5, child: badge!),
        ],
      ),
    );
  }
}

class _ProfileCardListTile extends StatelessWidget {
  const _ProfileCardListTile({
    required this.card,
    required this.badge,
    required this.onTap,
  });
  final CollectibleCard card;
  final Widget? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 88,
                child: FanArtwork(
                  imageUrl: card.imageUrl,
                  startColor: Color(card.colorStart),
                  endColor: Color(card.colorEnd),
                  label: card.idolName.characters
                      .take(2)
                      .toString()
                      .toUpperCase(),
                  borderRadius: 11,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.displayTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FanEntityName(
                      kind: 'idols',
                      id: card.idolId,
                      officialName: card.idolName,
                      suffix: ' · ${card.source}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${card.cardType} · ${card.version}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 7),
                      Align(alignment: Alignment.centerLeft, child: badge!),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: FanColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.album});
  final DigitalCardAlbum album;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(album.colorStart), Color(album.colorEnd)],
              ),
            ),
            child: const Icon(
              Icons.collections_bookmark_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Text(
          '${album.cardCount} 张 · ${album.updatedLabel}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

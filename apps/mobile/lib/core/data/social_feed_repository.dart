import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/social_feed_models.dart';

abstract interface class SocialFeedRepository {
  Future<SocialFeedPageData> fetchFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    String? cursor,
    int limit = 20,
  });

  Future<SocialFeedRefreshData> refreshFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    int limit = 20,
  });
}

class MockSocialFeedRepository implements SocialFeedRepository {
  MockSocialFeedRepository() : _posts = _createPosts();

  final List<SocialFeedPost> _posts;
  int _refreshCount = 0;

  @override
  Future<SocialFeedPageData> fetchFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    String? cursor,
    int limit = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    final filtered =
        _posts
            .where((post) => idolIds == null || idolIds.contains(post.idolId))
            .where((post) => platform == null || post.platform == platform)
            .toList()
          ..sort((a, b) => b.postedAt.compareTo(a.postedAt));
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final end = (offset + limit).clamp(0, filtered.length);
    final page = offset >= filtered.length
        ? const <SocialFeedPost>[]
        : filtered.sublist(offset, end);
    return SocialFeedPageData(
      posts: page,
      nextCursor: end < filtered.length ? '$end' : null,
      unavailablePlatforms: const {SocialPlatform.x},
      isFromCache: platform == SocialPlatform.x,
      newCount: cursor == null ? 5 : 0,
    );
  }

  @override
  Future<SocialFeedRefreshData> refreshFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    int limit = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 360));
    final page = await fetchFeed(
      idolIds: idolIds,
      platform: platform,
      limit: limit,
    );
    final newCount = _refreshCount++ == 0 ? 5 : 0;
    return SocialFeedRefreshData(page: page, newCount: newCount);
  }

  static List<SocialFeedPost> _createPosts() {
    final now = DateTime.now();
    const contents = [
      '今天的舞台彩排顺利结束。新的编排加入了很多有趣细节，期待很快和大家见面！从灯光到服装都反复调整了很多次，也记录下了练习室里值得纪念的瞬间。谢谢一直等待的你们，正式公开时一定要来看看。',
      '把巡演途中看到的晚霞分享给你们。谢谢每一座城市的相遇，也请继续期待下一站。',
      '新专辑的幕后记录更新啦。这次从造型、编舞到拍摄都参与了很多想法，照片里还藏着一个小彩蛋。',
      '签售活动圆满结束，收到了许多温暖的话。回去的路上仍然觉得今天像一场很长的梦。',
      '练习室的一小段日常。最近正在挑战新的风格，希望正式舞台能带来不一样的感觉。',
      '周末问候！记得好好吃饭、好好休息，我们下次见面时都要是元气满满的样子。',
    ];
    const mediaCounts = [1, 2, 4, 0, 7, 1];
    return List.generate(34, (index) {
      final idol = DemoCatalog.idols[index % DemoCatalog.idols.length];
      final group = DemoCatalog.groups.firstWhere(
        (item) => item.memberIds.contains(idol.id),
      );
      final isGroupAuthor = index % 9 == 4;
      final platform =
          SocialPlatform.values[index % SocialPlatform.values.length];
      final mediaCount = mediaCounts[index % mediaCounts.length];
      final isVideo = index % 6 == 5;
      final media = List.generate(
        mediaCount,
        (mediaIndex) => SocialPostMedia(
          type: isVideo ? SocialMediaType.video : SocialMediaType.image,
          colorStart: _shiftColor(idol.colorStart, mediaIndex * 0x00050505),
          colorEnd: _shiftColor(idol.colorEnd, mediaIndex * 0x00030303),
        ),
      );
      return SocialFeedPost(
        id: 'feed-${index + 1}',
        originalPostId: '${platform.name}-post-${1000 + index}',
        platform: platform,
        idolId: idol.id,
        idolName: isGroupAuthor ? '${group.name} Official' : idol.name,
        idolInitials: isGroupAuthor
            ? group.name.substring(0, group.name.length < 2 ? 1 : 2)
            : idol.initials,
        idolColorStart: isGroupAuthor ? group.colorStart : idol.colorStart,
        idolColorEnd: isGroupAuthor ? group.colorEnd : idol.colorEnd,
        groupId: group.id,
        groupName: group.name,
        authorType: isGroupAuthor
            ? SocialAuthorType.group
            : SocialAuthorType.idol,
        postedAt: now.subtract(Duration(hours: index * 3 + 1)),
        content: contents[index % contents.length],
        media: media,
        originalUrl: _webUrl(platform),
        deepLinkUrl: _deepLink(platform, index),
        fetchedAt: now.subtract(Duration(minutes: 8 + index)),
        relation: index % 3 == 0 ? _relation(index) : null,
        isAvailable: index != 23,
        likeCount: 68 + index * 7,
        commentCount: 4 + index % 19,
        shareCount: index % 8,
      );
    });
  }

  static int _shiftColor(int color, int offset) =>
      0xFF000000 | ((color + offset) & 0x00FFFFFF);

  static String _webUrl(SocialPlatform platform) => switch (platform) {
    SocialPlatform.weibo => 'https://weibo.com',
    SocialPlatform.instagram => 'https://www.instagram.com',
    SocialPlatform.x => 'https://x.com',
    SocialPlatform.xiaohongshu => 'https://www.xiaohongshu.com',
    SocialPlatform.douyin => 'https://www.douyin.com',
  };

  static String _deepLink(SocialPlatform platform, int index) =>
      switch (platform) {
        SocialPlatform.weibo => 'sinaweibo://detail?mblogid=$index',
        SocialPlatform.instagram => 'instagram://media?id=$index',
        SocialPlatform.x => 'twitter://status?id=$index',
        SocialPlatform.xiaohongshu => 'xhsdiscover://item/$index',
        SocialPlatform.douyin => 'snssdk1128://aweme/detail/$index',
      };

  static FeedRelation _relation(int index) {
    final card = DemoCatalog.cards[index % DemoCatalog.cards.length];
    return switch (index % 4) {
      0 => const FeedRelation(
        type: FeedRelationType.album,
        targetId: 'group-lumina',
        title: 'Starlit',
        route: '/group/group-lumina',
      ),
      1 => const FeedRelation(
        type: FeedRelationType.event,
        targetId: 'group-aster',
        title: '2026 ASTER LIVE TOUR',
        route: '/group/group-aster',
      ),
      2 => FeedRelation(
        type: FeedRelationType.card,
        targetId: card.id,
        title: card.displayTitle,
        route: '/card/${card.id}',
      ),
      _ => const FeedRelation(
        type: FeedRelationType.others,
        targetId: 'group-nova',
        title: 'Afterglow Tour Goods',
        route: '/group/group-nova',
      ),
    };
  }
}

class ApiSocialFeedRepository implements SocialFeedRepository {
  ApiSocialFeedRepository(this._client);

  final ApiClient _client;

  @override
  Future<SocialFeedPageData> fetchFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _client.getData(
      '/idol-feed',
      query: {
        if (idolIds != null) 'idol_ids': idolIds.join(','),
        if (platform != null) 'platform': platform.name,
        'cursor': ?cursor,
        'limit': limit,
      },
    ) as Map<String, dynamic>;
    return _parsePage(data);
  }

  @override
  Future<SocialFeedRefreshData> refreshFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    int limit = 20,
  }) async {
    final data = await _client.postData(
      '/idol-feed/refresh',
      data: {
        'idol_ids': ?idolIds,
        if (platform != null) 'platform': platform.name,
        'limit': limit,
      },
    ) as Map<String, dynamic>;
    return SocialFeedRefreshData(
      page: _parsePage(data),
      newCount: (data['new_count'] as num?)?.toInt() ?? 0,
    );
  }

  SocialFeedPageData _parsePage(Map<String, dynamic> data) =>
      SocialFeedPageData(
        posts: (data['items'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SocialFeedPost.fromJson)
            .toList(),
        nextCursor: data['next_cursor'] as String?,
        unavailablePlatforms:
            (data['unavailable_platforms'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .map(SocialPlatformInfo.fromWireName)
                .toSet(),
        isFromCache: (data['is_from_cache'] as bool?) ?? false,
        newCount: (data['new_count'] as num?)?.toInt() ?? 0,
      );
}

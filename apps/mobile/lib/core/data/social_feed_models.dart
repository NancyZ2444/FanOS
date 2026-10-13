enum SocialPlatform { weibo, instagram, x, xiaohongshu, douyin }

extension SocialPlatformInfo on SocialPlatform {
  String get displayName => switch (this) {
    SocialPlatform.weibo => '微博',
    SocialPlatform.instagram => 'Instagram',
    SocialPlatform.x => 'X',
    SocialPlatform.xiaohongshu => '小红书',
    SocialPlatform.douyin => '抖音',
  };

  static SocialPlatform fromWireName(String value) => switch (value) {
    'weibo' => SocialPlatform.weibo,
    'instagram' => SocialPlatform.instagram,
    'x' || 'twitter' => SocialPlatform.x,
    'xiaohongshu' || 'rednote' => SocialPlatform.xiaohongshu,
    'douyin' => SocialPlatform.douyin,
    _ => SocialPlatform.weibo,
  };
}

enum SocialMediaType { image, video }

enum SocialAuthorType { group, idol }

class SocialPostMedia {
  const SocialPostMedia({
    required this.type,
    required this.colorStart,
    required this.colorEnd,
    this.url,
    this.coverUrl,
  });

  final SocialMediaType type;
  final String? url;
  final String? coverUrl;
  final int colorStart;
  final int colorEnd;

  factory SocialPostMedia.fromJson(Map<String, dynamic> json) =>
      SocialPostMedia(
        type: json['type'] == 'video'
            ? SocialMediaType.video
            : SocialMediaType.image,
        url: json['url'] as String?,
        coverUrl: json['cover_url'] as String?,
        colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFFBBA9FF,
        colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF5A58A4,
      );
}

enum FeedRelationType { album, event, card, others }

class FeedRelation {
  const FeedRelation({
    required this.type,
    required this.targetId,
    required this.title,
    required this.route,
  });

  final FeedRelationType type;
  final String targetId;
  final String title;
  final String route;

  String get typeLabel => switch (type) {
    FeedRelationType.album => '专辑',
    FeedRelationType.event => '活动',
    FeedRelationType.card => '小卡',
    FeedRelationType.others => '其他来源',
  };

  factory FeedRelation.fromJson(Map<String, dynamic> json) => FeedRelation(
    type: switch (json['type']) {
      'event' => FeedRelationType.event,
      'card' => FeedRelationType.card,
      'others' || 'other' || 'merchandise' => FeedRelationType.others,
      _ => FeedRelationType.album,
    },
    targetId: json['target_id'] as String,
    title: json['title'] as String,
    route: json['route'] as String,
  );
}

class SocialFeedPost {
  const SocialFeedPost({
    required this.id,
    required this.originalPostId,
    required this.platform,
    required this.idolId,
    required this.idolName,
    required this.idolInitials,
    required this.idolColorStart,
    required this.idolColorEnd,
    required this.groupId,
    required this.groupName,
    required this.postedAt,
    required this.content,
    required this.media,
    required this.originalUrl,
    required this.fetchedAt,
    this.deepLinkUrl,
    this.relation,
    this.isAvailable = true,
    this.authorType = SocialAuthorType.idol,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.idolImageUrl,
  });

  final String id;
  final String originalPostId;
  final SocialPlatform platform;
  final String idolId;
  final String idolName;
  final String idolInitials;
  final int idolColorStart;
  final int idolColorEnd;
  final String groupId;
  final String groupName;
  final SocialAuthorType authorType;
  final DateTime postedAt;
  final String content;
  final List<SocialPostMedia> media;
  final String originalUrl;
  final String? deepLinkUrl;
  final DateTime fetchedAt;
  final FeedRelation? relation;
  final bool isAvailable;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final String? idolImageUrl;

  bool get isGroupAuthor => authorType == SocialAuthorType.group;

  String get authorRoute => isGroupAuthor ? '/group/$groupId' : '/idol/$idolId';

  String get groupRoute => '/group/$groupId';

  factory SocialFeedPost.fromJson(Map<String, dynamic> json) => SocialFeedPost(
    id: json['id'] as String,
    originalPostId: json['original_post_id'] as String,
    platform: SocialPlatformInfo.fromWireName(json['platform'] as String),
    idolId: json['idol_id'] as String,
    idolName: json['idol_name'] as String,
    idolInitials: (json['idol_initials'] as String?) ?? '?',
    idolImageUrl: json['idol_image_url'] as String?,
    idolColorStart: (json['idol_color_start'] as num?)?.toInt() ?? 0xFFBBA9FF,
    idolColorEnd: (json['idol_color_end'] as num?)?.toInt() ?? 0xFF5A58A4,
    groupId: (json['group_id'] as String?) ?? '',
    groupName: (json['group_name'] as String?) ?? '',
    authorType: json['author_type'] == 'group'
        ? SocialAuthorType.group
        : SocialAuthorType.idol,
    postedAt: DateTime.parse(json['post_time'] as String),
    content: (json['content'] as String?) ?? '',
    media: (json['media'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(SocialPostMedia.fromJson)
        .toList(),
    originalUrl: json['original_url'] as String,
    deepLinkUrl: json['deep_link_url'] as String?,
    fetchedAt: DateTime.parse(json['fetch_time'] as String),
    relation: json['relation'] is Map<String, dynamic>
        ? FeedRelation.fromJson(json['relation'] as Map<String, dynamic>)
        : null,
    isAvailable: (json['is_available'] as bool?) ?? true,
    likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
    commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
    shareCount: (json['share_count'] as num?)?.toInt() ?? 0,
  );
}

class FeedComment {
  const FeedComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
    this.parentId,
    this.replyToName,
    this.likeCount = 0,
    this.isMine = false,
  });

  final String id;
  final String postId;
  final String userId;
  final String userName;
  final String content;
  final DateTime createdAt;
  final String? parentId;
  final String? replyToName;
  final int likeCount;
  final bool isMine;

  factory FeedComment.fromJson(Map<String, dynamic> json) => FeedComment(
    id: json['id'] as String,
    postId: json['post_id'] as String,
    userId: json['user_id'] as String,
    userName: (json['user_name'] as String?) ?? 'Fan OS 用户',
    content: (json['content'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    parentId: json['parent_id'] as String?,
    replyToName: json['reply_to_name'] as String?,
    likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
    isMine: (json['is_mine'] as bool?) ?? false,
  );
}

class SocialFeedPageData {
  const SocialFeedPageData({
    required this.posts,
    required this.unavailablePlatforms,
    required this.isFromCache,
    this.nextCursor,
    this.newCount = 0,
  });

  final List<SocialFeedPost> posts;
  final String? nextCursor;
  final Set<SocialPlatform> unavailablePlatforms;
  final bool isFromCache;
  final int newCount;
}

class SocialFeedRefreshData {
  const SocialFeedRefreshData({required this.page, required this.newCount});

  final SocialFeedPageData page;
  final int newCount;
}

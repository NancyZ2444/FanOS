import 'package:dio/dio.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/data/social_feed_models.dart';

class UserAccountSnapshot {
  const UserAccountSnapshot({
    this.userId = 'current-user',
    required this.displayName,
    required this.bio,
    required this.weiboVisible,
    this.weiboName,
    this.weiboUrl,
    this.onboardingCompleted = true,
    this.passwordSetupRequired = false,
    required this.level,
    required this.experience,
    required this.nextLevelExperience,
    required this.privacy,
    required this.favoriteIdolIds,
    required this.primaryIdolId,
    required this.owned,
    required this.wishlist,
    required this.albums,
    required this.photos,
    required this.followingCount,
    required this.followersCount,
    this.avatarPath,
    this.backgroundPath,
  });

  final String displayName;
  final String userId;
  final String bio;
  final bool weiboVisible;
  final String? weiboName;
  final String? weiboUrl;
  final bool onboardingCompleted;
  final bool passwordSetupRequired;
  final int level;
  final int experience;
  final int nextLevelExperience;
  final ProfilePrivacy privacy;
  final Set<String> favoriteIdolIds;
  final String? primaryIdolId;
  final Map<String, int> owned;
  final Set<String> wishlist;
  final List<DigitalCardAlbum> albums;
  final List<ProfilePhoto> photos;
  final int followingCount;
  final int followersCount;
  final String? avatarPath;
  final String? backgroundPath;
}

abstract interface class UserDataRepository {
  Future<UserAccountSnapshot> fetchAccountSnapshot();
  Future<void> updateProfile(Map<String, dynamic> payload);
  Future<String?> saveProfileImage(String kind, String? path);
  Future<PublicUserProfile> fetchPublicProfile(String userId);
  Future<void> updateFavorites(Set<String> idolIds, String? primaryId);
  Future<void> setOwnedQuantity(String cardId, int quantity);
  Future<void> incrementOwned(String cardId);
  Future<void> setWishlist(String cardId, bool wished);
  Future<void> setFollow(String userId, bool following);
  Future<void> createAlbum(String name);
  Future<void> uploadProfilePhotos(Iterable<String> paths);
  Future<void> markPostViewed(String postId);
  Future<void> setPostLiked(String postId, bool liked);
  Future<List<FeedComment>> fetchComments(String postId);
  Future<FeedComment> createComment(
    String postId,
    String content, {
    String? parentId,
    String? replyToUserId,
  });
  Future<void> deleteComment(String commentId);
  Future<void> setCommentLiked(String commentId, bool liked);
  Future<void> reportComment(String commentId);
  Future<void> setNotificationSettings(Map<String, bool> payload);
}

class MockUserDataRepository implements UserDataRepository {
  @override
  Future<String?> saveProfileImage(String kind, String? path) async => path;
  @override
  Future<PublicUserProfile> fetchPublicProfile(String userId) async {
    final profile = DemoUserProfiles.find(userId);
    if (profile == null) throw StateError('用户不存在');
    return profile;
  }

  @override
  Future<UserAccountSnapshot> fetchAccountSnapshot() async =>
      const UserAccountSnapshot(
        displayName: '星河收藏家',
        bio: '把每一次心动，都好好收藏。',
        weiboVisible: false,
        level: 12,
        experience: 3280,
        nextLevelExperience: 4000,
        privacy: ProfilePrivacy(),
        favoriteIdolIds: {},
        primaryIdolId: null,
        owned: {'card-aria-01': 1},
        wishlist: {'card-lin-01'},
        albums: [],
        photos: [],
        followingCount: 128,
        followersCount: 2356,
      );

  @override
  Future<void> createAlbum(String name) async {}
  @override
  Future<FeedComment> createComment(
    String postId,
    String content, {
    String? parentId,
    String? replyToUserId,
  }) {
    throw UnsupportedError(
      'Mock comments are managed by FeedEngagementController',
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {}
  @override
  Future<List<FeedComment>> fetchComments(String postId) async => const [];
  @override
  Future<void> incrementOwned(String cardId) async {}
  @override
  Future<void> markPostViewed(String postId) async {}
  @override
  Future<void> reportComment(String commentId) async {}
  @override
  Future<void> setFollow(String userId, bool following) async {}
  @override
  Future<void> setNotificationSettings(Map<String, bool> payload) async {}
  @override
  Future<void> setOwnedQuantity(String cardId, int quantity) async {}
  @override
  Future<void> setPostLiked(String postId, bool liked) async {}
  @override
  Future<void> setCommentLiked(String commentId, bool liked) async {}
  @override
  Future<void> setWishlist(String cardId, bool wished) async {}
  @override
  Future<void> updateFavorites(Set<String> idolIds, String? primaryId) async {}
  @override
  Future<void> updateProfile(Map<String, dynamic> payload) async {}
  @override
  Future<void> uploadProfilePhotos(Iterable<String> paths) async {}
}

class ApiUserDataRepository implements UserDataRepository {
  ApiUserDataRepository(this._client);
  final ApiClient _client;

  @override
  Future<PublicUserProfile> fetchPublicProfile(String userId) async =>
      PublicUserProfile.fromJson(
        await _client.getData('/users/$userId') as Map<String, dynamic>,
      );

  @override
  Future<String?> saveProfileImage(String kind, String? path) async {
    if (path == null) {
      await _client.deleteData('/me/profile/images/$kind');
      return null;
    }
    final data = await _client.postData(
      '/me/profile/images/$kind',
      data: FormData.fromMap({'image': await MultipartFile.fromFile(path)}),
    ) as Map<String, dynamic>;
    return data['image_url'] as String?;
  }

  @override
  Future<UserAccountSnapshot> fetchAccountSnapshot() async {
    final profile =
        await _client.getData('/me/profile') as Map<String, dynamic>;
    final albumData =
        await _client.getData('/me/card-albums') as Map<String, dynamic>;
    final photoData =
        await _client.getData('/me/profile-photos') as Map<String, dynamic>;
    final privacy = (profile['privacy'] as Map<String, dynamic>?) ?? const {};
    final owned = (profile['owned'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );
    final albums = (albumData['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (item) => DigitalCardAlbum(
            id: item['id'] as String,
            name: item['name'] as String,
            cardCount: (item['card_count'] as num?)?.toInt() ?? 0,
            updatedLabel: (item['updated_label'] as String?) ?? '最近更新',
            colorStart: (item['color_start'] as num?)?.toInt() ?? 0xFF8176CA,
            colorEnd: (item['color_end'] as num?)?.toInt() ?? 0xFF272B53,
          ),
        )
        .toList();
    final photos = (photoData['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .toList()
        .indexed
        .map(
          (entry) => ProfilePhoto(
            id: entry.$2['id'] as String,
            localPath: entry.$2['image_url'] as String?,
            colorStart: entry.$1.isEven ? 0xFF91D7F2 : 0xFFFFB7C8,
            colorEnd: entry.$1.isEven ? 0xFF3977A8 : 0xFFB84670,
          ),
        )
        .toList();
    return UserAccountSnapshot(
      userId: (profile['id'] as String?) ?? 'current-user',
      avatarPath: profile['avatar_url'] as String?,
      backgroundPath: profile['background_url'] as String?,
      displayName: (profile['display_name'] as String?) ?? '星河收藏家',
      bio: (profile['bio'] as String?) ?? '',
      weiboVisible: profile['weibo_name'] != null,
      weiboName: profile['weibo_name'] as String?,
      weiboUrl:
          (profile['weibo_profile_url'] ?? profile['weibo_url']) as String?,
      onboardingCompleted: profile['onboarding_completed'] as bool? ?? true,
      passwordSetupRequired: profile['password_setup_required'] == true,
      level: (profile['level'] as num?)?.toInt() ?? 1,
      experience: (profile['experience'] as num?)?.toInt() ?? 0,
      nextLevelExperience:
          (profile['next_level_experience'] as num?)?.toInt() ?? 250,
      privacy: ProfilePrivacy(
        collectionVisible: privacy['collection_visible'] as bool? ?? true,
        likesVisible: privacy['likes_visible'] as bool? ?? true,
        albumsVisible: privacy['albums_visible'] as bool? ?? true,
        photosVisible: privacy['photos_visible'] as bool? ?? true,
        followingListVisible:
            privacy['following_list_visible'] as bool? ?? true,
        followersListVisible:
            privacy['followers_list_visible'] as bool? ?? true,
        favoritesVisible: privacy['favorites_visible'] as bool? ?? true,
        discoverable: privacy['discoverable'] as bool? ?? true,
      ),
      favoriteIdolIds:
          (profile['favorite_idol_ids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet(),
      primaryIdolId: profile['primary_idol_id'] as String?,
      owned: owned,
      wishlist: (profile['liked_card_ids'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
      albums: albums,
      photos: photos,
      followingCount: (profile['following_count'] as num?)?.toInt() ?? 0,
      followersCount: (profile['followers_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> payload) async {
    await _client.patchData('/me/profile', data: payload);
  }

  @override
  Future<void> updateFavorites(Set<String> idolIds, String? primaryId) async {
    await _client.putData(
      '/me/favorites',
      data: {'idol_ids': idolIds.toList(), 'primary_idol_id': primaryId},
    );
  }

  @override
  Future<void> setOwnedQuantity(String cardId, int quantity) async {
    await _client.putData(
      '/me/collection/$cardId',
      data: {'quantity': quantity},
    );
  }

  @override
  Future<void> incrementOwned(String cardId) async {
    await _client.postData('/me/collection/$cardId/increment');
  }

  @override
  Future<void> setWishlist(String cardId, bool wished) async {
    if (wished) {
      await _client.putData('/me/wishlist/$cardId');
    } else {
      await _client.deleteData('/me/wishlist/$cardId');
    }
  }

  @override
  Future<void> setFollow(String userId, bool following) async {
    if (following) {
      await _client.putData('/users/$userId/follow');
    } else {
      await _client.deleteData('/users/$userId/follow');
    }
  }

  @override
  Future<void> createAlbum(String name) async {
    await _client.postData('/me/card-albums', data: {'name': name});
  }

  @override
  Future<void> uploadProfilePhotos(Iterable<String> paths) async {
    for (final path in paths) {
      await _client.postData(
        '/me/profile-photos',
        data: FormData.fromMap({'image': await MultipartFile.fromFile(path)}),
      );
    }
  }

  @override
  Future<void> markPostViewed(String postId) async {
    await _client.putData('/idol-feed/$postId/view');
  }

  @override
  Future<void> setPostLiked(String postId, bool liked) async {
    if (liked) {
      await _client.putData('/idol-feed/$postId/like');
    } else {
      await _client.deleteData('/idol-feed/$postId/like');
    }
  }

  @override
  Future<List<FeedComment>> fetchComments(String postId) async {
    final data = await _client.getData(
      '/idol-feed/$postId/comments',
    ) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(FeedComment.fromJson)
        .toList();
  }

  @override
  Future<FeedComment> createComment(
    String postId,
    String content, {
    String? parentId,
    String? replyToUserId,
  }) async {
    final data = parentId == null
        ? await _client.postData(
            '/idol-feed/$postId/comments',
            data: {'content': content},
          )
        : await _client.postData(
            '/idol-feed/$postId/comments/$parentId/replies',
            data: {'content': content, 'reply_to_user_id': ?replyToUserId},
          );
    return FeedComment.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.deleteData('/comments/$commentId');
  }

  @override
  Future<void> setCommentLiked(String commentId, bool liked) async {
    if (liked) {
      await _client.putData('/comments/$commentId/like');
    } else {
      await _client.deleteData('/comments/$commentId/like');
    }
  }

  @override
  Future<void> reportComment(String commentId) async {
    await _client.postData(
      '/comments/$commentId/report',
      data: {'reason': 'user_report'},
    );
  }

  @override
  Future<void> setNotificationSettings(Map<String, bool> payload) async {
    await _client.patchData('/notifications/settings/idol-feed', data: payload);
  }
}

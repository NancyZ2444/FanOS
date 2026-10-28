class ProfilePrivacy {
  const ProfilePrivacy({
    this.collectionVisible = true,
    this.likesVisible = true,
    this.albumsVisible = true,
    this.photosVisible = true,
    this.followingListVisible = true,
    this.followersListVisible = true,
    this.favoritesVisible = true,
    this.discoverable = true,
  });

  final bool collectionVisible;
  final bool likesVisible;
  final bool albumsVisible;
  final bool photosVisible;
  final bool followingListVisible;
  final bool followersListVisible;
  final bool favoritesVisible;
  final bool discoverable;

  ProfilePrivacy copyWith({
    bool? collectionVisible,
    bool? likesVisible,
    bool? albumsVisible,
    bool? photosVisible,
    bool? followingListVisible,
    bool? followersListVisible,
    bool? favoritesVisible,
    bool? discoverable,
  }) => ProfilePrivacy(
    collectionVisible: collectionVisible ?? this.collectionVisible,
    likesVisible: likesVisible ?? this.likesVisible,
    albumsVisible: albumsVisible ?? this.albumsVisible,
    photosVisible: photosVisible ?? this.photosVisible,
    followingListVisible: followingListVisible ?? this.followingListVisible,
    followersListVisible: followersListVisible ?? this.followersListVisible,
    favoritesVisible: favoritesVisible ?? this.favoritesVisible,
    discoverable: discoverable ?? this.discoverable,
  );
}

class PublicUserProfile {
  const PublicUserProfile({
    required this.id,
    required this.displayName,
    required this.initial,
    required this.bio,
    required this.level,
    required this.experience,
    required this.nextLevelExperience,
    required this.primaryIdolId,
    required this.favoriteIdolIds,
    required this.followingCount,
    required this.followersCount,
    required this.ownedCardIds,
    required this.likedCardIds,
    required this.albumCount,
    required this.photoCount,
    this.weiboName,
    this.weiboUrl,
    this.avatarPath,
    this.backgroundPath,
    this.albums = const [],
    this.photos = const [],
    this.privacy = const ProfilePrivacy(),
    this.relationStatus = UserRelationStatus.none,
  });

  final String id;
  final String displayName;
  final String initial;
  final String bio;
  final int level;
  final int experience;
  final int nextLevelExperience;
  final String? primaryIdolId;
  final List<String> favoriteIdolIds;
  final int followingCount;
  final int followersCount;
  final Set<String> ownedCardIds;
  final Set<String> likedCardIds;
  final int albumCount;
  final int photoCount;
  final String? weiboName;
  final String? weiboUrl;
  final String? avatarPath;
  final String? backgroundPath;
  final List<DigitalCardAlbum> albums;
  final List<ProfilePhoto> photos;
  final ProfilePrivacy privacy;
  final UserRelationStatus relationStatus;

  factory PublicUserProfile.fromJson(Map<String, dynamic> json) {
    final name = json['display_name'] as String? ?? '收藏家';
    return PublicUserProfile(
      id: json['id'] as String,
      displayName: name,
      initial: name.isEmpty ? 'F' : name.substring(0, 1),
      bio: json['bio'] as String? ?? '',
      avatarPath: json['avatar_url'] as String?,
      backgroundPath: json['background_url'] as String?,
      albums: (json['albums'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DigitalCardAlbum.fromJson)
          .toList(),
      photos: (json['photos'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(ProfilePhoto.fromJson)
          .toList(),
      level: (json['level'] as num?)?.toInt() ?? 1,
      experience: (json['experience'] as num?)?.toInt() ?? 0,
      nextLevelExperience:
          (json['next_level_experience'] as num?)?.toInt() ?? 250,
      primaryIdolId: json['primary_idol_id'] as String?,
      favoriteIdolIds: (json['favorite_idol_ids'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      ownedCardIds: (json['owned'] as Map<String, dynamic>? ?? {}).keys.toSet(),
      likedCardIds: (json['liked_card_ids'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toSet(),
      albumCount: (json['album_count'] as num?)?.toInt() ?? 0,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      weiboName: json['weibo_name'] as String?,
      weiboUrl: (json['weibo_profile_url'] ?? json['weibo_url']) as String?,
      privacy: ProfilePrivacy(
        collectionVisible: json['owned'] != null,
        likesVisible: json['liked_card_ids'] != null,
        albumsVisible: json['album_count'] != null,
        photosVisible: json['photo_count'] != null,
        favoritesVisible: json['primary_idol_id'] != null,
        followingListVisible: json['following_list_visible'] as bool? ?? true,
        followersListVisible: json['followers_list_visible'] as bool? ?? true,
      ),
      relationStatus: userRelationStatusFromJson(json['relation_status']),
    );
  }
}

class DigitalCardAlbum {
  const DigitalCardAlbum({
    required this.id,
    required this.name,
    required this.cardCount,
    required this.updatedLabel,
    required this.colorStart,
    required this.colorEnd,
  });

  final String id;
  final String name;
  final int cardCount;
  final String updatedLabel;
  final int colorStart;
  final int colorEnd;
  factory DigitalCardAlbum.fromJson(Map<String, dynamic> json) =>
      DigitalCardAlbum(
        id: json['id'] as String,
        name: json['name'] as String,
        cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
        updatedLabel: json['updated_label'] as String? ?? '最近更新',
        colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFF8176CA,
        colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF272B53,
      );
}

class ProfilePhoto {
  const ProfilePhoto({
    required this.id,
    required this.colorStart,
    required this.colorEnd,
    this.localPath,
  });

  final String id;
  final int colorStart;
  final int colorEnd;
  final String? localPath;
  factory ProfilePhoto.fromJson(Map<String, dynamic> json) => ProfilePhoto(
    id: json['id'] as String,
    localPath: json['image_url'] as String?,
    colorStart: 0xFF91D7F2,
    colorEnd: 0xFF3977A8,
  );
}

enum UserRelationStatus { none, followsYou, following, mutual }

UserRelationStatus userRelationStatusFromJson(dynamic value) => switch (value) {
  'following' => UserRelationStatus.following,
  'follows_you' => UserRelationStatus.followsYou,
  'mutual' => UserRelationStatus.mutual,
  _ => UserRelationStatus.none,
};

abstract final class DemoUserProfiles {
  static const users = <PublicUserProfile>[
    PublicUserProfile(
      id: 'user-luna',
      displayName: '月光收藏家',
      initial: '月',
      bio: '记录每一次舞台和拆卡时刻，最近在整理 LUMINA 的 Starlit 系列。',
      level: 16,
      experience: 4620,
      nextLevelExperience: 5200,
      primaryIdolId: 'idol-lin',
      favoriteIdolIds: ['idol-lin', 'idol-aria'],
      followingCount: 86,
      followersCount: 1204,
      ownedCardIds: {'card-lin-01', 'card-aria-01', 'card-aria-02'},
      likedCardIds: {'card-yuna-01'},
      albumCount: 2,
      photoCount: 8,
      weiboName: '@月光收藏家',
    ),
    PublicUserProfile(
      id: 'user-mint',
      displayName: '薄荷汽水',
      initial: '薄',
      bio: 'ASTER 双人推，偶尔分享线下活动记录。',
      level: 8,
      experience: 1680,
      nextLevelExperience: 2000,
      primaryIdolId: 'idol-yuna',
      favoriteIdolIds: ['idol-yuna', 'idol-mina'],
      followingCount: 45,
      followersCount: 318,
      ownedCardIds: {'card-yuna-01', 'card-mina-01'},
      likedCardIds: {'card-aria-02'},
      albumCount: 1,
      photoCount: 0,
      privacy: ProfilePrivacy(
        likesVisible: false,
        photosVisible: false,
        followingListVisible: false,
      ),
    ),
  ];

  static PublicUserProfile? find(String id) {
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }
}

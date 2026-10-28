import 'dart:async';

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/token_store.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/name_preferences.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/core/data/social_feed_repository.dart';
import 'package:fan_os/core/data/user_data_repository.dart';
import 'package:fan_os/core/data/user_social_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: true);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(tokenStore: SecureTokenStore(ApiClient.baseUrl)),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (useMockApi) return MockAuthRepository();
  return ApiAuthRepository(ref.watch(apiClientProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  if (useMockApi) return MockCatalogRepository();
  return ApiCatalogRepository(ref.watch(apiClientProvider));
});

final dailyCardRepositoryProvider = Provider<DailyCardRepository>((ref) {
  if (useMockApi) return MockDailyCardRepository();
  return ApiDailyCardRepository(ref.watch(apiClientProvider));
});

final scanRepositoryProvider = Provider<ScanRepository>((ref) {
  if (useMockApi) return MockScanRepository();
  return ApiScanRepository(ref.watch(apiClientProvider));
});

final socialFeedRepositoryProvider = Provider<SocialFeedRepository>((ref) {
  if (useMockApi) return MockSocialFeedRepository();
  return ApiSocialFeedRepository(ref.watch(apiClientProvider));
});

final userDataRepositoryProvider = Provider<UserDataRepository>((ref) {
  if (useMockApi) return MockUserDataRepository();
  return ApiUserDataRepository(ref.watch(apiClientProvider));
});

void _syncRemote(Future<void> operation) {
  if (useMockApi) return;
  unawaited(operation.catchError((Object _) {}));
}

final catalogLoadTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

final catalogProvider = FutureProvider<CatalogBundle>(
  (ref) async {
    final preferences = ref.watch(namePreferencesProvider);
    final timeout = ref.watch(catalogLoadTimeoutProvider);
    final catalog = await ref
        .watch(catalogRepositoryProvider)
        .fetchCatalog()
        .timeout(
          timeout,
          onTimeout: () {
            throw const ApiException('REQUEST_TIMEOUT', '图鉴加载超时，请重新加载');
          },
        );
    return preferences.apply(catalog);
  },
  // Keep a visible, actionable error. Riverpod's automatic backoff should not
  // turn a timed-out catalog back into a seemingly endless loading indicator.
  retry: (_, _) => null,
);

class NamePreferencesController extends Notifier<NamePreferences> {
  @override
  NamePreferences build() => const NamePreferences();

  Future<void> load() async {
    if (useMockApi) return;
    final data = await ref
        .read(apiClientProvider)
        .getData('/me/name-preferences');
    state = NamePreferences.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> setMode(NameDisplayMode mode) async {
    if (!useMockApi) {
      await ref
          .read(apiClientProvider)
          .patchData('/me/name-preferences', data: {'mode': mode.value});
    }
    state = NamePreferences(mode: mode, aliases: state.aliases);
  }

  Future<void> setRemark(String kind, String id, String remark) async {
    final value = remark.trim();
    if (!useMockApi) {
      await ref
          .read(apiClientProvider)
          .putData('/me/name-preferences/$kind/$id', data: {'remark': value});
    }
    final names = {...?state.aliases[kind]};
    if (value.isEmpty) {
      names.remove(id);
    } else {
      names[id] = value;
    }
    state = NamePreferences(
      mode: state.mode,
      aliases: {...state.aliases, kind: names},
    );
  }
}

final namePreferencesProvider =
    NotifierProvider<NamePreferencesController, NamePreferences>(
      NamePreferencesController.new,
    );

final publicUserProfileProvider =
    FutureProvider.family<PublicUserProfile, String>((ref, id) {
      ref.watch(sessionProvider.select((session) => session.userId));
      return ref.watch(userDataRepositoryProvider).fetchPublicProfile(id);
    });

final userSocialRepositoryProvider = Provider<UserSocialRepository>(
  (ref) => useMockApi
      ? MockUserSocialRepository()
      : ApiUserSocialRepository(ref.watch(apiClientProvider)),
);

final userSearchProvider = FutureProvider.autoDispose
    .family<List<PublicUserProfile>, String>((ref, query) {
      ref.watch(sessionProvider.select((session) => session.userId));
      if (query.trim().isEmpty) return Future.value([]);
      return ref.watch(userSocialRepositoryProvider).search(query);
    });

final userRelationsProvider = FutureProvider.autoDispose
    .family<List<PublicUserProfile>, ({String userId, String type})>((
      ref,
      request,
    ) {
      ref.watch(sessionProvider.select((session) => session.userId));
      return ref
          .watch(userSocialRepositoryProvider)
          .relations(request.userId, request.type);
    });

class SessionState {
  const SessionState({
    this.isLoggedIn = false,
    this.isGuest = false,
    this.displayName = '星河收藏家',
    this.userId = 'current-user',
    this.weiboVisible = false,
    this.weiboName,
    this.weiboUrl,
    this.onboardingCompleted = true,
    this.passwordSetupRequired = false,
    this.bio = '把每一次心动，都好好收藏。',
    this.avatarPath,
    this.backgroundPath,
    this.level = 12,
    this.experience = 3280,
    this.nextLevelExperience = 4000,
    this.privacy = const ProfilePrivacy(),
  });

  final bool isLoggedIn;
  final bool isGuest;
  final String displayName;
  final String userId;
  final bool weiboVisible;
  final String? weiboName;
  final String? weiboUrl;
  final bool onboardingCompleted;
  final bool passwordSetupRequired;
  final String bio;
  final String? avatarPath;
  final String? backgroundPath;
  final int level;
  final int experience;
  final int nextLevelExperience;
  final ProfilePrivacy privacy;

  SessionState copyWith({
    bool? isLoggedIn,
    bool? isGuest,
    bool? passwordSetupRequired,
    bool? onboardingCompleted,
    String? displayName,
    bool? weiboVisible,
    String? bio,
    String? avatarPath,
    String? backgroundPath,
    bool clearBackground = false,
    bool clearAvatar = false,
    ProfilePrivacy? privacy,
  }) => SessionState(
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    isGuest: isGuest ?? this.isGuest,
    displayName: displayName ?? this.displayName,
    userId: userId,
    weiboVisible: weiboVisible ?? this.weiboVisible,
    weiboName: weiboName,
    weiboUrl: weiboUrl,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    passwordSetupRequired: passwordSetupRequired ?? this.passwordSetupRequired,
    bio: bio ?? this.bio,
    avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    backgroundPath: clearBackground
        ? null
        : (backgroundPath ?? this.backgroundPath),
    level: level,
    experience: experience,
    nextLevelExperience: nextLevelExperience,
    privacy: privacy ?? this.privacy,
  );
}

class SessionController extends Notifier<SessionState> {
  int _generation = 0;
  @override
  SessionState build() => const SessionState();

  Future<void> login(LoginMethod method, {String? phone, String? code}) async {
    final generation = ++_generation;
    await ref
        .read(authRepositoryProvider)
        .login(method, phone: phone, code: code);
    if (generation != _generation) return;
    if (useMockApi) {
      state = state.copyWith(isLoggedIn: true, isGuest: false);
      return;
    }
    await _loadAccount();
  }

  Future<void> acceptAuthentication(Map<String, dynamic> data) async {
    final generation = ++_generation;
    final client = ref.read(apiClientProvider);
    await client.saveAuthTokens(data);
    client.isNewAccount = data['is_new_user'] == true;
    client.onboardingCompleted =
        data['onboarding_completed'] as bool? ?? !client.isNewAccount;
    client.passwordSetupRequired = data['password_setup_required'] == true;
    if (generation != _generation) return;
    await _loadAccount();
  }

  Future<void> reloadAccount() => _loadAccount();

  void passwordRegistrationCompleted() {
    ref.read(apiClientProvider).passwordSetupRequired = false;
    state = state.copyWith(passwordSetupRequired: false);
  }

  Future<void> finishOnboarding() async {
    if (!useMockApi) {
      await ref
          .read(apiClientProvider)
          .postData('/account/onboarding/complete');
      ref.read(apiClientProvider).onboardingCompleted = true;
    }
    state = state.copyWith(onboardingCompleted: true);
  }

  Future<void> signOut() async {
    if (!useMockApi) await ref.read(apiClientProvider).revokeSession();
    await logout();
  }

  Future<bool> restore() async {
    if (useMockApi) return false;
    final client = ref.read(apiClientProvider);
    if (!await client.restoreAuthTokens()) return false;
    try {
      await _loadAccount();
      return state.isLoggedIn;
    } on ApiException catch (e) {
      if (e.statusCode == 401 ||
          e.code == 'AUTH_REQUIRED' ||
          e.code == 'INVALID_TOKEN') {
        await logout();
        return false;
      }
      rethrow;
    }
  }

  Future<void> _loadAccount() async {
    final generation = _generation;
    final snapshot = await ref
        .read(userDataRepositoryProvider)
        .fetchAccountSnapshot();
    if (generation != _generation) return;
    await ref.read(namePreferencesProvider.notifier).load();
    if (generation != _generation) return;
    state = SessionState(
      userId: snapshot.userId,
      isLoggedIn: true,
      displayName: snapshot.displayName,
      weiboVisible: snapshot.weiboVisible,
      weiboName: snapshot.weiboName,
      weiboUrl: snapshot.weiboUrl,
      onboardingCompleted: snapshot.onboardingCompleted,
      passwordSetupRequired: snapshot.passwordSetupRequired,
      bio: snapshot.bio,
      avatarPath: snapshot.avatarPath,
      backgroundPath: snapshot.backgroundPath,
      level: snapshot.level,
      experience: snapshot.experience,
      nextLevelExperience: snapshot.nextLevelExperience,
      privacy: snapshot.privacy,
    );
    ref
        .read(favoritesProvider.notifier)
        .hydrate(snapshot.favoriteIdolIds, snapshot.primaryIdolId);
    ref
        .read(collectionProvider.notifier)
        .hydrate(snapshot.owned, snapshot.wishlist);
    ref
        .read(profileAssetProvider.notifier)
        .hydrate(snapshot.albums, snapshot.photos);
    ref
        .read(profileRelationshipProvider.notifier)
        .hydrateCounts(snapshot.followingCount, snapshot.followersCount);
  }

  Future<void> continueAsGuest() async {
    await logout();
    state = state.copyWith(isLoggedIn: false, isGuest: true);
  }

  Future<void> saveProfileImage(String kind, String? path) async {
    final url = await ref
        .read(userDataRepositoryProvider)
        .saveProfileImage(kind, path);
    state = kind == 'background'
        ? state.copyWith(backgroundPath: url, clearBackground: url == null)
        : state.copyWith(avatarPath: url, clearAvatar: url == null);
  }

  void updateProfile({
    bool syncRemote = true,
    String? displayName,
    bool? weiboVisible,
    String? bio,
    String? avatarPath,
    ProfilePrivacy? privacy,
  }) {
    state = state.copyWith(
      displayName: displayName,
      weiboVisible: weiboVisible,
      bio: bio,
      avatarPath: avatarPath,
      privacy: privacy,
    );
    if (syncRemote) {
      _syncRemote(
        ref.read(userDataRepositoryProvider).updateProfile({
          'display_name': ?displayName,
          'bio': ?bio,
          'weibo_visible': ?weiboVisible,
          if (privacy != null)
            'privacy': {
              'collection_visible': privacy.collectionVisible,
              'likes_visible': privacy.likesVisible,
              'albums_visible': privacy.albumsVisible,
              'photos_visible': privacy.photosVisible,
              'following_list_visible': privacy.followingListVisible,
              'followers_list_visible': privacy.followersListVisible,
              'favorites_visible': privacy.favoritesVisible,
              'discoverable': privacy.discoverable,
            },
        }),
      );
    }
  }

  void reset() {
    ref.invalidate(namePreferencesProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(collectionProvider);
    ref.invalidate(profileAssetProvider);
    ref.invalidate(profileRelationshipProvider);
    ref.invalidate(publicUserProfileProvider);
    ref.invalidate(userRelationsProvider);
    ref.invalidate(userSearchProvider);
    ref.invalidate(userSocialRepositoryProvider);
    state = const SessionState();
  }

  Future<void> logout() async {
    _generation++;
    if (useMockApi) {
      ref.read(apiClientProvider).clearAccessToken();
    } else {
      await ref.read(apiClientProvider).logout();
    }
    reset();
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class FavoritesState {
  const FavoritesState({this.selectedIds = const {}, this.primaryId});

  final Set<String> selectedIds;
  final String? primaryId;

  FavoritesState copyWith({Set<String>? selectedIds, String? primaryId}) =>
      FavoritesState(
        selectedIds: selectedIds ?? this.selectedIds,
        primaryId: primaryId ?? this.primaryId,
      );
}

class FavoritesController extends Notifier<FavoritesState> {
  @override
  FavoritesState build() => const FavoritesState();

  void hydrate(Set<String> selectedIds, String? primaryId) {
    final selected = {...selectedIds};
    state = FavoritesState(
      selectedIds: selected,
      primaryId: selected.contains(primaryId) ? primaryId : null,
    );
  }

  void toggle(String id) {
    final next = {...state.selectedIds};
    if (next.contains(id)) {
      next.remove(id);
    } else if (next.length < 20) {
      next.add(id);
    }
    final primary = next.contains(state.primaryId) ? state.primaryId : null;
    state = FavoritesState(selectedIds: next, primaryId: primary);
    _syncRemote(
      ref.read(userDataRepositoryProvider).updateFavorites(next, primary),
    );
  }

  Future<void> saveSelection(Set<String> ids, String? primaryId) async {
    final selected = {...ids};
    final primary = selected.contains(primaryId) ? primaryId : null;
    await ref
        .read(userDataRepositoryProvider)
        .updateFavorites(selected, primary);
    hydrate(selected, primary);
  }

  void setPrimary(String id) {
    if (!state.selectedIds.contains(id)) return;
    final primary = state.primaryId == id ? null : id;
    state = FavoritesState(selectedIds: state.selectedIds, primaryId: primary);
    _syncRemote(
      ref
          .read(userDataRepositoryProvider)
          .updateFavorites(state.selectedIds, primary),
    );
  }
}

final favoritesProvider = NotifierProvider<FavoritesController, FavoritesState>(
  FavoritesController.new,
);

class ProfileRelationshipState {
  const ProfileRelationshipState({
    this.followingIds = const {},
    this.followsMeIds = const {},
    this.busyUserIds = const {},
    this.myFollowingCount = 0,
    this.myFollowersCount = 0,
    this.followerCountAdjustments = const {},
    this.knownStatuses = const {},
    this.targetFollowerCounts = const {},
  });

  final Set<String> followingIds;
  final Set<String> followsMeIds;
  final Set<String> busyUserIds;
  final int myFollowingCount;
  final int myFollowersCount;
  final Map<String, int> followerCountAdjustments;
  final Map<String, UserRelationStatus> knownStatuses;
  final Map<String, int> targetFollowerCounts;

  UserRelationStatus statusFor(
    String userId, {
    UserRelationStatus fallback = UserRelationStatus.none,
  }) {
    if (knownStatuses.containsKey(userId)) return knownStatuses[userId]!;
    final following = followingIds.contains(userId);
    final followsMe = followsMeIds.contains(userId);
    if (following && followsMe) return UserRelationStatus.mutual;
    if (following) return UserRelationStatus.following;
    if (followsMe) return UserRelationStatus.followsYou;
    return fallback;
  }

  int followerCountFor(PublicUserProfile profile) =>
      targetFollowerCounts[profile.id] ?? profile.followersCount;

  ProfileRelationshipState copyWith({
    Set<String>? followingIds,
    Set<String>? followsMeIds,
    Set<String>? busyUserIds,
    int? myFollowingCount,
    int? myFollowersCount,
    Map<String, int>? followerCountAdjustments,
    Map<String, UserRelationStatus>? knownStatuses,
    Map<String, int>? targetFollowerCounts,
  }) => ProfileRelationshipState(
    followingIds: followingIds ?? this.followingIds,
    followsMeIds: followsMeIds ?? this.followsMeIds,
    busyUserIds: busyUserIds ?? this.busyUserIds,
    myFollowingCount: myFollowingCount ?? this.myFollowingCount,
    myFollowersCount: myFollowersCount ?? this.myFollowersCount,
    followerCountAdjustments:
        followerCountAdjustments ?? this.followerCountAdjustments,
    knownStatuses: knownStatuses ?? this.knownStatuses,
    targetFollowerCounts: targetFollowerCounts ?? this.targetFollowerCounts,
  );
}

class ProfileRelationshipController extends Notifier<ProfileRelationshipState> {
  int _generation = 0;
  @override
  ProfileRelationshipState build() {
    _generation++;
    ref.onDispose(() => _generation++);
    return useMockApi
        ? const ProfileRelationshipState(
            followingIds: {'user-luna'},
            followsMeIds: {'user-luna', 'user-mint'},
            myFollowingCount: 128,
            myFollowersCount: 2356,
          )
        : const ProfileRelationshipState();
  }

  void hydrateCounts(int followingCount, int followersCount) {
    state = state.copyWith(
      myFollowingCount: followingCount,
      myFollowersCount: followersCount,
    );
  }

  Future<void> toggleFollow(
    String userId, {
    UserRelationStatus? currentStatus,
  }) async {
    if (state.busyUserIds.contains(userId) ||
        userId == ref.read(sessionProvider).userId) {
      return;
    }
    final actingUserId = ref.read(sessionProvider).userId;
    final generation = _generation;
    final status = state.statusFor(
      userId,
      fallback: currentStatus ?? UserRelationStatus.none,
    );
    final wasFollowing =
        status == UserRelationStatus.following ||
        status == UserRelationStatus.mutual;
    state = state.copyWith(busyUserIds: {...state.busyUserIds, userId});
    try {
      final result = await ref
          .read(userSocialRepositoryProvider)
          .setFollow(userId, !wasFollowing);
      if (generation != _generation ||
          ref.read(sessionProvider).userId != actingUserId) {
        return;
      }
      final nextFollowing = {...state.followingIds}..remove(userId);
      final nextFollowers = {...state.followsMeIds}..remove(userId);
      if (result.status == UserRelationStatus.following ||
          result.status == UserRelationStatus.mutual) {
        nextFollowing.add(userId);
      }
      if (result.status == UserRelationStatus.followsYou ||
          result.status == UserRelationStatus.mutual) {
        nextFollowers.add(userId);
      }
      state = state.copyWith(
        followingIds: nextFollowing,
        followsMeIds: nextFollowers,
        myFollowingCount: result.myFollowingCount,
        myFollowersCount: result.myFollowersCount,
        knownStatuses: {...state.knownStatuses, userId: result.status},
        targetFollowerCounts: {
          ...state.targetFollowerCounts,
          userId: result.followersCount,
        },
      );
      ref.invalidate(userRelationsProvider);
      ref.invalidate(userSearchProvider);
      ref.invalidate(publicUserProfileProvider(userId));
    } finally {
      if (generation == _generation &&
          ref.read(sessionProvider).userId == actingUserId) {
        state = state.copyWith(
          busyUserIds: {...state.busyUserIds}..remove(userId),
        );
      }
    }
  }
}

final profileRelationshipProvider =
    NotifierProvider<ProfileRelationshipController, ProfileRelationshipState>(
      ProfileRelationshipController.new,
    );

class ProfileAssetState {
  const ProfileAssetState({
    this.albums = const [
      DigitalCardAlbum(
        id: 'album-starlit',
        name: 'Starlit 收藏册',
        cardCount: 12,
        updatedLabel: '今天更新',
        colorStart: 0xFF8176CA,
        colorEnd: 0xFF272B53,
      ),
      DigitalCardAlbum(
        id: 'album-live',
        name: '现场回忆',
        cardCount: 8,
        updatedLabel: '3 天前更新',
        colorStart: 0xFFF2A8BB,
        colorEnd: 0xFF87415D,
      ),
    ],
    this.photos = const [
      ProfilePhoto(id: 'photo-1', colorStart: 0xFFBBA9FF, colorEnd: 0xFF5A58A4),
      ProfilePhoto(id: 'photo-2', colorStart: 0xFF91D7F2, colorEnd: 0xFF3977A8),
      ProfilePhoto(id: 'photo-3', colorStart: 0xFFFFB7C8, colorEnd: 0xFFB84670),
      ProfilePhoto(id: 'photo-4', colorStart: 0xFF9FE0CE, colorEnd: 0xFF2D8676),
    ],
  });

  final List<DigitalCardAlbum> albums;
  final List<ProfilePhoto> photos;

  ProfileAssetState copyWith({
    List<DigitalCardAlbum>? albums,
    List<ProfilePhoto>? photos,
  }) => ProfileAssetState(
    albums: albums ?? this.albums,
    photos: photos ?? this.photos,
  );
}

class ProfileAssetController extends Notifier<ProfileAssetState> {
  @override
  ProfileAssetState build() => const ProfileAssetState();

  void hydrate(List<DigitalCardAlbum> albums, List<ProfilePhoto> photos) {
    state = ProfileAssetState(albums: albums, photos: photos);
  }

  void createAlbum() {
    final number = state.albums.length + 1;
    state = state.copyWith(
      albums: [
        ...state.albums,
        DigitalCardAlbum(
          id: 'album-${DateTime.now().microsecondsSinceEpoch}',
          name: '我的卡册 $number',
          cardCount: 0,
          updatedLabel: '刚刚创建',
          colorStart: 0xFFA8B6FF,
          colorEnd: 0xFF4852A8,
        ),
      ],
    );
    _syncRemote(
      ref.read(userDataRepositoryProvider).createAlbum('我的卡册 $number'),
    );
  }

  void addPhotos(Iterable<String> paths) {
    final pathList = paths.toList();
    final incoming = pathList.indexed.map(
      (entry) => ProfilePhoto(
        id: 'photo-${DateTime.now().microsecondsSinceEpoch}-${entry.$1}',
        colorStart: 0xFFBBA9FF,
        colorEnd: 0xFF5A58A4,
        localPath: entry.$2,
      ),
    );
    state = state.copyWith(photos: [...state.photos, ...incoming]);
    _syncRemote(
      ref.read(userDataRepositoryProvider).uploadProfilePhotos(pathList),
    );
  }
}

final profileAssetProvider =
    NotifierProvider<ProfileAssetController, ProfileAssetState>(
      ProfileAssetController.new,
    );

class DailyCardState {
  const DailyCardState({
    this.drawnCards = const [],
    this.isDrawing = false,
    this.errorMessage,
  });

  final List<CollectibleCard> drawnCards;
  final bool isDrawing;
  final String? errorMessage;
  int get remaining => 3 - drawnCards.length;

  DailyCardState copyWith({
    List<CollectibleCard>? drawnCards,
    bool? isDrawing,
    String? errorMessage,
    bool clearError = false,
  }) => DailyCardState(
    drawnCards: drawnCards ?? this.drawnCards,
    isDrawing: isDrawing ?? this.isDrawing,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

class DailyCardController extends Notifier<DailyCardState> {
  @override
  DailyCardState build() => const DailyCardState();

  Future<CollectibleCard?> draw() async {
    if (state.isDrawing || state.remaining <= 0) return null;
    state = state.copyWith(isDrawing: true, clearError: true);
    try {
      final favoriteIds = ref.read(favoritesProvider).selectedIds.toList();
      final card = await ref
          .read(dailyCardRepositoryProvider)
          .draw(
            drawnCardIds: state.drawnCards.map((item) => item.id).toList(),
            favoriteIdolIds: favoriteIds,
          );
      state = DailyCardState(drawnCards: [...state.drawnCards, card]);
      return card;
    } catch (_) {
      state = state.copyWith(isDrawing: false, errorMessage: '翻卡失败，请稍后重试');
      return null;
    }
  }

  void resetDemo() => state = const DailyCardState();
}

final dailyCardProvider = NotifierProvider<DailyCardController, DailyCardState>(
  DailyCardController.new,
);

class CollectionState {
  const CollectionState({
    this.owned = const {'card-aria-01': 1},
    this.wishlist = const {'card-lin-01'},
  });

  final Map<String, int> owned;
  final Set<String> wishlist;

  int quantity(String cardId) => owned[cardId] ?? 0;
  bool isOwned(String cardId) => quantity(cardId) > 0;
  bool isWished(String cardId) => wishlist.contains(cardId);
}

class CollectionController extends Notifier<CollectionState> {
  @override
  CollectionState build() => const CollectionState();

  void hydrate(Map<String, int> owned, Set<String> wishlist) {
    state = CollectionState(owned: {...owned}, wishlist: {...wishlist});
  }

  void toggleOwned(String cardId) {
    final next = {...state.owned};
    if ((next[cardId] ?? 0) > 0) {
      next.remove(cardId);
    } else {
      next[cardId] = 1;
    }
    state = CollectionState(owned: next, wishlist: state.wishlist);
    _syncRemote(
      ref
          .read(userDataRepositoryProvider)
          .setOwnedQuantity(cardId, next[cardId] ?? 0),
    );
  }

  void incrementOwned(String cardId, {bool sync = true}) {
    final next = {...state.owned};
    next[cardId] = (next[cardId] ?? 0) + 1;
    state = CollectionState(owned: next, wishlist: state.wishlist);
    if (sync) {
      _syncRemote(ref.read(userDataRepositoryProvider).incrementOwned(cardId));
    }
  }

  void setOwnedQuantity(String cardId, int quantity) {
    final safeQuantity = quantity.clamp(0, 99);
    final next = {...state.owned};
    if (safeQuantity == 0) {
      next.remove(cardId);
    } else {
      next[cardId] = safeQuantity;
    }
    state = CollectionState(owned: next, wishlist: state.wishlist);
    _syncRemote(
      ref
          .read(userDataRepositoryProvider)
          .setOwnedQuantity(cardId, safeQuantity),
    );
  }

  void toggleWishlist(String cardId) {
    final next = {...state.wishlist};
    next.contains(cardId) ? next.remove(cardId) : next.add(cardId);
    state = CollectionState(owned: state.owned, wishlist: next);
    _syncRemote(
      ref
          .read(userDataRepositoryProvider)
          .setWishlist(cardId, next.contains(cardId)),
    );
  }
}

final collectionProvider =
    NotifierProvider<CollectionController, CollectionState>(
      CollectionController.new,
    );

final scanSessionProvider = FutureProvider.family<ScanSession, String?>((
  ref,
  path,
) {
  return ref.watch(scanRepositoryProvider).recognize(localImagePath: path);
});

class SocialFeedState {
  const SocialFeedState({
    this.posts = const [],
    this.homePostsCache = const [],
    this.unavailablePlatforms = const {},
    this.viewedPostIds = const {},
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.isHomeLoading = false,
    this.isFromCache = false,
    this.initialized = false,
    this.nextCursor,
    this.selectedIdolId,
    this.selectedPlatform,
    this.errorMessage,
    this.loadMoreError,
    this.newCount = 0,
  });

  final List<SocialFeedPost> posts;
  final List<SocialFeedPost> homePostsCache;
  final String? nextCursor;
  final String? selectedIdolId;
  final SocialPlatform? selectedPlatform;
  final Set<SocialPlatform> unavailablePlatforms;
  final Set<String> viewedPostIds;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool isHomeLoading;
  final bool isFromCache;
  final bool initialized;
  final String? errorMessage;
  final String? loadMoreError;
  final int newCount;

  bool get hasMore => nextCursor != null;

  List<SocialFeedPost> homePosts(String? primaryIdolId) {
    final result = [...(homePostsCache.isNotEmpty ? homePostsCache : posts)];
    result.sort((a, b) {
      final aPrimary = a.idolId == primaryIdolId ? 1 : 0;
      final bPrimary = b.idolId == primaryIdolId ? 1 : 0;
      if (aPrimary != bPrimary) return bPrimary.compareTo(aPrimary);
      return b.postedAt.compareTo(a.postedAt);
    });
    return result;
  }

  SocialFeedState copyWith({
    List<SocialFeedPost>? posts,
    List<SocialFeedPost>? homePostsCache,
    String? nextCursor,
    bool clearNextCursor = false,
    String? selectedIdolId,
    bool clearSelectedIdol = false,
    SocialPlatform? selectedPlatform,
    bool clearSelectedPlatform = false,
    Set<SocialPlatform>? unavailablePlatforms,
    Set<String>? viewedPostIds,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? isHomeLoading,
    bool? isFromCache,
    bool? initialized,
    String? errorMessage,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    int? newCount,
  }) => SocialFeedState(
    posts: posts ?? this.posts,
    homePostsCache: homePostsCache ?? this.homePostsCache,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    selectedIdolId: clearSelectedIdol
        ? null
        : (selectedIdolId ?? this.selectedIdolId),
    selectedPlatform: clearSelectedPlatform
        ? null
        : (selectedPlatform ?? this.selectedPlatform),
    unavailablePlatforms: unavailablePlatforms ?? this.unavailablePlatforms,
    viewedPostIds: viewedPostIds ?? this.viewedPostIds,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    isHomeLoading: isHomeLoading ?? this.isHomeLoading,
    isFromCache: isFromCache ?? this.isFromCache,
    initialized: initialized ?? this.initialized,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
    newCount: newCount ?? this.newCount,
  );
}

class SocialFeedController extends Notifier<SocialFeedState> {
  static const _pageSize = 20;

  @override
  SocialFeedState build() => const SocialFeedState();

  List<String> get _defaultFeedIdolIds {
    final favorites = ref.read(favoritesProvider).selectedIds.toList();
    if (favorites.isNotEmpty) return favorites;
    return DemoCatalog.groups.first.memberIds;
  }

  List<String> get _requestedIdolIds => state.selectedIdolId == null
      ? _defaultFeedIdolIds
      : [state.selectedIdolId!];

  Future<void> ensureLoaded() async {
    if (state.initialized || state.isInitialLoading) return;
    await _loadInitial();
  }

  Future<void> ensureHomeLoaded() async {
    if (state.homePostsCache.isNotEmpty || state.isHomeLoading) return;
    state = state.copyWith(isHomeLoading: true);
    try {
      final page = await ref
          .read(socialFeedRepositoryProvider)
          .fetchFeed(idolIds: _defaultFeedIdolIds, limit: _pageSize);
      final maySeedMainFeed =
          !state.initialized &&
          state.selectedIdolId == null &&
          state.selectedPlatform == null;
      ref.read(feedEngagementProvider.notifier).registerPosts(page.posts);
      state = state.copyWith(
        homePostsCache: page.posts,
        posts: maySeedMainFeed ? page.posts : null,
        nextCursor: maySeedMainFeed ? page.nextCursor : null,
        clearNextCursor: maySeedMainFeed && page.nextCursor == null,
        unavailablePlatforms: page.unavailablePlatforms,
        isFromCache: maySeedMainFeed ? page.isFromCache : null,
        isHomeLoading: false,
        initialized: maySeedMainFeed ? true : null,
        newCount: state.newCount == 0 ? page.newCount : null,
      );
    } catch (_) {
      state = state.copyWith(isHomeLoading: false);
    }
  }

  Future<void> selectIdol(String? idolId) async {
    if (state.selectedIdolId == idolId) return;
    state = state.copyWith(
      selectedIdolId: idolId,
      clearSelectedIdol: idolId == null,
      posts: const [],
      initialized: false,
      clearNextCursor: true,
      newCount: 0,
    );
    await _loadInitial();
  }

  Future<void> selectPlatform(SocialPlatform? platform) async {
    if (state.selectedPlatform == platform) return;
    state = state.copyWith(
      selectedPlatform: platform,
      clearSelectedPlatform: platform == null,
      posts: const [],
      initialized: false,
      clearNextCursor: true,
      newCount: 0,
    );
    await _loadInitial();
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(
      isInitialLoading: true,
      clearError: true,
      clearLoadMoreError: true,
    );
    try {
      final page = await ref
          .read(socialFeedRepositoryProvider)
          .fetchFeed(
            idolIds: _requestedIdolIds,
            platform: state.selectedPlatform,
            limit: _pageSize,
          );
      ref.read(feedEngagementProvider.notifier).registerPosts(page.posts);
      state = state.copyWith(
        posts: page.posts,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        unavailablePlatforms: page.unavailablePlatforms,
        isFromCache: page.isFromCache,
        isInitialLoading: false,
        initialized: true,
        newCount: page.newCount,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        isInitialLoading: false,
        initialized: true,
        isFromCache: state.posts.isNotEmpty,
        errorMessage: state.posts.isEmpty ? '动态暂时加载失败' : '部分动态可能不是最新',
      );
    }
  }

  Future<int?> refresh({bool exposeAsNew = false}) async {
    if (state.isRefreshing) return null;
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final result = await ref
          .read(socialFeedRepositoryProvider)
          .refreshFeed(
            idolIds: _requestedIdolIds,
            platform: state.selectedPlatform,
            limit: _pageSize,
          );
      ref
          .read(feedEngagementProvider.notifier)
          .registerPosts(result.page.posts);
      state = state.copyWith(
        posts: result.page.posts,
        nextCursor: result.page.nextCursor,
        clearNextCursor: result.page.nextCursor == null,
        unavailablePlatforms: result.page.unavailablePlatforms,
        isFromCache: result.page.isFromCache,
        isRefreshing: false,
        initialized: true,
        newCount: exposeAsNew ? result.newCount : 0,
        clearError: true,
      );
      return result.newCount;
    } catch (_) {
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: state.posts.isEmpty ? '动态暂时加载失败' : '部分动态可能不是最新',
        isFromCache: state.posts.isNotEmpty,
      );
      return null;
    }
  }

  Future<int?> refreshHome() async {
    if (state.isHomeLoading) return null;
    state = state.copyWith(isHomeLoading: true);
    try {
      final result = await ref
          .read(socialFeedRepositoryProvider)
          .refreshFeed(idolIds: _defaultFeedIdolIds, limit: _pageSize);
      final isMainFeed =
          state.selectedIdolId == null && state.selectedPlatform == null;
      ref
          .read(feedEngagementProvider.notifier)
          .registerPosts(result.page.posts);
      state = state.copyWith(
        homePostsCache: result.page.posts,
        posts: isMainFeed ? result.page.posts : null,
        nextCursor: isMainFeed ? result.page.nextCursor : null,
        clearNextCursor: isMainFeed && result.page.nextCursor == null,
        unavailablePlatforms: result.page.unavailablePlatforms,
        isFromCache: isMainFeed ? result.page.isFromCache : null,
        isHomeLoading: false,
        initialized: isMainFeed ? true : null,
        newCount: result.newCount,
      );
      return result.newCount;
    } catch (_) {
      state = state.copyWith(isHomeLoading: false);
      return null;
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isInitialLoading) return;
    final cursor = state.nextCursor;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    try {
      final page = await ref
          .read(socialFeedRepositoryProvider)
          .fetchFeed(
            idolIds: _requestedIdolIds,
            platform: state.selectedPlatform,
            cursor: cursor,
            limit: _pageSize,
          );
      final knownIds = state.posts.map((post) => post.id).toSet();
      ref.read(feedEngagementProvider.notifier).registerPosts(page.posts);
      state = state.copyWith(
        posts: [
          ...state.posts,
          ...page.posts.where((post) => !knownIds.contains(post.id)),
        ],
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        unavailablePlatforms: page.unavailablePlatforms,
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false, loadMoreError: '加载失败，点击重试');
    }
  }

  void markViewed(String postId) {
    state = state.copyWith(viewedPostIds: {...state.viewedPostIds, postId});
    _syncRemote(ref.read(userDataRepositoryProvider).markPostViewed(postId));
  }

  void markFeedOpened() {
    if (state.newCount != 0) state = state.copyWith(newCount: 0);
  }
}

final socialFeedProvider =
    NotifierProvider<SocialFeedController, SocialFeedState>(
      SocialFeedController.new,
    );

class FeedEngagementState {
  const FeedEngagementState({
    this.postsById = const {},
    this.likedPostIds = const {},
    this.commentsByPost = const {},
    this.likedCommentIds = const {},
    this.reportedCommentIds = const {},
  });

  final Map<String, SocialFeedPost> postsById;
  final Set<String> likedPostIds;
  final Map<String, List<FeedComment>> commentsByPost;
  final Set<String> likedCommentIds;
  final Set<String> reportedCommentIds;

  int likeCount(SocialFeedPost post) =>
      post.likeCount + (likedPostIds.contains(post.id) ? 1 : 0);

  int commentCount(SocialFeedPost post) =>
      post.commentCount +
      (commentsByPost[post.id]?.where((item) => item.isMine).length ?? 0);

  int commentLikeCount(FeedComment comment) =>
      comment.likeCount + (likedCommentIds.contains(comment.id) ? 1 : 0);

  FeedEngagementState copyWith({
    Map<String, SocialFeedPost>? postsById,
    Set<String>? likedPostIds,
    Map<String, List<FeedComment>>? commentsByPost,
    Set<String>? likedCommentIds,
    Set<String>? reportedCommentIds,
  }) => FeedEngagementState(
    postsById: postsById ?? this.postsById,
    likedPostIds: likedPostIds ?? this.likedPostIds,
    commentsByPost: commentsByPost ?? this.commentsByPost,
    likedCommentIds: likedCommentIds ?? this.likedCommentIds,
    reportedCommentIds: reportedCommentIds ?? this.reportedCommentIds,
  );
}

class FeedEngagementController extends Notifier<FeedEngagementState> {
  @override
  FeedEngagementState build() => const FeedEngagementState();

  void registerPosts(Iterable<SocialFeedPost> posts) {
    final next = {...state.postsById};
    var changed = false;
    for (final post in posts) {
      if (next[post.id] != post) {
        next[post.id] = post;
        changed = true;
      }
    }
    if (changed) state = state.copyWith(postsById: next);
  }

  void togglePostLike(String postId) {
    final next = {...state.likedPostIds};
    if (!next.add(postId)) next.remove(postId);
    state = state.copyWith(likedPostIds: next);
    _syncRemote(
      ref
          .read(userDataRepositoryProvider)
          .setPostLiked(postId, next.contains(postId)),
    );
  }

  void ensureDemoComments(String postId) {
    if (state.commentsByPost.containsKey(postId)) return;
    if (!useMockApi) {
      state = state.copyWith(
        commentsByPost: {...state.commentsByPost, postId: const []},
      );
      unawaited(_loadRemoteComments(postId));
      return;
    }
    final now = DateTime.now();
    final comments = [
      FeedComment(
        id: '$postId-comment-1',
        postId: postId,
        userId: 'fan-moon',
        userName: '月光收藏家',
        content: '今天的状态也太好了，已经开始期待正式舞台！',
        createdAt: now.subtract(const Duration(minutes: 36)),
        likeCount: 18,
      ),
      FeedComment(
        id: '$postId-comment-2',
        postId: postId,
        userId: 'fan-star',
        userName: '小行星',
        content: '造型和灯光的氛围感都很喜欢。',
        createdAt: now.subtract(const Duration(minutes: 18)),
        likeCount: 7,
      ),
      FeedComment(
        id: '$postId-comment-3',
        postId: postId,
        userId: 'fan-cloud',
        userName: '云端看台',
        content: '回复 月光收藏家：一起等正式公开！',
        createdAt: now.subtract(const Duration(minutes: 8)),
        parentId: '$postId-comment-1',
        replyToName: '月光收藏家',
        likeCount: 3,
      ),
    ];
    state = state.copyWith(
      commentsByPost: {...state.commentsByPost, postId: comments},
    );
  }

  void addComment(String postId, String content, {FeedComment? replyingTo}) {
    final text = content.trim();
    if (text.isEmpty) return;
    final existing = <FeedComment>[
      ...(state.commentsByPost[postId] ?? const <FeedComment>[]),
    ];
    final rootParentId = replyingTo == null
        ? null
        : (replyingTo.parentId ?? replyingTo.id);
    final pending = FeedComment(
      id: '$postId-mine-${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      userId: 'current-user',
      userName: ref.read(sessionProvider).displayName,
      content: text,
      createdAt: DateTime.now(),
      parentId: rootParentId,
      replyToName: replyingTo?.userName,
      isMine: true,
    );
    existing.add(pending);
    state = state.copyWith(
      commentsByPost: {...state.commentsByPost, postId: existing},
    );
    if (!useMockApi) {
      unawaited(_createRemoteComment(pending, replyingTo));
    }
  }

  void deleteComment(FeedComment comment) {
    if (!comment.isMine) return;
    final existing =
        <FeedComment>[
          ...(state.commentsByPost[comment.postId] ?? const <FeedComment>[]),
        ]..removeWhere(
          (item) => item.id == comment.id || item.parentId == comment.id,
        );
    state = state.copyWith(
      commentsByPost: {...state.commentsByPost, comment.postId: existing},
    );
    if (!useMockApi && !comment.id.contains('-mine-')) {
      _syncRemote(
        ref.read(userDataRepositoryProvider).deleteComment(comment.id),
      );
    }
  }

  void toggleCommentLike(String commentId) {
    final next = {...state.likedCommentIds};
    if (!next.add(commentId)) next.remove(commentId);
    state = state.copyWith(likedCommentIds: next);
    if (!useMockApi) {
      _syncRemote(
        ref
            .read(userDataRepositoryProvider)
            .setCommentLiked(commentId, next.contains(commentId)),
      );
    }
  }

  void reportComment(String commentId) {
    state = state.copyWith(
      reportedCommentIds: {...state.reportedCommentIds, commentId},
    );
    if (!useMockApi) {
      _syncRemote(
        ref.read(userDataRepositoryProvider).reportComment(commentId),
      );
    }
  }

  Future<void> _loadRemoteComments(String postId) async {
    try {
      final remote = await ref
          .read(userDataRepositoryProvider)
          .fetchComments(postId);
      final local = state.commentsByPost[postId] ?? const <FeedComment>[];
      final remoteIds = remote.map((item) => item.id).toSet();
      state = state.copyWith(
        commentsByPost: {
          ...state.commentsByPost,
          postId: [
            ...remote,
            ...local.where((item) => !remoteIds.contains(item.id)),
          ],
        },
      );
    } catch (_) {
      // Keep the empty/local state so the feed remains usable while offline.
    }
  }

  Future<void> _createRemoteComment(
    FeedComment pending,
    FeedComment? replyingTo,
  ) async {
    try {
      final created = await ref
          .read(userDataRepositoryProvider)
          .createComment(
            pending.postId,
            pending.content,
            parentId: replyingTo == null
                ? null
                : (replyingTo.parentId ?? replyingTo.id),
            replyToUserId: replyingTo?.userId,
          );
      final current = [
        ...(state.commentsByPost[pending.postId] ?? const <FeedComment>[]),
      ];
      final index = current.indexWhere((item) => item.id == pending.id);
      if (index == -1) {
        await ref.read(userDataRepositoryProvider).deleteComment(created.id);
        return;
      }
      current[index] = created;
      state = state.copyWith(
        commentsByPost: {...state.commentsByPost, pending.postId: current},
      );
    } catch (_) {
      // The optimistic comment remains visible and can be retried by resending.
    }
  }
}

final feedEngagementProvider =
    NotifierProvider<FeedEngagementController, FeedEngagementState>(
      FeedEngagementController.new,
    );

class IdolFeedNotificationSettings {
  const IdolFeedNotificationSettings({
    this.enabled = true,
    this.primaryIdolFirst = true,
    this.pushEnabled = false,
  });

  final bool enabled;
  final bool primaryIdolFirst;
  final bool pushEnabled;

  IdolFeedNotificationSettings copyWith({
    bool? enabled,
    bool? primaryIdolFirst,
    bool? pushEnabled,
  }) => IdolFeedNotificationSettings(
    enabled: enabled ?? this.enabled,
    primaryIdolFirst: primaryIdolFirst ?? this.primaryIdolFirst,
    pushEnabled: pushEnabled ?? this.pushEnabled,
  );
}

class IdolFeedNotificationController
    extends Notifier<IdolFeedNotificationSettings> {
  @override
  IdolFeedNotificationSettings build() => const IdolFeedNotificationSettings();

  void setEnabled(bool value) {
    state = state.copyWith(enabled: value);
    _syncSettings();
  }

  void setPrimaryIdolFirst(bool value) {
    state = state.copyWith(primaryIdolFirst: value);
    _syncSettings();
  }

  void setPushEnabled(bool value) {
    state = state.copyWith(pushEnabled: value);
    _syncSettings();
  }

  void _syncSettings() {
    _syncRemote(
      ref.read(userDataRepositoryProvider).setNotificationSettings({
        'enabled': state.enabled,
        'primary_idol_first': state.primaryIdolFirst,
        'push_enabled': state.pushEnabled,
      }),
    );
  }
}

final idolFeedNotificationProvider =
    NotifierProvider<
      IdolFeedNotificationController,
      IdolFeedNotificationSettings
    >(IdolFeedNotificationController.new);

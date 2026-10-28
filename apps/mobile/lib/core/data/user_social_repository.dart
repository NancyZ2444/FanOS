import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/profile_models.dart';

class FollowResult {
  const FollowResult({
    required this.status,
    required this.followersCount,
    required this.myFollowingCount,
    required this.myFollowersCount,
  });
  final UserRelationStatus status;
  final int followersCount;
  final int myFollowingCount;
  final int myFollowersCount;
}

abstract interface class UserSocialRepository {
  Future<List<PublicUserProfile>> search(String query);
  Future<List<PublicUserProfile>> relations(String userId, String type);
  Future<FollowResult> setFollow(String userId, bool following);
}

class ApiUserSocialRepository implements UserSocialRepository {
  ApiUserSocialRepository(this.client);
  final ApiClient client;

  List<PublicUserProfile> _items(dynamic data) =>
      ((data as Map)['items'] as List)
          .map(
            (item) => PublicUserProfile.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

  @override
  Future<List<PublicUserProfile>> search(String query) async =>
      _items(await client.getData('/users/search', query: {'q': query.trim()}));

  @override
  Future<List<PublicUserProfile>> relations(String userId, String type) async =>
      _items(await client.getData('/users/$userId/$type'));

  @override
  Future<FollowResult> setFollow(String userId, bool following) async {
    final dynamic result = following
        ? await client.putData('/users/$userId/follow')
        : await client.deleteData('/users/$userId/follow');
    return FollowResult(
      status: userRelationStatusFromJson(result['relation_status']),
      followersCount: (result['followers_count'] as num).toInt(),
      myFollowingCount: (result['my_following_count'] as num).toInt(),
      myFollowersCount: (result['my_followers_count'] as num).toInt(),
    );
  }
}

/// Used only with the explicit USE_MOCK_API build flag.
class MockUserSocialRepository implements UserSocialRepository {
  final _following = <String>{'user-luna'};
  final _followers = <String>{'user-luna', 'user-mint'};
  @override
  Future<List<PublicUserProfile>> search(String query) async => DemoUserProfiles
      .users
      .where(
        (user) =>
            user.displayName.toLowerCase().contains(query.trim().toLowerCase()),
      )
      .toList();

  @override
  Future<List<PublicUserProfile>> relations(String userId, String type) async =>
      DemoUserProfiles.users
          .where(
            (user) =>
                userId != 'current-user' ||
                (type == 'followers' ? _followers : _following).contains(
                  user.id,
                ),
          )
          .toList();

  @override
  Future<FollowResult> setFollow(String userId, bool following) async {
    following ? _following.add(userId) : _following.remove(userId);
    final profile = DemoUserProfiles.users.firstWhere(
      (user) => user.id == userId,
    );
    return FollowResult(
      status: following
          ? (_followers.contains(userId)
                ? UserRelationStatus.mutual
                : UserRelationStatus.following)
          : (_followers.contains(userId)
                ? UserRelationStatus.followsYou
                : UserRelationStatus.none),
      followersCount: profile.followersCount + (following ? 1 : 0),
      myFollowingCount: 127 + _following.length,
      myFollowersCount: 2356,
    );
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/data/user_social_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/search_page.dart';
import 'package:fan_os/features/profile/presentation/profile_support_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final fan = PublicUserProfile.fromJson({
  'id': 'actual-fan-user',
  'display_name': 'Fan OS 运营',
  'following_count': 2,
  'followers_count': 7,
  'relation_status': 'following',
});

class FakeSocial implements UserSocialRepository {
  final requests = <(String, bool)>[];
  String? searched;
  bool fail = false;
  Completer<FollowResult>? pending;
  @override
  Future<List<PublicUserProfile>> search(String query) async {
    searched = query;
    return [fan];
  }

  @override
  Future<List<PublicUserProfile>> relations(String userId, String type) async =>
      [fan];
  @override
  Future<FollowResult> setFollow(String userId, bool following) async {
    requests.add((userId, following));
    if (fail) throw const ApiException('NETWORK_ERROR', 'offline');
    return pending?.future ??
        Future.value(
          const FollowResult(
            status: UserRelationStatus.none,
            followersCount: 6,
            myFollowingCount: 3,
            myFollowersCount: 9,
          ),
        );
  }
}

void main() {
  test(
    'API repository uses real nickname endpoint and server follow totals',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: {
                  'code': 0,
                  'data': r.path.endsWith('/follow')
                      ? {
                          'relation_status': 'mutual',
                          'followers_count': 7,
                          'my_following_count': 3,
                          'my_followers_count': 9,
                        }
                      : {
                          'items': [
                            {
                              'id': 'actual-fan-user',
                              'display_name': 'Fan OS 运营',
                              'relation_status': 'following',
                            },
                          ],
                        },
                },
              ),
            );
          },
        ),
      );
      final repo = ApiUserSocialRepository(ApiClient(dio: dio));
      expect((await repo.search(' Fan ')).single.displayName, 'Fan OS 运营');
      expect(requests.last.path, '/users/search');
      expect(requests.last.queryParameters['q'], 'Fan');
      expect(
        (await repo.relations('person', 'followers')).single.relationStatus,
        UserRelationStatus.following,
      );
      expect(requests.last.path, '/users/person/followers');
      final result = await repo.setFollow('person', true);
      expect(result.myFollowingCount, 3);
      expect(result.myFollowersCount, 9);
      expect(result.followersCount, 7);
      expect(result.status, UserRelationStatus.mutual);
      expect(requests.last.method, 'PUT');
      await repo.setFollow('person', false);
      expect(requests.last.method, 'DELETE');
    },
  );

  test('failed follow preserves relationship and counts; success uses server totals', () async {
    final repo = FakeSocial()..fail = true;
    final container = ProviderContainer(
      overrides: [userSocialRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final controller = container.read(profileRelationshipProvider.notifier);
    controller.hydrateCounts(4, 9);
    await expectLater(
      controller.toggleFollow(fan.id, currentStatus: fan.relationStatus),
      throwsA(isA<ApiException>()),
    );
    var state = container.read(profileRelationshipProvider);
    expect(state.myFollowingCount, 4);
    expect(state.myFollowersCount, 9);
    expect(state.busyUserIds, isEmpty);
    expect(
      state.statusFor(fan.id, fallback: fan.relationStatus),
      UserRelationStatus.following,
    );
    repo.fail = false;
    await controller.toggleFollow(fan.id, currentStatus: fan.relationStatus);
    state = container.read(profileRelationshipProvider);
    expect(repo.requests.last, (fan.id, false));
    expect(state.myFollowingCount, 3);
    expect(state.myFollowersCount, 9);
    expect(state.followerCountFor(fan), 6);
    expect(state.statusFor(fan.id), UserRelationStatus.none);
  });

  test('duplicate taps send one mutation and disposed session ignores late response', () async {
    final repo = FakeSocial()..pending = Completer<FollowResult>();
    final container = ProviderContainer(
      overrides: [userSocialRepositoryProvider.overrideWithValue(repo)],
    );
    final controller = container.read(profileRelationshipProvider.notifier);
    final first = controller.toggleFollow(fan.id);
    await controller.toggleFollow(fan.id);
    expect(repo.requests, hasLength(1));
    container.dispose();
    repo.pending!.complete(
      const FollowResult(
        status: UserRelationStatus.following,
        followersCount: 8,
        myFollowingCount: 4,
        myFollowersCount: 9,
      ),
    );
    await first;
  });

  testWidgets(
    'user search displays real repository nickname instead of demo result',
    (tester) async {
      final repo = FakeSocial();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [userSocialRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const SearchPage(initialType: '用户'),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('catalog-search-input')),
        'Fan',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.searched, 'fan');
      expect(find.text('Fan OS 运营'), findsOneWidget);
      expect(find.text('月光收藏家'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('followers list loads actual profiles and relation status', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSocialRepositoryProvider.overrideWithValue(FakeSocial()),
        ],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const ProfileRelationsPage(
            userId: 'current-user',
            type: 'followers',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fan OS 运营'), findsOneWidget);
    expect(find.text('已关注'), findsOneWidget);
    expect(find.text('月光收藏家'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

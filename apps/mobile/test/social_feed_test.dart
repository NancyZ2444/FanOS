import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/config/feature_flags.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/core/data/social_feed_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feed/presentation/feed_page.dart';
import 'package:fan_os/features/feed/presentation/feed_post_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/notification/presentation/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mock feed supports 20-item pagination and isolated platform status',
    () async {
      final repository = MockSocialFeedRepository();
      final first = await repository.fetchFeed();
      final second = await repository.fetchFeed(cursor: first.nextCursor);
      final xPage = await repository.fetchFeed(platform: SocialPlatform.x);

      expect(first.posts, hasLength(20));
      expect(first.nextCursor, isNotNull);
      expect(second.posts, hasLength(14));
      expect(second.nextCursor, isNull);
      expect(
        first.posts.first.postedAt.isAfter(first.posts.last.postedAt),
        isTrue,
      );
      expect(
        xPage.posts.every((post) => post.platform == SocialPlatform.x),
        isTrue,
      );
      expect(xPage.unavailablePlatforms, contains(SocialPlatform.x));
      expect(xPage.isFromCache, isTrue);
    },
  );

  test(
    'feed state prioritizes primary idol only for home recommendations',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(socialFeedProvider.notifier);
      container.read(favoritesProvider.notifier).hydrate({
        'idol-aria',
        'idol-lin',
        'idol-mina',
        'idol-yuna',
      }, 'idol-aria');

      await controller.ensureHomeLoaded();
      var state = container.read(socialFeedProvider);
      expect(state.posts, hasLength(20));
      expect(state.newCount, 5);
      expect(
        state
            .homePosts('idol-aria')
            .take(3)
            .every((post) => post.idolId == 'idol-aria'),
        isTrue,
      );

      controller.markFeedOpened();
      expect(container.read(socialFeedProvider).newCount, 0);

      await controller.loadMore();
      state = container.read(socialFeedProvider);
      expect(state.posts, hasLength(23));
      expect(state.hasMore, isFalse);

      await controller.selectPlatform(SocialPlatform.x);
      state = container.read(socialFeedProvider);
      expect(
        state.posts.every((post) => post.platform == SocialPlatform.x),
        isTrue,
      );
      expect(state.isFromCache, isTrue);
      expect(
        state
            .homePosts('idol-aria')
            .take(3)
            .every((post) => post.idolId == 'idol-aria'),
        isTrue,
      );
    },
  );

  test('feed keeps cached posts when a refresh fails', () async {
    final container = ProviderContainer(
      overrides: [
        socialFeedRepositoryProvider.overrideWithValue(
          _RefreshFailingRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(socialFeedProvider.notifier);

    await controller.ensureLoaded();
    final refreshCount = await controller.refresh();
    final state = container.read(socialFeedProvider);

    expect(refreshCount, isNull);
    expect(state.posts, isNotEmpty);
    expect(state.isFromCache, isTrue);
    expect(state.errorMessage, '部分动态可能不是最新');
  });

  testWidgets('feed renders filters and records viewed state on expand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [idolFeedEnabledProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    container.read(favoritesProvider.notifier).hydrate({
      'idol-aria',
      'idol-lin',
      'idol-mina',
      'idol-yuna',
    }, 'idol-aria');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: FanOsTheme.light, home: const FeedPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();

    expect(find.text('本命动态'), findsOneWidget);
    expect(find.text('全部本命'), findsOneWidget);
    expect(find.text('全部平台'), findsOneWidget);
    expect(find.byKey(const Key('idol-feed-list')), findsOneWidget);
    expect(find.text('展开'), findsWidgets);

    final expand = find.text('展开').first;
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
    expect(
      container.read(socialFeedProvider).viewedPostIds,
      contains('feed-1'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification page controls idol feed notification settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [idolFeedEnabledProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(socialFeedProvider.notifier).ensureLoaded(),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const NotificationsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();

    expect(find.text('本命动态通知'), findsOneWidget);
    expect(find.text('本命有新动态'), findsOneWidget);
    expect(find.text('星标优先'), findsOneWidget);
    expect(find.text('接收 Push'), findsOneWidget);
    expect(find.textContaining('今天有 5 条新动态'), findsOneWidget);
    expect(find.byKey(const Key('compact-feed-notice')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('compact-feed-notice'))).height,
      lessThanOrEqualTo(48),
    );

    await tester.tap(find.text('本命有新动态'));
    await tester.pump();
    expect(container.read(idolFeedNotificationProvider).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('likes and comments stay synchronized by post id', () async {
    final repository = MockSocialFeedRepository();
    final post = (await repository.fetchFeed()).posts.first;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(feedEngagementProvider.notifier);

    controller.registerPosts([post]);
    controller.togglePostLike(post.id);
    controller.ensureDemoComments(post.id);
    final parent = container
        .read(feedEngagementProvider)
        .commentsByPost[post.id]!
        .first;
    controller.addComment(post.id, '新的站内评论', replyingTo: parent);

    final state = container.read(feedEngagementProvider);
    expect(state.likedPostIds, contains(post.id));
    expect(state.likeCount(post), post.likeCount + 1);
    expect(state.commentsByPost[post.id]!.last.parentId, parent.id);
    expect(state.commentsByPost[post.id]!.last.isMine, isTrue);
  });

  testWidgets('group and idol details expose social feed tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [idolFeedEnabledProvider.overrideWithValue(true)],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: GroupDetailPage(groupId: 'group-lumina'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(find.widgetWithText(Tab, '动态'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, '动态'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('全部平台'), findsOneWidget);
    expect(find.text('官方'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [idolFeedEnabledProvider.overrideWithValue(true)],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: IdolDetailPage(idolId: 'idol-aria'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));
    await tester.tap(find.widgetWithText(Tab, '动态'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('全部平台'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post detail supports publishing and replying to comments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final post = await tester.runAsync(
      () async => (await MockSocialFeedRepository().fetchFeed()).posts.first,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: FeedPostDetailPage(postId: post!.id, initialPost: post),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('feed-comment-input')),
      '期待新的舞台',
    );
    await tester.tap(find.byKey(const Key('send-feed-comment')));
    await tester.pump();

    expect(find.text('评论已发布'), findsOneWidget);
    expect(
      container
          .read(feedEngagementProvider)
          .commentsByPost[post.id]!
          .any((comment) => comment.content == '期待新的舞台'),
      isTrue,
    );
    expect(find.text('回复'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _RefreshFailingRepository implements SocialFeedRepository {
  final MockSocialFeedRepository _delegate = MockSocialFeedRepository();

  @override
  Future<SocialFeedPageData> fetchFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    String? cursor,
    int limit = 20,
  }) => _delegate.fetchFeed(
    idolIds: idolIds,
    platform: platform,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<SocialFeedRefreshData> refreshFeed({
    List<String>? idolIds,
    SocialPlatform? platform,
    int limit = 20,
  }) => Future.error(StateError('refresh unavailable'));
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/collection/presentation/collection_page.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guest prompts are horizontally centered', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const CollectionPage(),
        ),
      ),
    );

    expect(
      tester.getCenter(find.text('登录后建立你的收藏')).dx,
      moreOrLessEquals(187.5, epsilon: 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: FanOsTheme.light, home: const ProfilePage()),
      ),
    );

    expect(
      tester.getCenter(find.text('登录后创建个人主页')).dx,
      moreOrLessEquals(187.5, epsilon: 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile library defaults to gallery and remembers each tab view',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
          albumRepositoryProvider.overrideWithValue(MockAlbumRepository()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      container.read(favoritesProvider.notifier).hydrate({
        'idol-aria',
        'idol-lin',
      }, 'idol-aria');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(find.text('收藏'), findsNWidgets(2));
      expect(find.text('我的喜欢'), findsOneWidget);
      expect(find.text('卡册'), findsNWidgets(2));
      expect(find.text('照片'), findsOneWidget);
      expect(find.textContaining('Lv.12'), findsOneWidget);
      expect(find.byKey(const Key('favorite-idols-showcase')), findsOneWidget);
      expect(find.byKey(const Key('primary-idol-card')), findsOneWidget);
      expect(find.text('128 关注'), findsOneWidget);
      expect(find.text('2356 粉丝'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-gallery-collection')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('我的喜欢'));
      await tester.tap(find.text('我的喜欢'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-gallery-likes')),
        findsOneWidget,
      );

      final toggle = find.byKey(const Key('profile-view-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-list-likes')), findsOneWidget);

      await tester.tap(find.text('卡册').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlbumShelfBody), findsOneWidget);
      expect(find.text('我创建的'), findsOneWidget);
      expect(find.text('我收藏的'), findsOneWidget);

      await tester.tap(find.text('照片').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-gallery-photos')),
        findsOneWidget,
      );
      expect(find.text('添加图片'), findsOneWidget);

      await tester.tap(find.text('我的喜欢'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-list-likes')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collection shows favorites prominently above tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login(LoginMethod.phone);
    container.read(favoritesProvider.notifier).hydrate({
      'idol-aria',
      'idol-lin',
    }, 'idol-aria');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const CollectionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favorite-idols-showcase')), findsOneWidget);
    expect(find.byKey(const Key('primary-idol-card')), findsOneWidget);
    expect(find.text('Owned'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public profile respects privacy and supports back follow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const ProfilePage(userId: 'user-mint'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('薄荷汽水'), findsOneWidget);
    expect(find.text('回关'), findsOneWidget);
    expect(find.text('我的喜欢'), findsNothing);
    expect(find.text('相册'), findsNothing);

    await tester.tap(find.text('回关'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('互相关注'), findsOneWidget);
    expect(
      container.read(profileRelationshipProvider).followingIds,
      contains('user-mint'),
    );
    expect(tester.takeException(), isNull);
  });
}

class _InstantAuthRepository implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

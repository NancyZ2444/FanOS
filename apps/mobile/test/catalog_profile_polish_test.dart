import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/catalog/presentation/catalog_entity_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/onboarding/presentation/favorite_setup_page.dart';
import 'package:fan_os/features/profile/presentation/edit_profile_page.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _Catalog implements CatalogRepository {
  @override
  Future<CatalogBundle> fetchCatalog() async => CatalogBundle(
    groups: [
      FanGroup.fromJson({
        'id': 'g',
        'name': 'Stray Kids',
        'member_ids': ['a'],
        'debut_date': '2018-03-25',
      }),
    ],
    idols: [
      IdolProfile.fromJson({
        'id': 'a',
        'name': 'Bang Chan',
        'name_en': 'Bang Chan',
        'name_ko': '방찬',
        'name_translated': '方灿',
        'group_id': 'g',
      }),
    ],
    cards: [],
    albums: [
      CatalogAlbum.fromJson({
        'id': 'album',
        'name': 'SWITCH',
        'group_id': 'g',
        'artist_name': 'Stray Kids',
        'release_date': '2024-04-29',
        'versions': ['Digital'],
      }),
    ],
    events: [
      CatalogEvent.fromJson({
        'id': 'event',
        'name': '签售会',
        'group_id': 'g',
        'artist_name': 'Stray Kids',
        'event_type': 'Fansign',
        'start_date': '2026-10-13',
        'city': 'Seoul',
      }),
    ],
    others: [
      CatalogOther.fromJson({
        'id': 'other',
        'name': '品牌合作',
        'artist_name': 'Bang Chan',
        'artists': [
          {'type': 'idols', 'id': 'a'},
        ],
      }),
    ],
  );
}

void main() {
  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final type in CatalogEntityDetailType.values) {
    testWidgets('$type keeps related cards empty state and compact metadata', (
      tester,
    ) async {
      await size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [catalogRepositoryProvider.overrideWithValue(_Catalog())],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: CatalogEntityDetailPage(
              type: type,
              entityId: switch (type) {
                CatalogEntityDetailType.album => 'album',
                CatalogEntityDetailType.event => 'event',
                CatalogEntityDetailType.others => 'other',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('组合/艺人'), findsOneWidget);
      expect(find.text('活动类型'), findsNothing);
      expect(find.text('相关小卡'), findsOneWidget);
      expect(find.text('暂无相关小卡'), findsOneWidget);
      expect(
        tester.widget<FanArtwork>(find.byType(FanArtwork).first).fit,
        BoxFit.contain,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'group members prefer Chinese name with official name underneath',
    (tester) async {
      await size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [catalogRepositoryProvider.overrideWithValue(_Catalog())],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const GroupDetailPage(groupId: 'g'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('方灿'), findsOneWidget);
      expect(find.text('Bang Chan'), findsOneWidget);
      expect(tester.widget<Text>(find.text('当前成员 (1)')).style!.fontSize, 16);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logged-in favorites show starred then selected and top Save only',
    (tester) async {
      await size(tester);
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      final a = DemoCatalog.idols[0], b = DemoCatalog.idols[1];
      container.read(favoritesProvider.notifier).hydrate({a.id, b.id}, b.id);
      final router = GoRouter(
        initialLocation: '/favorites',
        routes: [
          GoRoute(
            path: '/favorites',
            builder: (_, _) => const FavoriteSetupPage(),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('saved')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('完成（'), findsNothing);
      expect(find.text('暂时跳过'), findsNothing);
      expect(
        tester.widgetList<IdolAvatar>(find.byType(IdolAvatar)).first.idol.id,
        b.id,
      );
      await tester.tap(find.text(a.displayName));
      await tester.tap(find.byKey(const Key('save-favorites')));
      await tester.pumpAndSettle();
      expect(container.read(favoritesProvider).selectedIds, {b.id});
      expect(find.text('saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile merges background into info and editor uses image overlays',
    (tester) async {
      await size(tester);
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      container
          .read(sessionProvider.notifier)
          .updateProfile(displayName: 'Fan OS 运营', bio: '');
      await container
          .read(sessionProvider.notifier)
          .saveProfileImage(
            'background',
            '/tmp/fan-os-qa-background-missing.png',
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我的空间'), findsNothing);
      expect(find.text('添加一句自我介绍'), findsNothing);
      expect(find.text('还没有填写简介'), findsOneWidget);
      expect(find.byType(ImageFiltered), findsNWidgets(2));
      expect(
        tester
            .getRect(find.byKey(const Key('profile-background')))
            .contains(tester.getCenter(find.text('Fan OS 运营'))),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const EditProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, '更换头像'), findsNothing);
      expect(find.widgetWithText(TextButton, '设置主页背景'), findsNothing);
      expect(find.byTooltip('更换头像'), findsOneWidget);
      expect(find.byTooltip('更换主页背景'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

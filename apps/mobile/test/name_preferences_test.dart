import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/name_preferences.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/onboarding/presentation/favorite_setup_page.dart';
import 'package:fan_os/features/profile/presentation/name_preferences_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
    'all name modes use official fallback and retain catalog identities',
    () {
      for (final mode in NameDisplayMode.values) {
        final names = NamePreferences(
          mode: mode,
          aliases: const {
            'groups': {'group-lumina': '我的团'},
            'idols': {'idol-aria': '小星星'},
          },
        );
        final data = names.apply(DemoCatalog.bundle);
        final group = data.groups.firstWhere((g) => g.id == 'group-lumina');
        final idol = data.idols.firstWhere((i) => i.id == 'idol-aria');
        expect(group.name, 'LUMINA');
        expect(idol.groupName, 'LUMINA');
        expect(group.displayName, switch (mode) {
          NameDisplayMode.official => 'LUMINA',
          NameDisplayMode.remark => '我的团',
          NameDisplayMode.combined => 'LUMINA（我的团）',
        });
        expect(idol.displayName, switch (mode) {
          NameDisplayMode.official => 'Aria',
          NameDisplayMode.remark => '小星星',
          NameDisplayMode.combined => 'Aria（小星星）',
        });
        expect(
          data.idols.firstWhere((i) => i.id == 'idol-lin').displayName,
          'Lin',
        );
        expect(names.display('idols', 'missing', 'Official'), 'Official');
      }
    },
  );

  test('favorite highlight is explicit, optional, and removable', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final favorites = container.read(favoritesProvider.notifier);
    favorites.hydrate({'idol-aria', 'idol-lin'}, null);
    expect(container.read(favoritesProvider).primaryId, isNull);
    favorites.setPrimary('idol-lin');
    expect(container.read(favoritesProvider).primaryId, 'idol-lin');
    favorites.setPrimary('idol-lin');
    expect(container.read(favoritesProvider).primaryId, isNull);
    favorites.setPrimary('idol-aria');
    favorites.toggle('idol-aria');
    expect(container.read(favoritesProvider).selectedIds, {'idol-lin'});
    expect(container.read(favoritesProvider).primaryId, isNull);
    await favorites.saveSelection({'idol-lin'}, null);
    expect(container.read(favoritesProvider).primaryId, isNull);
  });

  testWidgets('star toggles separately from selection and saves no highlight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
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
    await tester.tap(find.text('Aria'));
    await tester.pump();
    expect(find.text('完成（已选 1）'), findsOneWidget);
    final star = find.byKey(const ValueKey('favorite-star-idol-aria'));
    await tester.tap(star);
    await tester.pump();
    expect(find.byTooltip('取消星标'), findsOneWidget);
    await tester.tap(star);
    await tester.pump();
    expect(find.byTooltip('取消星标'), findsNothing);
    expect(find.textContaining('主本命'), findsNothing);
    await tester.tap(find.text('完成（已选 1）'));
    await tester.pumpAndSettle();
    expect(container.read(favoritesProvider).selectedIds, {'idol-aria'});
    expect(container.read(favoritesProvider).primaryId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remark editor saves, changes display mode, and safely clears', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(sessionProvider.notifier).login(LoginMethod.phone),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const NamePreferencesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('name-remark-group-lumina'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-remark-input')), '我的团');
    await tester.tap(find.byKey(const Key('name-remark-save')));
    await tester.pumpAndSettle();
    await container
        .read(namePreferencesProvider.notifier)
        .setMode(NameDisplayMode.remark);
    await tester.pumpAndSettle();
    expect(
      (await container.read(catalogProvider.future)).groups.first.displayName,
      '我的团',
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-remark-input')), '');
    await tester.tap(find.byKey(const Key('name-remark-save')));
    await tester.pumpAndSettle();
    expect(
      (await container.read(catalogProvider.future)).groups.first.displayName,
      'LUMINA',
    );
    expect(tester.takeException(), isNull);
  });

  test('online event uses platform rather than city', () {
    final event = CatalogEvent.fromJson({
      'id': 'event',
      'name': 'Live',
      'is_online': true,
      'platform': 'Weverse',
      'city': 'Seoul',
    });
    expect(event.locationLabel, 'Weverse');
  });
}

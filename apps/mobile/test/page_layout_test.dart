import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/search_page.dart';
import 'package:fan_os/features/daily_card/presentation/daily_card_page.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:fan_os/features/onboarding/presentation/privacy_page.dart';
import 'package:fan_os/features/scan/presentation/scan_page.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('home page has no phone-sized layout overflow', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: FanOsTheme.light, home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('daily card page has no phone-sized layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const DailyCardPage(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog and search have no phone-sized layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: FanOsTheme.light, home: const CatalogPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: FanOsTheme.light, home: const SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog detail pages fit a short phone', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final page in <Widget>[
      const GroupDetailPage(groupId: 'group-lumina'),
      const IdolDetailPage(idolId: 'idol-aria'),
      const CardDetailPage(cardId: 'card-aria-01'),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: FanOsTheme.light, home: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('scan page has no phone-sized layout overflow', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: FanOsTheme.light, home: const ScanPage()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows a compact add-favorite prompt when no idol is set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final favorites = container.read(favoritesProvider);
    for (final id in favorites.selectedIds.toList()) {
      container.read(favoritesProvider.notifier).toggle(id);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: FanOsTheme.light, home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有设置本命'), findsOneWidget);
    expect(find.text('添加本命'), findsOneWidget);
    expect(find.byKey(const Key('empty-favorites-prompt')), findsOneWidget);
    expect(find.byKey(const Key('home-feed-favorite-hint')), findsNothing);
    expect(find.textContaining('本命动态'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy consent action stays visible on a short phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: FanOsTheme.light, home: const PrivacyPage()),
    );
    await tester.pump();

    final action = find.byKey(const Key('privacy-agree-continue'));
    expect(action, findsOneWidget);
    expect(find.text('请先勾选协议'), findsOneWidget);
    expect(tester.getBottomRight(action).dy, lessThan(667));
    expect(tester.getSize(action).width, greaterThan(320));

    await tester.tap(find.byKey(const Key('privacy-agreement-checkbox')));
    await tester.pump();
    expect(find.text('同意并继续'), findsOneWidget);
    expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

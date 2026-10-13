import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/catalog/presentation/card_gallery_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_entity_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget home) => ProviderScope(
    child: MaterialApp(theme: FanOsTheme.light, home: home),
  );

  testWidgets('catalog home exposes all Phase 1 discovery categories', (
    tester,
  ) async {
    setPhoneSize(tester);
    await tester.pumpWidget(app(const CatalogPage()));
    await tester.pumpAndSettle();

    for (final category in ['组合', '艺人', '专辑', '活动', '小卡', '其他来源']) {
      expect(
        find.byKey(ValueKey('catalog-category-$category')),
        findsOneWidget,
      );
      final categoryRect = tester.getRect(
        find.byKey(ValueKey('catalog-category-$category')),
      );
      expect(categoryRect.height, lessThanOrEqualTo(76));
      expect(
        categoryRect.top,
        tester.getRect(find.byKey(const ValueKey('catalog-category-组合'))).top,
      );
    }
    expect(find.text('✦  最近更新'), findsOneWidget);
    expect(find.text('✦  热门组合'), findsOneWidget);
    expect(find.text('✦  全部组合'), findsOneWidget);
    expect(find.text('✦  我的本命'), findsNothing);
    expect(find.byTooltip('搜索'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog search debounces and returns cross-entity results', (
    tester,
  ) async {
    setPhoneSize(tester);
    await tester.pumpWidget(app(const SearchPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('catalog-search-input')),
      'Starlit',
    );
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump();

    expect(find.text('专辑'), findsWidgets);
    expect(find.text('Starlit'), findsWidgets);
    expect(find.text('小卡'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card gallery supports scoped and owned shortcuts', (
    tester,
  ) async {
    setPhoneSize(tester);
    await tester.pumpWidget(
      app(const CardGalleryPage(groupId: 'group-lumina')),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 张小卡'), findsOneWidget);
    expect(find.byKey(const Key('card-gallery-grid')), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-filter-owned')));
    await tester.pumpAndSettle();
    expect(find.text('1 张小卡'), findsOneWidget);
    expect(find.text('已拥有'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idol and album details expose cards and source metadata', (
    tester,
  ) async {
    setPhoneSize(tester);
    await tester.pumpWidget(app(const IdolDetailPage(idolId: 'idol-aria')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Tab, '小卡'), findsOneWidget);
    expect(find.text('2 张'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app(
        const CatalogEntityDetailPage(
          type: CatalogEntityDetailType.album,
          entityId: 'album-starlit',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Starlit'), findsWidgets);
    expect(find.text('Moon Ver.'), findsWidgets);
    expect(find.text('相关小卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'catalog error preserves search and categories, retries at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _Catalog()..fail = true;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
            child: MaterialApp(
              theme: FanOsTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const CatalogPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('搜索艺人、组合或小卡'), findsOneWidget);
        expect(find.byKey(const Key('catalog-category-艺人')), findsOneWidget);
        expect(find.text('内容暂时未能加载'), findsOneWidget);
        expect(tester.takeException(), isNull);
        repo.fail = false;
        await tester.tap(find.text('重新加载').first);
        await tester.pumpAndSettle();
        expect(repo.calls, 2);
        expect(find.text('暂时没有更新'), findsOneWidget);
        expect(find.text('暂无组合内容'), findsOneWidget);
        expect(find.text('清空筛选'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('guest home has an actionable empty artist state', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(_Catalog())],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).continueAsGuest();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: FanOsTheme.light, home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时没有推荐艺人'), findsOneWidget);
    expect(find.text('逛逛图鉴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Catalog implements CatalogRepository {
  bool fail = false;
  int calls = 0;
  @override
  Future<CatalogBundle> fetchCatalog() async {
    calls++;
    if (fail) throw StateError('Offline');
    return const CatalogBundle(idols: [], groups: [], cards: []);
  }
}

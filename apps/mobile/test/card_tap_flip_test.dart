import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Catalog implements CatalogRepository {
  _Catalog(this.hasBack);
  final bool hasBack;
  @override
  Future<CatalogBundle> fetchCatalog() async => CatalogBundle(
    cards: [
      CollectibleCard.fromJson({
        'id': 'flip-card',
        'title': 'Legacy identifier',
        'source': '测试专辑',
        'idol_name': '测试艺人',
        'group_name': '测试组合',
        'card_type': 'Regular',
        'version': '',
        'release_date': '',
        'region': '',
        if (hasBack) 'back_image_url': 'https://example.test/back.jpg',
      }),
    ],
    idols: [],
    groups: [],
    albums: [],
  );
}

void main() {
  for (final hasBack in [false, true]) {
    testWidgets('card tap flips only when back exists: $hasBack', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWithValue(_Catalog(hasBack)),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const CardDetailPage(cardId: 'flip-card'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder face(String text) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == text,
      );
      const front = '小卡正面，轻点查看背面';
      const back = '小卡背面，轻点翻回正面';
      expect(find.text('正面'), findsNothing);
      expect(find.text('背面'), findsNothing);
      expect(face(front), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('card-large-preview')));
      await tester.pumpAndSettle();
      expect(face(hasBack ? back : front), findsOneWidget);
      if (hasBack) {
        await tester.tap(find.byKey(const ValueKey('card-large-preview')));
        await tester.pumpAndSettle();
        expect(face(front), findsOneWidget);
      } else {
        expect(find.text('暂无卡背信息'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

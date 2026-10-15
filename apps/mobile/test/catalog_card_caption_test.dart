import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_list_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CollectibleCard fixture({bool group = false, List<String>? idolIds}) =>
    CollectibleCard.fromJson({
      'id': 'card',
      'title': '',
      'idol_id': 'idol-aria',
      'idol_name': 'Aria',
      'group_id': 'group-lumina',
      'group_name': 'LUMINA',
      'source': 'Starlit',
      'version': 'Moon Ver.',
      'card_type': 'POB',
      'region': 'Korea',
      'release_date': '',
      'is_group_pc': group,
      'idol_ids': idolIds,
      'tag_details': [
        {'id': 'tag', 'name': '不能遮住版本', 'entity_type': 'CARD'},
      ],
    });

void main() {
  test('card captions use official album and version relationships', () {
    final card = CollectibleCard.fromJson({
      'id': 'c',
      'title': '',
      'idol_id': 'a',
      'idol_name': 'Aria',
      'group_name': 'G',
      'source': 'Old Name',
      'version': 'Old Version',
      'card_type': 'POB',
      'release_date': '',
      'region': '',
      'source_entity_type': 'ALBUM',
      'source_entity_id': 'album',
      'entity_version_id': 'version',
    });
    final catalog = CatalogBundle(
      groups: [],
      idols: [],
      cards: [card],
      albums: [
        CatalogAlbum.fromJson({
          'id': 'album',
          'name': 'Album',
          'name_en': 'Current Album',
          'entity_versions': [
            {'id': 'version', 'name': 'Current Version'},
          ],
        }),
      ],
    );
    expect(catalog.cardSourceLabel(card), 'Current Album');
    expect(catalog.cardVersionLabel(card), 'Current Version');
    expect(
      DemoCatalog.bundle.cardSourceLabel(DemoCatalog.cards.first),
      'Starlit',
    );
  });

  Widget tile(CollectibleCard card, CardTileCaption caption) => ProviderScope(
    child: MaterialApp(
      theme: FanOsTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 110,
            child: CollectibleCardTile(
              card: card,
              compact: true,
              caption: caption,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('idol cards show album and version even when tags exist', (
    tester,
  ) async {
    await tester.pumpWidget(tile(fixture(), CardTileCaption.idol));
    expect(find.text('Starlit'), findsOneWidget);
    expect(find.text('Moon Ver.'), findsOneWidget);
    expect(find.text('Aria'), findsNothing);
    expect(find.text('不能遮住版本'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('individual group cards show artist and album', (tester) async {
    await tester.pumpWidget(tile(fixture(), CardTileCaption.group));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('艾莉娅'), findsOneWidget);
    expect(find.text('Starlit'), findsOneWidget);
    expect(find.text('Moon Ver.'), findsNothing);
  });

  testWidgets('group and multi-person cards never show a single artist label', (
    tester,
  ) async {
    for (final card in [
      fixture(group: true),
      fixture(idolIds: ['a', 'b']),
    ]) {
      await tester.pumpWidget(tile(card, CardTileCaption.group));
      expect(find.text('Aria'), findsNothing);
      expect(find.text('Starlit'), findsOneWidget);
      expect(find.text('不能遮住版本'), findsNothing);
    }
  });

  testWidgets('caption mode is wired to each detail tab', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const IdolDetailPage(idolId: 'idol-aria'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CollectibleCardTile>(find.byType(CollectibleCardTile))
          .every((tile) => tile.caption == CardTileCaption.idol),
      isTrue,
    );
    expect(find.byType(CollectibleCardTile), findsWidgets);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const GroupDetailPage(groupId: 'group-lumina'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '小卡'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectibleCardTile), findsWidgets);
    expect(
      tester
          .widgetList<CollectibleCardTile>(find.byType(CollectibleCardTile))
          .every((tile) => tile.caption == CardTileCaption.group),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'all group stats remain visible with long company name at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bundle = CatalogBundle(
          groups: [
            FanGroup.fromJson({
              'id': 'group-lumina',
              'name': 'SEVENTEEN',
              'name_ko': '세븐틴',
              'company': 'PLEDIS Entertainment Company With A Long Name',
              'member_ids': List.generate(13, (i) => 'id-$i'),
            }),
          ],
          idols: DemoCatalog.idols,
          albums: DemoCatalog.albums,
          cards: DemoCatalog.cards,
        );
        Widget page(Widget home) => ProviderScope(
          overrides: [catalogProvider.overrideWith((ref) async => bundle)],
          child: MaterialApp(theme: FanOsTheme.light, home: home),
        );
        await tester.pumpWidget(page(const CatalogPage()));
        await tester.pumpAndSettle();
        const statsKey = ValueKey('group-stats-group-lumina');
        await tester.ensureVisible(find.byKey(statsKey));
        await tester.pumpAndSettle();
        expect(find.text('13 位成员 · 2 张专辑 · 3 张小卡'), findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(statsKey),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          tester.getRect(find.byKey(statsKey)).bottom,
          lessThanOrEqualTo(844),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          page(const CatalogListPage(type: CatalogListType.groups)),
        );
        await tester.pumpAndSettle();
        expect(find.text('13 位成员 · 2 张专辑 · 3 张小卡'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

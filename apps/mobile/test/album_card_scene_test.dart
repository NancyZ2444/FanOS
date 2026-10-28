import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/presentation/album_card_scene.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PhotocardAlbum sceneAlbum({int count = 5}) => PhotocardAlbum({
  'id': 'scene-test',
  'name': '月光收藏',
  'is_owner': true,
  'description': '第一次收藏，记住心动的瞬间。',
  'pages': [
    {
      'id': 'page',
      'slots': List.generate(count, (i) => {'id': 's$i', 'card_id': 'c$i'}),
    },
  ],
  'card_view': {
    'default_mode': 'CARDS',
    'featured_slot_id': 's2',
    'cover_style': 'STACK_V1',
    'background': albumBackground(),
    'display_fields': ['idol', 'source'],
  },
  'cards': {
    for (int i = 0; i < count; i++)
      'c$i': {
        'id': 'c$i',
        'title': '收藏 $i',
        'idol_id': 'idol',
        'idol_name': 'MIRA',
        'group_name': 'LUNE',
        'group_id': 'group',
        'source': 'ECLIPSE',
        'card_type': 'Album Card',
        'version': 'Regular',
        'release_date': '2026-10-14',
        'region': 'Korea',
        'color_start': 0xFFA598D1,
        'color_end': 0xFF8274B2,
        if (i == 2) 'back_image_url': 'test-back',
      },
  },
});

void main() {
  testWidgets('album name choice affects both actors without storing remarks', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(namePreferencesProvider.notifier)
        .setRemark('idols', 'idol', '小星星');
    await container
        .read(namePreferencesProvider.notifier)
        .setRemark('groups', 'group', '我的团');
    for (final entry in {
      'remark': '小星星 · 我的团',
      'official': 'MIRA · LUNE',
      'combined': 'MIRA（小星星） · LUNE（我的团）',
    }.entries) {
      final album = sceneAlbum().edit((d) {
        (d['card_view'] as AlbumJson)['name_display_mode'] = entry.key;
        (d['card_view'] as AlbumJson)['display_fields'] = ['idol', 'group'];
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: AlbumViewer(
              key: ValueKey(entry.key),
              album: album,
              preview: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(album.json.toString(), isNot(contains('小星星')));
      expect(tester.takeException(), isNull);
    }
  });
  test('cover is deterministic, featured first, at most five actual slots', () {
    final album = sceneAlbum(count: 8);
    expect(album.coverSlots.map((s) => s['id']), [
      's2',
      's0',
      's1',
      's3',
      's4',
    ]);
    final edited = album.edit((d) {
      (d['card_view'] as AlbumJson).addAll({
        'order_customized': true,
        'card_order': album.orderedSlotIds.reversed.toList(),
      });
    });
    expect(edited.coverSlots.map((s) => s['id']), [
      's2',
      's7',
      's6',
      's5',
      's4',
    ]);
    expect(PhotocardAlbum(edited.json).coverSlots, edited.coverSlots);
    final removed = edited.edit(
      (d) => (d['pages'] as List)[0]['slots'][2]['card_id'] = null,
    );
    expect(removed.featuredSlotId, 's7');
    expect(sceneAlbum(count: 1).coverSlots.length, 1);
    expect(sceneAlbum(count: 0).coverSlots, isEmpty);
    final summary = PhotocardAlbum({
      'id': 'shelf',
      'cover_slots': edited.coverSlots,
      'cards': edited.json['cards'],
      'card_view': edited.cardView,
    });
    expect(summary.coverSlots, edited.coverSlots);
  });

  test('legacy handmade covers survive automatic cover upgrade', () {
    final album = sceneAlbum().edit((d) {
      (d['card_view'] as AlbumJson).remove('cover_style');
      d['cover'] = {
        'elements': [
          {'type': 'TEXT', 'content': '保留自定义'},
        ],
      };
    });
    expect(album.usesStackCover, isFalse);
    expect(
      album
          .edit(
            (d) => (d['card_view'] as AlbumJson)['cover_style'] = 'STACK_V1',
          )
          .usesStackCover,
      isTrue,
    );
  });

  Future<void> show(
    WidgetTester tester,
    PhotocardAlbum album, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          albumRepositoryProvider.overrideWithValue(MockAlbumRepository()),
        ],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: AlbumViewer(album: album, preview: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'extract any card, tap flip, next resets front, collapse keeps position',
    (tester) async {
      await show(tester, sceneAlbum());
      expect(find.text('03 / 05'), findsOneWidget);
      expect(find.text('正面'), findsNothing);
      expect(find.text('背面'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('album-scene-card-s2')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭放大'), findsOneWidget);
      final cardBounds = tester.getRect(
        find.byKey(const ValueKey('album-scene-card-s2')),
      );
      expect(cardBounds.center.dx, closeTo(195, 1));
      await tester.tap(find.byKey(const ValueKey('album-scene-card-s2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AlbumCardImage>(
              find.descendant(
                of: find.byKey(const ValueKey('album-scene-card-s2')),
                matching: find.byType(AlbumCardImage),
              ),
            )
            .back,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('album-card-next')));
      await tester.pumpAndSettle();
      expect(find.text('04 / 05'), findsOneWidget);
      expect(
        tester
            .widget<AlbumCardImage>(
              find.descendant(
                of: find.byKey(const ValueKey('album-scene-card-s3')),
                matching: find.byType(AlbumCardImage),
              ),
            )
            .back,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('album-scene-card-s3')));
      await tester.pumpAndSettle();
      expect(find.text('暂无背面图片'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭放大'));
      await tester.pumpAndSettle();
      expect(find.text('04 / 05'), findsOneWidget);
      expect(find.byType(AlbumCardScene), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('swipe snaps, small screens and landscape do not overflow', (
    tester,
  ) async {
    for (final size in [const Size(320, 568), const Size(667, 375)]) {
      await show(tester, sceneAlbum(), size: size);
      await tester.drag(
        find.byKey(const Key('album-card-stage')),
        const Offset(-85, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scene = tester.state<AlbumCardSceneState>(
        find.byType(AlbumCardScene),
      );
      final active = find.byKey(
        ValueKey(
          size.width < 400 ? 'album-scene-card-s3' : 'album-scene-card-s2',
        ),
      );
      await tester.tap(active);
      await tester.pumpAndSettle();
      expect(scene.expanded, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭放大'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('0/1/5-card covers render only actual fronts', (tester) async {
    for (final count in [0, 1, 5]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 180,
              height: 240,
              child: AlbumStackCover(album: sceneAlbum(count: count)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlbumCardImage), findsNWidgets(count));
      expect(
        tester
            .widgetList<AlbumCardImage>(find.byType(AlbumCardImage))
            .every((w) => !w.back && w.thumbnail),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'card preview keeps the story reachable without duplicate instructions',
    (tester) async {
      final album = sceneAlbum().edit((data) {
        data['description'] = List.generate(
          20,
          (i) => '第 ${i + 1} 段真实收藏故事。',
        ).join('\n');
      });
      await show(tester, album, size: const Size(360, 640));
      expect(find.text('收藏故事'), findsNothing);
      expect(find.text('查看官方图鉴详情'), findsNothing);
      expect(find.textContaining('左右滑动浏览'), findsNothing);
      expect(find.byKey(const Key('album-pocket-page')), findsNothing);
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('album-scene-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final story = tester.getRect(find.byKey(const Key('album-scene-story')));
      final viewport = tester.getRect(
        find.byKey(const Key('album-scene-scroll')),
      );
      expect(story.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(tester.takeException(), isNull);
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('album-scene-card-s2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('轻点小卡翻面'), findsNothing);
      expect(find.text('查看官方图鉴详情'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

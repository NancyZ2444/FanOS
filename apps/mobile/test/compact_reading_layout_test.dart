import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/presentation/album_card_scene.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_profile_tab.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'album_card_scene_test.dart' show sceneAlbum;

class _Feedback extends FeedbackRepository {
  _Feedback({this.imageUrl}) : super(ApiClient());
  final String? imageUrl;

  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async => {
    'id': 'layout-test',
    'kind': 'CORRECTION',
    'entity_type': 'groups',
    'entity_id': 'group',
    'name': 'IVE',
    'status_label': '待处理',
    'created_at': '2026-10-28T12:00:00',
    'updated_at': '2026-10-28T12:00:00',
    'image_url': imageUrl,
    'submission': {
      'fields': [
        {'label': '简介', 'current': '', 'suggested': '测试资料'},
      ],
    },
  };
}

void main() {
  Future<void> size(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('profile timestamp and actions share one row at $width', (
      tester,
    ) async {
      await size(tester, width);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProfileProvider('groups/test').overrideWith(
              (ref) async => {
                'published_at': '2026-10-22T15:37:58',
                'fields': <FeedbackJson>[],
              },
            ),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const Scaffold(
              body: CatalogProfileTab(kind: 'groups', entityId: 'test'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final updated = tester.getRect(find.textContaining('更新于'));
      final feedback = tester.getRect(find.text('资料反馈'));
      final history = tester.getRect(find.byTooltip('修订历史'));
      expect(updated.center.dy, closeTo(feedback.center.dy, 1));
      expect(updated.center.dy, closeTo(history.center.dy, 1));
      expect(
        tester.getSize(find.byKey(const Key('catalog-profile-toolbar'))).height,
        lessThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'card preview fills available space with full-safe-area gradient $width',
      (tester) async {
        await size(tester, width);
        final album = sceneAlbum().edit((data) {
          data['description'] = '';
          (data['card_view'] as AlbumJson)['background'] = {
            'type': 'GRADIENT',
            'colors': ['#D9D2FF', '#F5DCE4'],
            'angle': 90,
          };
        });
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: FanOsTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: const EdgeInsets.only(top: 59, bottom: 34)),
                child: child!,
              ),
              home: AlbumViewer(album: album),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final background = find.byKey(const Key('album-viewer-background'));
        expect(tester.getRect(background), Rect.fromLTWH(0, 0, width, 844));
        expect(
          (tester.widget<DecoratedBox>(background).decoration as BoxDecoration)
              .gradient,
          isNotNull,
        );
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          Colors.transparent,
        );
        for (final expanded in [false, true]) {
          if (expanded) {
            await tester.tap(find.byKey(const ValueKey('album-scene-card-s2')));
            await tester.pumpAndSettle();
          }
          final viewport = tester.getRect(
            find.byKey(const Key('album-scene-scroll')),
          );
          final metadata = tester.getRect(find.text('MIRA · ECLIPSE'));
          expect(viewport.bottom - metadata.bottom, inInclusiveRange(16, 48));
          final card = tester.getRect(
            find.byKey(const ValueKey('album-scene-card-s2')),
          );
          final stage = tester.getRect(
            find.byKey(const Key('album-card-stage')),
          );
          expect(stage.contains(card.topLeft), isTrue);
          expect(stage.contains(card.bottomRight), isTrue);
          expect(
            tester
                .state<AlbumCardSceneState>(find.byType(AlbumCardScene))
                .expanded,
            expanded,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final imageUrl in [null, 'https://example.invalid/missing-cover.png']) {
    testWidgets('correction reserves no target cover space: $imageUrl', (
      tester,
    ) async {
      await size(tester, 390);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedbackRepositoryProvider.overrideWithValue(
              _Feedback(imageUrl: imageUrl),
            ),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const FeedbackDetailPage(id: 'layout-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // FanEntityName resolves the catalog asynchronously after the record loads.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackMedia), findsNothing);
      final entity = tester.getRect(find.text('IVE'));
      final note = tester.getRect(find.text('已收到反馈，等待平台核实。'));
      expect(note.top - entity.bottom, closeTo(16, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('feedback front and back keep the same fixed card ratio', (
    tester,
  ) async {
    await size(tester, 390);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: const [
              FeedbackMedia(null, key: Key('front'), width: 140),
              FeedbackMedia(
                '/missing-landscape-photo.jpg',
                key: Key('back'),
                width: 140,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final front = tester.getSize(find.byKey(const Key('front')));
    final back = tester.getSize(find.byKey(const Key('back')));
    expect(front, back);
    expect(front.width / front.height, closeTo(55 / 85, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'album navigation remains legible on dark and light backgrounds',
    (tester) async {
      await size(tester, 390);
      for (final dark in [true, false]) {
        final album = sceneAlbum().edit((data) {
          (data['card_view'] as AlbumJson)['background'] = {
            'type': 'SOLID',
            'colors': [dark ? '#151C32' : '#F7F8FC'],
          };
        });
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: FanOsTheme.light,
              home: AlbumViewer(key: ValueKey(dark), album: album),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<AppBar>(find.byType(AppBar));
        expect(bar.foregroundColor, dark ? Colors.white : FanColors.ink);
        expect(bar.titleTextStyle!.color, bar.foregroundColor);
        expect(
          bar.systemOverlayStyle,
          dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        );
        final edit = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '编辑'),
        );
        expect(edit.style!.foregroundColor!.resolve({}), bar.foregroundColor);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

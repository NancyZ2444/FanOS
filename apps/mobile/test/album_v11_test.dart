import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/presentation/album_example_page.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ReadOnlyExamples extends MockAlbumRepository {
  int creates = 0;
  @override
  Future<PhotocardAlbum> create(
    String name,
    String display,
    String style, {
    String mode = 'BOOK',
    String description = '',
    String? requestId,
  }) {
    creates++;
    throw StateError('Examples must not create a work');
  }

  @override
  Future<List<AlbumJson>> resources() async => [];
}

void main() {
  test('card instances retain duplicate placements, order and main card without pages', () {
    final json = <String, dynamic>{
      'work_mode': 'CARDS',
      'pages': [],
      'card_instances': [
        {'id': 'a', 'card_id': 'one'},
        {'id': 'b', 'card_id': 'one'},
      ],
      'card_view': {
        'card_order': ['b', 'a'],
        'order_customized': true,
        'featured_slot_id': 'b',
      },
    };
    synchronizeAlbum(json);
    final work = PhotocardAlbum(json);
    expect(work.orderedSlotIds, ['b', 'a']);
    expect(work.featuredSlotId, 'b');
    expect(work.patch.containsKey('pages'), false);
    expect(work.patch.containsKey('cover'), false);
    expect(
      work
          .edit((d) => (d['card_instances'] as List).removeAt(1))
          .featuredSlotId,
      'a',
    );
  });
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('mode selection and isolated examples fit $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = ReadOnlyExamples();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [albumRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const AlbumCreatePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('创建后无法更换'), findsOneWidget);
      for (final i in [0, 1]) {
        final preview = find.text('预览效果').at(i);
        await tester.ensureVisible(preview);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(find.byType(AlbumExamplePage), findsOneWidget);
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('示例效果')),
          findsOneWidget,
        );
        expect(find.text('查看官方图鉴详情'), findsNothing);
        expect(tester.takeException(), isNull);
        if (i == 0) {
          await tester.tap(find.text('切换双面'));
          await tester.pumpAndSettle();
          expect(find.text('切换单面'), findsOneWidget);
          await tester.pageBack();
        } else {
          await tester.tap(find.text('使用此模式'));
        }
        await tester.pumpAndSettle();
      }
      expect(find.text('卡片作品 · 创建后不可更换'), findsOneWidget);
      expect(find.text('视觉风格'), findsNothing);
      expect(find.textContaining('展示方式 ·'), findsNothing);
      expect(repository.creates, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

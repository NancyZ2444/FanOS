import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:fan_os/features/daily_card/presentation/daily_card_page.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(isLoggedIn: true);
}

class _CreateCapture extends MockAlbumRepository {
  String? style;
  String? display;
  @override
  Future<PhotocardAlbum> create(
    String name,
    String display,
    String style, {
    String mode = 'BOOK',
    String description = '',
    String? requestId,
  }) async {
    this.style = style;
    this.display = display;
    throw const ApiException('TEST_CAPTURE', '测试保留在当前页面');
  }
}

class _Feedback extends FeedbackRepository {
  _Feedback({this.error = false}) : super(ApiClient());
  final bool error;
  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async {
    if (error) throw const ApiException('TEMPORARY', '网络暂时不可用');
    return {'items': [], 'next_offset': null};
  }
}

void main() {
  testWidgets('home and daily card omit redundant reminders', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final page in [const HomePage(), const DailyCardPage()]) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: FanOsTheme.light, home: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每天 3 次，发现与你有关的小卡'), findsNothing);
      expect(find.textContaining('不会自动加入 Owned'), findsNothing);
      expect(find.textContaining('Draw Record'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'feedback empty state is compact but load failure stays visible',
    (tester) async {
      for (final error in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(error),
            overrides: [
              feedbackRepositoryProvider.overrideWithValue(
                _Feedback(error: error),
              ),
            ],
            child: MaterialApp(
              theme: FanOsTheme.light,
              home: const FeedbackCenterPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('处理进度会显示在这里'), findsNothing);
        if (error) {
          expect(find.textContaining('网络暂时不可用'), findsOneWidget);
          expect(find.text('还没有反馈记录'), findsNothing);
        } else {
          expect(find.text('还没有反馈记录'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(FanEmptyState),
              matching: find.byType(Text),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'book setup at $width selects display inline without a style picker',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _CreateCapture();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith(_SignedIn.new),
              albumRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              theme: FanOsTheme.light,
              home: const AlbumCreatePage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择此模式').first);
        await tester.pumpAndSettle();
        expect(find.text('视觉风格'), findsNothing);
        expect(find.text('真实卡册'), findsNothing);
        expect(find.text('极简数字'), findsNothing);
        expect(find.text('展示方式'), findsOneWidget);
        expect(find.text('单面'), findsOneWidget);
        expect(find.text('双面'), findsOneWidget);
        await tester.ensureVisible(find.text('双面'));
        await tester.tap(find.text('双面'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        await tester.ensureVisible(find.text('创建相册'));
        await tester.tap(find.text('创建相册'));
        await tester.pumpAndSettle();
        expect(repo.style, 'REALISTIC');
        expect(repo.display, 'DOUBLE');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'legacy book styles render fixed pocket pages without mutating data',
    (tester) async {
      final page = <String, dynamic>{
        'id': 'page-1',
        'config': albumCanvas(),
        'grid_count': 1,
        'slots': [
          {'id': 'slot-1', 'card_id': 'unavailable-card'},
        ],
      };
      Rect? firstCardRect;
      for (final style in ['REALISTIC', 'MINIMAL']) {
        final album = PhotocardAlbum({
          'id': 'existing',
          'work_mode': 'BOOK',
          'visual_style': style,
          'pages': [page],
        });
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: FanOsTheme.light,
            home: Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: AlbumBinderWidget(
                  album: album,
                  page: page,
                  onTapSlot: (_) => taps++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlbumMaterial), findsOneWidget);
        expect(find.byKey(const Key('album-pocket-page')), findsOneWidget);
        expect(find.byKey(const Key('album-page-binding')), findsOneWidget);
        expect(find.byKey(const Key('album-pocket-slot-1')), findsOneWidget);
        final cardRect = tester.getRect(find.byType(AlbumCardImage));
        if (firstCardRect != null) expect(cardRect, firstCardRect);
        firstCardRect = cardRect;
        await tester.tap(find.byType(AlbumCardImage));
        expect(taps, 1);
        expect(album.patch['visual_style'], style);
        expect(album.pages, [page]);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

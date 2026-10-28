import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

PhotocardAlbum _album({
  required bool cards,
  bool owner = true,
  bool public = false,
  bool moderated = false,
  bool publicationBlocked = false,
}) => PhotocardAlbum({
  'id': 'toolbar-test',
  'name': '我的小卡册',
  'is_owner': owner,
  'user_id': 'author',
  'author_name': '创建者',
  'visibility': public ? 'PUBLIC' : 'PRIVATE',
  'is_moderated': moderated,
  'publication_blocked': publicationBlocked,
  'work_mode': cards ? 'CARDS' : 'BOOK',
  'display_type': 'SINGLE',
  'cover': albumCanvas(),
  'pages': cards ? <AlbumJson>[] : [blankAlbumPage(4)],
  'card_instances': <AlbumJson>[],
  'card_view': {'background': albumBackground()},
  'cards': <String, dynamic>{},
});

Widget _scope(Widget child) => ProviderScope(
  overrides: [albumResourcesProvider.overrideWith((ref) async => [])],
  child: child,
);

void main() {
  for (final cards in [false, true]) {
    final mode = cards ? 'cards' : 'book';

    testWidgets(
      '$mode edit opens original editor directly on a narrow screen',
      (tester) async {
        tester.view.physicalSize = const Size(360, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final album = _album(cards: cards);
        final router = GoRouter(
          initialLocation: '/digital-albums/${album.id}',
          routes: [
            GoRoute(
              path: '/digital-albums/:id',
              builder: (_, _) => AlbumViewer(album: album),
            ),
            GoRoute(
              path: '/digital-albums/:id/edit',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('原有编辑页')),
                body: Text('编辑 ${state.pathParameters['id']}'),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _scope(
            MaterialApp.router(
              theme: FanOsTheme.light,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  padding: const EdgeInsets.only(top: 59, bottom: 34),
                ),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final edit = find.byKey(const Key('album-viewer-edit'));
        final share = find.byKey(const Key('album-viewer-share'));
        expect(find.text('编辑与展示设置'), findsNothing);
        expect(find.text('编辑'), findsOneWidget);
        expect(find.byTooltip('分享相册链接'), findsOneWidget);
        expect(tester.getSize(edit).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(share).width, greaterThanOrEqualTo(44));
        expect(
          tester.getRect(edit).center.dy,
          closeTo(tester.getRect(share).center.dy, 1),
        );
        expect(tester.takeException(), isNull);

        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/digital-albums/${album.id}/edit');
        expect(router.state.uri.queryParameters, isEmpty);
        expect(find.text('原有编辑页'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('设置主图与顺序'), findsNothing);
        expect(find.text('相册设置'), findsNothing);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('album-viewer-edit')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final allowSave in [false, true]) {
      testWidgets('$mode preview keeps save=$allowSave without owner actions', (
        tester,
      ) async {
        Object? result = 'not-closed';
        await tester.pumpWidget(
          _scope(
            MaterialApp(
              theme: FanOsTheme.light,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => AlbumViewer(
                            album: _album(cards: cards),
                            preview: true,
                            allowSave: allowSave,
                          ),
                        ),
                      );
                    },
                    child: const Text('打开预览'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开预览'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('album-viewer-edit')), findsNothing);
        expect(find.byKey(const Key('album-viewer-share')), findsNothing);
        expect(find.text('编辑与展示设置'), findsNothing);
        expect(find.text('保存'), allowSave ? findsOneWidget : findsNothing);
        await tester.tap(find.text(allowSave ? '保存' : '返回编辑'));
        await tester.pumpAndSettle();
        expect(result, allowSave ? isTrue : isNull);
        expect(find.text('打开预览'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$mode guest retains sharing and reporting but not editing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(
          MaterialApp(
            theme: FanOsTheme.light,
            home: AlbumViewer(album: _album(cards: cards, owner: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('编辑'), findsNothing);
      expect(find.byKey(const Key('album-viewer-edit')), findsNothing);
      expect(find.byKey(const Key('album-viewer-share')), findsNothing);
      expect(find.text('收藏相册'), findsOneWidget);
      await tester.tap(find.byTooltip('相册操作'));
      await tester.pumpAndSettle();
      expect(find.text('分享相册链接'), findsOneWidget);
      expect(find.text('举报相册'), findsOneWidget);
      expect(find.text('编辑相册'), findsNothing);
      expect(find.text('设置主图与顺序'), findsNothing);
      expect(find.text('相册设置'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('separate sharing preserves private and moderation rules', (
    tester,
  ) async {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    for (final state in ['private', 'public', 'moderated', 'unpublished']) {
      final album = _album(
        cards: true,
        public: state == 'public',
        moderated: state == 'moderated',
        publicationBlocked: state == 'unpublished',
      );
      final count = copied.length;
      await tester.pumpWidget(
        _scope(
          MaterialApp(
            key: ValueKey(state),
            theme: FanOsTheme.light,
            home: AlbumViewer(album: album),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-viewer-share')));
      await tester.pumpAndSettle();
      if (state == 'moderated' || state == 'unpublished') {
        expect(copied.length, count);
        expect(
          find.text(
            state == 'moderated' ? '作品暂不可公开，限制解除并重新发布后可分享' : '请先主动发布修改内容后再分享',
          ),
          findsOneWidget,
        );
      } else {
        expect(copied.length, count + 1);
        expect(
          copied.last,
          '${album.name}\nfanos://app/digital-albums/${album.id}',
        );
        expect(album.isPublic, state == 'public');
        expect(find.text('相册链接已复制'), findsOneWidget);
      }
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}

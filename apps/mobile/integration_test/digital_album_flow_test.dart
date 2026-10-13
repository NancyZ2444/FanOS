import 'package:fan_os/app/app.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';
import 'package:fan_os/features/albums/presentation/album_editor_page.dart';
import 'package:fan_os/features/albums/presentation/album_card_picker.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _enabled = bool.fromEnvironment('RUN_ALBUM_NATIVE_E2E');

Future<void> _wait(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  expect(finder, findsWidgets, reason: 'Native album UI did not become ready');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(WidgetTester tester, String name) async {
    // Wait for the iOS route transition as well as the newly rebuilt page.
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets(
    'iOS creates an album, selects official cards, saves and previews',
    (tester) async {
      // Fail closed: this test may only write to the explicitly isolated API.
      expect(useMockApi, isFalse);
      expect(ApiClient.baseUrl, 'http://127.0.0.1:18001/api/v1');
      final store = AlbumDraftStore('native-album-e2e');
      final container = ProviderContainer(
        overrides: [albumDraftStoreProvider.overrideWithValue(store)],
      );
      String? albumId;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        if (albumId != null) {
          final repo = container.read(albumRepositoryProvider);
          await repo.delete(await repo.get(albumId));
          await store.remove('draft-$albumId');
        }
        container.dispose();
      });
      await container
          .read(sessionProvider.notifier)
          .login(LoginMethod.phone, phone: '13800000000', code: '123456');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FanOsApp(),
        ),
      );
      await _wait(tester, find.text('新建相册'));
      await tester.enterText(
        find.byType(TextField),
        'iOS Album QA ${DateTime.now().millisecondsSinceEpoch}',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('创建相册'));
      await tester.tap(find.text('创建相册'));
      await _wait(tester, find.text('封面编辑'));
      albumId = tester
          .widget<AlbumEditorPage>(find.byType(AlbumEditorPage))
          .albumId;
      await _wait(tester, find.byType(AlbumCanvasWidget));
      // The reported regression happens while the keyboard is still focused.
      await tester.tap(find.text('文字'));
      await _wait(tester, find.text('添加文字'));
      await tester.enterText(find.byType(TextField), '我的星光收藏');
      await tester.tap(find.text('确定'));
      await capture(tester, 'ios-album-text-saved');
      expect(find.text('我的星光收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我的星光收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await _wait(tester, find.text('编辑文字'));
      await tester.enterText(find.byType(TextField), '我的星光收藏 · 更新');
      await tester.tap(find.text('确定'));
      await capture(tester, 'ios-album-text-updated');
      expect(find.text('我的星光收藏 · 更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消选中'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小卡'));
      await _wait(tester, find.byType(AlbumCardPicker));
      await _wait(tester, find.byType(AlbumCardImage));
      await tester.tap(find.byType(AlbumCardImage).first);
      await _wait(tester, find.text('已选择 1 张 · 确认添加'));
      await tester.tap(find.text('已选择 1 张 · 确认添加'));
      await _wait(tester, find.text('封面编辑'));
      await capture(tester, 'ios-album-cover-editor');

      await tester.tap(find.byTooltip('添加页面'));
      await _wait(tester, find.text('内页编辑'));
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlbumBinderWidget),
              matching: find.byType(DragTarget<String>),
            )
            .first,
      );
      await _wait(tester, find.byType(AlbumCardPicker));
      await _wait(tester, find.byType(AlbumCardImage));
      await tester.tap(find.byType(AlbumCardImage).first);
      await _wait(tester, find.text('已选择 1 张 · 确认添加'));
      await tester.tap(find.text('已选择 1 张 · 确认添加'));
      await _wait(tester, find.text('内页编辑'));
      await capture(tester, 'ios-album-inner-editor');
      await tester.tap(find.text('完成'));
      await _wait(tester, find.byType(AlbumViewer));
      expect(find.text('封面 · 1 页'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await _wait(tester, find.text('1 / 1'));
      await tester.pump(const Duration(milliseconds: 500));
      await capture(tester, 'ios-album-reader');
      await tester.tap(find.byType(AlbumCardImage).first);
      await _wait(tester, find.byTooltip('关闭'));
      await capture(tester, 'ios-album-card-preview');
      await tester.tap(find.byTooltip('关闭'));
      await _wait(tester, find.text('1 / 1'));
      await tester.tap(find.text('卡片模式'));
      await _wait(tester, find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 500));
      await capture(tester, 'ios-album-carousel');
      final saved = await container.read(albumRepositoryProvider).get(albumId);
      expect(saved.pageCount, 1);
      expect(saved.cardCount, 1);
      expect(saved.json['status'], 'PUBLISHED');
      expect(saved.isPublic, isFalse);
      expect(
        (saved.cover['elements'] as List)
            .where((e) => e['type'] == 'TEXT')
            .single['content'],
        '我的星光收藏 · 更新',
      );
      expect(tester.takeException(), isNull);
    },
    skip: !_enabled,
  );
}

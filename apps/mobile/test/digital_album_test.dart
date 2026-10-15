import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/presentation/album_editor_page.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:fan_os/features/albums/presentation/album_editor_panels.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _MemoryStore extends AlbumDraftStore {
  _MemoryStore() : super('test');
  final values = <String, AlbumJson>{};
  @override
  Future<AlbumJson?> read(String key) async =>
      values[key] == null ? null : cloneAlbumJson(values[key]!);
  @override
  Future<void> write(String key, AlbumJson data) async {
    values[key] = cloneAlbumJson(data);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _FlakyRepository extends MockAlbumRepository {
  bool offline = false;
  Completer<void>? gate;
  @override
  Future<PhotocardAlbum> save(PhotocardAlbum album) async {
    if (offline) throw const ApiException('OFFLINE', '网络不可用');
    await gate?.future;
    return super.save(album);
  }
}

Future<PhotocardAlbum> _fixture(
  MockAlbumRepository repo, {
  String name = 'My Star Collection',
  int pages = 3,
}) async {
  final book = await repo.create(name, 'SINGLE', 'REALISTIC');
  return repo.save(
    book.edit((d) {
      final generated = List.generate(pages, (_) => blankAlbumPage(9));
      for (int i = 0; i < generated.length; i++) {
        final slots = (generated[i]['slots'] as List).cast<AlbumJson>();
        for (int j = 0; j < slots.length; j++) {
          slots[j]['card_id'] = j.isEven ? 'card-aria-01' : 'card-lin-01';
        }
      }
      d['pages'] = generated;
      d['cover'] = albumCanvas()
        ..['elements'] = [
          {
            'id': 'cover-card',
            'type': 'CARD',
            'content': 'card-aria-01',
            'x': .14,
            'y': .06,
            'width': .72,
            'height': .7,
            'rotation': 0,
            'z_index': 0,
          },
          {
            'id': 'cover-text',
            'type': 'TEXT',
            'content': 'MY STAR COLLECTION',
            'x': .10,
            'y': .79,
            'width': .80,
            'height': .15,
            'rotation': 0,
            'z_index': 1,
            'style': {'color': '#342A56', 'font_size': 18.0, 'bold': true},
          },
        ];
    }),
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['ALBUM_VISUAL_QA'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../../output/album-qa');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

ThemeData _qaTheme() {
  final base = FanOsTheme.light;
  if (Platform.environment['ALBUM_VISUAL_QA'] != '1') return base;
  const family = 'AlbumQA';
  final label = base.textTheme.labelLarge!.copyWith(fontFamily: family);
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: [family],
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: family,
      fontFamilyFallback: [family],
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: family,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: base.chipTheme.labelStyle?.copyWith(fontFamily: family),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      hintStyle: base.inputDecorationTheme.hintStyle?.copyWith(
        fontFamily: family,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(label),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(label),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(textStyle: WidgetStatePropertyAll(label)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['ALBUM_VISUAL_QA'] == '1') {
      final loader = FontLoader('AlbumQA')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('/System/Library/Fonts/STHeiti Medium.ttc')
                  .readAsBytes(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        );
      await icons.load();
    }
  });

  test('duplicate card placements retain stable unique slots and independent order', () async {
    final repo = MockAlbumRepository();
    final book = await _fixture(repo);
    final ids = book.orderedSlotIds;
    expect(ids.toSet().length, 27);
    final reordered = book.edit((d) {
      d['card_view'] = {
        'card_order': ids.reversed.toList(),
        'order_customized': true,
        'featured_slot_id': ids.last,
        'background': albumBackground(),
      };
    });
    expect(reordered.pages.first['id'], book.pages.first['id']);
    expect(reordered.orderedSlotIds.first, ids.last);
    final cleared = reordered.edit(
      (d) =>
          ((d['pages'] as List).last['slots'] as List).last['card_id'] = null,
    );
    expect(cleared.cardView['featured_slot_id'], isNull);
    expect(cleared.cardCount, 26);
    final copy = await repo.duplicate(book);
    expect(copy.orderedSlotIds.toSet().intersection(ids.toSet()), isEmpty);
    expect(copy.cardCount, book.cardCount);
    expect(copy.isPublic, isFalse);
  });

  test(
    'ordinary quota counts actual pages and display changes retain IDs',
    () async {
      final repo = MockAlbumRepository();
      final book = await _fixture(repo, pages: 10);
      final changed = await repo.save(
        book.edit((d) => d['display_type'] = 'DOUBLE'),
      );
      expect(changed.pageCount, 10);
      expect(changed.orderedSlotIds, book.orderedSlotIds);
      expect(
        () => repo.save(
          changed.edit((d) => (d['pages'] as List).add(blankAlbumPage(9))),
        ),
        throwsA(isA<ApiException>()),
      );
      for (int i = 1; i < 10; i++) {
        await repo.create('Book $i', 'SINGLE', 'MINIMAL');
      }
      expect(
        () => repo.create('Over limit', 'SINGLE', 'REALISTIC'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('durable draft and mock library persist and isolate accounts', () async {
    final root = await Directory.systemTemp.createTemp('fan-os-album-test-');
    addTearDown(() => root.delete(recursive: true));
    final a = AlbumDraftStore('user-a', directory: () async => root);
    final b = AlbumDraftStore('user-b', directory: () async => root);
    await a.write('draft-one', {
      'album': {'name': 'Saved offline'},
    });
    expect((await a.read('draft-one'))!['album']['name'], 'Saved offline');
    expect(await b.read('draft-one'), isNull);
    final repo = MockAlbumRepository(store: a);
    final book = await _fixture(repo);
    await repo.preferences('natural-wood', 'LIST');
    final restarted = MockAlbumRepository(store: a);
    expect((await restarted.get(book.id)).cardCount, 27);
    expect((await restarted.list()).theme, 'natural-wood');
    expect((await restarted.list()).viewMode, 'LIST');
  });

  test(
    'offline saving keeps local draft and retry does not lose edits',
    () async {
      final repo = _FlakyRepository();
      final store = _MemoryStore();
      final book = await _fixture(repo);
      final controller = AlbumEditorController(book.id, repo, store);
      addTearDown(controller.dispose);
      await controller.load();
      repo.offline = true;
      controller.edit((d) => d['name'] = 'Offline edit');
      await controller.save();
      expect(controller.dirty, isTrue);
      expect(store.values, contains('draft-${book.id}'));
      repo.offline = false;
      await controller.save();
      expect((await repo.get(book.id)).name, 'Offline edit');
      expect(controller.dirty, isFalse);
      expect(store.values, isNot(contains('draft-${book.id}')));
    },
  );

  test('edits during an in-flight save adopt revision without overwriting newest edit', () async {
    final repo = _FlakyRepository();
    final book = await _fixture(repo);
    final controller = AlbumEditorController(book.id, repo, _MemoryStore());
    addTearDown(controller.dispose);
    await controller.load();
    controller.edit((d) => d['name'] = 'First');
    repo.gate = Completer<void>();
    final saving = controller.save();
    await Future<void>.delayed(Duration.zero);
    controller.edit((d) => d['name'] = 'Newest');
    repo.gate!.complete();
    await saving;
    repo.gate = null;
    expect(controller.album!.name, 'Newest');
    await controller.save();
    expect((await repo.get(book.id)).name, 'Newest');
  });

  test(
    'conflict keeps local draft and archives it before explicit reload',
    () async {
      final repo = MockAlbumRepository();
      final book = await _fixture(repo);
      final store = _MemoryStore();
      final controller = AlbumEditorController(book.id, repo, store);
      addTearDown(controller.dispose);
      await controller.load();
      controller.edit((d) => d['name'] = 'Local version');
      await repo.save(book.edit((d) => d['name'] = 'Other device'));
      await controller.save();
      expect(controller.conflict, isTrue);
      expect(controller.album!.name, 'Local version');
      await controller.load(discardLocal: true);
      expect(controller.album!.name, 'Other device');
      expect(store.values.keys.any((k) => k.startsWith('backup-')), isTrue);
    },
  );

  test('undo redo and pending tray survive successful autosave', () async {
    final repo = MockAlbumRepository();
    final book = await _fixture(repo);
    final store = _MemoryStore();
    final controller = AlbumEditorController(book.id, repo, store);
    addTearDown(controller.dispose);
    await controller.load();
    controller.edit((d) => d['name'] = 'Changed');
    controller.undo();
    expect(controller.album!.name, book.name);
    controller.redo();
    expect(controller.album!.name, 'Changed');
    controller.edit((d) => d['_pending_cards'] = ['card-lin-01']);
    await controller.save();
    expect(controller.album!.json['_pending_cards'], ['card-lin-01']);
    expect(store.values, contains('draft-${book.id}'));
  });

  testWidgets(
    'shelf, editors, single/double book and card viewer fit phone sizes',
    (tester) async {
      final repo = MockAlbumRepository();
      final book = await _fixture(repo);
      await _fixture(repo, name: 'Moonlight Moments', pages: 1);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          albumRepositoryProvider.overrideWithValue(repo),
          albumDraftStoreProvider.overrideWithValue(_MemoryStore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      final key = GlobalKey();
      Future<void> show(
        Widget widget,
        String name, {
        Size size = const Size(390, 844),
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final theme = _qaTheme();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                home: widget,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await _capture(tester, key, name);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(const AlbumShelfPage(), 'shelf');
      await show(const AlbumCreatePage(), 'create');
      await show(AlbumEditorPage(albumId: book.id), 'cover-editor');
      await show(AlbumViewer(album: book, preview: true), 'book-cover');
      await show(
        AlbumViewer(album: book, preview: true, initialPage: 1),
        'book-single',
      );
      await show(
        AlbumViewer(
          album: book.edit((d) => d['display_type'] = 'DOUBLE'),
          preview: true,
          initialPage: 1,
        ),
        'book-double',
      );
      await show(
        AlbumViewer(
          album: book.edit((d) => d['visual_style'] = 'MINIMAL'),
          preview: true,
          initialPage: 3,
        ),
        'book-minimal',
        size: const Size(375, 667),
      );
    },
  );

  testWidgets(
    'editor can add a page, change layout, and return with draft retained',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockAlbumRepository();
      final book = await _fixture(repo);
      final store = _MemoryStore();
      final container = ProviderContainer(
        overrides: [
          albumRepositoryProvider.overrideWithValue(repo),
          albumDraftStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/edit'),
                child: const Text('Open editor'),
              ),
            ),
          ),
          GoRoute(
            path: '/edit',
            builder: (_, _) => AlbumEditorPage(albumId: book.id),
          ),
        ],
      );
      addTearDown(router.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: _qaTheme(),
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加页面'));
      await tester.pumpAndSettle();
      expect(find.text('内页编辑'), findsOneWidget);
      await _capture(tester, key, 'inner-editor');
      await tester.tap(find.byTooltip('返回书架'));
      await tester.pumpAndSettle();
      expect(find.text('Open editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('card mode and front/back preview keep reading position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MockAlbumRepository();
    final book = await _fixture(repo);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [albumRepositoryProvider.overrideWithValue(repo)],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _qaTheme(),
            home: AlbumViewer(album: book, preview: true, initialPage: 2),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('卡片模式'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'card-carousel');
    await tester.tap(find.text('相册模式'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byType(AlbumCardImage).first);
    await tester.pumpAndSettle();
    expect(find.text('查看官方图鉴详情'), findsOneWidget);
    await _capture(tester, key, 'card-preview');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('symmetric layouts expose exactly the requested fixed slots', (
    tester,
  ) async {
    final repo = MockAlbumRepository();
    final book = await _fixture(repo, pages: 1);
    for (final count in [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
      final page = blankAlbumPage(count);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 330,
              height: 420,
              child: AlbumBinderWidget(
                album: book,
                page: page,
                onSwap: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DragTarget<String>), findsNWidgets(count));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('closing background input keeps controllers alive through exit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AlbumJson? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: FanOsTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await editAlbumBackground(
                  context,
                  albumBackground(),
                  [],
                );
              },
              child: const Text('open-background'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-background'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '#AABBCC');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result?['colors'], ['#AABBCC']);
    expect(find.text('背景设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving cover text with keyboard focus does not destroy the dialog early',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockAlbumRepository();
      final book = await repo.create(
        'Cover text regression',
        'SINGLE',
        'REALISTIC',
      );
      final container = ProviderContainer(
        overrides: [
          albumRepositoryProvider.overrideWithValue(repo),
          albumDraftStoreProvider.overrideWithValue(_MemoryStore()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: AlbumEditorPage(albumId: book.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我的星光收藏');
      await tester.tap(
        find.descendant(
          of: find.byType(AlbumToolPanel),
          matching: find.text('完成'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加文字'), findsNothing);
      expect(find.text('我的星光收藏'), findsOneWidget);
      // Editing an existing element must retain its ID, not append another copy.
      await tester.tap(find.text('我的星光收藏'));
      await tester.pump();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '更新后的封面文字');
      await tester.tap(
        find.descendant(
          of: find.byType(AlbumToolPanel),
          matching: find.text('完成'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('更新后的封面文字'), findsOneWidget);
      for (final dismiss in ['cancel', 'back']) {
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '不应保存的文字');
        if (dismiss == 'cancel') {
          await tester.tap(find.byTooltip('取消'));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.text('更新后的封面文字'), findsOneWidget);
        expect(find.text('不应保存的文字'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await container.read(albumEditorProvider(book.id)).save();
      final saved = await repo.get(book.id);
      expect((saved.cover['elements'] as List).single['content'], '更新后的封面文字');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing album settings with focused fields retains the edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MockAlbumRepository();
    final book = await repo.create(
      'Settings regression',
      'SINGLE',
      'REALISTIC',
    );
    final container = ProviderContainer(
      overrides: [
        albumRepositoryProvider.overrideWithValue(repo),
        albumDraftStoreProvider.overrideWithValue(_MemoryStore()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: AlbumEditorPage(albumId: book.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('相册操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相册设置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新的相册名称');
    await tester.ensureVisible(find.text('返回编辑'));
    await tester.tap(find.text('返回编辑'));
    await tester.pumpAndSettle();
    await container.read(albumEditorProvider(book.id)).save();
    expect((await repo.get(book.id)).name, '新的相册名称');
    expect(find.text('相册设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shelf rename dismisses its input only after the route exits', (
    tester,
  ) async {
    final repo = MockAlbumRepository();
    final book = await repo.create('Rename regression', 'SINGLE', 'REALISTIC');
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        albumRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login(LoginMethod.phone);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const AlbumShelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('相册操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '重命名后的相册',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await repo.get(book.id)).name, '重命名后的相册');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

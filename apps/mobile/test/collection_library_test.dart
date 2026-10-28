import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/presentation/album_card_picker.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:fan_os/features/collection/data/library_search_repository.dart';
import 'package:fan_os/features/collection/presentation/collection_page.dart';
import 'package:fan_os/features/collection/presentation/library_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _ControlledSearch implements LibrarySearchRepository {
  final calls = <(String, String, int)>[];
  final replies = <Completer<LibrarySearchResult>>[];
  @override
  Future<LibrarySearchResult> search(
    String query, {
    String scope = 'all',
    int offset = 0,
  }) {
    calls.add((query, scope, offset));
    final reply = Completer<LibrarySearchResult>();
    replies.add(reply);
    return reply.future;
  }
}

LibrarySearchResult _results(
  List<CollectibleCard> cards, {
  int? next,
  int? total,
}) => LibrarySearchResult({
  'owned': LibrarySearchGroup(
    items: cards.map((c) => LibrarySearchItem(card: c, quantity: 1)).toList(),
    total: total ?? cards.length,
    nextOffset: next,
  ),
  'wishlist': const LibrarySearchGroup(),
  'albums': const LibrarySearchGroup(),
});

Future<PhotocardAlbum> _album(
  MockAlbumRepository repo,
  String name, {
  bool draft = false,
}) async {
  var album = await repo.create(name, 'SINGLE', 'MINIMAL', mode: 'CARDS');
  album = await repo.save(
    album.edit((d) {
      final page = blankAlbumPage(9);
      for (final slot in (page['slots'] as List).cast<AlbumJson>()) {
        slot['card_id'] = 'card-aria-01';
      }
      (page['slots'] as List).last['card_id'] = 'card-lin-01';
      d['card_instances'] = page['slots'];
      d['card_view'] = <String, dynamic>{
        'default_mode': 'CARDS',
        'cover_style': 'STACK_V1',
      };
    }),
  );
  return draft ? album : repo.publish(album);
}

Future<ProviderContainer> _container({
  MockAlbumRepository? albums,
  CatalogBundle? catalog,
  LibrarySearchRepository? search,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      catalogProvider.overrideWith(
        (ref) async => catalog ?? DemoCatalog.bundle,
      ),
      albumRepositoryProvider.overrideWithValue(
        albums ?? MockAlbumRepository(),
      ),
      if (search != null)
        librarySearchRepositoryProvider.overrideWithValue(search),
    ],
  );
  await container.read(sessionProvider.notifier).login(LoginMethod.phone);
  addTearDown(container.dispose);
  return container;
}

Future<GlobalKey> _mount(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/collection',
    routes: [
      GoRoute(path: '/collection', builder: (_, _) => const CollectionPage()),
      GoRoute(
        path: '/collection/search',
        builder: (_, _) => const LibrarySearchPage(),
      ),
      for (final path in [
        '/card/:id',
        '/digital-albums/:id',
        '/digital-albums/:id/edit',
      ])
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(
            appBar: AppBar(title: Text('详情 ${state.pathParameters['id']}')),
            body: const Text('Detail'),
          ),
        ),
    ],
  );
  addTearDown(router.dispose);
  final key = GlobalKey();
  final theme = FanOsTheme.light;
  const family = 'LibraryQA';
  final label = theme.textTheme.labelLarge!.copyWith(fontFamily: family);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: Platform.environment['COLLECTION_VISUAL_QA'] == '1'
            ? theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: family),
                primaryTextTheme: theme.primaryTextTheme.apply(
                  fontFamily: family,
                ),
                chipTheme: theme.chipTheme.copyWith(
                  labelStyle: theme.chipTheme.labelStyle?.copyWith(
                    fontFamily: family,
                  ),
                ),
                inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                  hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(
                    fontFamily: family,
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: theme.textButtonTheme.style?.copyWith(
                    textStyle: WidgetStatePropertyAll(label),
                  ),
                ),
                appBarTheme: theme.appBarTheme.copyWith(
                  titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
                    fontFamily: family,
                  ),
                ),
              )
            : theme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: key, child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['COLLECTION_VISUAL_QA'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../../output/collection-qa');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['COLLECTION_VISUAL_QA'] != '1') return;
    for (final entry in {
      'LibraryQA': '/System/Library/Fonts/STHeiti Medium.ttc',
      'MaterialIcons': '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(await File(entry.value).readAsBytes()),
            ),
          ))
          .load();
    }
  });

  test(
    'API search uses authenticated library route, not catalog search',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
      final client = ApiClient(dio: dio)..setAccessToken('test-token');
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/me/library/search');
            expect(options.headers['Authorization'], 'Bearer test-token');
            expect(options.queryParameters, {
              'q': 'Lin',
              'scope': 'albums',
              'offset': 20,
            });
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': 0,
                  'data': {
                    'groups': {
                      for (final key in ['owned', 'wishlist', 'albums'])
                        key: {'items': [], 'total': 0, 'next_offset': null},
                    },
                    'total': 0,
                  },
                },
              ),
            );
          },
        ),
      );
      expect(
        (await ApiLibrarySearchRepository(
          client,
        ).search(' Lin ', scope: 'albums', offset: 20)).total,
        0,
      );
      dio.close();
    },
  );

  test(
    'search matches inner album cards, separates relations, includes drafts',
    () async {
      final repo = MockAlbumRepository();
      final album = await _album(repo, 'Moonlight');
      await _album(repo, 'Draft notes', draft: true);
      final search = MockLibrarySearchRepository(
        () async => DemoCatalog.bundle,
        () => const CollectionState(),
        repo,
      );
      final result = await search.search('Lin');
      expect(result.groups['owned']!.total, 0);
      expect(result.groups['wishlist']!.total, 1);
      expect(result.groups['albums']!.total, 2);
      expect(result.groups['albums']!.items.map((i) => i.category).toSet(), {
        'draft',
        'created',
      });
      expect(
        (await search.search('Moonlight')).groups['albums']!.items.single.id,
        album.id,
      );
      expect(
        (await repo.list(status: 'DRAFT')).albums.single.name,
        'Draft notes',
      );
      expect((await repo.list(status: 'PUBLISHED')).albums.single.id, album.id);
      expect((await search.search('unrelated')).total, 0);
    },
  );

  testWidgets(
    'toolbar, independent content modes, album categories and back navigation',
    (tester) async {
      final repo = MockAlbumRepository();
      final created = await _album(repo, '月光收藏');
      final draft = await _album(repo, '未完成的草稿', draft: true);
      final container = await _container(albums: repo);
      final key = await _mount(tester, container);
      expect(find.text('我的收藏'), findsNothing);
      expect(find.text('我的本命'), findsNothing);
      expect(find.text('Aria'), findsOneWidget);
      await _capture(tester, key, '01-owned');
      await tester.tap(find.byKey(const Key('owned-content-mode')));
      await tester.pumpAndSettle();
      expect(find.text('Aria'), findsNothing);
      expect(find.text('纯图'), findsNothing);
      await tester.tap(find.byKey(const Key('collection-layout')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('切换网格'), findsOneWidget);
      await tester.tap(find.byKey(const Key('collection-card-card-aria-01')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('切换图文'), findsOneWidget);
      await tester.tap(find.byKey(const Key('collection-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('Lin'), findsOneWidget);
      expect(find.byTooltip('切换列表'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wishlist-content-mode')));
      await tester.pumpAndSettle();
      await _capture(tester, key, '02-wishlist-images');
      await tester.tap(find.byKey(const Key('collection-tab-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('album-shelf-${created.id}')), findsOneWidget);
      expect(find.text(draft.name), findsNothing);
      await _capture(tester, key, '03-album-shelf');
      await tester.tap(find.byTooltip('所属范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('草稿'));
      await tester.pumpAndSettle();
      expect(find.text(draft.name), findsOneWidget);
      expect(find.text(created.name), findsNothing);
      await tester.tap(find.byKey(const Key('collection-layout')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('album-list-${draft.id}')), findsOneWidget);
      await _capture(tester, key, '04-album-list');
      await tester.tap(find.byTooltip('所属范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我收藏的'));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏相册'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byKey(const Key('collection-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-search-input')),
        'Lin',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('心愿单 · 1'), findsOneWidget);
      expect(find.text('卡册 · 2'), findsOneWidget);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await _capture(tester, key, '05-library-search');
      await tester.tap(
        find.byKey(const ValueKey('library-result-wishlist-card-lin-01')),
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('library-search-input')))
            .controller!
            .text,
        'Lin',
      );
      expect(find.text('心愿单 · 1'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏相册'), findsOneWidget);
      expect(find.byTooltip('切换书架'), findsOneWidget);
      expect(container.read(collectionProvider).owned, {'card-aria-01': 1});
      expect(container.read(collectionProvider).wishlist, {'card-lin-01'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale responses cannot replace a new query; error retry and empty result',
    (tester) async {
      final search = _ControlledSearch();
      await _mount(tester, await _container(search: search));
      await tester.tap(find.byKey(const Key('collection-search')));
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('library-search-input'));
      await tester.enterText(input, 'Aria');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(input, 'Lin');
      search.replies[0].complete(_results([DemoCatalog.cards.first]));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('library-result-owned-card-aria-01')),
        findsNothing,
      );
      search.replies[1].completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('搜索暂时不可用'), findsOneWidget);
      await tester.tap(find.text('重新加载'));
      await tester.pump();
      search.replies[2].complete(_results([]));
      await tester.pumpAndSettle();
      expect(find.text('没有找到相关收藏'), findsOneWidget);
      expect(search.calls.map((c) => c.$1), ['Aria', 'Lin', 'Lin']);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.text('搜索你的收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination and return from detail retain later pages and position',
    (tester) async {
      final cards = List.generate(
        35,
        (i) => CollectibleCard.fromJson({
          ...albumCardJson(DemoCatalog.cards.first),
          'id': 'card-$i',
        }),
      );
      final catalog = CatalogBundle(
        idols: DemoCatalog.idols,
        groups: DemoCatalog.groups,
        cards: cards,
      );
      final container = await _container(catalog: catalog);
      container.read(collectionProvider.notifier).hydrate({
        for (final c in cards) c.id: 1,
      }, {});
      await _mount(tester, container);
      final grid = tester.widget<GridView>(
        find.byKey(const Key('owned-cards')),
      );
      grid.controller!.jumpTo(800);
      await tester.pumpAndSettle();
      final oldOffset = grid.controller!.offset;
      await tester.tap(find.byKey(const Key('collection-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-tab-0')));
      await tester.pumpAndSettle();
      expect(grid.controller!.offset, oldOffset);
      await tester.tap(find.byKey(const Key('collection-layout')));
      await tester.pumpAndSettle();
      expect(grid.controller!.offset, greaterThan(0));
      await tester.tap(find.byKey(const Key('collection-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-search-input')),
        'Aria',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library-scope-owned')));
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(LibrarySearchPage),
        matching: find.byType(ListView),
      );
      final controller = tester.widget<ListView>(list).controller!;
      expect(find.text('已拥有 · 35'), findsOneWidget);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        (tester.widget<ListView>(list).childrenDelegate
                as SliverChildListDelegate)
            .children
            .where(
              (w) => w.key == const ValueKey('library-result-owned-card-30'),
            )
            .length,
        1,
      );
      final late = find.byKey(const ValueKey('library-result-owned-card-30'));
      await tester.scrollUntilVisible(
        late,
        400,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final before = controller.offset;
      await tester.tap(late);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(late, findsOneWidget);
      expect(controller.offset, closeTo(before, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact toolbar, album filters, list and search fit a narrow large-text screen',
    (tester) async {
      final repo = MockAlbumRepository();
      await _album(repo, '很长的卡册名称用于小屏幕排版测试');
      final key = await _mount(
        tester,
        await _container(albums: repo),
        width: 320,
        scale: 1.4,
      );
      await tester.tap(find.byKey(const Key('collection-tab-2')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, key, '06-narrow-albums');
      await tester.tap(find.byKey(const Key('collection-layout')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('collection-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-search-input')),
        'Lin',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await _capture(tester, key, '07-narrow-search');
    },
  );
}

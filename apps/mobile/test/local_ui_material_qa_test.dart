// Explicit opt-in: read-only localhost data, actual Flutter pages and photos.
// No changes are sent to the local database. Editor interactions use memory.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:fan_os/features/albums/presentation/album_editor_page.dart';
import 'package:fan_os/features/albums/presentation/album_editor_panels.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/feedback/correction_page.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';

class _Catalog implements CatalogRepository {
  _Catalog(this.data);
  final CatalogBundle data;
  @override
  Future<CatalogBundle> fetchCatalog() async => data;
}

class _Feedback extends FeedbackRepository {
  _Feedback(this.object) : super(ApiClient());
  final FeedbackJson object;
  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async =>
      path.startsWith('/objects/') ? object : {'items': []};
}

class _Albums extends MockAlbumRepository {
  _Albums(this.rows);
  final List<PhotocardAlbum> rows;
  @override
  Future<AlbumShelfData> list({
    String q = '',
    String sort = 'updated',
    int offset = 0,
    bool favorites = false,
    String status = 'ALL',
    String? userId,
  }) async => AlbumShelfData(rows);
  @override
  Future<PhotocardAlbum> get(String id) async =>
      rows.firstWhere((a) => a.id == id);
  @override
  Future<PhotocardAlbum> save(PhotocardAlbum album) async {
    final i = rows.indexWhere((a) => a.id == album.id);
    rows[i] = album.edit((d) => d['revision'] = album.revision + 1);
    return rows[i];
  }
}

class _Memory extends AlbumDraftStore {
  _Memory() : super('ui-only');
  @override
  Future<AlbumJson?> read(String key) async => null;
  @override
  Future<void> write(String key, AlbumJson data) async {}
}

class _Session extends SessionController {
  @override
  SessionState build() => const SessionState(isLoggedIn: true);
}

ThemeData _qaTheme() {
  final theme = FanOsTheme.light;
  ButtonStyle font(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(
          (style?.textStyle?.resolve({}) ?? const TextStyle()).copyWith(
            fontFamily: 'FanQa',
          ),
        ),
      );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'FanQa'),
    filledButtonTheme: FilledButtonThemeData(
      style: font(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: font(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: font(theme.textButtonTheme.style),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'FanQa'),
      secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: 'FanQa',
      ),
    ),
  );
}

void main() {
  testWidgets(
    'real local photos: phone renders, flip, feedback and editor tools',
    (tester) async {
      final shadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = shadows);
      final output = Directory('../../output/ui-20261015').absolute
        ..createSync(recursive: true);
      final photos = <String>[];
      late AlbumJson bootstrap, correction;
      late List<PhotocardAlbum> albums;
      debugPrint('QA: loading localhost catalog');
      await tester.runAsync(() async {
        final old = HttpOverrides.current;
        HttpOverrides.global = null;
        final http = HttpClient()..findProxy = (_) => 'DIRECT';
        String? token;
        Future<dynamic> request(String path, [AlbumJson? body]) async {
          final req = await http.openUrl(
            body == null ? 'GET' : 'POST',
            Uri.parse('http://127.0.0.1:8000/api/v1$path'),
          );
          if (token != null) req.headers.set('Authorization', 'Bearer $token');
          if (body != null) {
            req.headers.contentType = ContentType.json;
            req.write(jsonEncode(body));
          }
          final response = await req.close();
          expect(response.statusCode, 200);
          return (jsonDecode(await utf8.decoder.bind(response).join())
              as AlbumJson)['data'];
        }

        final paths = <String, String>{};
        Future<dynamic> localize(dynamic data) async {
          if (data is List) {
            return [for (final value in data) await localize(value)];
          }
          if (data is Map) {
            final result = <String, dynamic>{};
            for (final entry in data.entries) {
              var value = entry.value;
              if (entry.key.toString().endsWith('image_url') ||
                  entry.key == 'thumbnail_url') {
                if (value is String && value.isNotEmpty) {
                  var uri = Uri.parse(value);
                  if (!uri.hasScheme) {
                    uri = Uri.parse('http://127.0.0.1:8000').resolveUri(uri);
                  }
                  if (!['localhost', '127.0.0.1'].contains(uri.host)) {
                    value = null;
                  } else {
                    final key = uri.toString();
                    if (!paths.containsKey(key)) {
                      final response = await (await http.getUrl(uri)).close();
                      if (response.statusCode == 200) {
                        final bytes = await response.fold<List<int>>(
                          [],
                          (a, b) => a..addAll(b),
                        );
                        final path = '${output.path}/photo-${paths.length}.img';
                        await File(path).writeAsBytes(bytes);
                        paths[key] = path;
                        photos.add(path);
                      }
                    }
                    value = paths[key];
                  }
                }
              } else {
                value = await localize(value);
              }
              result[entry.key as String] = value;
            }
            return result;
          }
          return data;
        }

        try {
          bootstrap =
              await localize(await request('/catalog/bootstrap')) as AlbumJson;
          token = (await request('/auth/login', {
            'method': 'phone',
            'phone': '13900000000',
            'code': '666666',
          }))['access_token'];
          correction = await localize(
            await request(
              '/feedback/objects/cards/${bootstrap['cards'][0]['id']}',
            ),
          ) as AlbumJson;
          final shelf = await request('/albums');
          albums = [
            for (final a in shelf['items'])
              PhotocardAlbum(
                await localize(await request('/albums/${a['id']}'))
                    as AlbumJson,
              ),
          ];
          expect(albums, isNotEmpty);
          debugPrint(
            'QA: loaded ${photos.length} photos and ${albums.length} albums',
          );
        } finally {
          http.close();
          HttpOverrides.global = old;
        }
        final data = ByteData.sublistView(
          await File('/System/Library/Fonts/STHeiti Light.ttc').readAsBytes(),
        );
        for (final family in [
          'FanQa',
          'Ahem',
          'Roboto',
          'PingFang SC',
          'Helvetica Neue',
          '.SF UI Text',
          '.SF UI Display',
        ]) {
          await (FontLoader(family)..addFont(Future.value(data))).load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        debugPrint('QA: fonts loaded');
        for (final path in photos) {
          final codec = await ui.instantiateImageCodec(
            await File(path).readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          PaintingBinding.instance.imageCache.putIfAbsent(
            FileImage(File(path)),
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: frame.image)),
            ),
          );
          codec.dispose();
        }
        debugPrint('QA: photos decoded');
        for (final name in ['paper', 'linen']) {
          final provider = ExactAssetImage(
            'assets/album/materials/$name.png',
            scale: 8,
          );
          final key = await provider.obtainKey(ImageConfiguration.empty);
          final data = await rootBundle.load(key.name);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          PaintingBinding.instance.imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: frame.image, scale: 8)),
            ),
          );
          codec.dispose();
        }
      });
      final catalog = CatalogBundle(
        idols: (bootstrap['idols'] as List)
            .map((v) => IdolProfile.fromJson(v))
            .toList(),
        groups: (bootstrap['groups'] as List)
            .map((v) => FanGroup.fromJson(v))
            .toList(),
        cards: (bootstrap['cards'] as List)
            .map((v) => CollectibleCard.fromJson(v))
            .toList(),
        albums: (bootstrap['albums'] as List)
            .map((v) => CatalogAlbum.fromJson(v))
            .toList(),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      final repo = _Albums(albums);
      var container = ProviderContainer();
      var captureKey = GlobalKey();
      Future<void> mount(Widget page, {double width = 390}) async {
        debugPrint('QA: mount ${page.runtimeType} at $width');
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        tester.view.physicalSize = Size(width, 844);
        container = ProviderContainer(
          overrides: [
            catalogRepositoryProvider.overrideWithValue(_Catalog(catalog)),
            feedbackRepositoryProvider.overrideWithValue(_Feedback(correction)),
            albumRepositoryProvider.overrideWithValue(repo),
            albumDraftStoreProvider.overrideWithValue(_Memory()),
            sessionProvider.overrideWith(_Session.new),
          ],
        );
        captureKey = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _qaTheme(),
                home: page,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        debugPrint('QA: capture $name');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (captureKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await mount(CardDetailPage(cardId: catalog.cards.first.id));
      expect(find.text('正面'), findsNothing);
      expect(find.text('背面'), findsNothing);
      await capture('01-card-detail');
      await tester.tap(find.byKey(const ValueKey('card-large-preview')));
      await tester.pump();
      if (catalog.cards.first.backImageUrl == null) {
        expect(find.text('暂无卡背信息'), findsOneWidget);
      }
      await mount(
        CorrectionPage(entityType: 'cards', entityId: catalog.cards.first.id),
      );
      expect(find.widgetWithText(CheckboxListTile, '名称'), findsNothing);
      expect(find.textContaining('当前：idol_'), findsNothing);
      await capture('02-correction');
      await tester.tap(find.widgetWithText(CheckboxListTile, '所属艺人'));
      await tester.pumpAndSettle();
      await capture('03-correction-expanded');
      final idol = catalog.idols.firstWhere((i) => i.name == 'Gaeul');
      await mount(IdolDetailPage(idolId: idol.id));
      await capture('04-artist-backdrop');
      await mount(const AlbumShelfPage());
      await capture('05-album-shelf');
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await capture('05b-album-stacked-cover');
      await mount(const AlbumCreatePage());
      await capture('06-new-album');
      final book = albums.firstWhere(
        (a) => !a.opensAsCards,
        orElse: () => albums.first,
      );
      // In-memory editor copy, never modify the person's real album.
      final copy = book.edit((d) {
        d['card_view'] = {...book.cardView, 'default_mode': 'BOOK'};
        d['is_owner'] = true;
      });
      albums[albums.indexOf(book)] = copy;
      for (final width in [360.0, 390.0, 430.0]) {
        repo.rows[repo.rows.indexWhere((a) => a.id == copy.id)] = copy;
        await mount(AlbumEditorPage(albumId: copy.id), width: width);
        expect(find.text('画笔'), findsOneWidget);
        expect(find.text('布局'), findsNothing);
        if (width == 390) await capture('07-cover-editor');
        final original = tester.getSize(find.byType(AlbumCanvasWidget).first);
        await tester.tap(find.text('背景'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(AlbumCanvasWidget).first).height,
          lessThan(original.height),
        );
        if (width == 390) await capture('08-background-panel');
        await tester.tap(find.byTooltip('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('文字'));
        await tester.pumpAndSettle();
        expect(find.byType(Slider), findsNothing);
        await tester.enterText(find.byType(TextField), '我的收藏故事');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(AlbumCanvasWidget).first).height,
          greaterThan(20),
        );
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        if (width == 390) await capture('09-text-panel');
        await tester.tap(find.byTooltip('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('画笔'));
        await tester.pumpAndSettle();
        await tester.dragFrom(
          tester.getCenter(find.byType(AlbumCanvasWidget).first),
          const Offset(45, 25),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlbumToolPanel),
            matching: find.text('完成'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          (container.read(albumEditorProvider(copy.id)).album!.cover['elements']
                  as List)
              .where((e) => e['type'] == 'STROKE'),
          isNotEmpty,
        );
        if (copy.pages.isNotEmpty) {
          await tester.tap(find.byTooltip('下一页'));
          await tester.pumpAndSettle();
          expect(find.text('文字'), findsNothing);
          expect(find.text('画笔'), findsNothing);
          expect(find.text('贴纸'), findsNothing);
          expect(find.text('布局'), findsOneWidget);
          if (width == 390) await capture('10-inner-page');
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      debugDisableShadows = shadows;
    },
    skip: !const bool.fromEnvironment('LOCAL_UI_QA'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

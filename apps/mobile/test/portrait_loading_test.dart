import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/core/data/name_preferences.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/widgets/portrait_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Keep widget timing deterministic; real filesystem caching is tested below.
class _WidgetPortraitCache extends PortraitCache {
  _WidgetPortraitCache()
    : super(
        directory: () async => throw UnimplementedError(),
        download: (_) async => throw UnimplementedError(),
      );

  int calls = 0;
  File? recoveredFile;
  File? _readyFile;

  @override
  File? peek(String url) => _readyFile;

  @override
  Future<File> get(String url) async {
    calls++;
    final file = recoveredFile;
    if (file == null) throw const SocketException('transient timeout');
    _readyFile = file;
    notifyListeners();
    return file;
  }

  @override
  Future<void> evict(String url) async => _readyFile = null;
}

void main() {
  testWidgets(
    'a recovered shared image refreshes an already-failed profile tile',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('portrait-sync'),
      ))!;
      final cache = _WidgetPortraitCache();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 100,
            height: 100,
            child: PortraitImage(
              url: 'https://example.test/yuqi.webp',
              cache: cache,
              fallback: const Text('loading'),
              errorFallback: const Text('failed'),
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('failed'), findsOneWidget);
      // A later detail view succeeds without rebuilding the earlier profile tab.
      cache.recoveredFile = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return File('${dir.path}/portrait.png')
            .writeAsBytes(data!.buffer.asUint8List());
      });
      await tester.runAsync(() => cache.get('https://example.test/yuqi.webp'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect(find.text('failed'), findsNothing);
      final future = tester.widget<FutureBuilder<File>>(
        find.byType(FutureBuilder<File>),
      );
      expect(future.future, isNotNull);
      expect(cache.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => dir.delete(recursive: true));
      cache.dispose();
    },
  );

  testWidgets('transient image requests retry once and cancel after disposal', (
    tester,
  ) async {
    final cache = _WidgetPortraitCache();
    await tester.pumpWidget(
      MaterialApp(
        home: PortraitImage(
          url: 'missing',
          cache: cache,
          fit: BoxFit.cover,
          fallback: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 5));
    expect(cache.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(cache.calls, 2);
    cache.dispose();
  });

  testWidgets('popular groups use full-card photos, mask and white text', (
    tester,
  ) async {
    final data = CatalogBundle(
      idols: [],
      cards: [],
      groups: [
        FanGroup.fromJson({
          'id': 'seventeen',
          'name': 'SEVENTEEN',
          'name_ko': '세븐틴',
          'image_url': '/private/tmp/fan-os-missing-portrait.jpg',
          'member_ids': ['a', 'b'],
        }),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogProvider.overrideWith((ref) async => data)],
        child: MaterialApp(theme: FanOsTheme.light, home: const CatalogPage()),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('popular-group-seventeen'));
    expect(
      find.descendant(of: card, matching: find.byType(CircleAvatar)),
      findsNothing,
    );
    final picture = tester.widget<FanImage>(
      find.descendant(of: card, matching: find.byType(FanImage)),
    );
    expect(picture.imageUrl, '/private/tmp/fan-os-missing-portrait.jpg');
    expect(picture.fit, BoxFit.cover);
    final texts = tester.widgetList<Text>(
      find.descendant(of: card, matching: find.byType(Text)),
    );
    expect(texts.every((text) => text.style?.color == Colors.white), isTrue);
    expect(tester.takeException(), isNull);
  });

  test('phone resolves legacy loopback uploads against the actual backend', () {
    const backend = 'http://192.168.0.112:8000/api/v1';
    expect(
      ApiClient.resolveMediaUrl(
        'http://localhost:8000/media/a.webp',
        backend: backend,
      ),
      'http://192.168.0.112:8000/media/a.webp',
    );
    expect(
      ApiClient.resolveMediaUrl(
        '/api/v1/catalog/images/idols/a?v=2',
        backend: backend,
      ),
      'http://192.168.0.112:8000/api/v1/catalog/images/idols/a?v=2',
    );
    expect(
      ApiClient.resolveMediaUrl(
        'https://external.example/a.jpg',
        backend: backend,
      ),
      'https://external.example/a.jpg',
    );
    expect(
      ApiClient.resolveMediaUrl('/private/tmp/photo.jpg', backend: backend),
      '/private/tmp/photo.jpg',
    );
  });

  test('portrait cache coalesces requests, survives reopening and changes versions', () async {
    final dir = await Directory.systemTemp.createTemp('portrait-test');
    addTearDown(() => dir.delete(recursive: true));
    var calls = 0;
    final response = Completer<List<int>>();
    final cache = PortraitCache(
      directory: () async => dir,
      download: (_) {
        calls++;
        return response.future;
      },
    );
    final first = cache.get('https://example.test/a?v=1');
    final second = cache.get('https://example.test/a?v=1');
    response.complete([1, 2, 3]);
    expect((await first).path, (await second).path);
    expect(calls, 1);
    final reopened = PortraitCache(
      directory: () async => dir,
      download: (_) async {
        calls++;
        return [4];
      },
    );
    expect(
      await (await reopened.get('https://example.test/a?v=1')).readAsBytes(),
      [1, 2, 3],
    );
    expect(calls, 1);
    await reopened.get('https://example.test/a?v=2');
    expect(calls, 2);
  });

  test('failed downloads can retry and do not poison disk cache', () async {
    final dir = await Directory.systemTemp.createTemp('portrait-retry');
    addTearDown(() => dir.delete(recursive: true));
    var calls = 0;
    final cache = PortraitCache(
      directory: () async => dir,
      download: (_) async {
        if (++calls == 1) throw const SocketException('offline');
        return [1];
      },
    );
    await expectLater(cache.get('image'), throwsA(isA<SocketException>()));
    expect(await (await cache.get('image')).readAsBytes(), [1]);
  });

  test(
    'name preferences preserve thumbnail without replacing full artwork',
    () {
      final idol = IdolProfile.fromJson({
        'id': 'a',
        'name': 'A',
        'image_url': 'full.jpg',
        'thumbnail_url': 'small.webp',
      });
      final data = const NamePreferences().apply(
        CatalogBundle(idols: [idol], groups: [], cards: []),
      );
      expect(data.idols.single.imageUrl, 'full.jpg');
      expect(data.idols.single.thumbnailUrl, 'small.webp');
    },
  );

  testWidgets(
    'network portraits show an immediate placeholder before the first frame',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 72,
            height: 72,
            child: FanImage(
              imageUrl: 'https://example.test/image.jpg',
              fallback: Text('头像占位'),
            ),
          ),
        ),
      );
      expect(find.text('头像占位'), findsOneWidget);
      await tester.pump();
      expect(find.text('头像占位'), findsOneWidget);
    },
  );
}

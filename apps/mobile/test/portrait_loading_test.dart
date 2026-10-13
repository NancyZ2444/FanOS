import 'dart:async';
import 'dart:io';

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/name_preferences.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/widgets/portrait_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

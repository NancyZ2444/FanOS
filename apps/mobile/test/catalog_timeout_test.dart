import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_profile_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _empty = CatalogBundle(
  idols: [],
  groups: [],
  cards: [],
  albums: [],
  events: [],
  others: [],
);

class _StallingAdapter implements HttpClientAdapter {
  bool respond = false;
  Duration responseDelay = Duration.zero;
  int cancelled = 0;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    cancelFuture?.then((_) {
      cancelled++;
    });
    if (!respond) return Completer<ResponseBody>().future;
    return Future.delayed(
      responseDelay,
      () => ResponseBody.fromString(
        '{"code":0,"data":{"fields":[],"items":[],"next_offset":null}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecoveringCatalog implements CatalogRepository {
  final pending = Completer<CatalogBundle>();
  bool recover = false;
  int calls = 0;
  @override
  Future<CatalogBundle> fetchCatalog() {
    calls++;
    return recover ? Future.value(_empty) : pending.future;
  }
}

void main() {
  for (final path in [
    '/catalog',
    '/catalog/bootstrap',
    '/catalog/profiles/GROUP/g',
    '/catalog/profiles/IDOL/i/history',
    '/catalog/profiles/IDOL/i/revisions/r',
  ]) {
    test('catalog read $path times out and cancels hung transport', () async {
      final adapter = _StallingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final api = ApiClient(
        dio: dio,
        catalogRequestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        api.getData(path, authenticated: false),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'timeout code',
            'REQUEST_TIMEOUT',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.receiveTimeout,
        const Duration(milliseconds: 20),
      );
      expect(adapter.cancelled, 1);
      dio.close(force: true);
    });
  }

  test(
    'catalog deadlines do not shorten slow scanning POST or noncatalog reads',
    () async {
      final adapter = _StallingAdapter()
        ..respond = true
        ..responseDelay = const Duration(milliseconds: 35);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final api = ApiClient(
        dio: dio,
        catalogRequestTimeout: const Duration(milliseconds: 5),
      );
      final scan = await api.postData(
        '/scan/recognize',
        receiveTimeout: const Duration(seconds: 120),
        authenticated: false,
      );
      expect(scan, isA<Map>());
      expect(
        adapter.requests.single.receiveTimeout,
        const Duration(seconds: 120),
      );
      expect(await api.getData('/catalogue', authenticated: false), isA<Map>());
      expect(
        await api.getData('/auth/capabilities', authenticated: false),
        isA<Map>(),
      );
      expect(adapter.cancelled, 0);
      dio.close(force: true);
    },
  );

  test(
    'profile timeout remains an error until explicit retry and then recovers',
    () async {
      final adapter = _StallingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final api = ApiClient(
        dio: dio,
        catalogRequestTimeout: const Duration(milliseconds: 20),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      final provider = catalogProfileProvider('GROUP/g');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
        dio.close(force: true);
      });
      await expectLater(
        container.read(provider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(provider).isLoading, isFalse);
      expect(container.read(provider).hasError, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        adapter.requests,
        hasLength(1),
        reason: 'No automatic retry spinner after failure',
      );
      adapter.respond = true;
      container.invalidate(provider);
      final recovered = await container.read(provider.future);
      expect(recovered['fields'], isEmpty);
      expect(container.read(provider).hasError, isFalse);
    },
  );

  testWidgets(
    'catalog aggregate never-ending future leaves loading, shows failure, then retry recovers',
    (tester) async {
      final repository = _RecoveringCatalog();
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
          catalogLoadTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 100),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const CatalogPage(),
          ),
        ),
      );
      expect(container.read(catalogProvider).isLoading, isTrue);
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pump();
      expect(container.read(catalogProvider).isLoading, isFalse);
      expect(container.read(catalogProvider).hasError, isTrue);
      expect(find.byKey(const Key('catalog-load-error')), findsOneWidget);
      expect(find.byKey(const Key('catalog-groups-empty')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.calls, 1);
      repository.recover = true;
      await tester.ensureVisible(find.text('重新加载').first);
      await tester.tap(find.text('重新加载').first);
      await tester.pumpAndSettle();
      expect(repository.calls, 2);
      expect(container.read(catalogProvider).hasError, isFalse);
      expect(find.byKey(const Key('catalog-load-error')), findsNothing);
      expect(find.byKey(const Key('catalog-groups-empty')), findsOneWidget);
      repository.pending.completeError(StateError('late old request failure'));
      await tester.pump();
      expect(container.read(catalogProvider).hasError, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

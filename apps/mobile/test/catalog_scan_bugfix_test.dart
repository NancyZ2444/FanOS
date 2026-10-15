import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/name_preferences.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/catalog/presentation/catalog_entity_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const backend = 'http://cloud.example:5173/api/v1';

ApiClient responseClient(
  Object data, {
  int status = 200,
  DioExceptionType? failure,
}) {
  final dio = Dio(BaseOptions(baseUrl: backend));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        final response = Response<Object>(
          requestOptions: request,
          data: data,
          statusCode: status,
        );
        if (status >= 400 || failure != null) {
          handler.reject(
            DioException(
              requestOptions: request,
              response: failure == null ? response : null,
              type: failure ?? DioExceptionType.badResponse,
            ),
          );
        } else {
          handler.resolve(response);
        }
      },
    ),
  );
  return ApiClient(dio: dio);
}

Future<CatalogBundle> catalog() => ApiCatalogRepository(
  responseClient({
    'code': 0,
    'data': {
      'groups': [
        {
          'id': 'g',
          'name': 'Group',
          'member_ids': ['a', 'hidden'],
          'former_member_ids': ['d'],
          'image_url': ' ',
          'cover_image': '/media/group.webp',
        },
      ],
      'idols': [
        {
          'id': 'a',
          'name': 'Artist A',
          'group_ids': ['g'],
          'image_url': '',
          'cover_image': '/media/a.webp',
        },
        {'id': 'b', 'name': 'Artist B', 'group_id': 'g'},
        {
          'id': 'c',
          'name': 'Artist C',
          'group_id': 'g',
          'membership_history': [
            {'group_id': 'g', 'status': 'former'},
          ],
        },
        {
          'id': 'd',
          'name': 'Artist D',
          'membership_history': [
            {'group_id': 'g', 'status': 'former'},
            {'group_id': 'g', 'status': 'active'},
          ],
        },
        {'id': 'unrelated', 'name': 'Artist E', 'group_name': 'Group'},
      ],
      'cards': [],
      'albums': [],
      'events': [],
      'others': [],
    },
  }),
).fetchCatalog();

void main() {
  test('published members resolve all ID relationships, never names or former membership', () async {
    final data = await catalog();
    expect(data.groups.single.memberIds, ['a', 'b', 'd']);
    expect(data.groups.single.formerMemberIds, ['c']);
    final named = const NamePreferences().apply(data);
    expect(
      named.groups.single.imageUrl,
      'http://cloud.example:5173/media/group.webp',
    );
    expect(named.groups.single.coverImageUrl, named.groups.single.imageUrl);
    expect(
      named.idols.first.imageUrl,
      'http://cloud.example:5173/media/a.webp',
    );
    expect(named.idols.first.coverImageUrl, named.idols.first.imageUrl);
  });

  test('media URLs use actual client origin including old thumbnail and backend port', () async {
    for (final input in [
      'http://localhost:8000/media/a.webp',
      'http://cloud.example:8000/media/a.webp',
      '/media/a.webp',
    ]) {
      expect(
        ApiClient.resolveMediaUrl(input, backend: backend),
        'http://cloud.example:5173/media/a.webp',
      );
    }
    expect(
      ApiClient.resolveMediaUrl(
        'http://localhost:8000/api/v1/catalog/images/idols/a?v=2',
        backend: backend,
      ),
      'http://cloud.example:5173/api/v1/catalog/images/idols/a?v=2',
    );
    expect(
      ApiClient.resolveMediaUrl(
        'https://cdn.example/media/a.webp',
        backend: backend,
      ),
      'https://cdn.example/media/a.webp',
    );
  });

  testWidgets(
    'group page renders recovered current and former members separately',
    (tester) async {
      final data = (await tester.runAsync(catalog))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [catalogProvider.overrideWith((ref) async => data)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const GroupDetailPage(groupId: 'g'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前成员 (3)'), findsOneWidget);
      expect(find.text('Artist A'), findsOneWidget);
      expect(find.text('Artist B'), findsOneWidget);
      expect(find.text('Artist D'), findsOneWidget);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(find.text('过往成员 (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'album uses a single current cover even with legacy front and back images',
    (tester) async {
      final album = CatalogAlbum.fromJson({
        'id': 'album',
        'name': 'Album',
        'image_url': '/media/current.jpg',
        'front_image_url': '/media/old.jpg',
        'back_image_url': '/media/back.jpg',
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(
              (ref) async => CatalogBundle(
                groups: [],
                idols: [],
                cards: [],
                albums: [album],
              ),
            ),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const CatalogEntityDetailPage(
              type: CatalogEntityDetailType.album,
              entityId: 'album',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('正面'), findsNothing);
      expect(find.text('背面'), findsNothing);
      expect(
        tester.widget<FanArtwork>(find.byType(FanArtwork).first).imageUrl,
        '/media/current.jpg',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [404, 405]) {
    test(
      'missing scan API $status explains deployment and never falls back to eager matching',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'scan-api-test',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = await File('${directory.path}/photo.jpg')
            .writeAsBytes([1, 2, 3]);
        final repo = ApiScanDetectionRepository(
          responseClient({'detail': 'Not Found'}, status: status),
        );
        await expectLater(
          repo.detect(file.path),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', 'SCAN_API_UPGRADE_REQUIRED')
                .having((e) => e.message, 'message', contains('照片已保留')),
          ),
        );
      },
    );
  }

  test('domain scan failures keep their precise reason', () async {
    final repo = ApiScanDetectionRepository(
      responseClient({
        'error_code': 'SCAN_INDEX_UNAVAILABLE',
        'message': '请先建立小卡索引',
      }, status: 503),
    );
    await expectLater(
      repo.recognize(const ScanDetection(sessionId: 's', regions: []), {'d'}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'SCAN_INDEX_UNAVAILABLE',
        ),
      ),
    );
  });

  for (final entry in {
    401: 'AUTH_REQUIRED',
    413: 'UPLOAD_TOO_LARGE',
    502: 'SERVICE_UNAVAILABLE',
    504: 'REQUEST_TIMEOUT',
  }.entries) {
    test(
      'HTTP ${entry.key} is not mislabeled as a generic network failure',
      () async {
        await expectLater(
          responseClient(
            '<html>error</html>',
            status: entry.key,
          ).getData('/test'),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', entry.value),
          ),
        );
      },
    );
  }
  test('upload timeout preserves actionable retry error', () async {
    await expectLater(
      responseClient(
        {},
        failure: DioExceptionType.sendTimeout,
      ).postData('/scan/detect'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'REQUEST_TIMEOUT'),
      ),
    );
  });
}

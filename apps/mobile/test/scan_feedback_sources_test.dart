import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/data/scan_feedback_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/state/scan_feedback_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _album = ScanFeedbackSourceOption(
  id: 'album-starlit',
  name: 'Starlit',
  entityType: 'ALBUM',
  subtitle: 'LUMINA · 2026.08.16',
  versions: [
    ScanFeedbackSourceVersion(id: 'canonical-version-1', name: 'Moon Ver.'),
  ],
);
const _event = ScanFeedbackSourceOption(
  id: 'event-live',
  name: 'Official Live Tour',
  entityType: 'EVENT',
);

void main() {
  test(
    'feedback stores canonical source IDs and history includes official names',
    () {
      final args = _args();
      final request = ScanFeedbackRequest(
        sessionId: args.session.id,
        detectedCardId: args.detectedCard.id,
        cropRegion: args.detectedCard.cropRegion,
        candidates: args.detectedCard.candidates,
        source: '专辑',
        sourceEntityType: 'ALBUM',
        sourceEntityId: _album.id,
        sourceVersionId: _album.versions.single.id,
      );
      expect(request.toJson()['source_mode'], 'KNOWN');
      expect(request.toJson()['source_entity_id'], 'album-starlit');
      expect(request.toJson()['source_version_id'], 'canonical-version-1');
      final record = ScanFeedbackRecord.fromJson({
        'id': 'feedback-1',
        'status': 'pending',
        'created_at': '2026-10-11T00:00:00Z',
        'updated_at': '2026-10-11T00:00:00Z',
        'source_mode': 'KNOWN',
        'source': '专辑',
        'source_entity_type': 'ALBUM',
        'source_entity_id': _album.id,
        'source_version_id': 'canonical-version-1',
        'source_name': 'Starlit',
        'source_version_name': 'Moon Ver.',
      });
      expect(record.sourceName, 'Starlit');
      expect(record.sourceVersionName, 'Moon Ver.');
    },
  );

  test('mock official options honor group, idol, source type and mock-only versions', () async {
    final repository = MockScanFeedbackOptionsRepository();
    final albums = await repository.fetchOptions(
      source: '专辑',
      groupId: 'group-lumina',
      idolId: 'idol-aria',
    );
    expect(albums.map((item) => item.id), ['album-starlit', 'album-blue-hour']);
    expect(albums.first.versions.first.id, startsWith('mock-'));
    expect(
      await repository.fetchOptions(
        source: '专辑',
        groupId: 'group-aster',
        idolId: 'idol-aria',
      ),
      isEmpty,
    );
    final concerts = await repository.fetchOptions(
      source: '演唱会',
      groupId: 'group-nova',
    );
    expect(concerts, hasLength(2));
    expect(concerts.map((item) => item.entityType), everyElement('EVENT'));
  });

  test('API options keep server version IDs and missing content is a review request', () async {
    final client = _Client();
    final repository = ApiScanFeedbackOptionsRepository(client);
    final options = await repository.fetchOptions(
      source: '专辑',
      groupId: 'g1',
      idolId: 'i1',
    );
    expect(client.path, '/scan/feedback-options');
    expect(client.query, {'source': '专辑', 'group_id': 'g1', 'idol_id': 'i1'});
    expect(options.single.versions.single.id, 'canonical-version-1');
    await repository.submitCatalogMissing(
      const CatalogMissingFeedbackRequest(
        entityType: 'albums',
        reason: '缺失版本',
        suggested: {'name': 'New Ver.'},
      ),
    );
    expect(client.path, '/catalog/feedback');
    expect((client.payload as Map)['entity_id'], '');
    expect((client.payload as Map)['suggested'], {'name': 'New Ver.'});
  });

  testWidgets('choose official album and version then submit exact IDs', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await _selectSource(tester, '专辑');
    await tester.ensureVisible(
      find.byKey(const Key('scan-feedback-official-picker')),
    );
    await tester.tap(find.byKey(const Key('scan-feedback-official-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scan-feedback-source-search')),
      'Starlit',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('official-source-album-starlit')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('source-version-album-starlit')),
    );
    await tester.tap(
      find.byKey(const ValueKey('source-version-album-starlit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moon Ver.').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('submit-scan-feedback')));
    await tester.tap(find.byKey(const Key('submit-scan-feedback')));
    await tester.pumpAndSettle();
    expect(fixture.scans.submissions.single.sourceEntityId, _album.id);
    expect(
      fixture.scans.submissions.single.sourceVersionId,
      'canonical-version-1',
    );
    expect(fixture.scans.submissions.single.sourceMode, 'KNOWN');
    expect(find.text('反馈历史测试页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uncertain and other require notes without sending official IDs',
    (tester) async {
      final fixture = await _mount(tester);
      await _selectSource(tester, '不确定');
      await tester.ensureVisible(find.byKey(const Key('submit-scan-feedback')));
      await tester.tap(find.byKey(const Key('submit-scan-feedback')));
      await tester.pump();
      expect(fixture.scans.submissions, isEmpty);
      expect(find.text('请补充备注，帮助我们核实小卡来源'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('scan-feedback-notes')),
        '不确定来源，2023 年获得',
      );
      await tester.ensureVisible(find.byKey(const Key('submit-scan-feedback')));
      await tester.tap(find.byKey(const Key('submit-scan-feedback')));
      await tester.pumpAndSettle();
      final submission = fixture.scans.submissions.single;
      expect(submission.sourceMode, 'UNCERTAIN');
      expect(submission.source, '不确定');
      expect(submission.sourceEntityId, isNull);
      expect(submission.sourceVersionId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late options from previous source cannot overwrite current choices',
    (tester) async {
      final options = _Options()..delayAlbums = true;
      final fixture = await _mount(tester, options: options);
      await _selectSource(tester, '专辑', settle: false);
      await _selectSource(tester, '活动');
      options.albums.complete([_album]);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('scan-feedback-official-picker')),
      );
      await tester.tap(find.byKey(const Key('scan-feedback-official-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Official Live Tour'), findsOneWidget);
      expect(find.text('Starlit'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('official-source-event-live')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-feedback-other')));
      await tester.tap(find.byKey(const Key('scan-feedback-other')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('scan-feedback-notes')),
        '有活动来源，但官方内容不全',
      );
      await tester.ensureVisible(find.byKey(const Key('submit-scan-feedback')));
      await tester.tap(find.byKey(const Key('submit-scan-feedback')));
      await tester.pumpAndSettle();
      expect(fixture.scans.submissions.single.sourceMode, 'OTHER');
      expect(fixture.scans.submissions.single.sourceEntityId, isNull);
      expect(fixture.scans.submissions.single.sourceVersionId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('official options reload with selected group and idol filters', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final group = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '所属组合',
    );
    await tester.enterText(group, 'LUMINA');
    await tester.pumpAndSettle();
    await tester.tap(find.text('LUMINA').last);
    await tester.pumpAndSettle();
    await _selectSource(tester, '专辑');
    expect(fixture.options.queries.last, {
      'source': '专辑',
      'group_id': 'group-lumina',
      'idol_id': null,
    });
    final idol = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Idol',
    );
    await tester.ensureVisible(idol);
    await tester.enterText(idol, 'Aria');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aria · LUMINA').last);
    await tester.pumpAndSettle();
    expect(fixture.options.queries.last, {
      'source': '专辑',
      'group_id': 'group-lumina',
      'idol_id': 'idol-aria',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'official options failure can retry without losing notes or source',
    (tester) async {
      final options = _Options()..fail = true;
      final fixture = await _mount(tester, options: options);
      await tester.ensureVisible(find.byKey(const Key('scan-feedback-notes')));
      await tester.enterText(
        find.byKey(const Key('scan-feedback-notes')),
        '网络失败仍保留备注',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _selectSource(tester, '专辑');
      expect(find.text('官方来源加载失败，请重试或反馈缺失内容。'), findsOneWidget);
      options.fail = false;
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scan-feedback-official-picker')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('scan-feedback-notes')))
            .controller!
            .text,
        '网络失败仍保留备注',
      );
      expect(fixture.options.queries, hasLength(2));
      expect(fixture.options.queries.last['source'], '专辑');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing album version preserves scan form and carries crop association',
    (tester) async {
      final fixture = await _mount(tester);
      await _selectSource(tester, '专辑');
      await tester.ensureVisible(
        find.byKey(const Key('scan-feedback-official-picker')),
      );
      await tester.tap(find.byKey(const Key('scan-feedback-official-picker')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('official-source-album-starlit')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-feedback-notes')));
      await tester.enterText(
        find.byKey(const Key('scan-feedback-notes')),
        '原扫描备注，稍后继续处理',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('scan-feedback-missing-version')),
      );
      await tester.tap(find.byKey(const Key('scan-feedback-missing-version')));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogMissingFeedbackPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('catalog-missing-name')),
        'Signed Ver.',
      );
      await tester.enterText(
        find.byKey(const Key('catalog-missing-notes')),
        '官方已公布签名版本，图鉴暂无',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('submit-catalog-missing-feedback')),
      );
      await tester.tap(
        find.byKey(const Key('submit-catalog-missing-feedback')),
      );
      await tester.pumpAndSettle();
      final contribution = fixture.options.missing.single;
      expect(contribution.entityType, 'albums');
      expect(contribution.entityId, 'album-starlit');
      expect(contribution.suggested['missing_kind'], 'ALBUM_VERSION');
      expect(contribution.suggested['scan_session_id'], 'feedback-scan');
      expect(contribution.suggested['detected_card_id'], 'feedback-region');
      expect(contribution.suggested['crop_region'], {
        'x': .1,
        'y': .2,
        'width': .3,
        'height': .4,
      });
      expect(find.byType(CatalogMissingFeedbackPage), findsNothing);
      expect(find.text('Starlit'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('scan-feedback-notes')))
            .controller!
            .text,
        '原扫描备注，稍后继续处理',
      );
      expect(fixture.scans.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

ScanFeedbackRouteArgs _args() {
  const region = DetectedScanCard(
    id: 'feedback-region',
    cropRegion: ScanCropRegion(x: .1, y: .2, width: .3, height: .4),
    candidates: [],
    status: ScanRecognitionStatus.unrecognized,
  );
  return const ScanFeedbackRouteArgs(
    session: ScanSession(id: 'feedback-scan', detectedCards: [region]),
    detectedCard: region,
  );
}

Future<({_Scans scans, _Options options})> _mount(
  WidgetTester tester, {
  _Options? options,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final scans = _Scans();
  final sources = options ?? _Options();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      catalogRepositoryProvider.overrideWithValue(_Catalog()),
      scanRepositoryProvider.overrideWithValue(scans),
      scanFeedbackOptionsRepositoryProvider.overrideWithValue(sources),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.notifier).login(LoginMethod.phone);
  final router = GoRouter(
    initialLocation: '/feedback',
    routes: [
      GoRoute(
        path: '/feedback',
        builder: (_, _) => ScanFeedbackPage(args: _args()),
      ),
      GoRoute(
        path: '/scan-feedback-history',
        builder: (_, _) => const Scaffold(body: Text('反馈历史测试页')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: FanOsTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (scans: scans, options: sources);
}

Future<void> _selectSource(
  WidgetTester tester,
  String source, {
  bool settle = true,
}) async {
  final field = find.byKey(const Key('scan-feedback-source'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  // Do not wait for an outstanding official-options request from a preceding
  // source: the progress indicator deliberately remains animated.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(source).last);
  await tester.pump(const Duration(milliseconds: 400));
  if (settle) await tester.pumpAndSettle();
}

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _Catalog implements CatalogRepository {
  @override
  Future<CatalogBundle> fetchCatalog() async => DemoCatalog.bundle;
}

class _Scans extends MockScanRepository {
  final submissions = <ScanFeedbackRequest>[];
  @override
  Future<void> submitFeedback(ScanFeedbackRequest request) async {
    submissions.add(request);
  }
}

class _Options implements ScanFeedbackOptionsRepository {
  bool delayAlbums = false;
  bool fail = false;
  final albums = Completer<List<ScanFeedbackSourceOption>>();
  final missing = <CatalogMissingFeedbackRequest>[];
  final queries = <Map<String, String?>>[];
  @override
  Future<List<ScanFeedbackSourceOption>> fetchOptions({
    required String source,
    String? groupId,
    String? idolId,
  }) async {
    queries.add({'source': source, 'group_id': groupId, 'idol_id': idolId});
    if (fail) throw StateError('offline-options-fixture');
    if (source == '专辑') return delayAlbums ? albums.future : [_album];
    return [_event];
  }

  @override
  Future<void> submitCatalogMissing(
    CatalogMissingFeedbackRequest request,
  ) async {
    missing.add(request);
  }
}

class _Client extends ApiClient {
  String? path;
  Map<String, dynamic>? query;
  Object? payload;
  @override
  Future<dynamic> getData(String path, {Map<String, dynamic>? query}) async {
    this.path = path;
    this.query = query;
    return {
      'items': [
        {
          'id': 'album-starlit',
          'name': 'Starlit',
          'entity_type': 'ALBUM',
          'versions': [
            {'id': 'canonical-version-1', 'name': 'Moon Ver.'},
          ],
        },
      ],
    };
  }

  @override
  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
  }) async {
    this.path = path;
    payload = data;
    return {'id': 'feedback-review', 'status': 'PENDING'};
  }
}

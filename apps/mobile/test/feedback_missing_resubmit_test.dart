import 'feedback_test_image.dart';

import 'dart:convert';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/data/scan_feedback_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/feedback/missing_card_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/state/scan_feedback_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Repository extends FeedbackRepository {
  _Repository() : super(ApiClient());
  final requests = <FeedbackJson>[];
  final paths = <String>[];
  bool failNext = false;
  String? imagePath;
  final crops = <FeedbackJson>[];
  FeedbackJson row = {
    'id': 'fb-needs-info',
    'kind': 'MISSING_CARD',
    'entity_type': 'cards',
    'entity_id': '',
    'name': '小卡缺失反馈',
    'image_url': null,
    'status': 'PROCESSED',
    'result': 'NEEDS_INFO',
    'status_label': '信息缺失待补充',
    'revision': 4,
    'can_resubmit': true,
    'public_note': '请补充购买渠道和背面图片',
    'created_at': '2026-10-20T10:00:00Z',
    'updated_at': '2026-10-20T10:10:00Z',
    'target_available': false,
    'submission': {
      'missing': {
        'group_id': 'group-lumina',
        'idol_id': 'idol-aria',
        'is_group_pc': false,
        'is_double_sided': false,
        'source_entity_type': 'ALBUM',
        'source_entity_id': 'album-starlit',
        'source_version_id': 'legacy-version-before-draft',
        'source_version_name': 'Moon Ver.',
      },
      'scan': {
        'scan_session_id': 'scan-original',
        'detected_card_id': 'detected-original',
        'original_image_url': null,
        'crop_image_url': null,
      },
      'front': {'id': 'image-original', 'image_url': null},
      'back': null,
      'notes': '原始提交说明',
      'links': ['https://example.com/original'],
      'evidence': [
        {'id': 'evidence-original', 'image_url': null},
      ],
    },
    'history': [
      {'note': '已收到反馈', 'at': '2026-10-20T10:00:00Z'},
      {'note': '请补充购买渠道和背面图片', 'at': '2026-10-20T10:10:00Z'},
    ],
    'decisions': <dynamic>[],
  };

  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async =>
      jsonDecode(jsonEncode(row)) as FeedbackJson;

  @override
  Future<FeedbackJson?> pickImage() async => {
    'id': 'image-added-back',
    'image_url': imagePath,
  };

  @override
  Future<FeedbackJson> post(String path, FeedbackJson body) async {
    if (path == '/images/crop') {
      crops.add(body);
      return {'id': 'image-added-back', 'image_url': imagePath};
    }
    paths.add(path);
    requests.add(jsonDecode(jsonEncode(body)) as FeedbackJson);
    if (failNext) {
      failNext = false;
      throw const ApiException('TEMPORARY', '网络暂时不可用，请重试');
    }
    row = {
      ...row,
      'status': 'PENDING',
      'result': 'PENDING',
      'status_label': '待处理',
      'revision': 5,
      'can_resubmit': false,
      'public_note': '已收到补充信息，等待平台核实',
      'submission': {
        ...row['submission'] as Map,
        'notes': body['notes'],
        'missing': body['missing'],
      },
    };
    return row;
  }
}

class _Options extends MockScanFeedbackOptionsRepository {
  @override
  Future<List<ScanFeedbackSourceOption>> fetchOptions({
    required String source,
    String? groupId,
    String? idolId,
  }) async => const [
    ScanFeedbackSourceOption(
      id: 'album-starlit',
      name: 'Starlit',
      entityType: 'ALBUM',
      versions: [
        ScanFeedbackSourceVersion(id: 'canonical-version-1', name: 'Moon Ver.'),
      ],
    ),
  ];
}

Future<void> _mount(
  WidgetTester tester,
  _Repository repository, {
  String location = '/feedback/fb-needs-info',
  bool returnToResult = false,
  ValueChanged<bool?>? onReturned,
}) async {
  final router = GoRouter(
    initialLocation: returnToResult ? '/return-test' : location,
    routes: [
      GoRoute(
        path: '/return-test',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await context.push<bool>('/scan-feedback');
              onReturned?.call(result);
            },
            child: const Text('原扫描对象'),
          ),
        ),
      ),
      GoRoute(
        path: '/scan-feedback',
        builder: (_, _) {
          const detected = DetectedScanCard(
            id: 'new-unrecognized-card',
            cropRegion: ScanCropRegion(x: 0, y: 0, width: 1, height: 1),
            candidates: [],
            status: ScanRecognitionStatus.unrecognized,
          );
          return MissingCardFeedbackPage(
            args: ScanFeedbackRouteArgs(
              session: const ScanSession(
                id: 'new-scan',
                detectedCards: [detected],
              ),
              detectedCard: detected,
              returnToResult: returnToResult,
            ),
          );
        },
      ),
      GoRoute(
        path: '/feedback/:id/supplement',
        builder: (_, state) =>
            MissingCardFeedbackPage(feedbackId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/feedback/:id',
        builder: (_, state) =>
            FeedbackDetailPage(id: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(repository),
        scanFeedbackOptionsRepositoryProvider.overrideWithValue(_Options()),
        catalogProvider.overrideWith((ref) async => DemoCatalog.bundle),
      ],
      child: MaterialApp.router(theme: FanOsTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final returnToResult in [false, true]) {
    testWidgets(
      'unrecognized scan submits full metadata, return to result: $returnToResult',
      (tester) async {
        final repository = _Repository();
        bool? returned;
        await _mount(
          tester,
          repository,
          location: '/scan-feedback',
          returnToResult: returnToResult,
          onReturned: (value) => returned = value,
        );
        if (returnToResult) {
          await tester.tap(find.text('原扫描对象'));
          await tester.pumpAndSettle();
        }
        Future<void> select(Finder field, String label) async {
          await tester.scrollUntilVisible(
            field,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await Scrollable.ensureVisible(tester.element(field), alignment: .2);
          await tester.pumpAndSettle();
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await select(find.byKey(const ValueKey('group-null')), 'LUMINA');
        await select(
          find.byKey(const ValueKey('idol-group-lumina-null')),
          DemoCatalog.idols.first.displayName,
        );
        await select(
          find.byKey(const Key('missing-feedback-source-type')),
          '专辑',
        );
        await select(
          find.byKey(
            const ValueKey('source-ALBUM-group-lumina-idol-aria-null'),
          ),
          'Starlit',
        );
        await select(
          find.byKey(const ValueKey('version-album-starlit')),
          'Moon Ver.',
        );
        final links = find.byKey(const Key('missing-feedback-links'));
        await tester.scrollUntilVisible(
          links,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(links, 'test');
        final submit = find.byKey(const Key('submit-missing-feedback'));
        await tester.scrollUntilVisible(
          submit,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repository.requests, isEmpty);
        expect(
          find.textContaining('请填写完整的 http:// 或 https:// 链接'),
          findsWidgets,
        );
        await tester.enterText(links, 'https://example.com/source');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repository.paths, ['']);
        final payload = repository.requests.single;
        expect(payload['kind'], 'MISSING_CARD');
        expect(payload['missing'], containsPair('scan_session_id', 'new-scan'));
        expect(
          payload['missing'],
          containsPair('detected_card_id', 'new-unrecognized-card'),
        );
        expect(payload['missing'], containsPair('group_id', 'group-lumina'));
        expect(payload['missing'], containsPair('idol_id', 'idol-aria'));
        expect(
          payload['missing'],
          containsPair('source_entity_id', 'album-starlit'),
        );
        expect(
          payload['missing'],
          containsPair('source_version_id', 'canonical-version-1'),
        );
        if (returnToResult) {
          expect(returned, isTrue);
          expect(find.text('原扫描对象'), findsOneWidget);
          expect(find.text('反馈进度'), findsNothing);
        } else {
          expect(find.text('反馈进度'), findsOneWidget);
          expect(find.text('待处理'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'image replacement opens crop and cancelling preserves original data',
    (tester) async {
      final repository = _Repository();
      repository.imagePath = await feedbackTestImage(tester);
      await _mount(tester, repository, location: '/scan-feedback');
      await tester.tap(find.byKey(const Key('missing-upload-back')));
      await waitForFeedbackCrop(tester);
      expect(find.text('裁剪背面'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repository.crops, isEmpty);
      expect(find.byKey(const Key('missing-crop-back')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supplement restores prior scan and fields, retries then returns to same record',
    (tester) async {
      final repository = _Repository()..failNext = true;
      repository.imagePath = await feedbackTestImage(tester);
      await _mount(tester, repository);
      await tester.ensureVisible(find.byKey(const Key('supplement-feedback')));
      await tester.tap(find.byKey(const Key('supplement-feedback')));
      await tester.pumpAndSettle();
      expect(find.text('补充小卡信息'), findsOneWidget);
      expect(find.text('平台需要你补充：请补充购买渠道和背面图片'), findsOneWidget);
      expect(find.text('更换正面'), findsNothing);
      expect(find.text('更换背面'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('missing-front-preview'))),
        tester.getSize(find.byKey(const Key('missing-back-preview'))),
      );
      await tester.tap(find.byKey(const Key('missing-upload-back')));
      await waitForFeedbackCrop(tester);
      await tester.tap(find.byKey(const Key('feedback-crop-confirm')));
      await tester.pumpAndSettle();
      final crop = repository.crops.single['crop'] as List;
      expect(crop[2] / crop[3], closeTo(55 / 85, .000001));
      final notes = find.byKey(const Key('missing-feedback-notes'));
      await tester.scrollUntilVisible(
        notes,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<TextField>(notes).controller!.text, '原始提交说明');
      // The form is lazy; restored canonical values are checked in the payload below.
      await tester.enterText(notes, '补充渠道：官方专辑预购，背面图片已上传');
      final submit = find.byKey(const Key('submit-missing-feedback'));
      await tester.scrollUntilVisible(
        submit,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('补充小卡信息'), findsOneWidget);
      expect(
        tester.widget<TextField>(notes).controller!.text,
        '补充渠道：官方专辑预购，背面图片已上传',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.paths, [
        '/records/fb-needs-info/resubmit',
        '/records/fb-needs-info/resubmit',
      ]);
      final body = repository.requests.last;
      expect(body['revision'], 4);
      expect(body['request_key'], repository.requests.first['request_key']);
      expect(body['missing'], containsPair('scan_session_id', 'scan-original'));
      expect(
        body['missing'],
        containsPair('detected_card_id', 'detected-original'),
      );
      expect(
        body['missing'],
        containsPair('source_entity_id', 'album-starlit'),
      );
      expect(
        body['missing'],
        containsPair('source_version_id', 'canonical-version-1'),
      );
      expect(body['missing'], containsPair('front_image_id', 'image-original'));
      expect(
        body['missing'],
        containsPair('back_image_id', 'image-added-back'),
      );
      expect(body['evidence_ids'], ['evidence-original']);
      expect(body['links'], ['https://example.com/original']);
      expect(find.text('反馈进度'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('待处理'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('待处理'), findsOneWidget);
      expect(find.byKey(const Key('supplement-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected submission is retained without a supplement action', (
    tester,
  ) async {
    final repository = _Repository();
    repository.row.addAll({
      'result': 'NOT_INCLUDED',
      'status_label': '无法采用',
      'can_resubmit': false,
      'public_note': '图片不是官方小卡，无法收录',
    });
    await _mount(tester, repository);
    expect(find.text('无法采用'), findsOneWidget);
    expect(find.text('图片不是官方小卡，无法收录'), findsOneWidget);
    expect(find.text('本次反馈无法采用，你提交的图片、信息及处理记录仍保留在这里。'), findsOneWidget);
    expect(find.byKey(const Key('supplement-feedback')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('原始提交说明'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('原始提交说明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adopted submission opens official catalog and cannot be resubmitted',
    (tester) async {
      final repository = _Repository();
      repository.row.addAll({
        'result': 'INCLUDED',
        'status_label': '已采用',
        'can_resubmit': false,
        'entity_id': 'card-published',
        'target_available': true,
        'public_note': '已登记为官方图鉴',
      });
      await _mount(tester, repository);
      expect(find.text('已采用'), findsOneWidget);
      expect(find.text('已采用并登记为官方图鉴，可查看收录结果。'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('查看图鉴内容'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('查看图鉴内容'), findsOneWidget);
      expect(find.byKey(const Key('supplement-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct supplement route refuses feedback that no longer needs information',
    (tester) async {
      final repository = _Repository();
      repository.row.addAll({'can_resubmit': false, 'result': 'PENDING'});
      await _mount(
        tester,
        repository,
        location: '/feedback/fb-needs-info/supplement',
      );
      expect(find.text('当前反馈无需补充'), findsOneWidget);
      expect(find.byKey(const Key('submit-missing-feedback')), findsNothing);
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

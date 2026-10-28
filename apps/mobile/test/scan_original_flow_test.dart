import 'feedback_test_image.dart';

import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _object = DetectedScanCard(
  id: 'stable-object',
  cropRegion: ScanCropRegion(x: .1, y: .2, width: .2, height: .4),
  candidates: [],
  status: ScanRecognitionStatus.unrecognized,
);
const _session = ScanSession(id: 'stable-session', detectedCards: [_object]);

void main() {
  testWidgets(
    'original capture automatically detects then matches all stable IDs',
    (tester) async {
      final repository = _Detection();
      final router = GoRouter(
        initialLocation: '/scan-original',
        routes: [
          GoRoute(path: '/scan-original', builder: (_, _) => const ScanPage()),
          GoRoute(
            path: '/scan-original-result',
            builder: (context, state) {
              expect((state.extra! as ScanSession).id, _session.id);
              return Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回测试'),
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scanDetectionRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('将一张或多张小卡完整放入画面'), findsOneWidget);
      expect(find.text('原图定位'), findsNothing);
      expect(
        tester.widget<Text>(find.text('将一张或多张小卡完整放入画面')).textAlign,
        TextAlign.center,
      );
      expect(find.byTooltip('我的扫描反馈'), findsOneWidget);
      expect(find.byTooltip('切换相机'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-shutter')));
      await tester.pump();
      expect(find.text('定位小卡'), findsNothing);
      expect(find.text('正在识别小卡…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repository.detection.complete(
        const ScanDetection(sessionId: 'stable-session', regions: [_object]),
      );
      await tester.pump();
      expect(repository.ids, {'stable-object'});
      expect(find.text('正在匹配 1 张小卡…'), findsOneWidget);
      expect(find.text('定位小卡'), findsNothing);
      expect(
        find.byKey(const ValueKey('progress-region-stable-object')),
        findsOneWidget,
      );
      repository.result.complete(_session);
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回测试'));
      await tester.pumpAndSettle();
      expect(find.text('继续核对'), findsOneWidget);
      expect(repository.calls, 1);
      await tester.tap(find.text('继续核对'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clue feedback keeps optional fields and retries same payload before returning',
    (tester) async {
      final feedback = _Feedback();
      feedback.imagePath = await feedbackTestImage(tester);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          catalogRepositoryProvider.overrideWithValue(_Catalog()),
          feedbackRepositoryProvider.overrideWithValue(feedback),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      bool? returned;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const ScanFeedbackPage(
                          args: ScanFeedbackRouteArgs(
                            session: _session,
                            detectedCard: _object,
                            returnToResult: true,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('打开反馈'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开反馈'));
      await tester.pumpAndSettle();
      expect(find.text('将附带扫描原图、裁剪图及候选信息'), findsOneWidget);
      expect(find.textContaining('stable-object'), findsNothing);
      await tester.tap(find.byKey(const Key('scan-clue-upload-back')));
      await waitForFeedbackCrop(tester);
      await tester.tap(find.byKey(const Key('feedback-crop-confirm')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('裁剪背面'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('scan-feedback-notes')),
        '保留的线索',
      );
      await tester.ensureVisible(find.byKey(const Key('submit-scan-feedback')));
      await tester.tap(find.byKey(const Key('submit-scan-feedback')));
      await tester.pumpAndSettle();
      expect(find.text('测试网络失败'), findsOneWidget);
      expect(find.text('保留的线索'), findsOneWidget);
      expect(returned, isNull);
      feedback.fail = false;
      await tester.ensureVisible(find.byKey(const Key('submit-scan-feedback')));
      await tester.tap(find.byKey(const Key('submit-scan-feedback')));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(feedback.bodies[0], feedback.bodies[1]);
      final body = feedback.bodies.last;
      expect(body['kind'], 'MISSING_CARD');
      expect((body['missing'] as Map)['feedback_mode'], 'SCAN_CLUE');
      expect((body['missing'] as Map)['detected_card_id'], 'stable-object');
      expect((body['missing'] as Map)['group_id'], isNull);
      expect((body['missing'] as Map)['back_image_id'], 'uploaded-back');
      expect((body['missing'] as Map)['is_double_sided'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Detection implements ScanDetectionRepository {
  final detection = Completer<ScanDetection>();
  final result = Completer<ScanSession>();
  Set<String>? ids;
  int calls = 0;
  @override
  Future<ScanDetection> detect(String? path) => detection.future;
  @override
  Future<ScanSession> recognize(
    ScanDetection detection,
    Set<String> selectedIds,
  ) {
    calls++;
    ids = selectedIds;
    return result.future;
  }
}

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _Catalog implements CatalogRepository {
  @override
  Future<CatalogBundle> fetchCatalog() async => DemoCatalog.bundle;
}

class _Feedback extends FeedbackRepository {
  _Feedback() : super(ApiClient());
  bool fail = true;
  String? imagePath;
  final bodies = <FeedbackJson>[];
  @override
  Future<FeedbackJson?> pickImage() async => {
    'id': 'uploaded-back',
    'image_url': imagePath,
  };
  @override
  Future<FeedbackJson> post(String path, FeedbackJson body) async {
    if (path == '/images/crop') {
      return {'id': 'uploaded-back', 'image_url': imagePath};
    }
    expect(path, '');
    bodies.add(body);
    if (fail) throw const ApiException('NETWORK', '测试网络失败');
    return {'id': 'feedback'};
  }
}

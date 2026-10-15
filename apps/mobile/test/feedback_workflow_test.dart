import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/features/feedback/correction_page.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Repository extends FeedbackRepository {
  _Repository() : super(ApiClient());
  final List<FeedbackJson> submissions = [];
  final List<String> paths = [];
  final row = <String, dynamic>{
    'id': 'fb-test',
    'kind': 'CORRECTION',
    'entity_type': 'albums',
    'entity_id': 'a1',
    'name': '测试专辑',
    'image_url': null,
    'status': 'PROCESSED',
    'status_label': '已处理',
    'result': 'NOT_INCLUDED',
    'revision': 2,
    'created_at': '2026-10-14T12:00:00',
    'updated_at': '2026-10-14T12:00:00',
    'public_note': '原资料准确，本次不作修改',
    'submission': {'fields': <dynamic>[]},
    'decisions': <dynamic>[],
    'history': <dynamic>[],
    'target_available': true,
  };
  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async {
    paths.add(path);
    if (path.startsWith('/objects/')) {
      return {
        'entity_type': 'albums',
        'entity_id': 'a1',
        'name': '测试专辑',
        'image_url': null,
        'version': 'v1',
        'fields': [
          {'key': 'name', 'label': '名称', 'type': 'text', 'current': '测试专辑'},
          {
            'key': 'description',
            'label': '介绍',
            'type': 'text',
            'current': '原介绍',
          },
          {
            'key': 'release_date',
            'label': '发行日期',
            'type': 'date',
            'current': '2026-01-01',
          },
        ],
      };
    }
    if (path.startsWith('/records/')) return row;
    return {
      'items': [row],
      'next_offset': null,
    };
  }

  @override
  Future<FeedbackJson> post(String path, FeedbackJson body) async {
    submissions.add(body);
    return row;
  }
}

void main() {
  testWidgets('reference picker stays above keyboard on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedbackRepositoryProvider.overrideWithValue(_Repository()),
        ],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    chooseFeedbackObject(context, 'albums', switchable: true),
                child: const Text('打开选择'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开选择'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(480));
    expect(tester.takeException(), isNull);
  });
  test('feedback retries reuse a key only for identical payload', () {
    final keys = FeedbackRequestKey();
    final a = keys.forPayload({'kind': 'CORRECTION', 'notes': 'one'});
    expect(keys.forPayload({'kind': 'CORRECTION', 'notes': 'one'}), a);
    expect(keys.forPayload({'kind': 'CORRECTION', 'notes': 'two'}), isNot(a));
  });
  testWidgets(
    'correction carries stable object and structured suggestions through preview',
    (tester) async {
      final repository = _Repository();
      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(
            path: '/edit',
            builder: (_, _) =>
                const CorrectionPage(entityType: 'albums', entityId: 'a1'),
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
          overrides: [feedbackRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.paths.first, '/objects/albums/a1');
      expect(find.text('切换反馈对象'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, '名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '新的专辑名称');
      await tester.scrollUntilVisible(
        find.text('预览并提交'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('预览并提交'));
      await tester.pumpAndSettle();
      expect(find.text('名称：新的专辑名称'), findsOneWidget);
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      final payload = repository.submissions.single;
      expect(payload['entity_id'], 'a1');
      expect(payload['entity_type'], 'albums');
      expect(payload['object_version'], 'v1');
      expect(payload['fields'], [
        {'key': 'name', 'mode': 'SET', 'value': '新的专辑名称', 'reason': ''},
      ]);
      expect(find.text('反馈进度'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'not adopted is processed and explains outcome without saying included',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedbackRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const FeedbackDetailPage(id: 'fb-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已处理'), findsOneWidget);
      expect(find.text('本次建议未采纳'), findsOneWidget);
      expect(find.text('原资料准确，本次不作修改'), findsOneWidget);
      expect(find.text('已收录'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'feedback center separates missing and correction without losing detail entry',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedbackRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const FeedbackCenterPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('扫描缺失'), findsOneWidget);
      expect(find.text('数据纠错'), findsOneWidget);
      expect(find.text('测试专辑'), findsOneWidget);
      await tester.tap(find.text('扫描缺失'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

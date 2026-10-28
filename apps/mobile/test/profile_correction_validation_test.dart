import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/features/feedback/correction_page.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _ProfileFeedback extends FeedbackRepository {
  _ProfileFeedback({this.failure}) : super(ApiClient());
  final ApiException? failure;
  final submissions = <FeedbackJson>[];

  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async => {
    'entity_type': 'idols',
    'entity_id': 'artist',
    'name': '测试艺人',
    'version': 'current-version',
    'profile': true,
    'fields': [
      {
        'key': 'career_text',
        'label': '从艺历程',
        'type': 'long_text',
        'section': 'career',
        'current': '原从艺历程',
        'max_length': 20000,
      },
    ],
  };

  @override
  Future<FeedbackJson> post(String path, FeedbackJson body) async {
    submissions.add(body);
    if (failure != null) {
      throw failure!;
    }
    return {'id': 'pending-profile-revision'};
  }
}

Finder input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> pumpEditor(
    WidgetTester tester,
    _ProfileFeedback repository,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, _) => const CorrectionPage(
            entityType: 'idols',
            entityId: 'artist',
            section: 'career',
          ),
        ),
        GoRoute(
          path: '/feedback/:id',
          builder: (_, _) => const Scaffold(body: Text('待审核资料修订')),
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
    await tester.tap(find.widgetWithText(CheckboxListTile, '从艺历程'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.maxLength == 20000,
      ),
      '2024年正式出道，核对后的从艺历程',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final target = input(label);
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(target, value);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> notes(WidgetTester tester) async {
    await fill(tester, '问题说明（选填）', '当前历程有遗漏');
    await fill(tester, '修订说明 / 可核实出处（必填）', '根据官方公布的出道资料补充');
  }

  testWidgets(
    'invalid reference link is inline and keeps profile suggestions',
    (tester) async {
      final repository = _ProfileFeedback();
      await pumpEditor(tester, repository);
      await notes(tester);
      await fill(tester, '参考链接（选填，每行一条，最多6条）', 'test');
      await tester.tap(find.text('预览并提交'));
      await tester.pumpAndSettle();
      expect(repository.submissions, isEmpty);
      expect(find.text('预览资料修订'), findsNothing);
      expect(find.text(feedbackLinkError('test')!), findsOneWidget);
      final links = tester.widget<TextField>(input('参考链接（选填，每行一条，最多6条）'));
      expect(links.controller!.text, 'test');
      expect(find.byTooltip('重新载入资料'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'valid profile revision previews then submits mapped fields for review',
    (tester) async {
      final repository = _ProfileFeedback();
      await pumpEditor(tester, repository);
      await notes(tester);
      await fill(
        tester,
        '参考链接（选填，每行一条，最多6条）',
        ' https://example.com/official-career ',
      );
      await tester.tap(find.text('预览并提交'));
      await tester.pumpAndSettle();
      expect(repository.submissions, isEmpty);
      expect(find.text('预览资料修订'), findsOneWidget);
      expect(find.textContaining('当前从艺历程：原从艺历程'), findsOneWidget);
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      final body = repository.submissions.single;
      expect(body['entity_type'], 'idols');
      expect(body['entity_id'], 'artist');
      expect(body['object_version'], 'current-version');
      expect(body['links'], ['https://example.com/official-career']);
      expect(body['fields'], [
        {
          'key': 'career_text',
          'mode': 'SET',
          'value': '2024年正式出道，核对后的从艺历程',
          'reason': '当前历程有遗漏',
        },
      ]);
      expect(find.text('待审核资料修订'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'server validation details appear beside links without discarding input',
    (tester) async {
      final repository = _ProfileFeedback(
        failure: const ApiException(
          'VALIDATION_ERROR',
          '请求参数不正确',
          statusCode: 422,
          details: {
            'details': [
              {
                'loc': ['body', 'links'],
                'msg': 'Value error, 该参考链接不可用，请检查',
              },
            ],
          },
        ),
      );
      await pumpEditor(tester, repository);
      await notes(tester);
      await fill(
        tester,
        '参考链接（选填，每行一条，最多6条）',
        'https://example.com/official-career',
      );
      await tester.tap(find.text('预览并提交'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(repository.submissions, hasLength(1));
      expect(find.text('该参考链接不可用，请检查'), findsOneWidget);
      expect(
        tester.widget<TextField>(input('参考链接（选填，每行一条，最多6条）')).controller!.text,
        'https://example.com/official-career',
      );
      expect(find.byTooltip('重新载入资料'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'field validation details preserve long suggestion and optional links remain optional',
    (tester) async {
      final repository = _ProfileFeedback(
        failure: const ApiException(
          'INVALID_VALUE',
          '请检查资料字段',
          statusCode: 422,
          details: {
            'details': [
              {
                'loc': ['body', 'fields', 0, 'value'],
                'field': 'career_text',
                'msg': '从艺历程内容需要核对',
              },
            ],
          },
        ),
      );
      await pumpEditor(tester, repository);
      await notes(tester);
      await tester.tap(find.text('预览并提交'));
      await tester.pumpAndSettle();
      expect(find.text('预览资料修订'), findsOneWidget);
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(repository.submissions.single['links'], isEmpty);
      expect(find.text('从艺历程内容需要核对'), findsOneWidget);
      final suggestion = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) => widget is TextField && widget.maxLength == 20000,
        ),
      );
      expect(suggestion.controller!.text, '2024年正式出道，核对后的从艺历程');
      expect(tester.takeException(), isNull);
    },
  );
}

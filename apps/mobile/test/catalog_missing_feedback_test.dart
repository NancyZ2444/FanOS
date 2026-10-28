import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(isLoggedIn: true);
}

class _Repository extends FeedbackRepository {
  _Repository() : super(ApiClient());
  final requestedKinds = <String>[];
  final submissions = <FeedbackJson>[];
  bool failNext = false;
  String? failSchemaFor;
  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async {
    final kind = query!['entity_type'] as String;
    requestedKinds.add(kind);
    if (kind == failSchemaFor) {
      failSchemaFor = null;
      throw const ApiException('SCHEMA_ERROR', '字段暂时不可用');
    }
    return {
      'entity_type': kind,
      'fields': [
        {'key': 'name', 'label': '名称', 'type': 'text', 'required': true},
        {'key': 'image_url', 'label': '图片', 'type': 'image'},
        if (kind == 'versions')
          {
            'key': 'album_id',
            'label': '所属专辑',
            'type': 'reference',
            'reference': 'albums',
            'required': true,
          },
      ],
    };
  }

  @override
  Future<FeedbackJson?> pickImage() async => {
    'id': 'uploaded-image',
    'image_url': null,
  };
  @override
  Future<FeedbackJson> post(String path, FeedbackJson body) async {
    submissions.add(body);
    if (failNext) {
      failNext = false;
      throw const ApiException('UNAVAILABLE', '提交失败，请重试');
    }
    return {
      'id': 'catalog-feedback-1',
      'kind': 'MISSING_CATALOG',
      'result': 'PENDING',
    };
  }
}

Future<void> _mount(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(repository),
        sessionProvider.overrideWith(_SignedIn.new),
      ],
      child: MaterialApp(
        theme: FanOsTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => const CatalogMissingFeedbackPage(),
                ),
              ),
              child: const Text('打开缺失内容'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开缺失内容'));
  await tester.pumpAndSettle();
}

void main() {
  test('missing catalog types contain exactly six objective entity kinds', () {
    expect(missingCatalogKinds.keys, [
      'groups',
      'idols',
      'albums',
      'versions',
      'events',
      'others',
    ]);
    expect(missingCatalogKinds.values, isNot(contains('小卡')));
  });

  testWidgets(
    'switching entity loads its own fields and preserves typed form state',
    (tester) async {
      final repository = _Repository();
      await _mount(tester, repository);
      await tester.enterText(
        find.byKey(const Key('catalog-missing-name')),
        '组合草稿',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('专辑版本').last);
      await tester.pumpAndSettle();
      expect(repository.requestedKinds, ['groups', 'versions']);
      expect(find.text('所属专辑 *'), findsOneWidget);
      expect(find.text('组合草稿'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('组合').last);
      await tester.pumpAndSettle();
      expect(find.text('组合草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uploaded image submits only to pending review and retries reuse request key',
    (tester) async {
      final repository = _Repository()..failNext = true;
      await _mount(tester, repository);
      await tester.enterText(
        find.byKey(const Key('catalog-missing-name')),
        '真实组合',
      );
      await tester.tap(find.text('上传图片'));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(
        find.byKey(const Key('submit-catalog-missing-feedback')),
      );
      await tester.tap(
        find.byKey(const Key('submit-catalog-missing-feedback')),
      );
      await tester.pumpAndSettle();
      expect(find.text('提交失败，请重试'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('submit-catalog-missing-feedback')),
      );
      await tester.tap(
        find.byKey(const Key('submit-catalog-missing-feedback')),
      );
      await tester.pumpAndSettle();
      expect(repository.submissions, hasLength(2));
      final request = repository.submissions.last;
      expect(
        request['request_key'],
        repository.submissions.first['request_key'],
      );
      expect(request['kind'], 'MISSING_CATALOG');
      expect(request['entity_type'], 'groups');
      expect(feedbackItems(request['fields']), [
        {'key': 'name', 'mode': 'SET', 'value': '真实组合'},
        {'key': 'image_url', 'mode': 'SET', 'value': 'uploaded-image'},
      ]);
      expect(request.containsKey('status'), false);
      expect(find.text('打开缺失内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed schema switch hides stale fields and retries the selected kind',
    (tester) async {
      final repository = _Repository()..failSchemaFor = 'versions';
      await _mount(tester, repository);
      await tester.enterText(
        find.byKey(const Key('catalog-missing-name')),
        '已保存的组合输入',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('专辑版本').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalog-missing-name')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('submit-catalog-missing-feedback')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('字段暂时不可用'), findsOneWidget);
      await tester.tap(find.text('重新加载字段'));
      await tester.pumpAndSettle();
      expect(find.text('所属专辑 *'), findsOneWidget);
      expect(repository.requestedKinds, ['groups', 'versions', 'versions']);
      expect(find.text('已保存的组合输入'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('组合').last);
      await tester.pumpAndSettle();
      expect(find.text('已保存的组合输入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

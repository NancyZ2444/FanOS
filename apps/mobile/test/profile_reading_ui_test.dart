import 'dart:math';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/catalog_profile_tab.dart';
import 'package:fan_os/features/catalog/presentation/profile_reading_widgets.dart';
import 'package:fan_os/features/catalog/presentation/profile_text_diff.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

FeedbackJson field(
  String key,
  dynamic value, {
  String type = 'text',
  String section = 'basic',
}) => {
  'key': key,
  'label': key,
  'current': value,
  'current_display': feedbackValue(value),
  'type': type,
  'section': section,
};
const member = {
  'id': 'm1',
  'name': 'Long Artist Name',
  'status': 'active',
  'start_date': '',
  'end_date': '',
};
FeedbackJson revision({bool initial = false}) => {
  'id': 'v1',
  'version': 1,
  'parent_version': initial ? null : 0,
  'source': initial ? 'INITIAL' : 'USER',
  'summary': initial ? '历史资料初始化' : '修正资料',
  'author': {'name': '测试作者'},
  'published_at': '2026-10-22T07:37:58Z',
  'fields': [
    field('官方名称', 'Official Name'),
    field('空字段', ''),
    field('成员经历', [member], type: 'relations'),
  ],
  'changes': [
    {
      'key': 'name',
      'label': '官方名称',
      'section': 'basic',
      'type': 'text',
      'before': initial ? null : 'Old Name',
      'after': 'Official Name',
    },
    {
      'key': 'empty',
      'label': '空字段',
      'section': 'basic',
      'type': 'text',
      'before': null,
      'after': '',
    },
    {
      'key': 'same',
      'label': '未变字段',
      'section': 'basic',
      'type': 'text',
      'before': '一样',
      'after': '一样',
    },
  ],
};

class _HistoryApi extends ApiClient {
  int calls = 0;
  bool fail = false;
  final queries = <Map<String, dynamic>>[];
  @override
  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    calls++;
    queries.add(query ?? {});
    if (fail) {
      fail = false;
      throw Exception('offline');
    }
    if (query?['section_key'] == 'honors') {
      return {'items': [], 'next_offset': null};
    }
    return {
      'items': [revision(initial: true)],
      'next_offset': (query?['offset'] ?? 0) == 0 ? 20 : null,
    };
  }
}

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

void main() {
  Future<void> size(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child, {double scale = 1}) => MaterialApp(
    theme: FanOsTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  );

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'reading profile has no duplicate controls, relations use full width at $width',
      (tester) async {
        await size(tester, width);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogProfileProvider('groups/g').overrideWith(
                (ref) async => {
                  'published_at': '2026-10-22T07:37:58Z',
                  'fields': [
                    field('简介', '一份简介', section: 'intro'),
                    field('官方名称', 'Official Name'),
                    field('成员经历', [member], type: 'relations'),
                    field('空字段', ''),
                  ],
                },
              ),
            ],
            child: app(
              const Scaffold(
                body: CatalogProfileTab(kind: 'groups', entityId: 'g'),
              ),
              scale: 1.5,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('编辑资料'), findsNothing);
        expect(find.text('补充内容'), findsNothing);
        expect(find.text('修订历史'), findsNothing);
        expect(find.text('从艺历程'), findsOneWidget);
        await tester.tap(find.text('成员经历 (1)'));
        await tester.pumpAndSettle();
        expect(find.text('活动中'), findsOneWidget);
        expect(find.text('active'), findsNothing);
        expect(find.text('日期未填写'), findsOneWidget);
        expect(
          tester.getSize(find.byType(ProfileRelationRecord)).width,
          moreOrLessEquals(width - 72),
        );
        await tester.ensureVisible(find.text('查看全部基本字段'));
        await tester.tap(find.text('查看全部基本字段'));
        await tester.pumpAndSettle();
        expect(find.text('空字段'), findsOneWidget);
        expect(find.text('收起未填写字段'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'initial version shows real fields without fabricated before values at $width',
      (tester) async {
        await size(tester, width);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogProfileProvider('groups/g/history/v1')
                  .overrideWith((ref) async => revision(initial: true)),
            ],
            child: app(
              const CatalogProfileVersion(
                kind: 'groups',
                entityId: 'g',
                versionId: 'v1',
              ),
              scale: 1.5,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('系统整理'), findsOneWidget);
        expect(find.text('初始资料 · 2 个有效字段'), findsOneWidget);
        expect(find.text('修改前'), findsNothing);
        expect(find.text('空字段'), findsNothing);
        expect(find.text('未变字段'), findsNothing);
        expect(find.text('Official Name'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'normal revision excludes equal and empty-equivalent changes; snapshot is separate',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProfileProvider('groups/g/history/v1')
                .overrideWith((ref) async => revision()),
          ],
          child: app(
            const CatalogProfileVersion(
              kind: 'groups',
              entityId: 'g',
              versionId: 'v1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('变更 1 项 · 基本资料'), findsOneWidget);
      expect(find.text('空字段'), findsNothing);
      expect(find.text('未变字段'), findsNothing);
      expect(find.text('修改前'), findsOneWidget);
      await tester.tap(find.text('查看该版完整资料'));
      await tester.pumpAndSettle();
      expect(find.text('空字段'), findsOneWidget);
    },
  );
  testWidgets(
    'missing before differs from an empty before, deletions retain old value',
    (tester) async {
      final data = revision();
      data['changes'] = [
        {'key': 'x', 'label': '未知原值', 'type': 'text', 'after': '新内容'},
        {
          'key': 'y',
          'label': '移除简介',
          'type': 'long_text',
          'before': '旧简介',
          'after': '',
        },
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProfileProvider('groups/g/history/v1')
                .overrideWith((ref) async => data),
          ],
          child: app(
            const CatalogProfileVersion(
              kind: 'groups',
              entityId: 'g',
              versionId: 'v1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原始内容不可用'), findsOneWidget);
      expect(find.text('已删除'), findsOneWidget);
      expect(find.text('旧简介'), findsOneWidget);
      expect(find.text('原值未填写'), findsNothing);
    },
  );
  testWidgets(
    'history compact filter, retry, pagination dedup and filtered empty',
    (tester) async {
      final api = _HistoryApi()..fail = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: app(
            const CatalogProfileHistory(kind: 'groups', entityId: 'g'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('修订记录加载失败'), findsOneWidget);
      expect(find.text('暂无修订记录'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('历史资料初始化'), findsOneWidget);
      await tester.tap(find.text('全部板块'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('荣誉记录').last);
      await tester.pumpAndSettle();
      expect(find.text('该板块暂无修订记录'), findsOneWidget);
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.text('历史资料初始化'), findsOneWidget);
      expect(api.queries.last['section_key'], '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'top pencil edits personal remark while profile feedback opens section sheet',
    (tester) async {
      var remarks = 0;
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              appBar: AppBar(
                actions: [
                  CatalogPersonalRemarkButton(onPressed: () => remarks++),
                ],
              ),
              body: const CatalogProfileActions(kind: 'groups', entityId: 'g'),
            ),
          ),
          GoRoute(
            path: '/catalog-correction',
            builder: (_, state) => Scaffold(
              body: Text('editing ${state.uri.queryParameters['section']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('编辑资料'), findsNothing);
      expect(find.byTooltip('修订历史'), findsOneWidget);
      expect(find.byTooltip('更多'), findsNothing);
      await tester.tap(find.byTooltip('个人备注'));
      await tester.pumpAndSettle();
      expect(remarks, 1);
      await tester.tap(find.text('资料反馈'));
      await tester.pumpAndSettle();
      expect(find.text('简介'), findsOneWidget);
      await tester.tap(find.text('从艺历程'));
      await tester.pumpAndSettle();
      expect(find.text('editing career'), findsOneWidget);
    },
  );
  testWidgets('profile feedback retains login requirement for guests', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: CatalogProfileActions(kind: 'groups', entityId: 'g'),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('登录后提交反馈')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: FanOsTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料反馈'));
    await tester.pumpAndSettle();
    expect(find.text('登录后提交反馈'), findsOneWidget);
    expect(find.text('从艺历程'), findsNothing);
  });
  testWidgets(
    'visitor background reaches the status bar without changing privacy',
    (tester) async {
      await size(tester, 390);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publicUserProfileProvider('p').overrideWith(
              (ref) async => PublicUserProfile.fromJson({
                'id': 'p',
                'display_name': '访客测试',
                'background_url': '/tmp/no-profile-qa-image.png',
              }),
            ),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(top: 54, bottom: 34)),
              child: child!,
            ),
            home: const ProfilePage(userId: 'p'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('profile-background'))).dy,
        0,
      );
      expect(
        tester.getTopLeft(find.byType(BackButton)).dy,
        greaterThanOrEqualTo(54),
      );
      expect(find.text('访客测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('long text always has accessible expand, even without newlines', (
    tester,
  ) async {
    await size(tester, 360);
    final text = List.filled(30, '长段正文 and complete words ').join();
    await tester.pumpWidget(
      app(Scaffold(body: ProfileReadingText(text: text))),
    );
    await tester.pumpAndSettle();
    expect(find.text('展开'), findsOneWidget);
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
  });
  test(
    'token diff preserves all text and highlights only changed portions',
    () {
      for (final pair in [
        ('姓名 张三 2020年', '姓名 李四 2021年'),
        ('abc', 'abc'),
        ('', 'new'),
        ('old', ''),
      ]) {
        for (final old in [true, false]) {
          final spans = profileDiffSpans(
            pair.$1,
            pair.$2,
            old: old,
          ).cast<TextSpan>();
          expect(spans.map((s) => s.text).join(), old ? pair.$1 : pair.$2);
          if (pair.$1 == pair.$2) {
            expect(spans.every((s) => s.style == null), isTrue);
          }
        }
      }
      final spans = profileDiffSpans(
        '姓名 张三 2020年',
        '姓名 李四 2021年',
        old: false,
      ).cast<TextSpan>();
      expect(
        spans.where((s) => s.style != null).map((s) => s.text).join(),
        '李四2021',
      );
      final random = Random(7);
      for (var n = 0; n < 100; n++) {
        final a = List.generate(
          random.nextInt(30),
          (_) => '甲乙丙丁'[random.nextInt(4)],
        ).join();
        final b = List.generate(
          random.nextInt(30),
          (_) => '甲乙丙丁'[random.nextInt(4)],
        ).join();
        expect(
          profileDiffSpans(
            a,
            b,
            old: true,
          ).cast<TextSpan>().map((s) => s.text).join(),
          a,
        );
        expect(
          profileDiffSpans(
            a,
            b,
            old: false,
          ).cast<TextSpan>().map((s) => s.text).join(),
          b,
        );
      }
    },
  );
}

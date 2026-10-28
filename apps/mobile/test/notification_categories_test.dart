import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/notification/presentation/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class NoticeApi extends ApiClient {
  final reads = <String>[];
  @override
  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    reads.add(path);
    return {};
  }
}

void main() {
  for (final width in [360.0, 430.0]) {
    testWidgets(
      'notice tabs separate content and refresh stays in header at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final loads = <NoticeSection, int>{};
        final client = NoticeApi();
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const NotificationsPage()),
            GoRoute(
              path: '/feedback/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('反馈详情 ${state.pathParameters['id']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              noticeItemsProvider.overrideWith((ref, section) async {
                loads[section] = (loads[section] ?? 0) + 1;
                return <FeedbackJson>[
                  switch (section) {
                    NoticeSection.announcements => {
                      'id': 'announcement',
                      'title': '平台公告',
                      'content': '公告正文',
                    },
                    NoticeSection.notifications => {
                      'id': 'ordinary',
                      'title': '普通通知',
                      'content': '通知正文',
                      'payload': {},
                    },
                    NoticeSection.feedback => {
                      'id': 'feedback',
                      'title': '反馈已采纳',
                      'content': '审核正文',
                      'payload': {'feedback_id': 'test-feedback'},
                    },
                  },
                ];
              }),
            ],
            child: MaterialApp.router(
              theme: FanOsTheme.light,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('我的反馈'), findsNothing);
        expect(find.text('普通通知'), findsOneWidget);
        expect(find.text('反馈已采纳'), findsNothing);
        expect(find.text('平台公告'), findsNothing);
        final refresh = find.byKey(const Key('notifications-refresh'));
        final title = find
            .descendant(of: find.byType(AppBar), matching: find.text('通知'))
            .first;
        expect(
          (tester.getCenter(refresh).dy - tester.getCenter(title).dy).abs(),
          lessThan(12),
        );
        final before = loads[NoticeSection.notifications]!;
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(loads[NoticeSection.notifications], before + 1);
        await tester.tap(find.text('普通通知'));
        await tester.pumpAndSettle();
        expect(client.reads, contains('/notifications/inbox/ordinary/read'));
        expect(find.text('通知正文'), findsWidgets);
        Navigator.of(tester.element(find.text('通知正文').last)).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(Tab, '公告'));
        await tester.pumpAndSettle();
        expect(find.text('平台公告'), findsOneWidget);
        expect(find.text('普通通知'), findsNothing);
        await tester.tap(find.widgetWithText(Tab, '反馈结果'));
        await tester.pumpAndSettle();
        expect(find.text('反馈已采纳'), findsOneWidget);
        expect(find.text('平台公告'), findsNothing);
        await tester.tap(find.text('反馈已采纳'));
        await tester.pumpAndSettle();
        expect(client.reads, contains('/notifications/inbox/feedback/read'));
        expect(find.text('反馈详情 test-feedback'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'category failures stay retryable from header without fake empty state',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            noticeItemsProvider.overrideWith((ref, section) async {
              if (section == NoticeSection.notifications && attempts++ == 0) {
                throw const ApiException('TEMPORARY', '暂时无法连接');
              }
              return <FeedbackJson>[];
            }),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const NotificationsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法连接'), findsOneWidget);
      expect(find.text('暂无通知'), findsNothing);
      await tester.tap(find.byKey(const Key('notifications-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('暂无通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

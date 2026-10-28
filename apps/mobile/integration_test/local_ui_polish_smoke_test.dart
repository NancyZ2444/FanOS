import 'package:fan_os/app/app.dart';
import 'package:fan_os/app/router.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _enabled = bool.fromEnvironment('RUN_LOCAL_UI_POLISH_SMOKE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local iOS startup, daily card and classified notices', (
    tester,
  ) async {
    expect(useMockApi, isFalse);
    expect(ApiClient.baseUrl, 'http://127.0.0.1:8000/api/v1');
    final resources = await ApiClient().getData('/albums/resources');
    expect(resources['items'], isA<List>());
    await tester.pumpWidget(const ProviderScope(child: FanOsApp()));
    var ready = false;
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      ready =
          fanOsRouter.routeInformationProvider.value.uri.path == '/home' ||
          find.text('开启旅程').evaluate().isNotEmpty;
      if (ready) break;
    }
    expect(ready, isTrue);
    expect(find.text('重新连接'), findsNothing);
    await binding.takeScreenshot('ios-startup');

    // Navigation and reads only. Never draw a card or mark an inbox item as read.
    fanOsRouter.go('/daily-card');
    await tester.pumpAndSettle();
    expect(find.text('每日翻卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('ios-daily-card');

    fanOsRouter.go('/notifications');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, '公告'), findsOneWidget);
    expect(find.widgetWithText(Tab, '通知'), findsOneWidget);
    expect(find.widgetWithText(Tab, '反馈结果'), findsOneWidget);
    expect(find.byKey(const Key('notifications-refresh')), findsOneWidget);
    expect(find.text('我的反馈'), findsNothing);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('ios-notifications');
    await tester.tap(find.widgetWithText(Tab, '公告'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ios-announcements');
    await tester.tap(find.widgetWithText(Tab, '反馈结果'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('ios-feedback-results');
    expect(tester.takeException(), isNull);
    fanOsRouter.go('/home');
    await tester.pumpAndSettle();
  }, skip: !_enabled);
}

import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/onboarding/presentation/launch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Session extends SessionController {
  Object? restoreError;
  Object? guestError;
  Completer<void>? guestWait;
  bool restored = false;
  int restoreCalls = 0;
  int guestCalls = 0;
  int logoutCalls = 0;

  @override
  Future<bool> restore() async {
    restoreCalls++;
    if (restoreError case final error?) throw error;
    return restored;
  }

  @override
  Future<void> continueAsGuest() async {
    guestCalls++;
    await guestWait?.future;
    if (guestError case final error?) throw error;
  }

  @override
  Future<void> logout() async => logoutCalls++;
}

Future<void> _mount(WidgetTester tester, _Session session) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LaunchPage()),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('首页')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (_, _) => const Scaffold(body: Text('隐私协议')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWith(() => session)],
      child: MaterialApp.router(theme: FanOsTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'welcome screen explicitly uses light status icons on dark background',
    (tester) async {
      await _mount(tester, _Session());
      final overlays = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(
        overlays.any(
          (overlay) =>
              overlay.value.statusBarBrightness == Brightness.dark &&
              overlay.value.statusBarIconBrightness == Brightness.light &&
              overlay.value.systemNavigationBarIconBrightness ==
                  Brightness.light,
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'Keychain entitlement failure is not presented as a network error',
    (tester) async {
      final session = _Session()
        ..restoreError = PlatformException(
          code: '-34018',
          message: "A required entitlement isn't present.",
        );
      await _mount(tester, session);

      expect(find.text('当前安装包无法访问安全登录存储，请更新 App 后重试。'), findsOneWidget);
      expect(find.textContaining('检查网络'), findsNothing);
      expect(find.text('重新连接'), findsNothing);
      expect(session.logoutCalls, 0);
      expect(tester.takeException(), isNull);

      session
        ..restoreError = null
        ..restored = true;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(session.restoreCalls, 2);
      expect(session.logoutCalls, 0);
      expect(find.text('首页'), findsOneWidget);
    },
  );

  testWidgets('temporary network failure preserves reconnect and credentials', (
    tester,
  ) async {
    final session = _Session()
      ..restoreError = const ApiException('NETWORK_ERROR', '暂时无法恢复登录，请检查网络后重试');
    await _mount(tester, session);

    expect(find.text('暂时无法恢复登录，请检查网络后重试。登录凭证已保留。'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
    expect(session.logoutCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('service failure retains its specific explanation', (
    tester,
  ) async {
    await _mount(
      tester,
      _Session()
        ..restoreError = const ApiException(
          'SERVICE_UNAVAILABLE',
          '服务器暂时不可用，请稍后重试',
          statusCode: 503,
        ),
    );
    expect(find.text('服务器暂时不可用，请稍后重试。登录凭证已保留。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('检查网络'), findsNothing);
  });

  testWidgets('unknown failure does not claim a network problem', (
    tester,
  ) async {
    await _mount(
      tester,
      _Session()..restoreError = StateError('unexpected response'),
    );
    expect(find.text('暂时无法恢复登录，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('检查网络'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest storage failure is caught and can be retried', (
    tester,
  ) async {
    final session = _Session()
      ..guestError = PlatformException(
        code: '-25308',
        message: 'User interaction is not allowed.',
      );
    await _mount(tester, session);
    await tester.tap(find.text('游客体验'));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法访问安全登录存储，请解锁设备后重试。'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(session.guestCalls, 1);

    session.guestError = null;
    await tester.tap(find.text('游客体验'));
    await tester.pumpAndSettle();
    expect(session.guestCalls, 2);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('guest transition prevents duplicate actions while pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final session = _Session()..guestWait = pending;
    await _mount(tester, session);
    await tester.tap(find.text('游客体验'));
    await tester.pump();

    expect(find.text('正在进入…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(session.guestCalls, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

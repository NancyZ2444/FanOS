import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:fan_os/features/onboarding/presentation/launch_page.dart';
import 'package:fan_os/features/onboarding/presentation/password_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Api extends ApiClient {
  final requests = <(String, Object?, String?)>[];
  bool expired = false;
  @override
  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async => {
    'wechat_available': true,
    'weibo_available': true,
    'qq_available': true,
  };
  @override
  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    requests.add((path, data, idempotencyKey));
    if (path == '/account/password') {
      if (expired) {
        throw const ApiException(
          'REAUTHENTICATION_REQUIRED',
          '需要重新认证',
          statusCode: 403,
        );
      }
      throw const ApiException('NETWORK_ERROR', '网络暂不可用');
    }
    throw const ApiException('INVALID_CREDENTIALS', '手机号或密码不正确');
  }
}

class _IncompleteSession extends SessionController {
  @override
  SessionState build() => const SessionState(
    isLoggedIn: true,
    onboardingCompleted: false,
    passwordSetupRequired: true,
  );
  @override
  Future<bool> restore() async => true;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 430.0]) {
    testWidgets('login entry and phone form fit width $width with large type', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Api())],
          child: MaterialApp(
            theme: FanOsTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const LoginPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-phone')), findsNothing);
      for (final provider in authProviders) {
        final button = tester.widget<IconButton>(
          find.byKey(Key('login-provider-$provider')),
        );
        expect(
          button.onPressed,
          isNull,
          reason:
              'Server capability alone cannot replace native SDK authorization',
        );
      }
      expect(find.text('QQ'), findsOneWidget);
      expect(find.text('未开通的平台授权暂不可用，请使用手机号。'), findsNothing);
      expect(
        tester
            .widget<Image>(find.byKey(const Key('login-hero')))
            .excludeFromSemantics,
        isTrue,
      );
      expect(
        tester
            .widget<Column>(find.byKey(const Key('login-choice-content')))
            .mainAxisAlignment,
        MainAxisAlignment.center,
      );
      final consent = find.byKey(const Key('login-consent'));
      final consentText = find.byKey(const Key('login-consent-text'));
      expect(
        tester.getCenter(consent).dy,
        closeTo(tester.getCenter(consentText).dy, 1),
      );
      expect(
        tester.getCenter(find.byKey(const Key('login-consent-group'))).dx,
        closeTo(width / 2, 1),
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, 'login-open-phone');
      expect(
        tester.getCenter(consent).dy,
        closeTo(tester.getCenter(consentText).dy, 1),
      );
      expect(
        tester.getCenter(find.byKey(const Key('login-consent-group'))).dx,
        closeTo(width / 2, 1),
      );
      expect(find.byKey(const Key('login-password')), findsNothing);
      await _tap(tester, 'login-switch-method');
      expect(find.byKey(const Key('login-password')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'password mode sends actual password contract without SMS and keeps failed input',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const LoginPage(showPhoneForm: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'login-switch-method');
      await tester.enterText(
        find.byKey(const Key('login-phone')),
        '13812345678',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'FanOS2026',
      );
      await _tap(tester, 'login-consent');
      await _tap(tester, 'login-submit');
      expect(api.requests.single.$1, '/auth/login');
      expect(api.requests.single.$2, {
        'method': 'password',
        'phone': '13812345678',
        'password': 'FanOS2026',
      });
      expect(find.text('手机号或密码不正确'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-password')))
            .controller!
            .text,
        'FanOS2026',
      );
    },
  );

  testWidgets(
    'password validation is local; network retry keeps idempotency key',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const PasswordSetupPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'setup-password-submit');
      expect(api.requests, isEmpty);
      await tester.enterText(
        find.byKey(const Key('setup-password')),
        'FanOS2026',
      );
      await tester.enterText(
        find.byKey(const Key('setup-password-confirm')),
        'FanOS2025',
      );
      await _tap(tester, 'setup-password-submit');
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(api.requests, isEmpty);
      await tester.enterText(
        find.byKey(const Key('setup-password-confirm')),
        'FanOS2026',
      );
      await _tap(tester, 'setup-password-submit');
      await _tap(tester, 'setup-password-submit');
      expect(api.requests.length, 2);
      expect(api.requests.first.$3, api.requests.last.$3);
    },
  );

  testWidgets(
    'expired password setup offers SMS reauthentication without logging out or skipping',
    (tester) async {
      final api = _Api()..expired = true;
      final router = GoRouter(
        initialLocation: '/onboarding/password',
        routes: [
          GoRoute(
            path: '/onboarding/password',
            builder: (_, _) => const PasswordSetupPage(returnTo: '/catalog'),
          ),
          GoRoute(
            path: '/login',
            builder: (_, state) => LoginPage(
              showPhoneForm: state.uri.queryParameters['phone'] == '1',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('setup-password')),
        'FanOS2026',
      );
      await tester.enterText(
        find.byKey(const Key('setup-password-confirm')),
        'FanOS2026',
      );
      await _tap(tester, 'setup-password-submit');
      expect(find.text('重新短信登录'), findsOneWidget);
      await _tap(tester, 'setup-password-submit');
      expect(router.state.uri.path, '/login');
      expect(router.state.uri.queryParameters['from'], '/catalog');
      expect(find.byKey(const Key('login-phone')), findsOneWidget);
      expect(find.byKey(const Key('login-password')), findsNothing);
      expect(api.requests.length, 1);
    },
  );

  testWidgets(
    'restore unfinished registration resumes password before favorites',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const LaunchPage()),
          GoRoute(
            path: '/onboarding/password',
            builder: (_, _) => const Scaffold(body: Text('密码登记引导')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith(_IncompleteSession.new)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('密码登记引导'), findsOneWidget);
    },
  );

  test('password policy matches server registration contract', () {
    for (final value in [
      '12345678',
      'abcdefgh',
      'abc123',
      'abc 123456',
      'A1${'x' * 63}',
    ]) {
      expect(registrationPasswordError(value), isNotNull);
    }
    expect(registrationPasswordError('FanOS2026!'), isNull);
  });
}

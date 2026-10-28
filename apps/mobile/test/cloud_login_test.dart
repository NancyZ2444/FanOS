import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:fan_os/features/profile/presentation/account_security_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthApi extends ApiClient {
  final requests = <(String, Object?, bool, String?)>[];
  bool failSend = false;
  String deliveryMode = 'test_code';
  @override
  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async => {
    'wechat_available': false,
    'weibo_available': false,
    'qq_available': false,
  };
  @override
  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    requests.add((path, data, authenticated, idempotencyKey));
    if (path == '/auth/sms/challenges') {
      if (failSend) throw const ApiException('SMS_UNAVAILABLE', '短信服务暂不可用');
      return {
        'challenge_id': 'challenge-1',
        'retry_after': 60,
        'expires_in': 300,
        'delivery_mode': deliveryMode,
      };
    }
    throw const ApiException('INVALID_VERIFICATION_CODE', '验证码不正确');
  }
}

class _SignedIn extends SessionController {
  @override
  SessionState build() =>
      const SessionState(isLoggedIn: true, userId: 'user-1');
}

class _ExpiredSensitiveApi extends _AuthApi {
  @override
  Future<dynamic> postData(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    if (path == '/auth/sms/challenges') {
      return {
        'challenge_id': 'sensitive',
        'delivery_mode': 'sms',
        'retry_after': 60,
      };
    }
    throw const ApiException('VERIFICATION_PURPOSE_MISMATCH', 'invalid');
  }
}

void main() {
  Future<void> mount(WidgetTester tester, _AuthApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-open-phone')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  testWidgets(
    'requires explicit consent and valid mainland phone before challenge',
    (tester) async {
      final api = _AuthApi();
      await mount(tester, api);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-phone')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('login-phone')),
        '13812345678',
      );
      await tap(tester, const Key('login-submit'));
      expect(api.requests, isEmpty);
      expect(find.text('请先阅读并同意用户协议与隐私政策'), findsOneWidget);
      await tap(tester, const Key('login-consent'));
      await tester.enterText(find.byKey(const Key('login-phone')), '123');
      await tap(tester, const Key('login-submit'));
      expect(api.requests, isEmpty);
      expect(find.text('请输入正确的 11 位大陆手机号'), findsOneWidget);
    },
  );
  testWidgets('challenge never exposes code and phone edit invalidates it', (
    tester,
  ) async {
    final api = _AuthApi();
    await mount(tester, api);
    await tester.enterText(find.byKey(const Key('login-phone')), '13812345678');
    await tap(tester, const Key('login-consent'));
    await tap(tester, const Key('login-submit'));
    await tester.pump();
    expect(api.requests.single.$1, '/auth/sms/challenges');
    expect(api.requests.single.$3, isFalse);
    expect(find.textContaining('测试'), findsNothing);
    expect(find.textContaining('666666'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('login-code')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(find.byKey(const Key('login-phone')), '13912345678');
    await tester.pump();
    expect(find.byKey(const Key('login-code')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'SMS notice stays on phone form and never leaks into entry page',
    (tester) async {
      final api = _AuthApi()..deliveryMode = 'sms';
      await mount(tester, api);
      await tester.enterText(
        find.byKey(const Key('login-phone')),
        '13812345678',
      );
      await tap(tester, const Key('login-consent'));
      await tap(tester, const Key('login-submit'));
      await tester.pump();
      expect(find.text('短信请求已受理，请查收验证码。'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-open-phone')), findsOneWidget);
      expect(find.text('短信请求已受理，请查收验证码。'), findsNothing);
      expect(find.textContaining('测试'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'whitelisted code is neither displayed nor reused as a password',
    (tester) async {
      final api = _AuthApi()..deliveryMode = 'whitelist';
      await mount(tester, api);
      await tester.enterText(
        find.byKey(const Key('login-phone')),
        '13812345678',
      );
      await tap(tester, const Key('login-consent'));
      await tap(tester, const Key('login-submit'));
      await tester.enterText(find.byKey(const Key('login-code')), '123456');
      await tap(tester, const Key('login-switch-method'));
      expect(find.textContaining('测试'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-password')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'AccountPassword9',
      );
      await tap(tester, const Key('login-submit'));
      expect(api.requests.last.$1, '/auth/login');
      expect(api.requests.last.$2, {
        'method': 'password',
        'phone': '13812345678',
        'password': 'AccountPassword9',
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed verification retains challenge and idempotency key for retry',
    (tester) async {
      final api = _AuthApi();
      await mount(tester, api);
      await tester.enterText(
        find.byKey(const Key('login-phone')),
        '13812345678',
      );
      await tap(tester, const Key('login-consent'));
      await tap(tester, const Key('login-submit'));
      await tester.ensureVisible(find.byKey(const Key('login-code')));
      await tester.enterText(find.byKey(const Key('login-code')), '123456');
      await tap(tester, const Key('login-submit'));
      await tester.pump();
      expect(find.text('验证码不正确'), findsOneWidget);
      final login = api.requests.last;
      expect(login.$2, {
        'method': 'phone',
        'phone': '13812345678',
        'code': '123456',
        'challenge_id': 'challenge-1',
      });
      await tap(tester, const Key('login-submit'));
      expect(api.requests.last.$4, login.$4);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'SMS outage displays persistent error without fallback challenge',
    (tester) async {
      final api = _AuthApi()..failSend = true;
      await mount(tester, api);
      await tester.enterText(
        find.byKey(const Key('login-phone')),
        '13812345678',
      );
      await tap(tester, const Key('login-consent'));
      await tap(tester, const Key('login-submit'));
      expect(find.text('短信服务暂不可用'), findsOneWidget);
      expect(find.byKey(const Key('login-code')), findsNothing);
      expect(find.textContaining('666666'), findsNothing);
    },
  );
  testWidgets(
    'unconfigured OAuth disabled and identities fail separately from unbound',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountIdentitiesProvider.overrideWith(
              (ref) async =>
                  throw const ApiException('NETWORK_ERROR', '身份信息加载失败'),
            ),
          ],
          child: const MaterialApp(home: AccountSecurityPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('身份信息加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('未绑定'), findsNothing);
      expect(find.textContaining('游戏账号'), findsNothing);
    },
  );
  testWidgets(
    'sensitive verification invalidated by session change requires a new challenge',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_SignedIn.new),
            apiClientProvider.overrideWithValue(_ExpiredSensitiveApi()),
            accountIdentitiesProvider.overrideWith(
              (ref) async => {'phone_masked': '138****5678', 'identities': []},
            ),
          ],
          child: const MaterialApp(home: AccountSecurityPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机号'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '13812345678');
      await tester.tap(find.text('获取短信验证码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('验证并继续'));
      await tester.pumpAndSettle();
      expect(find.text('本次验证已失效或登录会话已更新，请重新获取短信并完成验证。'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('获取短信验证码'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('return URLs never accept external, auth or admin destinations', () {
    for (final value in [
      'https://evil.test',
      '//evil.test/home',
      '/login',
      '/auth/logout',
      '/admin',
      '/catalog/../login',
    ]) {
      expect(safeLoginReturn(value), '/home');
    }
    expect(safeLoginReturn('/catalog'), '/catalog');
    expect(safeLoginReturn('/cards/card-1'), '/cards/card-1');
    expect(safeLoginReturn('/idol/idol-1'), '/idol/idol-1');
    expect(safeLoginReturn('/digital-albums/book-1'), '/digital-albums/book-1');
  });
  test('unknown delivery remains pending and countdown follows server elapsed window', () {
    final challenge = SmsChallenge.fromJson({
      'challenge_id': 'c',
      'delivery_mode': 'sms_pending',
      'retry_after': 60,
      'server_time': '2026-10-27T04:00:00Z',
      'retry_at': '2026-10-27T04:00:05Z',
    }, transitTime: const Duration(seconds: 2));
    expect(challenge.notice, contains('处理中'));
    expect(challenge.notice, isNot(contains('已受理')));
    expect(challenge.retrySeconds, lessThanOrEqualTo(3));
    expect(challenge.retrySeconds, greaterThanOrEqualTo(2));
  });
  test('native provider without SDK remains unavailable', () async {
    expect(await PlatformAuthorization().available('weibo'), isFalse);
  });
}

import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/core/api/token_store.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/data/user_data_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/onboarding/presentation/launch_page.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:fan_os/features/onboarding/presentation/privacy_page.dart';
import 'package:fan_os/features/onboarding/presentation/password_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MemoryTokens implements TokenStore {
  Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> tokens) async {
    value = {...tokens};
  }

  @override
  Future<void> clear() async => value = null;
}

/// All authentication traffic is handled in memory. No local or cloud account
/// is contacted, and the real SessionController still exercises token saving.
class _AuthApi extends ApiClient {
  _AuthApi(this.store) : super(tokenStore: store);

  final _MemoryTokens store;
  bool responseOnboardingCompleted = true;
  bool responsePasswordSetupRequired = false;
  bool failLogin = false;
  int loginCalls = 0;

  @override
  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    if (path == '/me/name-preferences') {
      return {'mode': 'default', 'aliases': <String, dynamic>{}};
    }
    throw StateError('Unexpected test GET: $path');
  }

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
        'challenge_id': 'navigation-test-challenge',
        'delivery_mode': 'test_code',
        'retry_after': 60,
      };
    }
    if (path == '/auth/login') {
      loginCalls++;
      expect(authenticated, isFalse);
      expect((data as Map)['challenge_id'], 'navigation-test-challenge');
      if (failLogin) {
        throw const ApiException('INVALID_VERIFICATION_CODE', '验证码不正确');
      }
      return {
        'access_token': 'navigation-test-access',
        'refresh_token': 'navigation-test-refresh',
        'expires_in': 3600,
        'is_new_user': !responseOnboardingCompleted,
        'onboarding_completed': responseOnboardingCompleted,
        'password_setup_required': responsePasswordSetupRequired,
      };
    }
    if (path == '/account/password') {
      expect((data as Map)['password'], 'FanOS2026');
      return {'password_setup_required': false, 'onboarding_completed': false};
    }
    throw StateError('Unexpected test POST: $path');
  }
}

class _AccountRepository extends MockUserDataRepository {
  @override
  Future<UserAccountSnapshot> fetchAccountSnapshot() async =>
      const UserAccountSnapshot(
        userId: 'navigation-test-user',
        displayName: 'Navigation test',
        bio: '',
        weiboVisible: false,
        level: 1,
        experience: 0,
        nextLevelExperience: 100,
        privacy: ProfilePrivacy(),
        favoriteIdolIds: {},
        primaryIdolId: null,
        owned: {},
        wishlist: {},
        albums: [],
        photos: [],
        followingCount: 0,
        followersCount: 0,
      );
}

class _BusinessPage extends StatefulWidget {
  const _BusinessPage({super.key});

  @override
  State<_BusinessPage> createState() => _BusinessPageState();
}

class _BusinessPageState extends State<_BusinessPage> {
  final draft = TextEditingController();
  int initiatingActions = 0;
  int loginReturns = 0;

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Text('业务页面'),
          TextField(key: const Key('business-draft'), controller: draft),
          FilledButton(
            key: const Key('business-login'),
            onPressed: () async {
              initiatingActions++;
              await context.push('/login');
              loginReturns++;
            },
            child: const Text('登录后继续'),
          ),
        ],
      ),
    ),
  );
}

class _Harness {
  _Harness(this.router, this.container, this.api, this.businessKey);

  final GoRouter router;
  final ProviderContainer container;
  final _AuthApi api;
  final GlobalKey<_BusinessPageState> businessKey;
}

Future<_Harness> _mount(
  WidgetTester tester, {
  String initialLocation = '/',
  bool firstLogin = false,
  bool failLogin = false,
  bool shellBusiness = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _AuthApi(_MemoryTokens())
    ..responseOnboardingCompleted = !firstLogin
    ..failLogin = failLogin;
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      userDataRepositoryProvider.overrideWithValue(_AccountRepository()),
    ],
  );
  final businessKey = GlobalKey<_BusinessPageState>();
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  var lastBusinessLocation = '/home';
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    redirect: (_, state) {
      if (state.uri.path == '/catalog/draft' || state.uri.path == '/home') {
        lastBusinessLocation = safeLoginReturn(state.uri.toString());
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LaunchPage()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyPage()),
      GoRoute(
        path: '/login',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => LoginPage(
          returnTo: state.uri.queryParameters['from'] ?? lastBusinessLocation,
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('首页')),
      ),
      if (shellBusiness)
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => navigationShell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/catalog/draft',
                  builder: (_, _) => _BusinessPage(key: businessKey),
                ),
              ],
            ),
          ],
        )
      else
        GoRoute(
          path: '/catalog/draft',
          builder: (_, _) => _BusinessPage(key: businessKey),
        ),
      GoRoute(
        path: '/onboarding/password',
        builder: (_, state) =>
            PasswordSetupPage(returnTo: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/onboarding/favorites',
        builder: (_, _) => const Scaffold(body: Text('本命引导')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: FanOsTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(router, container, api, businessKey);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _submitLogin(WidgetTester tester) async {
  await _tapKey(tester, 'login-open-phone');
  await tester.enterText(find.byKey(const Key('login-phone')), '13812345678');
  await _tapKey(tester, 'login-consent');
  await _tapKey(tester, 'login-submit');
  await tester.ensureVisible(find.byKey(const Key('login-code')));
  await tester.enterText(find.byKey(const Key('login-code')), '123456');
  await _tapKey(tester, 'login-submit');
}

void main() {
  testWidgets(
    'new registration requires password before favorites and keeps return target',
    (tester) async {
      final harness = await _mount(
        tester,
        initialLocation: '/catalog/draft',
        firstLogin: true,
      );
      harness.api.responsePasswordSetupRequired = true;
      await _tapKey(tester, 'business-login');
      await _submitLogin(tester);
      expect(harness.router.state.uri.path, '/onboarding/password');
      expect(
        harness.router.state.uri.queryParameters['from'],
        '/catalog/draft',
      );
      await tester.enterText(
        find.byKey(const Key('setup-password')),
        'FanOS2026',
      );
      await tester.enterText(
        find.byKey(const Key('setup-password-confirm')),
        'FanOS2026',
      );
      await _tapKey(tester, 'setup-password-submit');
      expect(harness.router.state.uri.path, '/onboarding/favorites');
      expect(
        harness.router.state.uri.queryParameters['from'],
        '/catalog/draft',
      );
      expect(harness.api.passwordSetupRequired, isFalse);
    },
  );
  testWidgets('startup consent login reaches home instead of launch page', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await tester.tap(find.text('开启旅程'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-open-phone')), findsOneWidget);
    expect(find.byKey(const Key('login-phone')), findsNothing);
    await _submitLogin(tester);

    expect(harness.container.read(sessionProvider).isLoggedIn, isTrue);
    expect(harness.api.store.value?['access_token'], 'navigation-test-access');
    expect(harness.router.state.uri.path, '/home');
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('开启旅程'), findsNothing);
  });

  testWidgets('login pushed directly above launch cannot pop back to launch', (
    tester,
  ) async {
    final harness = await _mount(tester);
    unawaited(harness.router.push('/login'));
    await tester.pumpAndSettle();
    expect(harness.router.canPop(), isTrue);
    await _submitLogin(tester);

    expect(harness.router.state.uri.path, '/home');
    expect(find.text('开启旅程'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  for (final shellBusiness in [false, true]) {
    testWidgets(
      'business login returns same draft without replay; shell: $shellBusiness',
      (tester) async {
        final harness = await _mount(
          tester,
          initialLocation: '/catalog/draft',
          shellBusiness: shellBusiness,
        );
        final originalState = harness.businessKey.currentState!;
        await tester.enterText(
          find.byKey(const Key('business-draft')),
          '保留正在编辑的反馈',
        );
        await _tapKey(tester, 'business-login');
        await _submitLogin(tester);

        expect(harness.router.state.uri.path, '/catalog/draft');
        expect(harness.businessKey.currentState, same(originalState));
        expect(originalState.draft.text, '保留正在编辑的反馈');
        expect(originalState.initiatingActions, 1);
        expect(originalState.loginReturns, 1);
        expect(harness.api.loginCalls, 1);
      },
    );
  }

  testWidgets('login above a pushed business route retains that route state', (
    tester,
  ) async {
    final harness = await _mount(tester, initialLocation: '/home');
    unawaited(harness.router.push('/catalog/draft'));
    await tester.pumpAndSettle();
    final originalState = harness.businessKey.currentState!;
    await tester.enterText(
      find.byKey(const Key('business-draft')),
      '编号 02 的核对状态',
    );
    await _tapKey(tester, 'business-login');
    await _submitLogin(tester);

    expect(harness.router.state.uri.path, '/catalog/draft');
    expect(harness.businessKey.currentState, same(originalState));
    expect(originalState.draft.text, '编号 02 的核对状态');
    expect(harness.router.canPop(), isTrue);
    expect(originalState.loginReturns, 1);
  });

  testWidgets('first login opens onboarding and retains business destination', (
    tester,
  ) async {
    final harness = await _mount(
      tester,
      initialLocation: '/catalog/draft',
      firstLogin: true,
    );
    await _tapKey(tester, 'business-login');
    await _submitLogin(tester);

    expect(harness.router.state.uri.path, '/onboarding/favorites');
    expect(harness.router.state.uri.queryParameters['welcome'], '1');
    expect(harness.router.state.uri.queryParameters['from'], '/catalog/draft');
    expect(find.text('本命引导'), findsOneWidget);
  });

  testWidgets('failed verification stays on login and retains entered code', (
    tester,
  ) async {
    final harness = await _mount(
      tester,
      initialLocation: '/login',
      failLogin: true,
    );
    await _submitLogin(tester);

    expect(harness.router.state.uri.path, '/login');
    expect(find.text('验证码不正确'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('login-code')))
          .controller!
          .text,
      '123456',
    );
    expect(harness.container.read(sessionProvider).isLoggedIn, isFalse);
    expect(harness.api.store.value, isNull);
  });

  testWidgets('login deep link without pop reaches its safe destination', (
    tester,
  ) async {
    final harness = await _mount(
      tester,
      initialLocation: '/login?from=%2Fcatalog%2Fdraft',
    );
    expect(harness.router.canPop(), isFalse);
    await _submitLogin(tester);

    expect(harness.router.state.uri.path, '/catalog/draft');
    expect(find.text('业务页面'), findsOneWidget);
    expect(harness.businessKey.currentState!.initiatingActions, 0);
  });
}

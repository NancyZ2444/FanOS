import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Authentication and feedback use isolated in-memory fixtures only.
class _Session extends SessionController {
  @override
  SessionState build() => const SessionState();

  void authenticate({bool firstLogin = false}) {
    final api = ref.read(apiClientProvider);
    api.onboardingCompleted = !firstLogin;
    api.passwordSetupRequired = firstLogin;
    state = SessionState(
      isLoggedIn: true,
      onboardingCompleted: !firstLogin,
      passwordSetupRequired: firstLogin,
    );
  }

  @override
  Future<void> acceptAuthentication(Map<String, dynamic> data) async {
    authenticate(firstLogin: data['is_new_user'] == true);
  }

  void expire() => state = const SessionState();
}

class _Api extends ApiClient {
  bool firstLogin = false;

  @override
  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    if (path == '/auth/capabilities') return <String, dynamic>{};
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
      return {'challenge_id': 'test-only', 'retry_after': 60};
    }
    if (path == '/auth/login') {
      return {
        'is_new_user': firstLogin,
        'onboarding_completed': !firstLogin,
        'password_setup_required': firstLogin,
      };
    }
    throw StateError('Unexpected test POST: $path');
  }
}

class _Feedback extends FeedbackRepository {
  _Feedback() : super(ApiClient());
  int schemaRequests = 0;

  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async {
    expect(path, '/missing-catalog/schema');
    schemaRequests++;
    return {
      'fields': [
        {'key': 'name', 'label': '名称', 'type': 'text', 'required': true},
      ],
    };
  }
}

class _Harness {
  const _Harness(this.router, this.container, this.api, this.feedback);
  final GoRouter router;
  final ProviderContainer container;
  final _Api api;
  final _Feedback feedback;
  _Session get session => container.read(sessionProvider.notifier) as _Session;
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool direct = false,
  bool signedIn = false,
  bool firstLogin = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _Api()..firstLogin = firstLogin;
  final feedback = _Feedback();
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      apiClientProvider.overrideWithValue(api),
      feedbackRepositoryProvider.overrideWithValue(feedback),
      catalogProvider.overrideWith(
        (_) async => const CatalogBundle(idols: [], groups: [], cards: []),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (signedIn) {
    (container.read(sessionProvider.notifier) as _Session).authenticate();
  }
  final router = GoRouter(
    initialLocation: direct ? '/catalog/feedback' : '/catalog',
    routes: [
      GoRoute(path: '/catalog', builder: (_, _) => const CatalogPage()),
      GoRoute(
        path: '/catalog/feedback',
        builder: (_, _) => const CatalogMissingFeedbackPage(
          args: CatalogMissingFeedbackRouteArgs(initialNotes: '已有的扫描备注'),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginPage(
          showPhoneForm: true,
          returnTo: state.uri.queryParameters['from'],
        ),
      ),
      GoRoute(
        path: '/onboarding/password',
        builder: (_, _) => const Scaffold(body: Text('设置密码引导')),
      ),
      GoRoute(
        path: '/onboarding/favorites',
        builder: (_, _) => const Scaffold(body: Text('选择本命引导')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: FanOsTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(router, container, api, feedback);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _entry(bool emptyState) => emptyState
    ? find.descendant(
        of: find.byKey(const Key('catalog-groups-empty')),
        matching: find.widgetWithText(OutlinedButton, '反馈缺失内容'),
      )
    : find.byKey(const Key('catalog-missing-feedback'));

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login-phone')), '13812345678');
  await _tap(tester, find.byKey(const Key('login-consent')));
  await _tap(tester, find.byKey(const Key('login-submit')));
  await tester.enterText(find.byKey(const Key('login-code')), '123456');
  await _tap(tester, find.byKey(const Key('login-submit')));
}

void main() {
  for (final emptyState in [false, true]) {
    testWidgets(
      '${emptyState ? 'empty-state' : 'footer'} entry authenticates before opening feedback',
      (tester) async {
        final harness = await _mount(tester);
        await _tap(tester, _entry(emptyState));
        expect(harness.router.state.uri.path, '/login');
        expect(
          harness.router.state.uri.queryParameters['from'],
          '/catalog/feedback',
        );
        expect(harness.feedback.schemaRequests, 0);
        expect(
          find.byType(CatalogMissingFeedbackPage, skipOffstage: false),
          findsNothing,
        );
        expect(find.text('请先登录后反馈缺失内容'), findsOneWidget);

        harness.router.pop();
        await tester.pumpAndSettle();
        expect(harness.router.state.uri.path, '/catalog');
        expect(harness.feedback.schemaRequests, 0);
        // The login hint is intentionally transient and floats over the lower
        // footer. Finish its actual lifetime before tapping that footer again;
        // ensureVisible cannot move a button out from under an overlay.
        final hint = find.byType(SnackBar);
        if (hint.evaluate().isNotEmpty) {
          await tester.pump(tester.widget<SnackBar>(hint).duration);
          await tester.pumpAndSettle();
        }
        await _tap(tester, _entry(emptyState));
        expect(harness.router.state.uri.path, '/login');
        await _login(tester);
        expect(harness.router.state.uri.path, '/catalog/feedback');
        expect(find.byKey(const Key('catalog-missing-name')), findsOneWidget);
        expect(harness.feedback.schemaRequests, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('signed-in catalog entry opens feedback without extra login', (
    tester,
  ) async {
    final harness = await _mount(tester, signedIn: true);
    await _tap(tester, _entry(false));
    expect(harness.router.state.uri.path, '/catalog/feedback');
    expect(find.byType(LoginPage, skipOffstage: false), findsNothing);
    expect(harness.feedback.schemaRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct guest route never loads protected schema before login', (
    tester,
  ) async {
    final harness = await _mount(tester, direct: true);
    expect(harness.router.state.uri.path, '/login');
    expect(harness.feedback.schemaRequests, 0);
    expect(find.byType(Form, skipOffstage: false), findsNothing);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('catalog-missing-login-required')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('submit-catalog-missing-feedback')),
      findsNothing,
    );
    expect(harness.feedback.schemaRequests, 0);

    await _tap(tester, find.text('去登录'));
    await _login(tester);
    expect(harness.router.state.uri.path, '/catalog/feedback');
    expect(harness.feedback.schemaRequests, 1);
    expect(find.text('已有的扫描备注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direct in [false, true]) {
    testWidgets(
      '${direct ? 'direct' : 'catalog'} login leaves new-account onboarding in front',
      (tester) async {
        final harness = await _mount(tester, direct: direct, firstLogin: true);
        if (!direct) await _tap(tester, _entry(false));
        await _login(tester);
        expect(harness.router.state.uri.path, '/onboarding/password');
        expect(
          harness.router.state.uri.queryParameters['from'],
          '/catalog/feedback',
        );
        expect(find.text('设置密码引导'), findsOneWidget);
        expect(harness.feedback.schemaRequests, 0);
        // Complete the independent onboarding flow: its safe return must still
        // lead to feedback, rather than pushing over the password step early.
        harness.session.authenticate();
        harness.router.go('/catalog/feedback');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('catalog-missing-name')), findsOneWidget);
        expect(harness.feedback.schemaRequests, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'session loss hides the form and reauthentication retains its draft',
    (tester) async {
      final harness = await _mount(tester, direct: true, signedIn: true);
      await tester.enterText(
        find.byKey(const Key('catalog-missing-name')),
        '未提交的组合',
      );
      harness.session.expire();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('catalog-missing-login-required')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('catalog-missing-name')), findsNothing);
      expect(harness.feedback.schemaRequests, 1);
      await _tap(tester, find.text('去登录'));
      expect(harness.feedback.schemaRequests, 1);
      await _login(tester);
      expect(find.text('未提交的组合'), findsOneWidget);
      expect(harness.feedback.schemaRequests, 2);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:fan_os/app/app.dart';
import 'package:fan_os/app/router.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _enabled = bool.fromEnvironment('RUN_LOCAL_CONNECTION_SMOKE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native credential storage and local API are available', (
    tester,
  ) async {
    expect(ApiClient.baseUrl, 'http://127.0.0.1:8000/api/v1');
    // Use a separate key: never replace or clear the user's saved session.
    final namespace =
        'native-keychain-smoke-${DateTime.now().microsecondsSinceEpoch}';
    final store = SecureTokenStore(namespace);
    final credentials = <String, dynamic>{
      'access_token': 'test-only-access',
      'refresh_token': 'test-only-refresh',
      'expires_at': DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    };
    addTearDown(store.clear);
    expect(await store.read(), isNull);
    await store.write(credentials);
    expect(await SecureTokenStore(namespace).read(), credentials);
    await store.clear();
    expect(await store.read(), isNull);

    // Reading the normal session namespace must also succeed. Never log it.
    await SecureTokenStore(ApiClient.baseUrl).read();
    final resources = await ApiClient().getData('/albums/resources');
    expect(resources, contains('items'));
    expect(resources['items'], isA<List>());
  }, skip: !_enabled);

  testWidgets(
    'normal app startup finishes without the connection error screen',
    (tester) async {
      expect(ApiClient.baseUrl, 'http://127.0.0.1:8000/api/v1');
      await tester.pumpWidget(const ProviderScope(child: FanOsApp()));
      var ready = false;
      for (var attempt = 0; attempt < 150; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
        ready =
            find.text('开启旅程').evaluate().isNotEmpty ||
            fanOsRouter.routeInformationProvider.value.uri.path == '/home';
        if (ready) break;
      }
      expect(
        ready,
        isTrue,
        reason: 'Startup must finish with the real Keychain',
      );
      expect(find.text('重新连接'), findsNothing);
      expect(find.textContaining('无法恢复登录'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !_enabled,
  );
}

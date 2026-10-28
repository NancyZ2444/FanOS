import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/feedback/catalog_contributors.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final kind in [
    'cards',
    'groups',
    'idols',
    'albums',
    'events',
    'others',
    'versions',
  ]) {
    testWidgets(
      '$kind official-only content has no attribution or reserved space',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogCreditsProvider((kind: kind, id: 'test'))
                  .overrideWith((ref) async => []),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    CatalogContributors(kind: kind, entityId: 'test'),
                    const Text('正文'),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('贡献来源：'), findsNothing);
        expect(tester.getTopLeft(find.text('正文')).dy, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real contributor is linked without copyright reminder on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(20),
                child: CatalogContributors(kind: 'cards', entityId: 'test'),
              ),
            ),
          ),
          GoRoute(
            path: '/user/user-1',
            builder: (_, _) => const Scaffold(body: Text('真实贡献者主页')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogCreditsProvider((kind: 'cards', id: 'test')).overrideWith(
              (ref) async => [
                {
                  'user_id': 'user-1',
                  'name': '真实贡献者',
                  'profile_available': true,
                  'source_type': 'USER_SUBMITTED',
                  'copyright_status': 'OFFICIAL_SOURCE',
                },
              ],
            ),
          ],
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('贡献来源：'), findsOneWidget);
      expect(find.text('真实贡献者'), findsOneWidget);
      expect(find.textContaining('已核实官方来源'), findsNothing);
      expect(find.textContaining('用户提交'), findsNothing);
      await tester.tap(find.text('真实贡献者'));
      await tester.pumpAndSettle();
      expect(find.text('真实贡献者主页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inactive contribution is plain text rather than a disabled action',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogCreditsProvider((kind: 'idols', id: 'test')).overrideWith(
              (ref) async => [
                {
                  'name': '已注销用户',
                  'profile_available': false,
                  'source_type': 'USER_SUBMITTED',
                },
              ],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CatalogContributors(kind: 'idols', entityId: 'test'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已注销用户'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    },
  );
}

import 'package:fan_os/features/shell/presentation/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('light pages reset the status bar after the dark scan branch', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => MainShell(navigationShell: shell),
          branches: [
            for (final name in [
              'home',
              'catalog',
              'scan',
              'library',
              'profile',
            ])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/$name',
                    builder: (_, _) => Scaffold(body: Text(name)),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    SystemUiOverlayStyle style() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .descendant(
                of: find.byType(MainShell),
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .first,
        )
        .value;
    expect(style(), SystemUiOverlayStyle.dark);
    router.go('/scan');
    await tester.pumpAndSettle();
    expect(style(), SystemUiOverlayStyle.light);
    expect(find.byType(NavigationBar), findsNothing);
    router.go('/home');
    await tester.pumpAndSettle();
    expect(style(), SystemUiOverlayStyle.dark);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

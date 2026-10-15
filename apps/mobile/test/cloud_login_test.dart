import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'API login does not autofill demo credentials or claim SMS delivery',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginPage())),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.text('获取验证码'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '13812345678');
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      expect(find.text('演示验证码已填写：666666'), findsNothing);
      expect(find.text('测试环境验证码：666666'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: useMockApi,
  );
  testWidgets('failed API login shows the error and enables retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(_FailedAuth())],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '13812345678');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '654321');
    await tester.tap(find.text('登录并继续'));
    await tester.pump();
    expect(find.text('验证码不正确'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: useMockApi);
}

class _FailedAuth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {
    throw const ApiException('INVALID_VERIFICATION_CODE', '验证码不正确');
  }
}

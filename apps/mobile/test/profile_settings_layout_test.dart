import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/profile/presentation/edit_profile_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'privacy settings keep native switch proportions and fit $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: FanOsTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const EditProfilePage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.backgroundColor!.a, 1);
        expect(find.text('保存'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('公开展示我的本命'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        for (final switchFinder in find.byType(CupertinoSwitch).evaluate()) {
          final size = switchFinder.size!;
          expect(size.width, lessThanOrEqualTo(59));
          expect(size.height, lessThanOrEqualTo(44));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/card_geometry.dart';
import 'package:fan_os/features/daily_card/presentation/daily_card_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('daily cards use the bundled back and a stable photocard ratio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const DailyCardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final images = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/cards/default-card-back.png',
    );
    expect(images, findsNWidgets(3));
    final firstSize = tester.getSize(images.first);
    for (final element in images.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size, firstSize);
      expect(size.width / size.height, closeTo(photocardAspectRatio, .001));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('翻开第一张'));
    await tester.pumpAndSettle();
    expect(images, findsNWidgets(2));
    expect(find.text('查看最新卡片详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/card_geometry.dart';
import 'package:fan_os/features/feedback/feedback_crop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final imageSize in [
    const Size(1000, 1000),
    const Size(1600, 900),
    const Size(900, 1600),
  ]) {
    testWidgets('fixed crop preserves source pixel ratio for $imageSize', (
      tester,
    ) async {
      final size = Size(300, 300 * imageSize.height / imageSize.width);
      var crop = initialPhotocardCrop(imageSize.aspectRatio);
      void verifyRatio() {
        expect(
          crop.width * imageSize.width / (crop.height * imageSize.height),
          closeTo(photocardAspectRatio, .000001),
        );
        expect(crop.left, greaterThanOrEqualTo(-.000001));
        expect(crop.top, greaterThanOrEqualTo(-.000001));
        expect(crop.right, lessThanOrEqualTo(1.000001));
        expect(crop.bottom, lessThanOrEqualTo(1.000001));
      }

      verifyRatio();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: StatefulBuilder(
                  builder: (_, setState) => FeedbackCropCanvas(
                    crop: crop,
                    aspectRatio: photocardAspectRatio,
                    onChanged: (value) => setState(() => crop = value),
                    child: const ColoredBox(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final canvas = find.byKey(const Key('feedback-crop-canvas'));
      final origin = tester.getTopLeft(canvas);
      Future<void> drag(Offset from, Offset by) async {
        final gesture = await tester.startGesture(origin + from);
        await gesture.moveBy(by / 2);
        await gesture.moveBy(by / 2);
        await gesture.up();
        await tester.pump();
        verifyRatio();
      }

      await drag(
        Offset(crop.left * size.width + 2, crop.top * size.height + 2),
        const Offset(50, 60),
      );
      await drag(
        Offset(crop.right * size.width - 2, crop.bottom * size.height - 2),
        const Offset(-35, -30),
      );
      await drag(
        Offset(crop.center.dx * size.width, crop.center.dy * size.height),
        const Offset(-600, -600),
      );
      await drag(
        Offset(crop.right * size.width - 2, crop.bottom * size.height - 2),
        const Offset(800, 800),
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('finger crop resizes, moves and clamps on $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var crop = const Rect.fromLTWH(0, 0, 1, 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width - 48,
                height: 450,
                child: StatefulBuilder(
                  builder: (_, setState) => FeedbackCropCanvas(
                    crop: crop,
                    onChanged: (rect) => setState(() => crop = rect),
                    child: const ColoredBox(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final canvas = find.byKey(const Key('feedback-crop-canvas'));
      final origin = tester.getTopLeft(canvas), size = tester.getSize(canvas);
      Future<void> drag(Offset from, Offset by) async {
        final gesture = await tester.startGesture(from);
        await gesture.moveBy(by / 2);
        await gesture.moveBy(by / 2);
        await gesture.up();
        await tester.pump();
      }

      await drag(origin + const Offset(3, 3), const Offset(55, 70));
      expect(crop.left, greaterThan(0));
      expect(crop.top, greaterThan(0));
      await drag(
        origin + Offset(size.width - 3, size.height - 3),
        const Offset(-45, -55),
      );
      expect(crop.right, lessThan(1));
      expect(crop.bottom, lessThan(1));
      final beforeMove = crop;
      await drag(
        origin +
            Offset(crop.center.dx * size.width, crop.center.dy * size.height),
        const Offset(-150, -180),
      );
      expect(crop.width, closeTo(beforeMove.width, .0001));
      expect(crop.height, closeTo(beforeMove.height, .0001));
      expect(crop.left, 0);
      expect(crop.top, 0);
      expect(crop.right, lessThanOrEqualTo(1));
      expect(crop.bottom, lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });
  }
}

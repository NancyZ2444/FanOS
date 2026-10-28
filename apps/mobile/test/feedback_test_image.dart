import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> feedbackTestImage(WidgetTester tester) async {
  final dir = await tester.runAsync(
    () => Directory.systemTemp.createTemp('fanos-crop-test-'),
  );
  addTearDown(() => dir!.delete(recursive: true));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 320, 320),
    Paint()..color = Colors.purple,
  );
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(320, 320));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  final file = File('${dir!.path}/card.png');
  await tester.runAsync(() => file.writeAsBytes(bytes!.buffer.asUint8List()));
  image!.dispose();
  picture.dispose();
  return file.path;
}

Future<void> waitForFeedbackCrop(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('feedback-crop-confirm')),
    );
    if (button.onPressed != null) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Uploaded test image did not load');
}

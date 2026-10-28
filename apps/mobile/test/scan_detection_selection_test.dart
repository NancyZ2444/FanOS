import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/features/scan/presentation/scan_page.dart';
import 'package:fan_os/features/scan/presentation/scan_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'no-person detection keeps retake and disables scan and select-all',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retakes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: ScanSelection(
              detection: const ScanDetection(
                sessionId: 'no-people',
                regions: [],
              ),
              imageSize: const Size(900, 1200),
              onRetake: () => retakes++,
              onScan: (_) async => fail('An empty detection must not scan'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('未检测到清晰的人物小卡'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('detect-start-scan')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('detect-select-all')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('重拍'));
      expect(retakes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'capture detects only, defaults all selected, retry preserves selection',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [scanDetectionRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const ScanPage(originalLocation: false),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('scan-shutter')));
      await tester.pumpAndSettle();
      expect(repo.detectCalls, 1);
      expect(repo.matchCalls, isEmpty);
      expect(find.text('扫描（4）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detect-thumb-detected-02')));
      await tester.pump();
      expect(find.text('扫描（3）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detect-start-scan')));
      await tester.pumpAndSettle();
      expect(repo.matchCalls.single, {
        'detected-01',
        'detected-03',
        'detected-04',
      });
      expect(find.text('扫描（3）'), findsOneWidget);
      expect(find.textContaining('已保留选中的小卡'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detect-start-scan')));
      await tester.pumpAndSettle();
      expect(repo.matchCalls.length, 2);
      expect(repo.detectCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(375, 812),
    const Size(320, 568),
    const Size(812, 375),
  ]) {
    testWidgets('selection fits $size and empty selection cannot scan', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detection = await MockScanDetectionRepository().detect(null);
      final requests = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: ScanSelection(
              detection: detection,
              imageSize: const Size(900, 1200),
              onRetake: () {},
              onScan: (ids) async => requests.add(ids),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('扫描（4）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detect-select-all')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('detect-start-scan')))
            .onPressed,
        isNull,
      );
      expect(requests, isEmpty);
      await tester.tap(find.byKey(const Key('detect-thumb-detected-01')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('detect-start-scan')));
      await tester.pump();
      expect(requests.single, {'detected-01'});
      expect(tester.takeException(), isNull);
    });
  }
}

class _Repository implements ScanDetectionRepository {
  int detectCalls = 0;
  final matchCalls = <Set<String>>[];
  @override
  Future<ScanDetection> detect(String? path) {
    detectCalls++;
    return MockScanDetectionRepository().detect(path);
  }

  @override
  Future<ScanSession> recognize(
    ScanDetection detection,
    Set<String> ids,
  ) async {
    matchCalls.add(ids);
    throw StateError('Test transient failure');
  }
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/features/scan/presentation/scan_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _corners = [
  {'x': .25, 'y': .1},
  {'x': .8, 'y': .25},
  {'x': .7, 'y': .9},
  {'x': .1, 'y': .75},
];

Map<String, dynamic> _regionJson([Object? corners = _corners]) => {
  'x': .1,
  'y': .1,
  'width': .7,
  'height': .8,
  'corners': ?corners,
};

DetectedScanCard _card(ScanCropRegion region, [String id = 'tilted']) =>
    DetectedScanCard(
      id: id,
      cropRegion: region,
      candidates: const [],
      status: ScanRecognitionStatus.unrecognized,
    );

Widget _selection(List<DetectedScanCard> cards, {bool busy = false}) =>
    MaterialApp(
      theme: FanOsTheme.light,
      home: Scaffold(
        body: ScanSelection(
          detection: ScanDetection(sessionId: 'polygon', regions: cards),
          imageSize: const Size(900, 1200),
          busy: busy,
          onRetake: () {},
          onScan: (_) async {},
        ),
      ),
    );

void main() {
  test(
    'optional ordered corners round-trip while legacy JSON stays unchanged',
    () {
      final polygon = ScanCropRegion.fromJson(_regionJson());
      expect(polygon.corners, hasLength(4));
      expect(polygon.corners![0].x, .25);
      expect(polygon.toJson(), _regionJson());
      final legacy = ScanCropRegion.fromJson(_regionJson(null));
      expect(legacy.corners, isNull);
      expect(legacy.toJson(), _regionJson(null));
    },
  );

  final malformed = <String, Object?>{
    'empty': [],
    'three points': _corners.take(3).toList(),
    'non-map': [false, ..._corners.skip(1)],
    'non-numeric': [
      {'x': '.25', 'y': .1},
      ..._corners.skip(1),
    ],
    'NaN': [
      {'x': double.nan, 'y': .1},
      ..._corners.skip(1),
    ],
    'infinite': [
      {'x': .25, 'y': double.infinity},
      ..._corners.skip(1),
    ],
    'outside image': [
      {'x': -0.1, 'y': .1},
      ..._corners.skip(1),
    ],
    'outside region': [
      {'x': .05, 'y': .1},
      ..._corners.skip(1),
    ],
    'self-crossing': [_corners[0], _corners[2], _corners[1], _corners[3]],
    'zero area': List.filled(4, {'x': .3, 'y': .3}),
  };
  for (final entry in malformed.entries) {
    test('${entry.key} corners safely fall back to rectangle', () {
      final region = ScanCropRegion.fromJson(_regionJson(entry.value));
      expect(region.corners, isNull);
      expect(region.toJson(), _regionJson(null));
    });
  }

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('polygon excludes bounding-box corners at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _selection([_card(ScanCropRegion.fromJson(_regionJson()))]),
      );
      await tester.pumpAndSettle();
      final overlay = find.byKey(const Key('detect-region-tilted'));
      final rect = tester.getRect(overlay);
      final blankCorner =
          rect.topLeft + Offset(rect.width * .02, rect.height * .02);
      await tester.tapAt(blankCorner);
      await tester.pump();
      expect(find.text('扫描（1）'), findsOneWidget);
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(find.text('扫描（0）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detect-thumb-tilted')));
      await tester.pump();
      expect(find.text('扫描（1）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'transparent polygon corner lets a lower region receive the tap',
    (tester) async {
      final polygon = ScanCropRegion.fromJson(_regionJson());
      await tester.pumpWidget(
        _selection([
          _card(
            const ScanCropRegion(x: .1, y: .1, width: .15, height: .15),
            'behind',
          ),
          _card(polygon),
        ]),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const Key('detect-region-tilted')),
      );
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * .04, rect.height * .04),
      );
      await tester.pump();
      expect(find.text('扫描（1）'), findsOneWidget);
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(find.text('扫描（0）'), findsOneWidget);
    },
  );

  for (final corners in [null, malformed['self-crossing']]) {
    testWidgets(
      'legacy or invalid geometry still selects through its rectangle ($corners)',
      (tester) async {
        await tester.pumpWidget(
          _selection([_card(ScanCropRegion.fromJson(_regionJson(corners)))]),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const Key('detect-region-tilted')),
        );
        await tester.tapAt(rect.topLeft + const Offset(12, 12));
        await tester.pump();
        expect(find.text('扫描（0）'), findsOneWidget);
      },
    );
  }

  testWidgets('busy polygon remains selected after a tap', (tester) async {
    await tester.pumpWidget(
      _selection([_card(ScanCropRegion.fromJson(_regionJson()))], busy: true),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('detect-region-tilted'))),
    );
    await tester.pump();
    expect(find.text('正在识别…'), findsOneWidget);
    expect(find.text('已选择 1 / 1 张'), findsOneWidget);
  });
}

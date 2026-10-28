import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/core/data/user_data_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/scan/presentation/scan_spatial_result_page.dart';
import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:fan_os/features/scan/state/scan_spatial_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DetectedScanCard region(
  String id, {
  bool failed = false,
  bool approximate = false,
  bool empty = false,
}) => DetectedScanCard(
  id: id,
  cropRegion: const ScanCropRegion(x: .1, y: .1, width: .3, height: .4),
  candidates: empty || failed
      ? []
      : [
          ScanCandidate(
            card: DemoCatalog.cards.first,
            similarity: .96,
            scores: approximate ? const {'approximate': 1.0} : const {},
          ),
        ],
  matchingFailed: failed,
  status: failed || empty
      ? ScanRecognitionStatus.unrecognized
      : ScanRecognitionStatus.recommended,
);

ScanSession session(List<DetectedScanCard> rows) =>
    ScanSession(id: 'spatial-test', detectedCards: rows);

void main() {
  testWidgets(
    'classic result entry is hidden without removing the original workflow',
    (tester) async {
      await mount(tester, session([region('a')]));
      expect(find.text('经典结果'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('扫描结果'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    },
  );

  testWidgets(
    'no-match drawer follows content rather than an expanded fixed fraction',
    (tester) async {
      await mount(tester, session([region('a'), region('b', empty: true)]));
      await tester.tap(find.byTooltip('展开核对'));
      await tester.pumpAndSettle();
      final expandedHeight = tester
          .getSize(find.byKey(const Key('spatial-detail-panel')))
          .height;
      await tester.tap(find.byKey(const Key('spatial-thumb-b')));
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const Key('spatial-detail-panel')),
      );
      final content = tester.getRect(
        find.byKey(const Key('spatial-detail-content')),
      );
      expect(panel.height, lessThan(expandedHeight - 48));
      expect(panel.bottom - content.bottom, closeTo(12, 1));
      expect(find.text('搜索图鉴').hitTestable(), findsOneWidget);
      expect(find.text('找不到卡？').hitTestable(), findsOneWidget);
      expect(find.byTooltip('展开核对'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'switching unmatched and matched keeps thumbnails against drawer at width $width',
      (tester) async {
        final photo = await cacheLayoutPhoto(tester);
        final container = await mount(
          tester,
          ScanSession(
            id: 'switch-layout',
            originalImagePath: photo,
            detectedCards: [region('missing', empty: true), region('matched')],
          ),
          width: width,
        );

        void expectContinuousLayout() {
          final photo = tester.getRect(
            find.byKey(const Key('spatial-original')),
          );
          final thumbnails = tester.getRect(
            find.byKey(const Key('spatial-thumbnails')),
          );
          final drawer = tester.getRect(
            find.byKey(const Key('spatial-detail-panel')),
          );
          expect(photo.bottom, closeTo(thumbnails.top, .75));
          expect(
            thumbnails.bottom,
            closeTo(drawer.top, .75),
            reason: 'Photo and queue must use the actual drawer extent, including bound changes.',
          );
          expect(tester.takeException(), isNull);
        }

        Future<void> tapAndCheck(Finder target) async {
          await tester.tap(target);
          // Check intermediate animation frames as well as the final position.
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expectContinuousLayout();
          }
          await tester.pumpAndSettle();
          expectContinuousLayout();
          final sheet = tester.widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          );
          expect(
            container
                .read(spatialScanCacheProvider)['switch-layout']!
                .panelExtent,
            closeTo(sheet.controller!.size, .001),
          );
        }

        expectContinuousLayout();
        await tapAndCheck(find.byKey(const Key('spatial-thumb-matched')));
        await tapAndCheck(find.byTooltip('展开核对'));
        // Replacing expanded bounds with the equal min/max of an unmatched
        // drawer does not emit a DraggableScrollableNotification in Flutter.
        await tapAndCheck(find.byKey(const Key('spatial-thumb-missing')));
        await tapAndCheck(find.byKey(const Key('spatial-thumb-matched')));
        await tapAndCheck(find.byTooltip('展开核对'));
        await tapAndCheck(find.byTooltip('收起核对'));
        await tapAndCheck(find.byKey(const Key('spatial-thumb-missing')));
        await tapAndCheck(find.byKey(const Key('spatial-thumb-matched')));
        final state = container.read(
          spatialScanCacheProvider,
        )['switch-layout']!;
        expect(state.selectedId, 'matched');
        expect(state.numberOf('missing'), 1);
        expect(state.numberOf('matched'), 2);
        expect(container.read(collectionProvider).owned, isEmpty);
      },
    );

    testWidgets('matched drawer fits its content at width $width', (
      tester,
    ) async {
      await mount(tester, session([region('a')]), width: width);
      for (final expanded in [false, true]) {
        if (expanded) {
          await tester.tap(find.byTooltip('展开核对'));
          await tester.pumpAndSettle();
        }
        final panel = tester.getRect(
          find.byKey(const Key('spatial-detail-panel')),
        );
        final content = tester.getRect(
          find.byKey(const Key('spatial-detail-content')),
        );
        expect(panel.bottom - content.bottom, closeTo(12, 1));
        expect(find.text('找不到卡？').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  test('drawer viewport changes restore fitted and zoomed photo contexts', () {
    const image = Size(390, 520);
    const compact = Size(390, 420);
    const expanded = Size(390, 230);
    for (final view in [
      const SpatialPhotoView(),
      const SpatialPhotoView(center: Offset(.35, .6), zoom: 2.2),
    ]) {
      final original = view.transformFor(compact, image);
      final smaller = view.transformFor(expanded, image);
      final reprojected = SpatialPhotoView.fromTransform(
        smaller,
        expanded,
        image,
      ).transformFor(compact, image);
      for (var index = 0; index < 16; index++) {
        expect(
          reprojected.storage[index],
          closeTo(original.storage[index], .00001),
        );
      }
    }
    final fit = const SpatialPhotoView().transformFor(compact, image);
    expect(fit.storage[13], closeTo(0, .001));
    expect(fit.storage[12], greaterThan(0));
  });

  testWidgets(
    'expanding then collapsing restores original photo fit and user zoom',
    (tester) async {
      const path = '/scan-layout-fixture.png';
      final provider = FileImage(File(path));
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 390, 520),
          Paint()..color = FanColors.lavenderSoft,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(390, 520);
        PaintingBinding.instance.imageCache.putIfAbsent(
          provider,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image)),
          ),
        );
        picture.dispose();
      });
      addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
      final container = await mount(
        tester,
        ScanSession(
          id: 'photo-resize',
          originalImagePath: path,
          detectedCards: [region('a')],
        ),
      );
      InteractiveViewer viewer() => tester.widget<InteractiveViewer>(
        find.byKey(const Key('spatial-original')),
      );
      for (final zoomed in [false, true]) {
        if (zoomed) {
          viewer().transformationController!.value = Matrix4.identity()
            ..setEntry(0, 0, 1.2)
            ..setEntry(1, 1, 1.2)
            ..setEntry(2, 2, 1.2)
            ..setEntry(0, 3, -42)
            ..setEntry(1, 3, -108);
          viewer().onInteractionEnd!(ScaleEndDetails());
          await tester.pumpAndSettle();
        }
        final before = viewer().transformationController!.value.clone();
        await tester.tap(find.byTooltip('展开核对'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('收起核对'));
        await tester.pumpAndSettle();
        final restored = viewer().transformationController!.value;
        for (var index = 0; index < 16; index++) {
          expect(restored.storage[index], closeTo(before.storage[index], .001));
        }
        expect(
          container.read(spatialScanCacheProvider)['photo-resize']!.selectedId,
          'a',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'missing-card entry opens upload feedback and returns to the same object',
    (tester) async {
      await mount(
        tester,
        session([region('a'), region('missing', empty: true)]),
      );
      await tester.tap(find.byKey(const Key('spatial-thumb-missing')));
      await tester.pumpAndSettle();
      await reach(tester, find.text('找不到卡？'));
      await tester.tap(find.text('找不到卡？'));
      await tester.pumpAndSettle();
      expect(find.text('我要反馈'), findsOneWidget);
      expect(find.byKey(const Key('missing-upload-front')), findsOneWidget);
      expect(find.byKey(const Key('missing-upload-back')), findsOneWidget);
      expect(
        find.byKey(const Key('missing-feedback-source-type')),
        findsOneWidget,
      );
      expect(find.text('将附带扫描原图、裁剪图及候选信息'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('对象 02 · 暂未找到匹配'), findsOneWidget);
      expect(find.text('已反馈'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('approximate results need individual confirmation and selection is not saving', () {
    final item = SpatialScanObject(region('a', approximate: true));
    expect(item.matchState, SpatialMatchState.needsConfirmation);
    expect(item.canSave, isFalse);
    item.select(item.detected.candidates.first);
    expect(item.canSave, isFalse);
    item.confirmed = true;
    item.choosing = false;
    expect(item.canSave, isTrue);
    item.choosing = true;
    expect(item.matchState, SpatialMatchState.needsConfirmation);
    expect(item.canSave, isFalse);
  });

  test('only real unique alternatives appear and choosing does not mutate relationships', () {
    final chosen = ScanCandidate(
      card: DemoCatalog.cards.first,
      similarity: .96,
    );
    final other = ScanCandidate(
      card: DemoCatalog.cards[1],
      similarity: .72,
      scores: const {'approximate': 1},
    );
    final item = SpatialScanObject(
      DetectedScanCard(
        id: 'a',
        cropRegion: const ScanCropRegion(x: 0, y: 0, width: 1, height: 1),
        candidates: [chosen, other, other],
        status: ScanRecognitionStatus.recommended,
      ),
    );
    expect(item.candidates, hasLength(2));
    expect(item.hasOtherCandidates, isTrue);
    item.select(
      ScanCandidate(card: DemoCatalog.cards[2], similarity: 0),
      searched: true,
    );
    item.confirmed = true;
    item.choosing = false;
    item.chooseOtherCandidate();
    expect(item.manuallySearched, isFalse);
    expect(item.chosen, isNull);
    expect(item.canSave, isFalse);
    expect(item.candidates.map((c) => c.card.id), [
      chosen.card.id,
      other.card.id,
    ]);
    expect(
      SpatialScanObject(region('empty', empty: true)).hasOtherCandidates,
      isFalse,
    );
    expect(SpatialScanObject(region('single')).hasOtherCandidates, isFalse);
  });

  test(
    'matching colors use purple, orange and gray independently of selection',
    () {
      expect(
        spatialMatchColor(SpatialMatchState.recommended),
        FanColors.lavender,
      );
      expect(
        spatialMatchColor(SpatialMatchState.confirmed),
        FanColors.lavender,
      );
      expect(
        spatialMatchColor(SpatialMatchState.needsConfirmation),
        const Color(0xFFB76512),
      );
      expect(
        spatialMatchColor(SpatialMatchState.unmatched),
        FanColors.textSecondary,
      );
    },
  );

  test('scan direction follows selected candidate and invalid values use detected direction', () {
    final first = ScanCandidate(
      card: DemoCatalog.cards.first,
      similarity: .96,
      scores: const {'display_rotation_quarter_turns': 0},
    );
    final second = ScanCandidate(
      card: DemoCatalog.cards[1],
      similarity: .72,
      scores: const {'display_rotation_quarter_turns': 2},
    );
    const crop = ScanCropRegion(x: .2, y: .3, width: .3, height: .4);
    final detected = DetectedScanCard(
      id: 'rotated',
      cropRegion: crop,
      displayRotationQuarterTurns: 1,
      candidates: [first, second],
      status: ScanRecognitionStatus.recommended,
    );
    final item = SpatialScanObject(detected);
    expect(item.scanQuarterTurns, 0);
    item.select(second);
    expect(item.scanQuarterTurns, 2);
    expect(item.detected.cropRegion, same(crop));
    for (final invalid in [-1.0, 4.0, 1.5, double.nan]) {
      item.select(
        ScanCandidate(
          card: first.card,
          similarity: .8,
          scores: {'display_rotation_quarter_turns': invalid},
        ),
      );
      expect(item.scanQuarterTurns, 1);
    }
    item.chooseOtherCandidate();
    expect(item.scanQuarterTurns, 1);
  });

  testWidgets(
    'scan preview thumbnail and magnifier share direction without rotating catalog',
    (tester) async {
      await mount(
        tester,
        session([
          DetectedScanCard(
            id: 'rotated',
            cropImagePath: '/missing-test-scan.png',
            cropRegion: const ScanCropRegion(
              x: .1,
              y: .1,
              width: .3,
              height: .4,
            ),
            displayRotationQuarterTurns: 1,
            candidates: [
              ScanCandidate(
                card: DemoCatalog.cards.first,
                similarity: .96,
                scores: const {'display_rotation_quarter_turns': 2},
              ),
            ],
            status: ScanRecognitionStatus.recommended,
          ),
        ]),
      );
      expect(
        tester
            .widget<ScanImage>(
              find.byKey(const Key('spatial-thumb-rotation-rotated')),
            )
            .quarterTurns,
        2,
      );
      expect(
        tester
            .widget<ScanImage>(
              find.byKey(const Key('spatial-scan-preview-rotation')),
            )
            .quarterTurns,
        2,
      );
      expect(
        tester
            .widget<ScanImage>(
              find.descendant(
                of: find.byKey(
                  Key('spatial-official-image-${DemoCatalog.cards.first.id}'),
                ),
                matching: find.byType(ScanImage),
              ),
            )
            .quarterTurns,
        0,
      );
      await tester.tap(find.byKey(const Key('spatial-scan-preview-rotation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScanImage>(
              find.byKey(const Key('spatial-fullscreen-scan-rotation')),
            )
            .quarterTurns,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '90 degree rotation preserves portrait frame and gives raw image landscape bounds',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 148,
              height: 200,
              child: ScanImage(
                path: 'https://example.invalid/test-scan.jpg',
                quarterTurns: 1,
                fallback: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ScanImage)), const Size(148, 200));
      expect(tester.getSize(find.byType(Image)), const Size(200, 148));
      expect(
        find.ancestor(
          of: find.byType(RotatedBox),
          matching: find.byType(AspectRatio),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('summary thumbnail and object status share matching colors', (
    tester,
  ) async {
    await mount(
      tester,
      session([
        region('a'),
        region('b', approximate: true),
        region('c', empty: true),
      ]),
    );
    final summary =
        tester.widget<Text>(find.byKey(const Key('spatial-summary'))).textSpan!
            as TextSpan;
    final spans = summary.children!.whereType<TextSpan>().toList();
    expect(spans[0].style!.color, FanColors.lavender);
    expect(spans[2].style!.color, const Color(0xFFB76512));
    expect(spans[4].style!.color, FanColors.textSecondary);
    await tester.tap(find.byKey(const Key('spatial-thumb-b')));
    await tester.pumpAndSettle();
    final frame =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('spatial-thumb-frame-b')),
                )
                .decoration
            as BoxDecoration;
    expect((frame.border! as Border).top.color, const Color(0xFFB76512));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('spatial-object-title')))
          .style!
          .color,
      const Color(0xFFB76512),
    );
  });

  testWidgets(
    'reported similarity is a bold badge and missing match has no score',
    (tester) async {
      await mount(tester, session([region('a'), region('b', empty: true)]));
      final score = tester.widget<Text>(find.text('相似度 96%'));
      expect(score.style!.fontWeight, FontWeight.w700);
      expect(score.style!.fontSize, 14);
      await tester.tap(find.byKey(const Key('spatial-thumb-b')));
      await tester.pumpAndSettle();
      expect(find.textContaining('相似度'), findsNothing);
    },
  );

  for (final target in ['image', 'info']) {
    testWidgets(
      'official $target opens catalog and returning preserves current object',
      (tester) async {
        await mount(tester, session([region('a'), region('b')]));
        await tester.tap(find.byKey(const Key('spatial-thumb-b')));
        await tester.pumpAndSettle();
        final id = DemoCatalog.cards.first.id;
        await tester.tap(find.byKey(Key('spatial-official-$target-$id')));
        await tester.pumpAndSettle();
        expect(find.text('catalog:$id'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('对象 02 · 推荐匹配'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'collapsed approximate suggestions are horizontal images and scores, with details on tap',
    (tester) async {
      final first = region('a', approximate: true);
      final second = ScanCandidate(card: DemoCatalog.cards[1], similarity: .72);
      await mount(
        tester,
        session([
          DetectedScanCard(
            id: 'a',
            cropRegion: first.cropRegion,
            candidates: [...first.candidates, second],
            status: first.status,
          ),
        ]),
      );
      final rail = find.byKey(const Key('spatial-recommendations'));
      expect(rail, findsOneWidget);
      expect(
        find.descendant(of: rail, matching: find.text('96%')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.text('72%')),
        findsOneWidget,
      );
      expect(find.text(DemoCatalog.cards.first.source), findsNothing);
      expect(
        tester
            .widget<ListView>(
              find.descendant(of: rail, matching: find.byType(ListView)),
            )
            .scrollDirection,
        Axis.horizontal,
      );
      await tester.tap(
        find.byKey(Key('spatial-official-image-${second.card.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('catalog:${second.card.id}'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开核对'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('spatial-candidate-${second.card.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('spatial-select-${second.card.id}')),
        findsOneWidget,
      );
      await reach(tester, find.byKey(Key('spatial-select-${second.card.id}')));
      await tester.tap(find.byKey(Key('spatial-select-${second.card.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('spatial-confirm')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real alternatives are exposed, single candidate has no alternatives entry',
    (tester) async {
      final first = region('a');
      final second = ScanCandidate(card: DemoCatalog.cards[1], similarity: .72);
      await mount(
        tester,
        session([
          DetectedScanCard(
            id: 'a',
            cropRegion: first.cropRegion,
            candidates: [...first.candidates, second],
            status: first.status,
          ),
        ]),
      );
      await tester.tap(find.byTooltip('展开核对'));
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(const Key('spatial-other-candidates')));
      await tester.tap(find.byKey(const Key('spatial-other-candidates')));
      await tester.pumpAndSettle();
      await reach(
        tester,
        find.byKey(Key('spatial-candidate-${second.card.id}')),
      );
      expect(
        find.byKey(Key('spatial-candidate-${second.card.id}')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('spatial-confirm')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(Key('spatial-select-${second.card.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('spatial-confirm')))
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('spatial-owned')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'failed retry keeps IDs, selected object, feedback and viewport state',
    () {
      final state = SpatialScanState(
        session([
          region('a'),
          region('b', failed: true),
          region('c', empty: true),
        ]),
      );
      state.selectedId = 'b';
      state.objects.first.confirmed = true;
      state.objects.last.feedbackSubmitted = true;
      state.thumbnailOffset = 42;
      state.transform.setEntry(0, 3, 31);
      expect(state.counts, (1, 0, 1));
      expect(state.failedCount, 1);
      state.mergeRetry(session([region('c'), region('b'), region('a')]));
      expect(state.objects.map((e) => e.detected.id), ['a', 'b', 'c']);
      expect(state.numberOf('b'), 2);
      expect(state.selectedId, 'b');
      expect(state.objects.first.confirmed, isTrue);
      expect(state.objects.last.feedbackSubmitted, isTrue);
      expect(state.objects.last.matchState, SpatialMatchState.unmatched);
      expect(state.failedCount, 0);
      expect(state.thumbnailOffset, 42);
      expect(state.transform.storage[12], 31);
    },
  );

  test('revealing selected object retains zoom unless object does not fit', () {
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, 2)
      ..setEntry(1, 1, 2)
      ..setEntry(2, 2, 2);
    final visible = keepSpatialObjectVisible(
      matrix,
      const Rect.fromLTWH(200, 200, 40, 60),
      const Size(360, 180),
    );
    expect(visible.getMaxScaleOnAxis(), 2);
    expect(400 + visible.storage[12], greaterThanOrEqualTo(12));
    expect(520 + visible.storage[13], lessThanOrEqualTo(168));
    final reduced = keepSpatialObjectVisible(
      matrix,
      const Rect.fromLTWH(0, 0, 100, 200),
      const Size(360, 180),
    );
    expect(reduced.getMaxScaleOnAxis(), lessThan(2));
  });

  for (final width in [360.0, 390.0]) {
    testWidgets(
      'phone width $width preserves no-match and failure distinction',
      (tester) async {
        await mount(
          tester,
          session([region('a', empty: true), region('b', failed: true)]),
          width: width,
        );
        expect(find.byKey(const Key('spatial-other-candidates')), findsNothing);
        expect(find.text('对象 01 · 暂未找到匹配'), findsOneWidget);
        expect(find.byKey(const Key('spatial-owned')), findsNothing);
        expect(find.byKey(const Key('spatial-confirm')), findsNothing);
        expect(find.textContaining('失败 1'), findsOneWidget);
        await tester.tap(find.byKey(const Key('spatial-thumb-b')));
        await tester.pumpAndSettle();
        expect(find.text('对象 02 · 匹配失败'), findsOneWidget);
        expect(find.byKey(const Key('spatial-retry')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'owned uses atomic ensure, duplicate detections share quantity, wishlist stays independent',
    (tester) async {
      final repository = RecordingScan();
      final edits = RecordingUserData();
      final container = await mount(
        tester,
        session([region('a'), region('b')]),
        scans: repository,
        userData: edits,
      );
      final id = DemoCatalog.cards.first.id;
      await expandIfNeeded(tester);
      await reach(tester, find.byKey(const Key('spatial-owned')));
      await tester.tap(find.byKey(const Key('spatial-owned')));
      await tester.pumpAndSettle();
      expect(repository.calls.single.single.ensureOwned, isTrue);
      expect(repository.calls.single.single.selected, isFalse);
      expect(container.read(collectionProvider).quantity(id), 3);
      expect(container.read(collectionProvider).isWished(id), isFalse);
      await tester.tap(find.byKey(const Key('spatial-thumb-b')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('spatial-owned')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const Key('spatial-wishlist')));
      await tester.tap(find.byKey(const Key('spatial-wishlist')));
      await tester.pumpAndSettle();
      expect(repository.calls.last.single.addToWishlist, isTrue);
      expect(repository.calls.last.single.ensureOwned, isFalse);
      expect(container.read(collectionProvider).quantity(id), 3);
      expect(container.read(collectionProvider).isWished(id), isTrue);
      await expandIfNeeded(tester);
      await reach(tester, find.byKey(const Key('spatial-owned')));
      await tester.tap(find.byKey(const Key('spatial-owned')));
      await tester.pumpAndSettle();
      expect(find.text('取消拥有？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(edits.quantities, [(id, 0)]);
      expect(container.read(collectionProvider).quantity(id), 0);
      expect(container.read(collectionProvider).isWished(id), isTrue);
      await reach(tester, find.byKey(const Key('spatial-wishlist')));
      await tester.tap(find.byKey(const Key('spatial-wishlist')));
      await tester.pumpAndSettle();
      expect(find.text('移出心愿单？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(edits.wishes, [(id, false)]);
      expect(container.read(collectionProvider).isWished(id), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed save keeps relation absent and shows persistent error', (
    tester,
  ) async {
    final repository = RecordingScan()..fail = true;
    final container = await mount(
      tester,
      session([region('a')]),
      scans: repository,
      textScale: 1.5,
    );
    await tester.tap(find.byTooltip('展开核对'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('spatial-owned')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('spatial-detail-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('spatial-owned')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('spatial-owned')));
    await tester.pumpAndSettle();
    expect(container.read(collectionProvider).owned, isEmpty);
    expect(find.byKey(const Key('spatial-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed save after leaving page never uses disposed widget ref',
    (tester) async {
      final pending = Completer<Map<String, int>?>();
      final repository = RecordingScan()..pending = pending;
      await mount(tester, session([region('a')]), scans: repository);
      await tester.ensureVisible(find.byKey(const Key('spatial-owned')));
      await tester.tap(find.byKey(const Key('spatial-owned')));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete({DemoCatalog.cards.first.id: 1});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retry calls only current failed ID and keeps selection', (
    tester,
  ) async {
    final detection = RecordingDetection();
    await mount(
      tester,
      session([region('a'), region('b', failed: true)]),
      detection: detection,
    );
    await tester.tap(find.byKey(const Key('spatial-thumb-b')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('spatial-retry')));
    await tester.tap(find.byKey(const Key('spatial-retry')));
    await tester.pumpAndSettle();
    expect(detection.ids, {'b'});
    expect(find.text('对象 02 · 推荐匹配'), findsOneWidget);
    expect(find.byKey(const Key('spatial-thumb-a')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<String> cacheLayoutPhoto(WidgetTester tester) async {
  const path = '/scan-switch-layout-fixture.png';
  final provider = FileImage(File(path));
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 390, 520),
      Paint()..color = FanColors.lavenderSoft,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(390, 520);
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))),
    );
    picture.dispose();
  });
  addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
  return path;
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  ScanSession value, {
  double width = 390,
  double textScale = 1,
  RecordingScan? scans,
  ScanDetectionRepository? detection,
  UserDataRepository? userData,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(InstantAuth()),
      scanRepositoryProvider.overrideWithValue(scans ?? RecordingScan()),
      if (detection != null)
        scanDetectionRepositoryProvider.overrideWithValue(detection),
      if (userData != null)
        userDataRepositoryProvider.overrideWithValue(userData),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.notifier).login(LoginMethod.phone);
  container.read(collectionProvider.notifier).hydrate({}, {});
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ScanSpatialResultPage(session: value),
      ),
      GoRoute(
        path: '/card/:cardId',
        builder: (_, state) => Scaffold(
          appBar: AppBar(title: const Text('小卡详情')),
          body: Center(
            child: Text('catalog:${state.pathParameters['cardId']}'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: FanOsTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> reach(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.descendant(
      of: find.byKey(const Key('spatial-detail-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> expandIfNeeded(WidgetTester tester) async {
  if (find.byTooltip('展开核对').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('展开核对'));
    await tester.pumpAndSettle();
  }
}

class RecordingUserData extends MockUserDataRepository {
  final quantities = <(String, int)>[];
  final wishes = <(String, bool)>[];
  @override
  Future<void> setOwnedQuantity(String id, int quantity) async =>
      quantities.add((id, quantity));
  @override
  Future<void> setWishlist(String id, bool wished) async =>
      wishes.add((id, wished));
}

class RecordingScan extends MockScanRepository {
  final calls = <List<ScanConfirmation>>[];
  bool fail = false;
  Completer<Map<String, int>?>? pending;
  @override
  Future<Map<String, int>?> confirm(
    String id,
    List<ScanConfirmation> values,
  ) async {
    calls.add(values);
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return {
      for (final value in values)
        if (value.ensureOwned) value.cardId: 3,
    };
  }
}

class RecordingDetection extends MockScanDetectionRepository {
  Set<String>? ids;
  @override
  Future<ScanSession> recognize(
    ScanDetection detection,
    Set<String> selectedIds,
  ) async {
    ids = selectedIds;
    return session([region('a'), region('b')]);
  }
}

class InstantAuth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

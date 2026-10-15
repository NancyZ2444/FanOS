import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:fan_os/features/scan/presentation/scan_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unrecognized card can be manually selected from catalog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: ScanResultPage(
            session: ScanSession(
              id: 'manual-scan',
              detectedCards: [_scanFixture().detectedCards.last],
            ),
          ),
        ),
      ),
    );
    final search = find.text('搜索图鉴');
    await tester.ensureVisible(search);
    await tester.tap(search);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Aria');
    await tester.pump();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('手动选择'), findsOneWidget);
    expect(find.text('标记拥有（1）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wishlist waits for server and never increments owned quantity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ServerScanRepository()..fail = true;
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
        scanRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login(LoginMethod.phone);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: ScanResultPage(
            session: ScanSession(
              id: 'wish-scan',
              detectedCards: [_scanFixture().detectedCards.first],
            ),
          ),
        ),
      ),
    );
    final confirm = find.text('确认是这张');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    final wishlist = find.widgetWithText(TextButton, '喜欢');
    await tester.ensureVisible(wishlist);
    await tester.tap(wishlist);
    await tester.pump();
    expect(
      container.read(collectionProvider).isWished('card-aria-01'),
      isFalse,
    );
    expect(find.text('保存喜欢失败，请稍后重试'), findsOneWidget);
    repository.fail = false;
    await tester.tap(wishlist);
    await tester.pump();
    expect(container.read(collectionProvider).isWished('card-aria-01'), isTrue);
    expect(container.read(collectionProvider).quantity('card-aria-01'), 1);
    expect(repository.lastConfirmation!.selected, isFalse);
    expect(repository.lastConfirmation!.addToWishlist, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'API quantities replace local state and added regions cannot add owned twice',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ServerScanRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
          scanRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: ScanResultPage(session: _scanFixture()),
          ),
        ),
      );
      final first = find.text('确认是这张').first;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pump();
      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pump();
      expect(container.read(collectionProvider).quantity('card-aria-01'), 7);
      expect(repository.confirmCount, 1);
      expect(find.text('已更新为拥有 7 张'), findsOneWidget);
      final candidate = find.text('查看其他相似结果').first;
      await tester.ensureVisible(candidate);
      await tester.pumpAndSettle();
      await tester.tap(candidate);
      await tester.pump();
      expect(find.text('相似结果选择'), findsNothing);
      expect(find.text('标记拥有（0）'), findsOneWidget);
    },
  );

  testWidgets(
    'failed confirmation keeps selections for retry without local quantity changes',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ServerScanRepository()..fail = true;
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
          scanRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: ScanResultPage(session: _scanFixture()),
          ),
        ),
      );
      final first = find.text('确认是这张').first;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pump();
      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pump();
      expect(container.read(collectionProvider).quantity('card-aria-01'), 1);
      expect(find.text('标记拥有（1）'), findsOneWidget);
      repository.fail = false;
      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pump();
      expect(container.read(collectionProvider).quantity('card-aria-01'), 7);
    },
  );

  test('history preserves remote crops and previously added state', () {
    final session = ScanSession.fromJson({
      'session_id': 'scan-history',
      'original_image_path': 'https://example.test/original.jpg',
      'detected_cards': [
        {
          'detected_card_id': 'd1',
          'crop_image_path': 'https://example.test/crop.jpg',
          'crop_region': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          'recognition_status': 'recommended',
          'owned_added': true,
          'user_confirmed_card_id': 'card-aria-01',
          'candidates': [],
        },
      ],
    });
    expect(session.detectedCards.single.ownedAdded, isTrue);
    expect(
      session.detectedCards.single.cropImagePath,
      'https://example.test/crop.jpg',
    );
  });
  test('mock scan returns independent multi-card results', () async {
    final session = await MockScanRepository().recognize();

    expect(session.detectedCards, hasLength(4));
    expect(
      session.detectedCards.map((item) => item.status),
      containsAll([
        ScanRecognitionStatus.recommended,
        ScanRecognitionStatus.needsConfirmation,
        ScanRecognitionStatus.unrecognized,
      ]),
    );
    expect(session.detectedCards.last.candidates, isNotEmpty);
    expect(session.detectedCards.last.userConfirmedCardId, isNull);
  });

  test(
    'nine-card API payload retains every region and independent crop URL',
    () {
      final session = ScanSession.fromJson(_nineCardApiPayload());

      expect(session.detectedCount, 9);
      expect(
        session.originalImagePath,
        'https://scan.example.invalid/original.jpg',
      );
      expect(
        session.detectedCards.map((card) => card.id),
        orderedEquals(List.generate(9, (index) => 'grid-card-${index + 1}')),
      );
      expect(
        session.detectedCards.map((card) => card.cropImagePath),
        orderedEquals(
          List.generate(
            9,
            (index) => 'https://scan.example.invalid/crops/${index + 1}.jpg',
          ),
        ),
      );
      for (var index = 0; index < 9; index++) {
        final card = session.detectedCards[index];
        expect(card.cropRegion.x, closeTo((index % 3) / 3, .000001));
        expect(card.cropRegion.y, closeTo((index ~/ 3) / 3, .000001));
        expect(card.cropRegion.width, closeTo(1 / 3, .000001));
        expect(card.cropRegion.height, closeTo(1 / 3, .000001));
        // Repeated copies of one official card must remain separate detections.
        expect(card.topCandidate!.card.id, 'card-aria-01');
        expect(card.userConfirmedCardId, isNull);
        expect(card.ownedAdded, isFalse);
      }
      expect(
        session.detectedCards.take(8).map((card) => card.status),
        everyElement(ScanRecognitionStatus.recommended),
      );
      expect(
        session.detectedCards.last.status,
        ScanRecognitionStatus.unrecognized,
      );
    },
  );

  testWidgets(
    'nine-card results show independent crops and preserve per-region selections',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _NineCardRecordingRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
          scanRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      final session = ScanSession.fromJson(_nineCardApiPayload());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: ScanResultPage(session: session),
          ),
        ),
      );
      // TestWidgetsFlutterBinding replaces HTTP with offline responses. The
      // real-shaped remote URLs exercise crop routing without external I/O.
      await tester.pumpAndSettle();
      expect(find.text('扫描结果 · 识别到 9 张'), findsOneWidget);
      expect(find.text('标记拥有（0）'), findsOneWidget);
      for (var number = 1; number <= 9; number++) {
        expect(find.text('识别对象 $number'), findsOneWidget);
      }
      final cropImages = tester
          .widgetList<ScanImage>(find.byType(ScanImage))
          .where((image) => image.path?.contains('/crops/') == true);
      expect(
        cropImages.map((image) => image.path),
        orderedEquals(session.detectedCards.map((card) => card.cropImagePath)),
      );

      Finder region(int number) => find
          .ancestor(of: find.text('识别对象 $number'), matching: find.byType(Card))
          .first;
      final firstConfirm = find.descendant(
        of: region(1),
        matching: find.text('确认是这张'),
      );
      await tester.ensureVisible(firstConfirm);
      await tester.pumpAndSettle();
      await tester.tap(firstConfirm);
      await tester.pump();
      expect(find.text('标记拥有（1）'), findsOneWidget);

      // An unmatched ninth region can be confirmed independently; it does not
      // prevent earlier regions from staying selected.
      final ninthCandidates = find.descendant(
        of: region(9),
        matching: find.text('查看相似结果'),
      );
      await tester.ensureVisible(ninthCandidates);
      await tester.pumpAndSettle();
      await tester.tap(ninthCandidates);
      await tester.pumpAndSettle();
      expect(find.text('相似结果选择'), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('标记拥有（2）'), findsOneWidget);
      expect(
        find.descendant(of: region(1), matching: find.text('✓ 已确认')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: region(9), matching: find.text('✓ 已确认')),
        findsOneWidget,
      );

      final firstCheckbox = find.byKey(
        const Key('scan-region-select-grid-card-1'),
      );
      await tester.ensureVisible(firstCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(firstCheckbox);
      await tester.pump();
      expect(find.text('标记拥有（1）'), findsOneWidget);
      final ninthCheckbox = find.byKey(
        const Key('scan-region-select-grid-card-9'),
      );
      expect(tester.widget<Checkbox>(ninthCheckbox).value, isTrue);
      await tester.tap(firstCheckbox);
      await tester.pump();
      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pump();

      expect(repository.sessionId, session.id);
      expect(
        repository.confirmations.map((card) => card.detectedCardId),
        orderedEquals(['grid-card-1', 'grid-card-9']),
      );
      expect(
        repository.confirmations.map((card) => card.cardId),
        orderedEquals(['card-aria-01', 'card-aria-01']),
      );
      expect(container.read(collectionProvider).quantity('card-aria-01'), 3);
      expect(find.text('已标记拥有'), findsNWidgets(2));
      expect(find.text('确认是这张'), findsNWidgets(7));
      expect(find.text('标记拥有（0）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('feedback metadata keeps scan context and candidate similarities', () {
    final session = _scanFixture();
    final detected = session.detectedCards.last;
    final request = ScanFeedbackRequest(
      sessionId: session.id,
      detectedCardId: detected.id,
      cropRegion: detected.cropRegion,
      candidates: detected.candidates,
      userId: '10086',
      source: '签售',
    );

    final json = request.toJson();
    expect(json['scan_session_id'], session.id);
    expect(json['detected_card_id'], detected.id);
    expect(json['crop_region'], isA<Map<String, double>>());
    expect(json['ai_candidates'], hasLength(2));
    expect(json['source'], '签售');
  });

  testWidgets('confirmed scan cards can be added in one batch', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login(LoginMethod.phone);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: ScanResultPage(session: _scanFixture()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('扫描结果 · 识别到 4 张'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('暂未找到匹配的小卡'), findsOneWidget);
    expect(find.text('标记拥有（0）'), findsOneWidget);

    final firstConfirm = find.text('确认是这张').first;
    await tester.ensureVisible(firstConfirm);
    await tester.tap(firstConfirm);
    await tester.pump();
    expect(find.text('标记拥有（1）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-batch-confirm')));
    await tester.pump();
    expect(container.read(collectionProvider).quantity('card-aria-01'), 2);
    expect(find.text('已更新为拥有 2 张'), findsOneWidget);
    expect(find.text('标记拥有（0）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback form exposes optional searchable metadata fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login(LoginMethod.phone);
    final session = _scanFixture();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: ScanFeedbackPage(
            args: ScanFeedbackRouteArgs(
              session: session,
              detectedCard: session.detectedCards.last,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text('帮助我们补充官方图鉴'), findsOneWidget);
    expect(find.text('所属组合'), findsOneWidget);
    expect(find.text('Idol'), findsOneWidget);
    expect(find.text('卡片来源'), findsOneWidget);
    expect(find.text('备注（选填）'), findsOneWidget);
    expect(find.byKey(const Key('submit-scan-feedback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ScanSession _scanFixture() {
  final cards = DemoCatalog.cards;
  ScanCandidate candidate(int index, double similarity) =>
      ScanCandidate(card: cards[index], similarity: similarity);
  return ScanSession(
    id: 'scan-test',
    detectedCards: [
      DetectedScanCard(
        id: 'detected-01',
        cropRegion: const ScanCropRegion(
          x: .08,
          y: .08,
          width: .38,
          height: .39,
        ),
        candidates: [candidate(0, .96), candidate(1, .72)],
        status: ScanRecognitionStatus.recommended,
      ),
      DetectedScanCard(
        id: 'detected-02',
        cropRegion: const ScanCropRegion(
          x: .54,
          y: .08,
          width: .38,
          height: .39,
        ),
        candidates: [candidate(1, .92), candidate(0, .74)],
        status: ScanRecognitionStatus.recommended,
      ),
      DetectedScanCard(
        id: 'detected-03',
        cropRegion: const ScanCropRegion(
          x: .08,
          y: .53,
          width: .38,
          height: .39,
        ),
        candidates: [candidate(3, .81), candidate(4, .76)],
        status: ScanRecognitionStatus.needsConfirmation,
      ),
      DetectedScanCard(
        id: 'detected-04',
        cropRegion: const ScanCropRegion(
          x: .54,
          y: .53,
          width: .38,
          height: .39,
        ),
        candidates: [candidate(5, .44), candidate(6, .39)],
        status: ScanRecognitionStatus.unrecognized,
      ),
    ],
  );
}

class _InstantAuthRepository implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

Map<String, dynamic> _nineCardApiPayload() => {
  'session_id': 'scan-grid-nine',
  'original_image_path': 'https://scan.example.invalid/original.jpg',
  'detected_cards': List.generate(
    9,
    (index) => {
      'detected_card_id': 'grid-card-${index + 1}',
      'crop_image_path': 'https://scan.example.invalid/crops/${index + 1}.jpg',
      'crop_region': {
        'x': (index % 3) / 3,
        'y': (index ~/ 3) / 3,
        'width': 1 / 3,
        'height': 1 / 3,
      },
      'recognition_status': index == 8 ? 'unrecognized' : 'recommended',
      'user_confirmed_card_id': null,
      'owned_added': false,
      'candidates': [
        {
          'similarity': index == 8 ? .44 : .96,
          'card': {
            'id': 'card-aria-01',
            'title': 'Aria · Grid Scan Card',
            'idol_id': 'aria',
            'idol_name': 'Aria',
            'group_id': 'lune',
            'group_name': 'LUNE',
            'source': 'The First Light',
            'card_type': 'Album Card',
            'version': 'POB',
            'release_date': '2026-01-01',
            'region': 'Korea',
            'image_url': null,
          },
        },
      ],
    },
  ),
};

class _NineCardRecordingRepository extends MockScanRepository {
  String? sessionId;
  List<ScanConfirmation> confirmations = [];

  @override
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> confirmations,
  ) async {
    this.sessionId = sessionId;
    this.confirmations = List.of(confirmations);
    return {'card-aria-01': 3};
  }
}

class _ServerScanRepository extends MockScanRepository {
  int confirmCount = 0;
  bool fail = false;
  ScanConfirmation? lastConfirmation;
  @override
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> confirmations,
  ) async {
    confirmCount++;
    lastConfirmation = confirmations.first;
    if (fail) throw StateError('Connection dropped');
    return {'card-aria-01': 7};
  }
}

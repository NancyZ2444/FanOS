import 'package:fan_os/app/app.dart';
import 'package:fan_os/app/router.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_feedback_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/state/scan_feedback_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _ScanRecorder extends MockScanRepository {
  final batches = <List<ScanConfirmation>>[];
  final submissions = <ScanFeedbackRequest>[];
  @override
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> cards,
  ) async {
    batches.add(cards);
    return null;
  }

  @override
  Future<void> submitFeedback(ScanFeedbackRequest request) async {
    submissions.add(request);
    await super.submitFeedback(request);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS compact scan batches, card navigation and official-source feedback',
    (tester) async {
      // Mock-only UI test: never changes the real account or backend database.
      expect(useMockApi, isTrue);
      final scans = _ScanRecorder();
      final options = MockScanFeedbackOptionsRepository();
      final container = ProviderContainer(
        overrides: [
          scanRepositoryProvider.overrideWithValue(scans),
          scanFeedbackOptionsRepositoryProvider.overrideWithValue(options),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      });
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      final session = ScanSession(
        id: 'native-scan-ui',
        detectedCards: [
          for (var index = 0; index < 9; index++)
            DetectedScanCard(
              id: 'r${index + 1}',
              cropRegion: ScanCropRegion(
                x: (index % 3) / 3,
                y: (index ~/ 3) / 3,
                width: 1 / 3,
                height: 1 / 3,
              ),
              status: index < 7
                  ? ScanRecognitionStatus.recommended
                  : index == 7
                  ? ScanRecognitionStatus.needsConfirmation
                  : ScanRecognitionStatus.unrecognized,
              candidates: index == 8
                  ? []
                  : [
                      ScanCandidate(
                        card: DemoCatalog.cards[index % 2],
                        similarity: index < 7 ? .96 : .75,
                      ),
                    ],
            ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FanOsApp(),
        ),
      );
      fanOsRouter.go('/scan-result', extra: session);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('ios-scan-compact-results');
      await tester.tap(find.byKey(const Key('scan-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认推荐并全选'));
      await tester.pumpAndSettle();
      expect(find.text('标记拥有（7）'), findsOneWidget);
      final before = container.read(collectionProvider).owned;
      await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
      await tester.pumpAndSettle();
      expect(container.read(collectionProvider).owned, before);
      expect(
        scans.batches.single.every(
          (card) => !card.selected && card.addToWishlist,
        ),
        isTrue,
      );
      expect(find.text('标记拥有（7）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pumpAndSettle();
      expect(scans.batches.last, hasLength(7));
      expect(
        scans.batches.last.every(
          (card) => card.selected && !card.addToWishlist,
        ),
        isTrue,
      );
      expect(find.text('标记拥有（0）'), findsOneWidget);
      await binding.takeScreenshot('ios-scan-batch-complete');

      final official = find.byKey(const Key('scan-official-r7'));
      await tester.ensureVisible(official);
      await tester.pumpAndSettle();
      final offset = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      await tester.tap(official);
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        closeTo(offset, 1),
      );
      expect(find.text('标记拥有（0）'), findsOneWidget);

      final feedback = find.descendant(
        of: find.byKey(const Key('scan-region-r9')),
        matching: find.text('主动反馈'),
      );
      await tester.ensureVisible(feedback);
      await tester.pumpAndSettle();
      await tester.tap(feedback);
      await tester.pumpAndSettle();
      expect(find.byType(ScanFeedbackPage), findsOneWidget);
      final source = find.byKey(const Key('scan-feedback-source'));
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('专辑').last);
      await tester.pumpAndSettle();
      final picker = find.byKey(const Key('scan-feedback-official-picker'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('official-source-album-starlit')),
      );
      await tester.pumpAndSettle();
      final version = find.byKey(
        const ValueKey('source-version-album-starlit'),
      );
      await tester.ensureVisible(version);
      await tester.tap(version);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moon Ver.').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scan-feedback-notes')),
        '保留原备注，缺少签售版本',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final missing = find.byKey(const Key('scan-feedback-missing-version'));
      await tester.ensureVisible(missing);
      await tester.tap(missing);
      await tester.pumpAndSettle();
      expect(find.byType(CatalogMissingFeedbackPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('catalog-missing-name')),
        'Offline Fansign Ver.',
      );
      final submitMissing = find.byKey(
        const Key('submit-catalog-missing-feedback'),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(submitMissing);
      await tester.tap(submitMissing);
      await tester.pumpAndSettle();
      expect(
        options.suggestions.single.suggested['missing_kind'],
        'ALBUM_VERSION',
      );
      expect(
        options.suggestions.single.suggested['scan_session_id'],
        session.id,
      );
      expect(find.byType(ScanFeedbackPage), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('scan-feedback-notes')))
            .controller!
            .text,
        '保留原备注，缺少签售版本',
      );
      await binding.takeScreenshot('ios-scan-feedback-official-source');
      // The successful missing-content toast briefly covers the form's CTA.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      final submit = find.byKey(const Key('submit-scan-feedback'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(scans.submissions.single.sourceEntityId, 'album-starlit');
      expect(scans.submissions.single.sourceVersionId, isNotNull);
      expect(find.text('我的扫描反馈'), findsOneWidget);
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.text('扫描结果 · 识别到 9 张'), findsOneWidget);
      expect(find.text('标记拥有（0）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !const bool.fromEnvironment('RUN_SCAN_UI_E2E'),
  );
}

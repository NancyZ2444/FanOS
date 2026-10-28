import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/user_data_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/scan/presentation/scan_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'approximate marker is explicit and older responses remain supported',
    () {
      const card = {
        'id': 'card',
        'title': 'Card',
        'idol_name': 'Idol',
        'group_name': 'Group',
        'source': '',
        'card_type': '',
        'version': '',
        'release_date': '',
        'region': '',
      };
      ScanCandidate parse(Object? scores) => ScanCandidate.fromJson({
        'card': card,
        'similarity': .99,
        'scores': scores,
      });
      expect(parse({'approximate': 1}).isApproximate, isTrue);
      expect(parse({'approximate': 1.0}).isApproximate, isTrue);
      for (final scores in [
        null,
        {},
        {'approximate': 0},
        {'approximate': '1'},
        {'approximate': true},
        {'approximate': double.nan},
      ]) {
        expect(parse(scores).isApproximate, isFalse);
      }
    },
  );

  for (final status in [
    ScanRecognitionStatus.needsConfirmation,
    ScanRecognitionStatus.recommended,
  ]) {
    testWidgets(
      'approximate $status requires individual choice before saving',
      (tester) async {
        final repository = _RecordingRepository();
        final card = DemoCatalog.cards.first;
        final container = await _mount(
          tester,
          repository,
          session: _approximateSession(status),
        );
        expect(find.text('相似候选，需手动确认'), findsOneWidget);
        expect(_selected(tester, 'approximate'), isFalse);
        expect(
          find.byKey(const Key('scan-official-approximate')),
          findsNothing,
        );
        await _selectRecommended(tester);
        expect(_selected(tester, 'approximate'), isFalse);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('scan-batch-confirm')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('scan-batch-wishlist')),
              )
              .onPressed,
          isNull,
        );
        expect(repository.calls, isEmpty);
        expect(container.read(collectionProvider).owned, isEmpty);
        expect(container.read(collectionProvider).wishlist, isEmpty);

        await tester.tap(
          find.byKey(const Key('scan-region-select-approximate')),
        );
        await tester.pumpAndSettle();
        expect(find.text('相似结果选择'), findsOneWidget);
        expect(find.text('相似候选，需手动确认').hitTestable(), findsOneWidget);
        final option = find.widgetWithText(ListTile, card.displayTitle);
        expect(
          find.descendant(
            of: option,
            matching: find.byIcon(Icons.check_circle_rounded),
          ),
          findsNothing,
        );
        expect(repository.calls, isEmpty);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(_selected(tester, 'approximate'), isTrue);
        expect(find.text('相似候选 · 已手动确认'), findsOneWidget);
        expect(repository.calls, isEmpty);
        expect(container.read(collectionProvider).owned, isEmpty);
        expect(container.read(collectionProvider).wishlist, isEmpty);

        await tester.tap(find.byKey(const Key('scan-batch-confirm')));
        await tester.pumpAndSettle();
        expect(repository.calls.single.single.cardId, card.id);
        expect(container.read(collectionProvider).quantity(card.id), 1);
        expect(container.read(collectionProvider).wishlist, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inline approximate choice still needs an explicit save', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    final card = DemoCatalog.cards.first;
    final container = await _mount(
      tester,
      repository,
      session: _approximateSession(ScanRecognitionStatus.needsConfirmation),
    );
    await tester.tap(find.byKey(Key('scan-choose-candidate-${card.id}')));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'approximate'), isTrue);
    expect(repository.calls, isEmpty);
    expect(container.read(collectionProvider).owned, isEmpty);
    expect(container.read(collectionProvider).wishlist, isEmpty);
    await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
    await tester.pumpAndSettle();
    expect(repository.calls.single.single.addToWishlist, isTrue);
    expect(repository.calls.single.single.selected, isFalse);
    expect(container.read(collectionProvider).isWished(card.id), isTrue);
    expect(container.read(collectionProvider).owned, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'batch likes wait for the server and keep owned actions independent',
    (tester) async {
      final repository = _RecordingRepository();
      final container = await _mount(tester, repository);
      await _selectRecommended(tester);
      expect(repository.calls, isEmpty);
      expect(find.text('标记拥有（2）'), findsOneWidget);
      expect(find.text('喜欢（2）'), findsOneWidget);

      repository.pending = Completer<Map<String, int>?>();
      await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
      await tester.pump();
      expect(container.read(collectionProvider).wishlist, isEmpty);
      expect(container.read(collectionProvider).owned, isEmpty);
      final likeCall = repository.calls.single;
      expect(likeCall.map((item) => item.detectedCardId), [
        'recommended-1',
        'recommended-2',
      ]);
      expect(
        likeCall.every((item) => !item.selected && item.addToWishlist),
        isTrue,
      );
      // Even if the service returns quantities, a Wishlist-only operation must
      // never use them to overwrite the user's Owned state.
      repository.pending!.complete({'card-aria-01': 99});
      repository.pending = null;
      await tester.pumpAndSettle();
      expect(container.read(collectionProvider).wishlist, {
        DemoCatalog.cards[0].id,
        DemoCatalog.cards[1].id,
      });
      expect(container.read(collectionProvider).owned, isEmpty);
      expect(find.text('喜欢（0）'), findsOneWidget);
      expect(find.text('标记拥有（2）'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(2));
      expect(
        repository.calls.last.every(
          (item) => item.selected && !item.addToWishlist,
        ),
        isTrue,
      );
      expect(
        container.read(collectionProvider).quantity(DemoCatalog.cards[0].id),
        1,
      );
      expect(
        container.read(collectionProvider).quantity(DemoCatalog.cards[1].id),
        1,
      );
      expect(container.read(collectionProvider).wishlist, hasLength(2));
      expect(find.text('标记拥有（0）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed batch likes preserve selection and can be retried', (
    tester,
  ) async {
    final repository = _RecordingRepository()..fail = true;
    final container = await _mount(tester, repository);
    await _selectRecommended(tester);
    await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
    await tester.pump();
    expect(container.read(collectionProvider).wishlist, isEmpty);
    expect(container.read(collectionProvider).owned, isEmpty);
    expect(find.text('批量喜欢失败，请稍后重试'), findsOneWidget);
    expect(find.text('喜欢（2）'), findsOneWidget);
    expect(find.text('标记拥有（2）'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
    await tester.pumpAndSettle();
    expect(container.read(collectionProvider).wishlist, hasLength(2));
    expect(container.read(collectionProvider).owned, isEmpty);
    expect(repository.calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk selection is explicit and clear keeps all scan regions', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    final container = await _mount(tester, repository);
    await tester.tap(find.byKey(const Key('scan-select-all')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('标记拥有（2）'), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(find.text('标记拥有（2）'), findsOneWidget);
    expect(find.text('喜欢（2）'), findsOneWidget);
    expect(container.read(collectionProvider).owned, isEmpty);
    expect(container.read(collectionProvider).wishlist, isEmpty);
    expect(_selected(tester, 'recommended-1'), isTrue);
    expect(_selected(tester, 'recommended-2'), isTrue);
    expect(_selected(tester, 'medium'), isFalse);
    expect(_selected(tester, 'unknown'), isFalse);

    await tester.tap(find.byKey(const Key('scan-clear-selection')));
    await tester.pump();
    expect(find.text('标记拥有（0）'), findsOneWidget);
    expect(find.text('喜欢（0）'), findsOneWidget);
    for (final id in ['recommended-1', 'recommended-2', 'medium', 'unknown']) {
      expect(find.byKey(Key('scan-region-$id')), findsOneWidget);
      expect(_selected(tester, id), isFalse);
    }
    // Clearing cancels inclusion, not the previously confirmed result.
    await tester.tap(find.byKey(const Key('scan-region-select-recommended-1')));
    await tester.pump();
    expect(find.text('标记拥有（1）'), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeat physical cards add two owned copies but one liked card', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    final container = await _mount(
      tester,
      repository,
      session: _fixture(duplicate: true),
    );
    await _selectRecommended(tester);
    expect(find.text('标记拥有（2）'), findsOneWidget);
    expect(find.text('喜欢（1）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
    await tester.pumpAndSettle();
    expect(container.read(collectionProvider).wishlist, {
      DemoCatalog.cards[0].id,
    });
    expect(
      container.read(collectionProvider).quantity(DemoCatalog.cards[0].id),
      0,
    );
    await tester.tap(find.byKey(const Key('scan-batch-confirm')));
    await tester.pumpAndSettle();
    expect(repository.calls.last.map((item) => item.detectedCardId), [
      'recommended-1',
      'recommended-2',
    ]);
    expect(repository.calls.last.map((item) => item.cardId), [
      DemoCatalog.cards[0].id,
      DemoCatalog.cards[0].id,
    ]);
    expect(
      container.read(collectionProvider).quantity(DemoCatalog.cards[0].id),
      2,
    );
    expect(container.read(collectionProvider).wishlist, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('already added history can be liked without adding owned again', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    final card = DemoCatalog.cards.first;
    final container = await _mount(
      tester,
      repository,
      session: ScanSession(
        id: 'history-already-owned',
        detectedCards: [
          DetectedScanCard(
            id: 'already-added',
            cropRegion: const ScanCropRegion(x: 0, y: 0, width: 1, height: 1),
            candidates: [ScanCandidate(card: card, similarity: .98)],
            status: ScanRecognitionStatus.recommended,
            userConfirmedCardId: card.id,
            ownedAdded: true,
          ),
        ],
      ),
    );
    container.read(collectionProvider.notifier).hydrate({card.id: 3}, {});
    await tester.pump();
    expect(find.text('标记拥有（0）'), findsOneWidget);
    expect(find.text('喜欢（1）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
    await tester.pumpAndSettle();
    expect(container.read(collectionProvider).quantity(card.id), 3);
    expect(container.read(collectionProvider).isWished(card.id), isTrue);
    expect(repository.calls.single.single.selected, isFalse);
    expect(repository.calls.single.single.addToWishlist, isTrue);
    final ownedButton = tester.widget<FilledButton>(
      find.byKey(const Key('scan-batch-confirm')),
    );
    expect(ownedButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'official card detail returns to the selected scan list and offset',
    (tester) async {
      final repository = _RecordingRepository();
      await _mount(tester, repository);
      await _selectRecommended(tester);
      final official = find.byKey(const Key('scan-official-recommended-2'));
      await tester.ensureVisible(official);
      await tester.pumpAndSettle();
      final scrollList = find
          .descendant(
            of: find.byType(ScanResultPage),
            matching: find.byType(ListView),
          )
          .first;
      final controller = tester.widget<ListView>(scrollList).controller!;
      final position = controller.offset;
      await tester.tap(official);
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsOneWidget);
      expect(find.text('小卡详情'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsNothing);
      expect(find.text('标记拥有（2）'), findsOneWidget);
      expect(_selected(tester, 'recommended-2'), isTrue);
      expect(controller.offset, closeTo(position, .1));
      expect(repository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate detail returns to the picker without confirming a card',
    (tester) async {
      final repository = _RecordingRepository();
      await _mount(tester, repository);
      final region = find.byKey(const Key('scan-region-medium'));
      final candidates = find.descendant(
        of: region,
        matching: find.text('查看相似结果'),
      );
      await tester.ensureVisible(candidates);
      await tester.pumpAndSettle();
      await tester.tap(candidates);
      await tester.pumpAndSettle();
      final picker = find.byType(BottomSheet);
      expect(find.text('相似结果选择'), findsOneWidget);
      await tester.tap(
        find.descendant(of: picker, matching: find.byTooltip('查看小卡详情')).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('相似结果选择'), findsOneWidget);
      // Viewing a candidate does not silently turn it into a selection.
      expect(find.text('标记拥有（0）'), findsOneWidget);
      expect(repository.calls, isEmpty);
      await tester.tap(
        find.descendant(of: picker, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('相似结果选择'), findsNothing);
      expect(find.text('标记拥有（1）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate picker can search beyond AI candidates without losing the region',
    (tester) async {
      final repository = _RecordingRepository();
      await _mount(tester, repository);
      final candidates = find.descendant(
        of: find.byKey(const Key('scan-region-recommended-1')),
        matching: find.text('查看其他相似结果'),
      );
      await tester.ensureVisible(candidates);
      await tester.tap(candidates);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidates-search')));
      await tester.pumpAndSettle();
      expect(find.text('相似结果选择'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Aria');
      await tester.pump();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.text('标记拥有（1）'), findsOneWidget);
      expect(repository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog search detail preserves the search and scan selection', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await _mount(tester, repository);
    final search = find.descendant(
      of: find.byKey(const Key('scan-region-unknown')),
      matching: find.text('搜索图鉴'),
    );
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Aria');
    await tester.pump();
    final picker = find.byType(BottomSheet);
    await tester.tap(
      find.descendant(of: picker, matching: find.byTooltip('查看小卡详情')).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CardDetailPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Aria',
    );
    expect(find.text('标记拥有（0）'), findsOneWidget);
    await tester.tap(
      find.descendant(of: picker, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('手动选择'), findsOneWidget);
    expect(find.text('标记拥有（1）'), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel likes and owned independently, restore without replaying scan',
    (tester) async {
      final scans = _RecordingRepository();
      final edits = _CollectionEdits();
      final container = await _mount(tester, scans, userData: edits);
      await _selectRecommended(tester);
      await tester.tap(find.byKey(const Key('scan-batch-wishlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-batch-confirm')));
      await tester.pumpAndSettle();
      final id = DemoCatalog.cards[0].id;
      container.read(collectionProvider.notifier).hydrate({id: 3}, {id});
      await tester.pump();
      final owned = find.byKey(const Key('scan-owned-recommended-1'));
      await tester.ensureVisible(owned);
      await tester.tap(owned);
      await tester.pumpAndSettle();
      expect(find.textContaining('当前拥有 3 张'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '取消拥有'));
      await tester.pumpAndSettle();
      expect(edits.quantities, [(id, 0)]);
      expect(container.read(collectionProvider).quantity(id), 0);
      expect(container.read(collectionProvider).isWished(id), isTrue);
      await tester.ensureVisible(owned);
      await tester.tap(owned);
      await tester.pumpAndSettle();
      expect(container.read(collectionProvider).quantity(id), 1);
      expect(edits.quantities, [(id, 0), (id, 1)]);
      expect(scans.calls, hasLength(2));
      final likes = find.byKey(const Key('scan-like-recommended-1'));
      await Scrollable.ensureVisible(tester.element(likes), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(likes);
      await tester.pumpAndSettle();
      expect(edits.likes, [(id, false)]);
      expect(container.read(collectionProvider).isWished(id), isFalse);
      expect(container.read(collectionProvider).quantity(id), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed cancellation retains quantity and retry selection', (
    tester,
  ) async {
    final edits = _CollectionEdits()..fail = true;
    final container = await _mount(
      tester,
      _RecordingRepository(),
      userData: edits,
    );
    await _selectRecommended(tester);
    final id = DemoCatalog.cards[0].id;
    container.read(collectionProvider.notifier).hydrate({id: 2}, {id});
    await tester.pump();
    final action = find.byKey(const Key('scan-owned-recommended-1'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '取消拥有'));
    await tester.pumpAndSettle();
    expect(container.read(collectionProvider).quantity(id), 2);
    expect(container.read(collectionProvider).isWished(id), isTrue);
    expect(_selected(tester, 'recommended-1'), isTrue);
    expect(find.text('保存失败，原状态已保留，请重试'), findsOneWidget);
  });

  for (final state in ['missing', 'error', 'loading']) {
    testWidgets('card detail $state state can return to selected scans', (
      tester,
    ) async {
      final repository = _RecordingRepository();
      final pending = Completer<CatalogBundle>();
      const emptyCatalog = CatalogBundle(idols: [], groups: [], cards: []);
      Future<CatalogBundle> loadCatalog() => switch (state) {
        'missing' => Future.value(emptyCatalog),
        'error' => Future.error(StateError('Catalog unavailable')),
        _ => pending.future,
      };
      await _mount(tester, repository, loadCatalog: loadCatalog);
      await _selectRecommended(tester);
      await tester.tap(find.byKey(const Key('scan-official-recommended-1')));
      if (state == 'loading') {
        // Do not wait for the intentionally pending catalog request.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } else {
        await tester.pumpAndSettle();
        expect(
          find.text(state == 'missing' ? '没有找到这张小卡' : '小卡加载失败'),
          findsOneWidget,
        );
      }
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 350));
      if (state == 'loading') pending.complete(emptyCatalog);
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsNothing);
      expect(find.text('标记拥有（2）'), findsOneWidget);
      expect(_selected(tester, 'recommended-1'), isTrue);
      expect(_selected(tester, 'recommended-2'), isTrue);
      expect(repository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

ScanSession _approximateSession(ScanRecognitionStatus status) => ScanSession(
  id: 'approximate-session',
  detectedCards: [
    DetectedScanCard(
      id: 'approximate',
      cropRegion: const ScanCropRegion(x: 0, y: 0, width: 1, height: 1),
      candidates: [
        ScanCandidate(
          card: DemoCatalog.cards.first,
          similarity: .72,
          scores: const {'approximate': 1.0},
        ),
      ],
      status: status,
    ),
  ],
);

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _RecordingRepository repository, {
  ScanSession? session,
  UserDataRepository? userData,
  Future<CatalogBundle> Function()? loadCatalog,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
      scanRepositoryProvider.overrideWithValue(repository),
      if (userData != null)
        userDataRepositoryProvider.overrideWithValue(userData),
      if (loadCatalog != null)
        catalogProvider.overrideWith((ref) => loadCatalog()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.notifier).login(LoginMethod.phone);
  container.read(collectionProvider.notifier).hydrate({}, {});
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FanOsTheme.light,
        home: ScanResultPage(session: session ?? _fixture()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _selectRecommended(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scan-select-all')));
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String id) =>
    tester.widget<Checkbox>(find.byKey(Key('scan-region-select-$id'))).value!;

ScanSession _fixture({bool duplicate = false}) {
  DetectedScanCard region(
    String id,
    int cardIndex,
    ScanRecognitionStatus status,
  ) => DetectedScanCard(
    id: id,
    cropRegion: const ScanCropRegion(x: 0, y: 0, width: .3, height: .3),
    candidates: [
      ScanCandidate(card: DemoCatalog.cards[cardIndex], similarity: .96),
      ScanCandidate(card: DemoCatalog.cards[cardIndex + 1], similarity: .72),
    ],
    status: status,
  );
  return ScanSession(
    id: 'interaction-fixture',
    detectedCards: [
      region('recommended-1', 0, ScanRecognitionStatus.recommended),
      region(
        'recommended-2',
        duplicate ? 0 : 1,
        ScanRecognitionStatus.recommended,
      ),
      region('medium', 3, ScanRecognitionStatus.needsConfirmation),
      region('unknown', 5, ScanRecognitionStatus.unrecognized),
    ],
  );
}

class _RecordingRepository extends MockScanRepository {
  final List<List<ScanConfirmation>> calls = [];
  bool fail = false;
  Completer<Map<String, int>?>? pending;

  @override
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> confirmations,
  ) async {
    calls.add(List.of(confirmations));
    if (fail) throw StateError('Network unavailable');
    if (pending != null) return pending!.future;
    // Null is the Mock Repository contract: increment one quantity for each
    // selected detection, not once for each unique official card ID.
    return null;
  }
}

class _InstantAuthRepository implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _CollectionEdits extends MockUserDataRepository {
  bool fail = false;
  final quantities = <(String, int)>[];
  final likes = <(String, bool)>[];
  @override
  Future<void> setOwnedQuantity(String id, int value) async {
    if (fail) throw StateError('offline');
    quantities.add((id, value));
  }

  @override
  Future<void> setWishlist(String id, bool value) async {
    if (fail) throw StateError('offline');
    likes.add((id, value));
  }
}

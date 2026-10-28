import 'dart:io';
import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/widgets/card_geometry.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/feedback/missing_card_page.dart';
import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:fan_os/features/scan/state/scan_spatial_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Color spatialMatchColor(SpatialMatchState state) => switch (state) {
  SpatialMatchState.recommended ||
  SpatialMatchState.confirmed => FanColors.lavender,
  SpatialMatchState.needsConfirmation => const Color(0xFFB76512),
  SpatialMatchState.unmatched ||
  SpatialMatchState.failed => FanColors.textSecondary,
};

/// Alternate original-photo workflow. The classic result screen stays intact.
class ScanSpatialResultPage extends ConsumerStatefulWidget {
  const ScanSpatialResultPage({required this.session, super.key});
  final ScanSession? session;

  @override
  ConsumerState<ScanSpatialResultPage> createState() =>
      _ScanSpatialResultPageState();
}

class _ScanSpatialResultPageState extends ConsumerState<ScanSpatialResultPage> {
  late final SpatialScanState _state;
  late final (String, bool) _identity;
  late final ScrollController _thumbnails;
  final _sheet = DraggableScrollableController();
  final _photo = GlobalKey<_OriginalPhotoState>();
  final _panelHeights = <(String, bool), double>{};
  double _compactExtent = .36;
  double _expandedExtent = .62;
  bool _draggingPanel = false;
  bool _sheetSyncScheduled = false;
  (double, double)? _panelConstraints;

  @override
  void initState() {
    super.initState();
    final account = ref.read(sessionProvider);
    _identity = (account.userId, account.isLoggedIn);
    final session = widget.session;
    final cache = ref.read(spatialScanCacheProvider);
    _state = session == null
        ? SpatialScanState(const ScanSession(id: '', detectedCards: []))
        : cache.putIfAbsent(session.id, () => SpatialScanState(session));
    // Bounded, ephemeral history; there is no claim of disk persistence.
    if (cache.length > 10) cache.remove(cache.keys.first);
    _thumbnails = ScrollController(initialScrollOffset: _state.thumbnailOffset)
      ..addListener(() => _state.thumbnailOffset = _thumbnails.offset);
    _sheet.addListener(_syncSheetExtent);
  }

  @override
  void dispose() {
    _thumbnails.dispose();
    _sheet.removeListener(_syncSheetExtent);
    _sheet.dispose();
    super.dispose();
  }

  void _select(SpatialScanObject item) {
    if (_state.busy) return;
    setState(() {
      _state.selectedId = item.detected.id;
      if (!_canExpand(item)) _state.panelExpanded = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _photo.currentState?.reveal();
      _settlePanel();
    });
    if (_thumbnails.hasClients) {
      final offset = ((_state.numberOf(item.detected.id) - 1) * 62.0 - 100)
          .clamp(0.0, _thumbnails.position.maxScrollExtent);
      _thumbnails.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _expand() {
    setState(() => _state.panelExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _settlePanel());
  }

  bool _canExpand(SpatialScanObject item) =>
      item.chosen != null || item.candidates.isNotEmpty;

  void _syncSheetExtent() {
    if (!mounted || !_sheet.isAttached) return;
    // Changing content can replace the sheet's min/max bounds during build.
    // Flutter notifies the controller, but emits no drag notification for that
    // clamp. Defer only this build-phase cache update, not the layout source.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_sheetSyncScheduled) return;
      _sheetSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetSyncScheduled = false;
        _syncSheetExtent();
      });
      return;
    }
    final actualExtent = _sheet.size;
    if ((_state.panelExtent - actualExtent).abs() < .000001) return;
    setState(() => _state.panelExtent = actualExtent);
  }

  void _settlePanel() {
    if (!mounted || _draggingPanel) return;
    if (_sheet.isAttached) {
      _syncSheetExtent();
      final target = _state.panelExpanded ? _expandedExtent : _compactExtent;
      if ((_sheet.size - target).abs() < .000001) return;
      _sheet.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _measurePanel(String id, bool expanded, double height) {
    if (!mounted || id != _state.current?.detected.id) return;
    final key = (id, expanded);
    if (((_panelHeights[key] ?? 0) - height).abs() < .5) return;
    setState(() => _panelHeights[key] = height);
    WidgetsBinding.instance.addPostFrameCallback((_) => _settlePanel());
  }

  Future<void> _openCatalog(CollectibleCard card) async {
    if (_state.busy) return;
    await context.push('/card/${Uri.encodeComponent(card.id)}');
  }

  bool get _sameAccount {
    if (!mounted) return false;
    final account = ref.read(sessionProvider);
    return _identity == (account.userId, account.isLoggedIn);
  }

  ScanSession get _currentSession => ScanSession(
    id: widget.session!.id,
    originalImagePath: widget.session!.originalImagePath,
    detectedCards: [
      for (final item in _state.objects)
        DetectedScanCard(
          id: item.detected.id,
          cropRegion: item.detected.cropRegion,
          cropImagePath: item.detected.cropImagePath,
          status: item.detected.status,
          candidates: [
            ...item.detected.candidates,
            if (item.chosen != null &&
                !item.detected.candidates.any(
                  (c) => c.card.id == item.chosen!.card.id,
                ))
              item.chosen!,
          ],
          userConfirmedCardId: item.confirmed
              ? item.chosen?.card.id
              : item.detected.userConfirmedCardId,
          ownedAdded: item.detected.ownedAdded,
          matchingFailed: item.detected.matchingFailed,
          displayRotationQuarterTurns:
              item.detected.displayRotationQuarterTurns,
        ),
    ],
  );

  Future<void> _retry(SpatialScanObject item) => _perform(item, () async {
    final session = _currentSession;
    final updated = await ref.read(scanDetectionRepositoryProvider).recognize(
      ScanDetection(
        sessionId: session.id,
        regions: session.detectedCards,
        imagePath: session.originalImagePath,
      ),
      {item.detected.id},
    );
    if (!_sameAccount) return;
    _state.mergeRetry(updated);
  });

  Future<void> _perform(
    SpatialScanObject item,
    Future<void> Function() action,
  ) async {
    if (!mounted || !_sameAccount || _state.busy) return;
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }
    setState(() {
      _state.busy = true;
      item.error = null;
    });
    try {
      await action();
    } catch (error) {
      item.error = error is ApiException ? error.message : '操作未完成，原状态已保留，请重试';
    } finally {
      _state.busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirm(SpatialScanObject item) => _perform(item, () async {
    if (item.chosen == null) return;
    await ref.read(scanRepositoryProvider).confirm(widget.session!.id, [
      ScanConfirmation(
        detectedCardId: item.detected.id,
        cardId: item.chosen!.card.id,
        selected: false,
      ),
    ]);
    if (!_sameAccount) return;
    item.confirmed = true;
    item.choosing = false;
  });

  Future<void> _save(
    SpatialScanObject item, {
    required bool wishlist,
  }) => _perform(item, () async {
    if (!item.canSave || item.chosen == null) return;
    final id = item.chosen!.card.id;
    // selected:false confirms the catalogue association without the legacy +1.
    final quantities = await ref.read(scanRepositoryProvider).confirm(
      widget.session!.id,
      [
        ScanConfirmation(
          detectedCardId: item.detected.id,
          cardId: id,
          selected: false,
          addToWishlist: wishlist,
          ensureOwned: !wishlist,
        ),
      ],
    );
    if (!_sameAccount) return;
    item.confirmed = true;
    if (wishlist) {
      final current = ref.read(collectionProvider);
      ref.read(collectionProvider.notifier).hydrate(current.owned, {
        ...current.wishlist,
        id,
      });
    } else {
      final quantity = quantities?[id];
      if (quantity != null) {
        final current = ref.read(collectionProvider);
        ref.read(collectionProvider.notifier).hydrate({
          ...current.owned,
          id: quantity,
        }, current.wishlist);
      } else {
        // Older/mock repositories may not return quantities; refresh truth,
        // never fall back to a second write or an invented successful count.
        final snapshot = await ref
            .read(userDataRepositoryProvider)
            .fetchAccountSnapshot();
        if (!_sameAccount) return;
        ref
            .read(collectionProvider.notifier)
            .hydrate(snapshot.owned, snapshot.wishlist);
        if ((snapshot.owned[id] ?? 0) == 0) throw StateError('拥有状态尚未确认，请重试');
      }
    }
    if (mounted) showFanToast(context, wishlist ? '已加入心愿单' : '已标记拥有');
  });

  Future<void> _remove(SpatialScanObject item, {required bool wishlist}) async {
    final card = item.chosen?.card;
    if (card == null || _state.busy) return;
    final allowed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                wishlist ? '移出心愿单？' : '取消拥有？',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(wishlist ? '拥有状态不会改变。' : '拥有数量将变为 0，心愿单不会改变。'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      ),
    );
    if (allowed != true || !mounted) return;
    await _perform(item, () async {
      final repository = ref.read(userDataRepositoryProvider);
      wishlist
          ? await repository.setWishlist(card.id, false)
          : await repository.setOwnedQuantity(card.id, 0);
      if (!_sameAccount) return;
      final current = ref.read(collectionProvider);
      final owned = {...current.owned};
      final wishes = {...current.wishlist};
      wishlist ? wishes.remove(card.id) : owned.remove(card.id);
      ref.read(collectionProvider.notifier).hydrate(owned, wishes);
      if (mounted) showFanToast(context, wishlist ? '已移出心愿单' : '已取消拥有');
    });
  }

  Future<void> _feedback(SpatialScanObject item) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MissingCardFeedbackPage(
          args: ScanFeedbackRouteArgs(
            session: _currentSession,
            detectedCard: item.detected,
            returnToResult: true,
          ),
        ),
      ),
    );
    if (mounted && result == true && _sameAccount) {
      setState(() => item.feedbackSubmitted = true);
    }
  }

  Future<void> _search(SpatialScanObject item) async {
    final result = await Navigator.of(context).push<CollectibleCard>(
      MaterialPageRoute(builder: (_) => const _SpatialCatalogSearch()),
    );
    if (!mounted || result == null || !_sameAccount) return;
    setState(
      () => item.select(
        ScanCandidate(card: result, similarity: 0),
        searched: true,
      ),
    );
    _expand();
  }

  String _status(SpatialScanObject item) => switch (item.matchState) {
    SpatialMatchState.recommended => '推荐匹配',
    SpatialMatchState.confirmed => '已核对',
    SpatialMatchState.needsConfirmation => '暂无精确匹配',
    SpatialMatchState.unmatched => '暂未找到匹配',
    SpatialMatchState.failed => '匹配失败',
  };

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(sessionProvider);
    final collection = ref.watch(collectionProvider);
    final current = _state.current;
    if (_identity != (account.userId, account.isLoggedIn)) {
      return Scaffold(
        appBar: AppBar(title: const Text('扫描结果')),
        body: const Center(child: Text('账号已变更，请返回扫描')),
      );
    }
    final counts = _state.counts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描结果'),
        actions: [
          TextButton(
            onPressed: _state.busy ? null : () => Navigator.maybePop(context),
            child: const Text('完成'),
          ),
        ],
      ),
      body: widget.session == null || current == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.crop_free,
                    size: 40,
                    color: FanColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(widget.session == null ? '扫描结果不可用' : '未检测到小卡'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.maybePop(context),
                    child: const Text('返回重新拍摄或导入'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '匹配 ${counts.$1}',
                            style: TextStyle(
                              color: spatialMatchColor(
                                SpatialMatchState.recommended,
                              ),
                            ),
                          ),
                          const TextSpan(text: ' · '),
                          TextSpan(
                            text: '待确认 ${counts.$2}',
                            style: TextStyle(
                              color: spatialMatchColor(
                                SpatialMatchState.needsConfirmation,
                              ),
                            ),
                          ),
                          const TextSpan(text: ' · '),
                          TextSpan(
                            text: '未匹配 ${counts.$3}',
                            style: TextStyle(
                              color: spatialMatchColor(
                                SpatialMatchState.unmatched,
                              ),
                            ),
                          ),
                          if (_state.failedCount > 0)
                            TextSpan(text: ' · 失败 ${_state.failedCount}'),
                        ],
                      ),
                      key: const Key('spatial-summary'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: FanColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final panelConstraints = (
                        constraints.maxWidth,
                        MediaQuery.textScalerOf(context).scale(15),
                      );
                      if (_panelConstraints != panelConstraints) {
                        _panelConstraints = panelConstraints;
                        _panelHeights.clear();
                      }
                      final maxExtent = math
                          .min(
                            .65,
                            (constraints.maxHeight - 170) /
                                constraints.maxHeight,
                          )
                          .clamp(.2, .65);
                      _compactExtent =
                          ((_panelHeights[(current.detected.id, false)] ??
                                      300) /
                                  constraints.maxHeight)
                              .clamp(.18, maxExtent);
                      _expandedExtent = _canExpand(current)
                          ? ((_panelHeights[(current.detected.id, true)] ??
                                        480) /
                                    constraints.maxHeight)
                                .clamp(_compactExtent, maxExtent)
                          : _compactExtent;
                      // The live controller is the geometry authority. The
                      // cached extent is only used before attachment/re-entry.
                      final extent =
                          (_sheet.isAttached ? _sheet.size : _state.panelExtent)
                              .clamp(_compactExtent, _expandedExtent);
                      final panelExpanded = _state.panelExpanded;
                      final viewportHeight = math.max(
                        40.0,
                        constraints.maxHeight * (1 - extent) - 82,
                      );
                      return Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: viewportHeight,
                            child: _OriginalPhoto(
                              key: _photo,
                              path: widget.session!.originalImagePath,
                              state: _state,
                              onSelect: _select,
                            ),
                          ),
                          Positioned(
                            top: viewportHeight,
                            left: 0,
                            right: 0,
                            height: 82,
                            child: ColoredBox(
                              color: FanColors.canvas,
                              child: ListView.separated(
                                key: const Key('spatial-thumbnails'),
                                controller: _thumbnails,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                scrollDirection: Axis.horizontal,
                                itemCount: _state.objects.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (_, index) {
                                  final item = _state.objects[index];
                                  final chosenId = item.chosen?.card.id;
                                  return Semantics(
                                    label: '对象 ${index + 1}，${_status(item)}',
                                    selected: identical(item, current),
                                    child: InkWell(
                                      key: Key(
                                        'spatial-thumb-${item.detected.id}',
                                      ),
                                      onTap: () => _select(item),
                                      child: SizedBox(
                                        width: 54,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: DecoratedBox(
                                                key: Key(
                                                  'spatial-thumb-frame-${item.detected.id}',
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    width:
                                                        identical(item, current)
                                                        ? 2
                                                        : 1,
                                                    color:
                                                        spatialMatchColor(
                                                          item.matchState,
                                                        ).withValues(
                                                          alpha:
                                                              identical(
                                                                item,
                                                                current,
                                                              )
                                                              ? 1
                                                              : .45,
                                                        ),
                                                  ),
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    3,
                                                  ),
                                                  child: ScanImage(
                                                    key: Key(
                                                      'spatial-thumb-rotation-${item.detected.id}',
                                                    ),
                                                    quarterTurns:
                                                        item.scanQuarterTurns,
                                                    path: item
                                                        .detected
                                                        .cropImagePath,
                                                    fallback: const Icon(
                                                      Icons.photo_outlined,
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              left: 2,
                                              top: 2,
                                              child: _NumberBadge(
                                                index + 1,
                                                color: spatialMatchColor(
                                                  item.matchState,
                                                ),
                                              ),
                                            ),
                                            if (item.feedbackSubmitted ||
                                                chosenId != null &&
                                                    (collection.isWished(
                                                          chosenId,
                                                        ) ||
                                                        collection.quantity(
                                                              chosenId,
                                                            ) >
                                                            0))
                                              Positioned(
                                                bottom: 2,
                                                right: 2,
                                                child: CircleAvatar(
                                                  radius: 9,
                                                  backgroundColor: Colors.white,
                                                  child: Icon(
                                                    item.feedbackSubmitted
                                                        ? Icons
                                                              .chat_bubble_outline
                                                        : collection.quantity(
                                                                chosenId!,
                                                              ) >
                                                              0
                                                        ? Icons.check
                                                        : Icons.favorite,
                                                    size: 12,
                                                    color: FanColors.lavender,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          NotificationListener<DraggableScrollableNotification>(
                            onNotification: (notification) {
                              if (_draggingPanel && _canExpand(current)) {
                                final expanded =
                                    notification.extent >
                                    (_compactExtent + _expandedExtent) / 2;
                                if (_state.panelExpanded != expanded) {
                                  setState(
                                    () => _state.panelExpanded = expanded,
                                  );
                                }
                              }
                              return false;
                            },
                            child: Listener(
                              onPointerDown: (_) => _draggingPanel = true,
                              onPointerUp: (_) => _draggingPanel = false,
                              onPointerCancel: (_) => _draggingPanel = false,
                              child: DraggableScrollableSheet(
                                controller: _sheet,
                                initialChildSize: extent,
                                minChildSize: _compactExtent,
                                maxChildSize: _expandedExtent,
                                snap: _expandedExtent - _compactExtent > .001,
                                builder: (context, controller) => Container(
                                  key: const Key('spatial-detail-panel'),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                    border: Border(
                                      top: BorderSide(color: FanColors.line),
                                    ),
                                  ),
                                  child: SingleChildScrollView(
                                    key: const Key('spatial-detail-list'),
                                    controller: controller,
                                    child: _PanelSizeObserver(
                                      key: ValueKey((
                                        current.detected.id,
                                        panelExpanded,
                                      )),
                                      onSize: (size) => _measurePanel(
                                        current.detected.id,
                                        panelExpanded,
                                        size.height,
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          12 +
                                              MediaQuery.paddingOf(context)
                                                  .bottom,
                                        ),
                                        child: Column(
                                          key: const Key(
                                            'spatial-detail-content',
                                          ),
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: _panel(current),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _panel(SpatialScanObject item) {
    final expanded = _state.panelExpanded;
    final candidate = item.chosen;
    final pending = item.matchState == SpatialMatchState.needsConfirmation;
    final unmatched = item.matchState == SpatialMatchState.unmatched;
    final failed = item.matchState == SpatialMatchState.failed;
    return [
      Center(
        child: SizedBox(
          height: 20,
          width: 36,
          child: Center(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: FanColors.line,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              '对象 ${_state.numberOf(item.detected.id).toString().padLeft(2, '0')} · ${_status(item)}',
              key: const Key('spatial-object-title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: spatialMatchColor(item.matchState),
              ),
            ),
          ),
          if (item.feedbackSubmitted)
            const Text(
              '已反馈',
              style: TextStyle(fontSize: 12, color: FanColors.textSecondary),
            ),
          if (_canExpand(item))
            IconButton(
              tooltip: expanded ? '收起核对' : '展开核对',
              onPressed: () {
                setState(() => _state.panelExpanded = !expanded);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _settlePanel(),
                );
              },
              icon: Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (pending && !expanded)
        _compactCandidates(item)
      else if (expanded && candidate != null && !pending)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _picture(
                item.detected.cropImagePath,
                '扫描图',
                height: 140,
                quarterTurns: item.scanQuarterTurns,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _picture(
                candidate.card.imageUrl,
                '图鉴推荐',
                height: 140,
                catalogCard: candidate.card,
              ),
            ),
          ],
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 80,
              child: _zoomable(
                item.detected.cropImagePath,
                quarterTurns: item.scanQuarterTurns,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: candidate == null || pending
                  ? Text(
                      failed
                          ? '此小卡暂时无法匹配，可单独重试；其他结果已保留。'
                          : unmatched
                          ? '暂无相似推荐，可搜索图鉴或提交反馈'
                          : !expanded && !item.manuallySearched
                          ? '有 ${item.candidates.length} 个相似候选，展开核对卡面、来源与版本。'
                          : '请核对卡面、来源与版本后确认。',
                      style: const TextStyle(
                        fontSize: 13,
                        color: FanColors.textSecondary,
                      ),
                    )
                  : _cardInfo(
                      candidate,
                      similarity: !item.manuallySearched,
                      openCatalog: true,
                    ),
            ),
            if (candidate != null && !pending) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 54,
                height: 76,
                child: _catalogImage(candidate.card),
              ),
            ],
          ],
        ),
      if (expanded && candidate != null && !pending) ...[
        const SizedBox(height: 12),
        _cardInfo(
          candidate,
          similarity: !item.manuallySearched,
          openCatalog: true,
        ),
      ],
      if (pending && expanded) ...[
        const SizedBox(height: 12),
        if (item.manuallySearched && candidate != null)
          _candidateTile(item, candidate, manual: true),
        if (!item.manuallySearched)
          LayoutBuilder(
            builder: (context, constraints) {
              final candidates = item.candidates;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final option in candidates)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: _candidateTile(item, option),
                    ),
                ],
              );
            },
          ),
      ],
      if (item.error != null) ...[
        const SizedBox(height: 12),
        Text(
          item.error!,
          key: const Key('spatial-error'),
          style: const TextStyle(color: Color(0xFF9C3A43), fontSize: 13),
        ),
      ],
      const SizedBox(height: 12),
      if (pending)
        FilledButton(
          key: const Key('spatial-confirm'),
          onPressed: _state.busy || candidate == null
              ? null
              : () => _confirm(item),
          style: _primaryStyle,
          child: const Text('确认是这张'),
        ),
      if (unmatched)
        FilledButton(
          onPressed: _state.busy ? null : () => _search(item),
          style: _primaryStyle,
          child: const Text('搜索图鉴'),
        ),
      if (failed)
        FilledButton(
          key: const Key('spatial-retry'),
          onPressed: _state.busy ? null : () => _retry(item),
          style: _primaryStyle,
          child: const Text('重试匹配'),
        ),
      if (item.canSave) _saveButtons(item),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          if (!unmatched && !pending && item.hasOtherCandidates)
            TextButton(
              key: const Key('spatial-other-candidates'),
              onPressed: _state.busy
                  ? null
                  : () {
                      setState(item.chooseOtherCandidate);
                      _expand();
                    },
              child: const Text('其他候选'),
            ),
          if (pending || failed)
            TextButton(
              onPressed: _state.busy ? null : () => _search(item),
              child: const Text('搜索图鉴'),
            ),
          TextButton(
            onPressed: _state.busy ? null : () => _feedback(item),
            child: const Text('找不到卡？'),
          ),
        ],
      ),
      if (_state.busy)
        const LinearProgressIndicator(minHeight: 2, color: FanColors.lavender),
    ];
  }

  ButtonStyle get _primaryStyle => FilledButton.styleFrom(
    backgroundColor: FanColors.lavender,
    minimumSize: const Size(0, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _saveButtons(SpatialScanObject item) {
    final collection = ref.watch(collectionProvider);
    final id = item.chosen!.card.id;
    final wished = collection.isWished(id);
    final quantity = collection.quantity(id);
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          OutlinedButton.icon(
            key: const Key('spatial-wishlist'),
            onPressed: _state.busy
                ? null
                : wished
                ? () => _remove(item, wishlist: true)
                : () => _save(item, wishlist: true),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: FanColors.lavender,
            ),
            icon: Icon(
              wished ? Icons.favorite : Icons.favorite_border,
              size: 20,
            ),
            label: Text(wished ? '已在心愿单' : '加入心愿单'),
          ),
          FilledButton.icon(
            key: const Key('spatial-owned'),
            onPressed: _state.busy
                ? null
                : quantity > 0
                ? () => _remove(item, wishlist: false)
                : () => _save(item, wishlist: false),
            style: _primaryStyle.copyWith(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            icon: Icon(
              quantity > 0 ? Icons.check_circle : Icons.check,
              size: 20,
            ),
            label: Text(quantity > 0 ? '已拥有×$quantity' : '标记已拥有'),
          ),
        ];
        if (MediaQuery.textScalerOf(context).scale(15) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [buttons[0], const SizedBox(height: 8), buttons[1]],
          );
        }
        return Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: 12),
            Expanded(child: buttons[1]),
          ],
        );
      },
    );
  }

  Widget _cardInfo(
    ScanCandidate candidate, {
    required bool similarity,
    bool openCatalog = false,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FanEntityName(
          kind: 'idols',
          id: candidate.card.idolId,
          officialName: candidate.card.idolName,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          [
            candidate.card.source,
            candidate.card.version,
          ].where((v) => v.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 13, color: FanColors.textSecondary),
        ),
        if (similarity &&
            candidate.similarity.isFinite &&
            candidate.similarity > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              key: Key('spatial-similarity-${candidate.card.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FanColors.lavenderSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '相似度 ${(candidate.similarity * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: FanColors.lavender,
                ),
              ),
            ),
          ),
      ],
    );
    if (!openCatalog) return content;
    return Semantics(
      button: true,
      label: '查看图鉴详情',
      child: InkWell(
        key: Key('spatial-official-info-${candidate.card.id}'),
        onTap: _state.busy ? null : () => _openCatalog(candidate.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: content,
        ),
      ),
    );
  }

  Widget _catalogImage(CollectibleCard card) => Semantics(
    button: true,
    label: '查看图鉴详情',
    child: InkWell(
      key: Key('spatial-official-image-${card.id}'),
      onTap: _state.busy ? null : () => _openCatalog(card),
      child: ScanImage(
        path: card.imageUrl,
        aspectRatio: photocardAspectRatio,
        fallback: const Icon(
          Icons.photo_outlined,
          color: FanColors.textSecondary,
        ),
      ),
    ),
  );

  Widget _compactCandidates(SpatialScanObject item) {
    final options = [
      if (item.manuallySearched && item.chosen != null) item.chosen!,
      ...item.candidates.where(
        (candidate) =>
            !item.manuallySearched || candidate.card.id != item.chosen?.card.id,
      ),
    ];
    return SizedBox(
      key: const Key('spatial-recommendations'),
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final option = options[index];
          final score = option.similarity;
          final hasScore = score.isFinite && score > 0;
          return SizedBox(
            key: Key('spatial-recommendation-${option.card.id}'),
            width: 76,
            child: Column(
              children: [
                SizedBox(
                  width: 76,
                  height: 76 / photocardAspectRatio,
                  child: _catalogImage(option.card),
                ),
                const SizedBox(height: 4),
                Text(
                  hasScore
                      ? '${(score.clamp(0, 1) * 100).toStringAsFixed(0)}%'
                      : '手动选择',
                  semanticsLabel: hasScore
                      ? '相似度 ${(score.clamp(0, 1) * 100).toStringAsFixed(0)}%'
                      : '手动选择',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FanColors.lavender,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _candidateTile(
    SpatialScanObject item,
    ScanCandidate option, {
    bool manual = false,
  }) {
    final selected = option.card.id == item.chosen?.card.id;
    return Container(
      key: Key('spatial-candidate-${option.card.id}'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? FanColors.lavenderSoft : FanColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? FanColors.lavender : FanColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              height: 140,
              width: 140 * photocardAspectRatio,
              child: _catalogImage(option.card),
            ),
          ),
          const SizedBox(height: 8),
          _cardInfo(option, similarity: !manual),
          TextButton.icon(
            key: Key('spatial-select-${option.card.id}'),
            onPressed: _state.busy
                ? null
                : () => setState(() => item.select(option, searched: manual)),
            icon: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
            ),
            label: Text(selected ? '已选择' : '选择此卡'),
          ),
        ],
      ),
    );
  }

  Widget _picture(
    String? path,
    String label, {
    required double height,
    CollectibleCard? catalogCard,
    int quarterTurns = 0,
  }) => Column(
    children: [
      SizedBox(
        height: height,
        width: double.infinity,
        child: catalogCard == null
            ? _zoomable(path, quarterTurns: quarterTurns)
            : _catalogImage(catalogCard),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: FanColors.textSecondary),
      ),
    ],
  );

  Widget _zoomable(String? path, {int quarterTurns = 0}) => Semantics(
    button: true,
    label: '放大图片',
    child: InkWell(
      onTap: path == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: FanColors.ink,
                  appBar: AppBar(title: const Text('查看图片')),
                  body: Center(
                    child: InteractiveViewer(
                      minScale: .5,
                      maxScale: 5,
                      child: ScanImage(
                        key: const Key('spatial-fullscreen-scan-rotation'),
                        quarterTurns: quarterTurns,
                        path: path,
                        fallback: const Text(
                          '图片无法加载',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      child: ScanImage(
        key: const Key('spatial-scan-preview-rotation'),
        quarterTurns: quarterTurns,
        path: path,
        fallback: const Icon(
          Icons.photo_outlined,
          color: FanColors.textSecondary,
        ),
      ),
    ),
  );
}

/// Measures the complete scroll content, including safe-area padding. The
/// drawer grows only to the content (up to its viewport cap); larger text and
/// candidate lists continue scrolling instead of being clipped.
class _PanelSizeObserver extends SingleChildRenderObjectWidget {
  const _PanelSizeObserver({
    required this.onSize,
    required super.child,
    super.key,
  });
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PanelSizeRender(onSize);

  @override
  void updateRenderObject(BuildContext context, _PanelSizeRender renderObject) {
    renderObject.onSize = onSize;
  }
}

class _PanelSizeRender extends RenderProxyBox {
  _PanelSizeRender(this.onSize);
  ValueChanged<Size> onSize;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_lastSize == size) return;
    _lastSize = size;
    final measured = size;
    final callback = onSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) callback(measured);
    });
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number, {required this.color});
  final int number;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      number.toString().padLeft(2, '0'),
      style: const TextStyle(
        fontSize: 11,
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _OriginalPhoto extends StatefulWidget {
  const _OriginalPhoto({
    required this.path,
    required this.state,
    required this.onSelect,
    super.key,
  });
  final String? path;
  final SpatialScanState state;
  final ValueChanged<SpatialScanObject> onSelect;
  @override
  State<_OriginalPhoto> createState() => _OriginalPhotoState();
}

class _OriginalPhotoState extends State<_OriginalPhoto> {
  late final TransformationController _transform;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio;
  bool _failed = false;
  Size _viewport = Size.zero;
  Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _transform = TransformationController(widget.state.transform.clone())
      ..addListener(() => widget.state.transform = _transform.value.clone());
    _load();
  }

  void _load() {
    final path = widget.path;
    if (path == null || path.isEmpty) {
      _failed = true;
      return;
    }
    _provider = path.startsWith('http')
        ? NetworkImage(path)
        : FileImage(File(path));
    _stream = _provider!.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _ratio = info.image.width / info.image.height;
          _failed = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!widget.state.positioned) {
            fit();
          } else {
            _restoreView();
          }
        });
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  void fit() {
    if (_viewport.isEmpty || _imageSize.isEmpty) return;
    widget.state.photoView = const SpatialPhotoView();
    _transform.value = widget.state.photoView.transformFor(
      _viewport,
      _imageSize,
    );
    widget.state.positioned = true;
  }

  void _rememberView() {
    widget.state.photoView = SpatialPhotoView.fromTransform(
      _transform.value,
      _viewport,
      _imageSize,
    );
  }

  void _restoreView() {
    _transform.value = widget.state.photoView.transformFor(
      _viewport,
      _imageSize,
    );
    // Temporary occlusion adjustments are not a new user pan/zoom context.
    if (widget.state.panelExpanded) reveal(remember: false);
  }

  void reveal({bool remember = true}) {
    if (!mounted || _imageSize.isEmpty || !widget.state.positioned) return;
    final region = widget.state.current?.detected.cropRegion;
    if (region == null) return;
    _transform.value = keepSpatialObjectVisible(
      _transform.value,
      Rect.fromLTWH(
        region.x * _imageSize.width,
        region.y * _imageSize.height,
        region.width * _imageSize.width,
        region.height * _imageSize.height,
      ),
      _viewport,
    );
    if (remember) _rememberView();
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '原图无法加载',
              style: TextStyle(fontSize: 13, color: FanColors.textSecondary),
            ),
            TextButton(
              onPressed: () {
                if (_listener != null) _stream?.removeListener(_listener!);
                setState(() {
                  _failed = false;
                  _ratio = null;
                });
                _load();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_ratio == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewport != viewport) {
          _viewport = viewport;
          _imageSize = Size(viewport.width, viewport.width / _ratio!);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!widget.state.positioned) {
              fit();
            } else {
              _restoreView();
            }
          });
        }
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: InteractiveViewer(
                  key: const Key('spatial-original'),
                  transformationController: _transform,
                  constrained: false,
                  minScale: .05,
                  maxScale: 8,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  onInteractionEnd: (_) => _rememberView(),
                  child: SizedBox(
                    width: _imageSize.width,
                    height: _imageSize.height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image(image: _provider!, fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _DetectionPainter(widget.state),
                          ),
                        ),
                        for (final item in widget.state.objects) _target(item),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: '查看全图',
                onPressed: fit,
                icon: const Icon(Icons.fit_screen, size: 22),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _target(SpatialScanObject item) {
    final r = item.detected.cropRegion;
    return Positioned(
      left: r.x * _imageSize.width,
      top: r.y * _imageSize.height,
      width: r.width * _imageSize.width,
      height: r.height * _imageSize.height,
      child: Semantics(
        label: '选中对象 ${widget.state.numberOf(item.detected.id)}',
        button: true,
        child: GestureDetector(
          key: Key('spatial-region-${item.detected.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(item),
          child: Align(
            alignment: Alignment.topLeft,
            child: _NumberBadge(
              widget.state.numberOf(item.detected.id),
              color: spatialMatchColor(item.matchState),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter(SpatialScanState state)
    : objects = state.objects,
      selectedId = state.selectedId,
      states = [for (final item in state.objects) item.matchState];
  final List<SpatialScanObject> objects;
  final String? selectedId;
  final List<SpatialMatchState> states;
  @override
  void paint(Canvas canvas, Size size) {
    for (final item in objects) {
      final r = item.detected.cropRegion;
      final points = r.corners;
      final path = Path();
      if (points != null) {
        path.moveTo(points.first.x * size.width, points.first.y * size.height);
        for (final p in points.skip(1)) {
          path.lineTo(p.x * size.width, p.y * size.height);
        }
        path.close();
      } else {
        path.addRect(
          Rect.fromLTWH(
            r.x * size.width,
            r.y * size.height,
            r.width * size.width,
            r.height * size.height,
          ),
        );
      }
      final selected = item.detected.id == selectedId;
      if (!selected) {
        canvas.drawPath(
          path,
          Paint()..color = FanColors.ink.withValues(alpha: .16),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 3 : 1.5
          ..color = spatialMatchColor(item.matchState)
              .withValues(alpha: selected ? 1 : .7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) =>
      oldDelegate.selectedId != selectedId ||
      oldDelegate.objects != objects ||
      oldDelegate.states.length != states.length ||
      Iterable<int>.generate(states.length)
          .any((index) => oldDelegate.states[index] != states[index]);
}

class _SpatialCatalogSearch extends ConsumerStatefulWidget {
  const _SpatialCatalogSearch();
  @override
  ConsumerState<_SpatialCatalogSearch> createState() =>
      _SpatialCatalogSearchState();
}

class _SpatialCatalogSearchState extends ConsumerState<_SpatialCatalogSearch> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索图鉴')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '艺人、来源或版本',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('图鉴加载失败'),
                      TextButton(
                        onPressed: () => ref.invalidate(catalogProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
                data: (bundle) {
                  final results = bundle.cards
                      .where(
                        (card) =>
                            '${card.displayTitle} ${card.idolName} ${card.groupName} ${card.source} ${card.version}'
                                .toLowerCase()
                                .contains(_query),
                      )
                      .toList();
                  if (results.isEmpty) {
                    return const Center(child: Text('暂无匹配结果'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final card = results[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: SizedBox(
                          width: 44,
                          height: 64,
                          child: ScanImage(
                            path: card.imageUrl,
                            fallback: const Icon(Icons.photo_outlined),
                          ),
                        ),
                        title: FanEntityName(
                          kind: 'idols',
                          id: card.idolId,
                          officialName: card.idolName,
                        ),
                        subtitle: Text('${card.source} · ${card.version}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, card),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

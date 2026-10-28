import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ScanResultPage extends ConsumerStatefulWidget {
  const ScanResultPage({required this.session, super.key});

  final ScanSession? session;

  @override
  ConsumerState<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends ConsumerState<ScanResultPage> {
  late final Map<String, _DetectedSelection> _selections;
  final Map<String, ScanCandidate> _manualCandidates = {};
  final _scrollController = ScrollController();
  bool _isSubmitting = false;

  ScanSession? get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _selections = {
      for (final detected in _session?.detectedCards ?? const [])
        detected.id: _DetectedSelection(
          cardId:
              detected.userConfirmedCardId ??
              (detected.status == ScanRecognitionStatus.unrecognized ||
                      detected.topCandidate?.isApproximate == true
                  ? null
                  : detected.topCandidate?.card.id),
          confirmed: detected.userConfirmedCardId != null,
          included: detected.userConfirmedCardId != null,
          added: detected.ownedAdded,
        ),
    };
  }

  int get _batchCount => _selections.values
      .where(
        (selection) =>
            selection.confirmed &&
            selection.included &&
            !selection.added &&
            selection.cardId != null,
      )
      .length;

  Iterable<MapEntry<String, _DetectedSelection>> get _selectedEntries =>
      _selections.entries.where(
        (entry) =>
            entry.value.confirmed &&
            entry.value.included &&
            entry.value.cardId != null,
      );

  int get _wishlistCount => _selectedEntries
      .map((entry) => entry.value.cardId!)
      .where((id) => !ref.read(collectionProvider).isWished(id))
      .toSet()
      .length;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _selectRecommended() async {
    if (_isSubmitting) return;
    final eligible = (_session?.detectedCards ?? const <DetectedScanCard>[])
        .where(
          (card) =>
              _selections[card.id]!.confirmed ||
              card.status == ScanRecognitionStatus.recommended &&
                  card.topCandidate != null &&
                  !card.topCandidate!.isApproximate,
        )
        .toList();
    if (eligible.isEmpty) {
      showFanToast(context, '请先为未识别或待确认的小卡选择正确图鉴');
      return;
    }
    setState(() {
      for (final card in eligible) {
        final selection = _selections[card.id]!;
        _selections[card.id] = selection.copyWith(
          cardId: selection.cardId ?? card.topCandidate?.card.id,
          confirmed: true,
          included: true,
        );
      }
    });
  }

  void _clearSelection() {
    if (_isSubmitting) return;
    setState(() {
      for (final entry in _selections.entries.toList()) {
        _selections[entry.key] = entry.value.copyWith(included: false);
      }
    });
  }

  ScanCandidate? _selectedCandidate(DetectedScanCard detected) {
    if (_manualCandidates.containsKey(detected.id)) {
      return _manualCandidates[detected.id];
    }
    final cardId = _selections[detected.id]?.cardId;
    if (cardId == null) return null;
    for (final candidate in detected.candidates) {
      if (candidate.card.id == cardId) return candidate;
    }
    return null;
  }

  void _confirm(DetectedScanCard detected) {
    final selection = _selections[detected.id]!;
    if (selection.cardId == null) {
      _showCandidates(detected);
      return;
    }
    setState(() {
      _selections[detected.id] = selection.copyWith(
        confirmed: true,
        included: true,
      );
    });
  }

  Future<void> _showCandidates(DetectedScanCard detected) async {
    if (_isSubmitting || _selections[detected.id]!.added) return;
    if (detected.candidates.isEmpty) {
      showFanToast(context, '暂时没有可供选择的相似结果');
      return;
    }
    var searchRequested = false;
    final selected = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CandidatePicker(
        detected: detected,
        selectedCardId: _selections[detected.id]?.cardId,
        onSearch: () {
          searchRequested = true;
          Navigator.of(context).pop();
        },
      ),
    );
    if (searchRequested && mounted) {
      await _searchCatalog(detected);
      return;
    }
    if (selected == null || !mounted) return;
    if (selected == false) {
      setState(() {
        _manualCandidates.remove(detected.id);
        _selections[detected.id] = const _DetectedSelection(
          cardId: null,
          confirmed: false,
          included: false,
        );
      });
      return;
    }
    if (selected is! ScanCandidate) return;
    setState(() {
      _manualCandidates.remove(detected.id);
      _selections[detected.id] = _selections[detected.id]!.copyWith(
        cardId: selected.card.id,
        confirmed: true,
        included: true,
        added: false,
      );
    });
  }

  void _toggleIncluded(DetectedScanCard detected, bool included) {
    final selection = _selections[detected.id]!;
    if (included && !selection.confirmed) {
      if (detected.status == ScanRecognitionStatus.recommended &&
          selection.cardId != null) {
        _confirm(detected);
      } else {
        _showCandidates(detected);
      }
      return;
    }
    setState(() {
      _selections[detected.id] = _selections[detected.id]!.copyWith(
        included: included,
      );
    });
  }

  Future<void> _searchCatalog(DetectedScanCard detected) async {
    if (_isSubmitting || _selections[detected.id]!.added) return;
    try {
      final catalog = await ref.read(catalogProvider.future);
      if (!mounted) return;
      var query = '';
      final card = await showModalBottomSheet<CollectibleCard>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) {
            final results = catalog.cards
                .where(
                  (card) =>
                      '${card.title} ${card.idolName} ${card.groupName} ${card.source} ${card.version}'
                          .toLowerCase()
                          .contains(query.toLowerCase()),
                )
                .toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .55,
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '搜索图鉴并选择这张小卡',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setSheetState(() => query = value.trim()),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: results.isEmpty
                            ? const Center(child: Text('暂无匹配的小卡，可提交反馈'))
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final result = results[index];
                                  return ListTile(
                                    leading: SizedBox(
                                      width: 36,
                                      child: ScanImage(
                                        path: result.imageUrl,
                                        fallback: const Icon(
                                          Icons.photo_outlined,
                                        ),
                                      ),
                                    ),
                                    title: Text(result.displayTitle),
                                    subtitle: FanEntityName(
                                      kind: 'idols',
                                      id: result.idolId,
                                      officialName: result.idolName,
                                      suffix:
                                          ' · ${result.source} · ${result.version}',
                                    ),
                                    trailing: IconButton(
                                      key: Key(
                                        'scan-catalog-detail-${result.id}',
                                      ),
                                      tooltip: '查看小卡详情',
                                      onPressed: () =>
                                          _openScanCardDetail(context, result),
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 18,
                                      ),
                                    ),
                                    onTap: () => Navigator.pop(context, result),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (card == null || !mounted) return;
      setState(() {
        _manualCandidates[detected.id] = ScanCandidate(
          card: card,
          similarity: 0,
        );
        _selections[detected.id] = _selections[detected.id]!.copyWith(
          cardId: card.id,
          confirmed: true,
          included: true,
        );
      });
    } catch (_) {
      if (mounted) showFanToast(context, '图鉴加载失败，请稍后重试');
    }
  }

  Future<void> _toggleWishlist(DetectedScanCard detected) async {
    if (_isSubmitting) return;
    final selection = _selections[detected.id]!;
    if (!selection.confirmed || selection.cardId == null) {
      showFanToast(context, '请先确认这张小卡');
      return;
    }
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }
    final cardId = selection.cardId!;
    final wished = !ref.read(collectionProvider).isWished(cardId);
    setState(() => _isSubmitting = true);
    try {
      if (wished) {
        await ref.read(scanRepositoryProvider).confirm(_session!.id, [
          ScanConfirmation(
            detectedCardId: detected.id,
            cardId: cardId,
            selected: false,
            addToWishlist: true,
          ),
        ]);
      } else {
        await ref.read(userDataRepositoryProvider).setWishlist(cardId, false);
      }
      if (!mounted) return;
      final current = ref.read(collectionProvider);
      final wishlist = {...current.wishlist};
      wished ? wishlist.add(cardId) : wishlist.remove(cardId);
      ref.read(collectionProvider.notifier).hydrate(current.owned, wishlist);
      showFanToast(context, wished ? '已加入我的喜欢' : '已从我的喜欢移除');
    } catch (_) {
      if (mounted) showFanToast(context, '保存喜欢失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _setOwned(DetectedScanCard detected) async {
    final selection = _selections[detected.id]!;
    if (_isSubmitting || !selection.confirmed || selection.cardId == null) {
      return;
    }
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }
    final id = selection.cardId!;
    final quantity = ref.read(collectionProvider).quantity(id);
    if (quantity > 0) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('取消拥有这款小卡？'),
          content: Text('当前拥有 $quantity 张，取消后数量变为 0；喜欢状态不受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('取消拥有'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    setState(() => _isSubmitting = true);
    try {
      // A scan's original +1 remains idempotent. Reinstating a cancelled mark is
      // an explicit collection edit, not a replay of that original confirmation.
      await ref
          .read(userDataRepositoryProvider)
          .setOwnedQuantity(id, quantity > 0 ? 0 : 1);
      if (!mounted) return;
      final current = ref.read(collectionProvider);
      final owned = {...current.owned};
      quantity > 0 ? owned.remove(id) : owned[id] = 1;
      ref.read(collectionProvider.notifier).hydrate(owned, current.wishlist);
      showFanToast(context, quantity > 0 ? '已取消拥有，喜欢状态不变' : '已标记拥有 1 张');
    } catch (_) {
      if (mounted) showFanToast(context, '保存失败，原状态已保留，请重试');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _addConfirmedCards() async {
    if (_isSubmitting) return;
    final eligible = _selections.entries
        .where(
          (entry) =>
              entry.value.confirmed &&
              entry.value.included &&
              !entry.value.added &&
              entry.value.cardId != null,
        )
        .toList();
    if (eligible.isEmpty) return;
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }

    final collection = ref.read(collectionProvider);
    final previousQuantities = {
      for (final entry in eligible)
        entry.value.cardId!: collection.quantity(entry.value.cardId!),
    };
    setState(() => _isSubmitting = true);
    Map<String, int>? serverQuantities;
    try {
      serverQuantities = await ref
          .read(scanRepositoryProvider)
          .confirm(
            _session!.id,
            eligible
                .map(
                  (entry) => ScanConfirmation(
                    detectedCardId: entry.key,
                    cardId: entry.value.cardId!,
                  ),
                )
                .toList(),
          );
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showFanToast(context, '保存扫描结果失败，请稍后重试');
      }
      return;
    }
    if (!mounted) return;
    if (serverQuantities != null) {
      final current = ref.read(collectionProvider);
      ref.read(collectionProvider.notifier).hydrate({
        ...current.owned,
        ...serverQuantities,
      }, current.wishlist);
    } else {
      for (final entry in eligible) {
        ref
            .read(collectionProvider.notifier)
            .incrementOwned(entry.value.cardId!, sync: useMockApi);
      }
    }
    setState(() {
      _isSubmitting = false;
      for (final entry in eligible) {
        _selections[entry.key] = entry.value.copyWith(added: true);
      }
    });

    if (eligible.length == 1 &&
        previousQuantities[eligible.single.value.cardId!]! > 0) {
      final cardId = eligible.single.value.cardId!;
      showFanToast(
        context,
        '已更新为拥有 ${ref.read(collectionProvider).quantity(cardId)} 张',
      );
      return;
    }
    showFanToast(context, '已标记拥有 ${eligible.length} 张小卡');
  }

  Future<void> _addSelectedToWishlist() async {
    if (_isSubmitting) return;
    final entries = _selectedEntries
        .where(
          (entry) =>
              !ref.read(collectionProvider).isWished(entry.value.cardId!),
        )
        .toList();
    if (entries.isEmpty) return;
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(scanRepositoryProvider)
          .confirm(
            _session!.id,
            entries
                .map(
                  (entry) => ScanConfirmation(
                    detectedCardId: entry.key,
                    cardId: entry.value.cardId!,
                    selected: false,
                    addToWishlist: true,
                  ),
                )
                .toList(),
          );
      if (!mounted) return;
      final current = ref.read(collectionProvider);
      final ids = entries.map((entry) => entry.value.cardId!).toSet();
      ref.read(collectionProvider.notifier).hydrate(current.owned, {
        ...current.wishlist,
        ...ids,
      });
      showFanToast(context, '已将 ${ids.length} 种小卡加入喜欢');
    } catch (_) {
      if (mounted) showFanToast(context, '批量喜欢失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('扫描结果')),
        body: FanEmptyState(
          icon: Icons.history_rounded,
          title: '扫描结果已失效',
          message: '请重新扫描或从相册选择照片。',
          actionLabel: '重新扫描',
          onAction: () => context.go('/scan'),
        ),
      );
    }

    final collection = ref.watch(collectionProvider);
    final allUnrecognized =
        session.detectedCards.isNotEmpty &&
        session.detectedCards.every(
          (item) => item.status == ScanRecognitionStatus.unrecognized,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('扫描结果')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: FanColors.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isSubmitting
                    ? '正在保存，请勿重复操作…'
                    : '已选 ${_selectedEntries.length} 张 · 喜欢与拥有独立保存',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('scan-batch-wishlist'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontSize: 13),
                      ),
                      onPressed: _wishlistCount == 0 || _isSubmitting
                          ? null
                          : _addSelectedToWishlist,
                      icon: const Icon(Icons.favorite_border_rounded, size: 18),
                      label: Text('喜欢（$_wishlistCount）'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('scan-batch-confirm'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontSize: 13),
                      ),
                      onPressed: _batchCount == 0 || _isSubmitting
                          ? null
                          : _addConfirmedCards,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text('标记拥有（$_batchCount）'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: session.detectedCards.isEmpty
          ? FanEmptyState(
              icon: Icons.search_off_rounded,
              title: '暂时没有找到匹配的小卡',
              message: '已保留原始照片，请重新扫描、搜索图鉴或我要反馈。',
              actionLabel: '重新扫描',
              onAction: () => context.go('/scan'),
            )
          : ListView(
              key: PageStorageKey('scan-results-${session.id}'),
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 18),
              children: [
                FanContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ResultSummary(
                        count: session.detectedCount,
                        allUnrecognized: allUnrecognized,
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            key: const Key('scan-select-all'),
                            onPressed: _isSubmitting
                                ? null
                                : _selectRecommended,
                            icon: const Icon(Icons.done_all_rounded, size: 17),
                            label: const Text('全选推荐'),
                          ),
                          const Spacer(),
                          TextButton(
                            key: const Key('scan-clear-selection'),
                            onPressed: _isSubmitting ? null : _clearSelection,
                            child: const Text('清空选择'),
                          ),
                        ],
                      ),
                      if (session.originalImagePath != null)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('查看原始照片'),
                          children: [
                            SizedBox(
                              height: 180,
                              child: ScanImage(
                                path: session.originalImagePath,
                                fallback: const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('原图暂时无法加载，请检查网络'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      for (final entry
                          in session.detectedCards.asMap().entries) ...[
                        AbsorbPointer(
                          absorbing: _isSubmitting,
                          child: _DetectedResultCard(
                            key: ValueKey(entry.value.id),
                            index: entry.key,
                            session: session,
                            detected: entry.value,
                            candidate: _selectedCandidate(entry.value),
                            selection: _selections[entry.value.id]!,
                            ownedQuantity:
                                _selectedCandidate(entry.value) == null
                                ? 0
                                : collection.quantity(
                                    _selectedCandidate(entry.value)!.card.id,
                                  ),
                            wished: _selectedCandidate(entry.value) == null
                                ? false
                                : collection.isWished(
                                    _selectedCandidate(entry.value)!.card.id,
                                  ),
                            onConfirm: () => _confirm(entry.value),
                            onCandidates: () => _showCandidates(entry.value),
                            onIncludedChanged: (value) =>
                                _toggleIncluded(entry.value, value),
                            onWishlist: () => _toggleWishlist(entry.value),
                            onOwned: () => _setOwned(entry.value),
                            sameCardCount: session.detectedCards
                                .where(
                                  (d) =>
                                      _selectedCandidate(d)?.card.id ==
                                      _selectedCandidate(entry.value)?.card.id,
                                )
                                .length,
                            onSearch: () => _searchCatalog(entry.value),
                            onFeedback: () => context.push(
                              '/scan-feedback',
                              extra: ScanFeedbackRouteArgs(
                                session: session,
                                detectedCard: entry.value,
                              ),
                            ),
                            onDetail: () {
                              final candidate = _selectedCandidate(entry.value);
                              if (candidate != null) {
                                _openScanCardDetail(context, candidate.card);
                              }
                            },
                            onChooseCandidate: (candidate) {
                              if (_isSubmitting ||
                                  _selections[entry.value.id]!.added) {
                                return;
                              }
                              setState(() {
                                _manualCandidates.remove(entry.value.id);
                                _selections[entry.value.id] =
                                    _selections[entry.value.id]!.copyWith(
                                      cardId: candidate.card.id,
                                      confirmed: true,
                                      included: true,
                                    );
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: () => context.go('/scan'),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('重新扫描'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.count, required this.allUnrecognized});
  final int count;
  final bool allUnrecognized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: allUnrecognized ? const Color(0xFFFFF0E9) : FanColors.lavenderSoft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(
          Icons.document_scanner_outlined,
          size: 22,
          color: allUnrecognized ? FanColors.coral : FanColors.lavender,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '扫描结果 · 识别到 $count 张',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                allUnrecognized
                    ? '暂未匹配到图鉴，可逐张搜索或反馈。'
                    : '核对后可批量喜欢或标记拥有；点官方卡图查看详情。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DetectedResultCard extends StatelessWidget {
  const _DetectedResultCard({
    super.key,
    required this.index,
    required this.session,
    required this.detected,
    required this.candidate,
    required this.selection,
    required this.ownedQuantity,
    required this.wished,
    required this.onConfirm,
    required this.onCandidates,
    required this.onIncludedChanged,
    required this.onWishlist,
    required this.onOwned,
    required this.sameCardCount,
    required this.onSearch,
    required this.onFeedback,
    required this.onDetail,
    required this.onChooseCandidate,
  });
  final int index;
  final ScanSession session;
  final DetectedScanCard detected;
  final ScanCandidate? candidate;
  final _DetectedSelection selection;
  final int ownedQuantity;
  final int sameCardCount;
  final bool wished;
  final VoidCallback onConfirm,
      onCandidates,
      onWishlist,
      onOwned,
      onSearch,
      onFeedback,
      onDetail;
  final ValueChanged<bool> onIncludedChanged;
  final ValueChanged<ScanCandidate> onChooseCandidate;

  @override
  Widget build(BuildContext context) {
    final options = detected.candidates
        .where(
          (item) => candidate == null || item.card.id != candidate!.card.id,
        )
        .take(3)
        .toList();
    final approximate =
        (candidate ?? detected.topCandidate)?.isApproximate == true;
    final compactStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
    return Card(
      key: Key('scan-region-${detected.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Checkbox(
                    key: Key('scan-region-select-${detected.id}'),
                    value: selection.confirmed && selection.included,
                    onChanged:
                        (candidate != null || detected.candidates.isNotEmpty)
                        ? (value) => onIncludedChanged(value ?? false)
                        : null,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '识别对象 ${index + 1}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _RecognitionBadge(
                  status: approximate
                      ? ScanRecognitionStatus.needsConfirmation
                      : detected.status,
                  confirmed: selection.confirmed,
                  added: selection.added && ownedQuantity > 0,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (candidate != null)
                  InkWell(
                    key: Key('scan-official-${detected.id}'),
                    onTap: onDetail,
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        _CardThumbnail(
                          path: candidate!.card.imageUrl,
                          card: candidate!.card,
                          width: 84,
                          height: 120,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '官方图鉴 ↗',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                else
                  _CardThumbnail(
                    path: detected.cropImagePath ?? session.originalImagePath,
                    width: 72,
                    height: 102,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (candidate != null) ...[
                        FanEntityName(
                          kind: candidate!.card.hasIndividualIdol
                              ? 'idols'
                              : 'groups',
                          id: candidate!.card.hasIndividualIdol
                              ? candidate!.card.idolId
                              : candidate!.card.groupId,
                          officialName: !candidate!.card.hasIndividualIdol
                              ? candidate!.card.groupName
                              : candidate!.card.idolName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (candidate!.card.source.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            candidate!.card.source,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (candidate!.card.version.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            candidate!.card.version,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          candidate!.isApproximate
                              ? '相似候选 · 已手动确认'
                              : candidate!.similarity > 0
                              ? '相似度 ${(candidate!.similarity * 100).round()}%'
                              : '手动选择',
                          style: const TextStyle(
                            fontSize: 12,
                            color: FanColors.textSecondary,
                          ),
                        ),
                        if (ownedQuantity > 0)
                          Text(
                            '已拥有 ×$ownedQuantity',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (sameCardCount > 1)
                          Text(
                            '本次有 $sameCardCount 张匹配同款，请核对',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _CardThumbnail(
                              path:
                                  detected.cropImagePath ??
                                  session.originalImagePath,
                              width: 28,
                              height: 40,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '扫描对照',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          approximate ? '相似候选，需手动确认' : '暂未找到匹配的小卡',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          approximate
                              ? '请对照卡面选择，确认后可喜欢或标记拥有。'
                              : '可搜索图鉴或反馈，不影响其他小卡。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (options.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          candidate == null ? '相似结果' : '其他相似结果',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in options)
                              _CandidateThumbnail(
                                candidate: option,
                                selected:
                                    selection.confirmed &&
                                    selection.cardId == option.card.id,
                                onDetail: () =>
                                    _openScanCardDetail(context, option.card),
                                onChoose: () => onChooseCandidate(option),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (candidate != null && !selection.confirmed)
                  FilledButton(
                    style: compactStyle,
                    onPressed: onConfirm,
                    child: const Text('确认是这张'),
                  ),
                OutlinedButton(
                  style: compactStyle,
                  onPressed: selection.added ? null : onCandidates,
                  child: Text(
                    detected.status == ScanRecognitionStatus.recommended
                        ? '查看其他相似结果'
                        : '查看相似结果',
                  ),
                ),
                if (!selection.added && candidate == null)
                  TextButton(
                    style: compactStyle,
                    onPressed: onSearch,
                    child: const Text('搜索图鉴'),
                  ),
                if (selection.confirmed) ...[
                  TextButton.icon(
                    key: Key('scan-like-${detected.id}'),
                    style: compactStyle,
                    onPressed: onWishlist,
                    icon: Icon(
                      wished ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                    ),
                    label: Text(wished ? '取消喜欢' : '喜欢'),
                  ),
                  if (ownedQuantity > 0 || selection.added)
                    TextButton.icon(
                      key: Key('scan-owned-${detected.id}'),
                      style: compactStyle,
                      onPressed: onOwned,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(ownedQuantity > 0 ? '取消拥有' : '标记拥有'),
                    ),
                ],
                TextButton(
                  style: compactStyle,
                  onPressed: onFeedback,
                  child: const Text('我要反馈'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardThumbnail extends StatelessWidget {
  const _CardThumbnail({
    required this.path,
    required this.width,
    required this.height,
    this.card,
  });
  final String? path;
  final double width, height;
  final CollectibleCard? card;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ScanImage(
      path: path,
      fallback: card == null
          ? Container(
              color: const Color(0xFFF0F2F6),
              child: const Icon(
                Icons.photo_outlined,
                color: FanColors.textSecondary,
                size: 20,
              ),
            )
          : FanArtwork(
              startColor: Color(card!.colorStart),
              endColor: Color(card!.colorEnd),
              label: card!.idolName.characters.take(2).toString(),
              borderRadius: 8,
            ),
    ),
  );
}

class _CandidateThumbnail extends StatelessWidget {
  const _CandidateThumbnail({
    required this.candidate,
    required this.selected,
    required this.onDetail,
    required this.onChoose,
  });
  final ScanCandidate candidate;
  final bool selected;
  final VoidCallback onDetail, onChoose;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Column(
      children: [
        InkWell(
          onTap: onDetail,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? FanColors.lavender : FanColors.line,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _CardThumbnail(
              path: candidate.card.imageUrl,
              card: candidate.card,
              width: 40,
              height: 57,
            ),
          ),
        ),
        InkWell(
          key: Key('scan-choose-candidate-${candidate.card.id}'),
          onTap: onChoose,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 13,
                  color: selected
                      ? FanColors.lavender
                      : FanColors.textSecondary,
                ),
                const SizedBox(width: 2),
                const Text('选择', style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecognitionBadge extends StatelessWidget {
  const _RecognitionBadge({
    required this.status,
    required this.confirmed,
    required this.added,
  });
  final ScanRecognitionStatus status;
  final bool confirmed, added;
  @override
  Widget build(BuildContext context) {
    final text = added
        ? '已标记拥有'
        : confirmed
        ? '✓ 已确认'
        : switch (status) {
            ScanRecognitionStatus.recommended => '✓ 推荐结果',
            ScanRecognitionStatus.needsConfirmation => '待确认',
            ScanRecognitionStatus.unrecognized => '需要确认',
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: added || confirmed
            ? FanColors.lavenderSoft
            : const Color(0xFFF0F2F6),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: FanColors.textSecondary,
        ),
      ),
    );
  }
}

Future<void> _openScanCardDetail(
  BuildContext context,
  CollectibleCard card,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => CardDetailPage(cardId: card.id)),
  );
}

class _CandidatePicker extends StatelessWidget {
  const _CandidatePicker({
    required this.detected,
    required this.selectedCardId,
    required this.onSearch,
  });

  final DetectedScanCard detected;
  final String? selectedCardId;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: (220.0 + detected.candidates.take(5).length * 124).clamp(
          240.0,
          MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('相似结果选择', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '请选择最符合扫描图的小卡，选择后即完成单张确认。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('scan-candidates-search'),
                      onPressed: onSearch,
                      icon: const Icon(Icons.search_rounded, size: 16),
                      label: const Text('搜索更多图鉴'),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('scan-candidates-none'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('都不是'),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: detected.candidates.take(5).length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final candidate = detected.candidates[index];
                  return Card(
                    child: ListTile(
                      onTap: () => Navigator.of(context).pop(candidate),
                      contentPadding: const EdgeInsets.all(10),
                      leading: SizedBox(
                        width: 48,
                        child: ScanImage(
                          path: candidate.card.imageUrl,
                          fallback: FanArtwork(
                            startColor: Color(candidate.card.colorStart),
                            endColor: Color(candidate.card.colorEnd),
                            label: candidate.card.idolName.characters.first,
                            borderRadius: 9,
                          ),
                        ),
                      ),
                      title: Text(
                        candidate.card.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FanEntityName(
                            kind: 'idols',
                            id: candidate.card.idolId,
                            officialName: candidate.card.idolName,
                            suffix:
                                ' · ${candidate.card.source}\n${candidate.card.version}',
                          ),
                          Text(
                            candidate.isApproximate
                                ? '相似候选，需手动确认'
                                : '相似度 ${(candidate.similarity * 100).round()}%',
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key(
                              'scan-candidate-detail-${candidate.card.id}',
                            ),
                            tooltip: '查看小卡详情',
                            onPressed: () =>
                                _openScanCardDetail(context, candidate.card),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                            ),
                          ),
                          if (selectedCardId == candidate.card.id)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: FanColors.mint,
                              size: 14,
                            ),
                        ],
                      ),
                    ),
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

class _DetectedSelection {
  const _DetectedSelection({
    required this.cardId,
    required this.confirmed,
    required this.included,
    this.added = false,
  });

  final String? cardId;
  final bool confirmed;
  final bool included;
  final bool added;

  _DetectedSelection copyWith({
    String? cardId,
    bool? confirmed,
    bool? included,
    bool? added,
  }) => _DetectedSelection(
    cardId: cardId ?? this.cardId,
    confirmed: confirmed ?? this.confirmed,
    included: included ?? this.included,
    added: added ?? this.added,
  );
}

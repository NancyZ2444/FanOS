import 'package:fan_os/core/widgets/catalog_tags.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({required this.cardId, super.key});

  final String cardId;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return catalog.when(
      loading: () => Scaffold(
        appBar: AppBar(leading: const BackButton(), title: const Text('小卡详情')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(leading: const BackButton(), title: const Text('小卡详情')),
        body: const FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '小卡加载失败',
          message: '请稍后重试。',
        ),
      ),
      data: (data) {
        final card = data.cards
            .where((item) => item.id == widget.cardId)
            .firstOrNull;
        if (card == null) {
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('小卡详情'),
            ),
            body: const FanEmptyState(
              icon: Icons.style_outlined,
              title: '没有找到这张小卡',
              message: '该内容可能已下架，但已有收藏关系仍会保留。',
            ),
          );
        }
        return _buildScaffold(context, card, data);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    CollectibleCard card,
    CatalogBundle data,
  ) {
    final collection = ref.watch(collectionProvider);
    final idolName = entityDisplayName(
      ref,
      'idols',
      card.idolId,
      card.idolName,
    );
    final groupName = entityDisplayName(
      ref,
      'groups',
      card.groupId,
      card.groupName,
    );
    final quantity = collection.quantity(card.id);
    final isWished = collection.isWished(card.id);
    final related = _relatedCards(card, data.cards);
    final sourceTarget = _findSourceTarget(card, data);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('小卡详情'),
        actions: [
          IconButton(
            tooltip: '分享',
            onPressed: () => showFanToast(context, '分享链接已准备'),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: () => _showMoreActions(card),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: FanColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('card-owned-action'),
                  onPressed: () => _protectedAction(() {
                    if (quantity == 0) {
                      ref
                          .read(collectionProvider.notifier)
                          .setOwnedQuantity(card.id, 1);
                      showFanToast(context, '已加入收藏');
                    } else {
                      _showQuantityEditor(card, quantity);
                    }
                  }),
                  icon: Icon(
                    quantity > 0
                        ? Icons.check_circle_rounded
                        : Icons.add_rounded,
                  ),
                  label: Text(quantity > 0 ? '已拥有 $quantity' : '我有这张'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('card-wishlist-action'),
                  onPressed: () => _protectedAction(() {
                    ref
                        .read(collectionProvider.notifier)
                        .toggleWishlist(card.id);
                    showFanToast(context, isWished ? '已移出我的喜欢' : '已加入我的喜欢');
                  }),
                  icon: Icon(
                    isWished
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isWished ? FanColors.lavender : null,
                  ),
                  label: Text(isWished ? '已喜欢' : '喜欢'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: FanContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardPreview(
                card: card,
                showBack: _showBack,
                onSelectSide: (showBack) => setState(() {
                  _showBack = showBack;
                }),
                onOpen: () => _showImagePreview(card),
              ),
              const SizedBox(height: 16),
              CardContributors(cardId: card.id),
              Text(idolName, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(
                data.cardSourceLabel(card),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (card.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                CatalogTagChips(tags: card.tags),
              ],
              if (card.secondaryTitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  card.secondaryTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: FanColors.textSecondary),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (card.cardType.trim().isNotEmpty)
                    Chip(label: Text(card.cardType)),
                  if (card.version.trim().isNotEmpty)
                    Chip(label: Text(card.version)),
                  if (card.region.trim().isNotEmpty)
                    Chip(label: Text(card.region)),
                  if (card.releaseDate.trim().isNotEmpty)
                    Chip(label: Text(card.releaseDate)),
                ],
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: '小卡信息'),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _InfoRow(
                        label: '所属艺人',
                        value: idolName,
                        onTap: () => context.push(
                          card.idolId.isEmpty
                              ? '/group/${card.groupId}'
                              : '/idol/${card.idolId}',
                        ),
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        label: '所属组合',
                        value: groupName,
                        onTap: () => context.push('/group/${card.groupId}'),
                      ),
                      const Divider(height: 1),
                      _InfoRow(
                        label: '来源',
                        value: card.source,
                        onTap: sourceTarget == null
                            ? null
                            : () => context.push(sourceTarget.route),
                      ),
                      const Divider(height: 1),
                      _InfoRow(label: '小卡类型', value: card.cardType),
                      const Divider(height: 1),
                      _InfoRow(label: '版本', value: card.version),
                      const Divider(height: 1),
                      _InfoRow(label: '发行日期', value: card.releaseDate),
                      const Divider(height: 1),
                      _InfoRow(label: '地区', value: card.region),
                      const Divider(height: 1),
                      _InfoRow(
                        onTap: card.cardNumber.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: card.cardNumber),
                                );
                                if (context.mounted) {
                                  showFanToast(context, '编号已复制');
                                }
                              },
                        label: '编号',
                        value: card.cardNumber.isEmpty
                            ? '暂未收录'
                            : card.cardNumber,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: '来源链路'),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SourceStep(
                          icon: Icons.groups_2_outlined,
                          label: '组合',
                          value: groupName,
                          onTap: () => context.push('/group/${card.groupId}'),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: FanColors.textSecondary,
                      ),
                      Expanded(
                        child: _SourceStep(
                          icon:
                              sourceTarget?.icon ?? Icons.inventory_2_outlined,
                          label: sourceTarget?.typeLabel ?? '来源',
                          value: sourceTarget?.label ?? card.source,
                          onTap: sourceTarget == null
                              ? null
                              : () => context.push(sourceTarget.route),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: FanColors.textSecondary,
                      ),
                      const Expanded(
                        child: _SourceStep(
                          icon: Icons.style_outlined,
                          label: '小卡',
                          value: '当前',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (related.isNotEmpty) ...[
                const SizedBox(height: 28),
                SectionHeader(
                  title: '相关小卡',
                  actionLabel: '查看更多',
                  onAction: () => context.push(
                    '/cards?group=${card.groupId}&idol=${card.idolId}',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 230,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: related.take(6).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 118,
                      child: CollectibleCardTile(
                        card: related[index],
                        compact: true,
                        onTap: () => context.pushReplacement(
                          '/card/${related[index].id}',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<CollectibleCard> _relatedCards(
    CollectibleCard card,
    List<CollectibleCard> cards,
  ) {
    final result = cards
        .where((item) => item.id != card.id && item.groupId == card.groupId)
        .toList();
    result.sort((a, b) {
      int score(CollectibleCard item) {
        var value = 0;
        if (item.source == card.source) value += 8;
        if (item.version == card.version) value += 4;
        if (item.idolId == card.idolId) value += 2;
        return value;
      }

      return score(b).compareTo(score(a));
    });
    return result;
  }

  _SourceTarget? _findSourceTarget(CollectibleCard card, CatalogBundle data) {
    if (card.sourceEntityId != null) {
      final id = card.sourceEntityId;
      final name = switch (card.sourceEntityType) {
        'ALBUM' =>
          data.albums.where((i) => i.id == id).firstOrNull?.displayName,
        'EVENT' =>
          data.events.where((i) => i.id == id).firstOrNull?.displayName,
        'OTHER' =>
          data.others.where((i) => i.id == id).firstOrNull?.displayName,
        _ => null,
      };
      if (name == null) return null;
      final route = {
        'ALBUM': 'album',
        'EVENT': 'event',
        'OTHER': 'other',
      }[card.sourceEntityType];
      return _SourceTarget(
        label: name,
        typeLabel: {
          'ALBUM': '专辑',
          'EVENT': '活动',
          'OTHER': '其他来源',
        }[card.sourceEntityType]!,
        route: '/$route/$id',
        icon: Icons.book_outlined,
      );
    }
    final source = card.source.toLowerCase();
    if (card.cardType != 'Album Card') {
      final event = data.events.where((item) {
        final root = item.name.toLowerCase().split(RegExp(r'[ ·]')).first;
        return item.groupId == card.groupId &&
            source.contains(root) &&
            (source.contains('fansign') ||
                source.contains('tour') ||
                source.contains('pop-up'));
      }).firstOrNull;
      if (event != null) {
        return _SourceTarget(
          label: event.name,
          typeLabel: '活动',
          route: '/event/${event.id}',
          icon: Icons.auto_awesome_outlined,
        );
      }
    }
    final album = data.albums.where((item) {
      return item.groupId == card.groupId &&
          source.contains(item.name.toLowerCase());
    }).firstOrNull;
    if (album != null) {
      return _SourceTarget(
        label: album.name,
        typeLabel: '专辑',
        route: '/album/${album.id}',
        icon: Icons.album_outlined,
      );
    }
    return null;
  }

  void _protectedAction(VoidCallback action) {
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }
    action();
  }

  Future<void> _showQuantityEditor(
    CollectibleCard card,
    int initialQuantity,
  ) async {
    var quantity = initialQuantity;
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('管理拥有数量', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                card.secondaryTitle.isEmpty
                    ? card.displayTitle
                    : '${card.displayTitle} · ${card.secondaryTitle}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('quantity-minus'),
                    onPressed: quantity == 0
                        ? null
                        : () => setSheetState(() => quantity -= 1),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 88,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('quantity-plus'),
                    onPressed: quantity == 99
                        ? null
                        : () => setSheetState(() => quantity += 1),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                quantity == 0 ? '数量为 0 时将从收藏移除' : '重复卡可直接调整数量',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(quantity),
                child: const Text('保存数量'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    ref.read(collectionProvider.notifier).setOwnedQuantity(card.id, result);
    showFanToast(context, result == 0 ? '已从收藏移除' : '已更新为拥有 $result 张');
  }

  Future<void> _showImagePreview(CollectibleCard card) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _CardFace(card: card, showBack: _showBack),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreActions(CollectibleCard card) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('反馈资料错误'),
                subtitle: Text(
                  card.cardNumber.isEmpty
                      ? card.id.toUpperCase()
                      : card.cardNumber,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/catalog-correction?type=cards&id=${card.id}');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardPreview extends StatelessWidget {
  const _CardPreview({
    required this.card,
    required this.showBack,
    required this.onSelectSide,
    required this.onOpen,
  });

  final CollectibleCard card;
  final bool showBack;
  final ValueChanged<bool> onSelectSide;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final hasBack = card.backImageUrl?.trim().isNotEmpty == true;
    return Center(
      child: SizedBox(
        width: (MediaQuery.sizeOf(context).height * .36).clamp(200.0, 268.0),
        child: Semantics(
          label: showBack ? '小卡背面，轻点翻回正面' : '小卡正面，轻点查看背面',
          button: true,
          child: GestureDetector(
            key: const ValueKey('card-large-preview'),
            onTap: () {
              if (hasBack) {
                onSelectSide(!showBack);
              } else {
                showFanToast(context, '暂无卡背信息');
              }
            },
            onLongPress: onOpen,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _CardFace(
                key: ValueKey(showBack),
                card: card,
                showBack: showBack && hasBack,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.showBack, super.key});

  final CollectibleCard card;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return FanArtwork(
      imageUrl: showBack ? card.backImageUrl : card.imageUrl,
      fit: BoxFit.contain,
      startColor: showBack ? Color(card.colorEnd) : Color(card.colorStart),
      endColor: showBack ? FanColors.ink : Color(card.colorEnd),
      label: showBack
          ? 'BACK'
          : card.idolName.characters.take(2).toString().toUpperCase(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 82,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '暂未收录' : value,
                maxLines: label == '编号' ? 1 : null,
                overflow: label == '编号' ? TextOverflow.ellipsis : null,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceStep extends StatelessWidget {
  const _SourceStep({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Icon(icon, size: 20, color: FanColors.lavender),
            const SizedBox(height: 5),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTarget {
  const _SourceTarget({
    required this.label,
    required this.typeLabel,
    required this.route,
    required this.icon,
  });

  final String label;
  final String typeLabel;
  final String route;
  final IconData icon;
}

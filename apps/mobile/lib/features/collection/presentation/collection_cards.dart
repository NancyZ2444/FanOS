import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionCards extends ConsumerStatefulWidget {
  const CollectionCards({super.key, required this.wished, required this.list});
  final bool wished, list;
  @override
  ConsumerState<CollectionCards> createState() => _CollectionCardsState();
}

class _CollectionCardsState extends ConsumerState<CollectionCards> {
  bool _imagesOnly = false;
  String? _idol, _group, _type;
  final _scroll = ScrollController();
  int _columns = 3;
  double _extent = 180;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CollectionCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.list != widget.list) _retainAnchor(() {});
  }

  void _retainAnchor(VoidCallback change) {
    final anchor = _scroll.hasClients
        ? (_scroll.offset / (_extent + 8)).floor() * _columns
        : 0;
    setState(change);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(
          (anchor ~/ _columns * (_extent + 8)).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _filter(VoidCallback change) {
    setState(change);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final relation = ref.watch(collectionProvider);
    return ref
        .watch(catalogProvider)
        .when(
          loading: () => const FanPageSkeleton(),
          error: (_, _) => FanEmptyState(
            icon: Icons.cloud_off_outlined,
            title: '收藏暂时未能加载',
            message: '请检查网络后重试',
            actionLabel: '重新加载',
            onAction: () => ref.invalidate(catalogProvider),
          ),
          data: (catalog) {
            final all = catalog.cards
                .where(
                  (c) => widget.wished
                      ? relation.isWished(c.id)
                      : relation.isOwned(c.id),
                )
                .toList();
            final cards = all
                .where(
                  (c) =>
                      (_idol == null || c.idolId == _idol) &&
                      (_group == null || c.groupId == _group) &&
                      (_type == null || c.cardType == _type),
                )
                .toList();
            final filtered = _idol != null || _group != null || _type != null;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: () => _filter(() {
                                  _idol = _group = _type = null;
                                }),
                                child: Text(
                                  '全部',
                                  style: TextStyle(
                                    color: !filtered
                                        ? FanColors.lavender
                                        : FanColors.textSecondary,
                                  ),
                                ),
                              ),
                              _filterMenu('艺人', _idol, {
                                for (final c in all)
                                  if (c.hasIndividualIdol) c.idolId: c.idolName,
                              }, (v) => _filter(() => _idol = v)),
                              _filterMenu('组合', _group, {
                                for (final c in all)
                                  if (c.groupId.isNotEmpty)
                                    c.groupId: c.groupName,
                              }, (v) => _filter(() => _group = v)),
                              _filterMenu('类型', _type, {
                                for (final c in all)
                                  if (c.cardType.isNotEmpty)
                                    c.cardType: c.cardType,
                              }, (v) => _filter(() => _type = v)),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key(
                          widget.wished
                              ? 'wishlist-content-mode'
                              : 'owned-content-mode',
                        ),
                        tooltip: _imagesOnly ? '切换图文' : '切换纯图',
                        onPressed: () =>
                            _retainAnchor(() => _imagesOnly = !_imagesOnly),
                        style: IconButton.styleFrom(
                          backgroundColor: FanColors.lavenderSoft,
                          foregroundColor: FanColors.lavender,
                        ),
                        icon: Icon(
                          _imagesOnly
                              ? Icons.image_outlined
                              : Icons.photo_library_outlined,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? FanEmptyState(
                          icon: filtered
                              ? Icons.filter_alt_off_outlined
                              : widget.wished
                              ? Icons.favorite_border
                              : Icons.style_outlined,
                          title: filtered
                              ? '没有符合条件的小卡'
                              : widget.wished
                              ? '心愿单还是空的'
                              : '还没有拥有的小卡',
                          message: filtered ? '试试调整筛选条件。' : '去图鉴发现喜欢的小卡。',
                          actionLabel: filtered ? '清空筛选' : '去逛图鉴',
                          onAction: filtered
                              ? () => _filter(() {
                                  _idol = _group = _type = null;
                                })
                              : () => context.go('/catalog'),
                        )
                      : LayoutBuilder(
                          builder: (context, bounds) {
                            final scale =
                                MediaQuery.textScalerOf(context).scale(14) / 14;
                            _columns = widget.list
                                ? 1
                                : bounds.maxWidth < 340 || scale > 1.3
                                ? 2
                                : 3;
                            final width =
                                (bounds.maxWidth - 32 - (_columns - 1) * 8) /
                                _columns;
                            _extent = widget.list
                                ? (_imagesOnly ? 310 : 126 * scale)
                                : width / .70 + (_imagesOnly ? 8 : 54 * scale);
                            return GridView.builder(
                              key: Key(
                                widget.wished
                                    ? 'wishlist-cards'
                                    : 'owned-cards',
                              ),
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: cards.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _columns,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                    mainAxisExtent: _extent,
                                  ),
                              itemBuilder: (context, index) {
                                final c = cards[index];
                                final image = ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: ColoredBox(
                                    color: Colors.white,
                                    child: AlbumCardImage(c, thumbnail: true),
                                  ),
                                );
                                final title = c.hasIndividualIdol
                                    ? c.idolName
                                    : c.groupName;
                                final caption = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      c.source,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: FanColors.textSecondary,
                                      ),
                                    ),
                                    if (widget.list)
                                      Text(
                                        [
                                          c.version,
                                          if (!widget.wished)
                                            '已拥有 ×${relation.quantity(c.id)}',
                                        ].where((v) => v.isNotEmpty).join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: FanColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                );
                                return Semantics(
                                  label:
                                      '${c.displayTitle}${widget.wished ? '，心愿单' : '，已拥有 ${relation.quantity(c.id)} 张'}',
                                  button: true,
                                  child: InkWell(
                                    key: ValueKey('collection-card-${c.id}'),
                                    onTap: () => context.push('/card/${c.id}'),
                                    borderRadius: BorderRadius.circular(12),
                                    child: _imagesOnly
                                        ? image
                                        : widget.list
                                        ? Row(
                                            children: [
                                              SizedBox(width: 76, child: image),
                                              const SizedBox(width: 12),
                                              Expanded(child: caption),
                                              const Icon(
                                                Icons.chevron_right,
                                                size: 18,
                                              ),
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: image),
                                              const SizedBox(height: 6),
                                              caption,
                                            ],
                                          ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
  }

  Widget _filterMenu(
    String label,
    String? selected,
    Map<String, String> options,
    ValueChanged<String?> change,
  ) => PopupMenuButton<String>(
    tooltip: '筛选$label',
    initialValue: selected ?? '',
    onSelected: (v) => change(v.isEmpty ? null : v),
    itemBuilder: (_) => [
      PopupMenuItem(value: '', child: Text('全部$label')),
      for (final e in options.entries)
        PopupMenuItem(value: e.key, child: Text(e.value)),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 88),
            child: Text(
              options[selected] ?? label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: selected == null
                    ? FanColors.textSecondary
                    : FanColors.lavender,
              ),
            ),
          ),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    ),
  );
}

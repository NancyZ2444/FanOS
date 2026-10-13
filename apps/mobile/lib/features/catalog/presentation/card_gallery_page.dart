import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CardGalleryPage extends ConsumerStatefulWidget {
  const CardGalleryPage({super.key, this.groupId, this.idolId});
  final String? groupId;
  final String? idolId;

  @override
  ConsumerState<CardGalleryPage> createState() => _CardGalleryPageState();
}

class _CardGalleryPageState extends ConsumerState<CardGalleryPage> {
  String _sort = '最新发行';
  bool _ownedOnly = false;
  bool _wishlistOnly = false;
  Set<String> _idolIds = {};
  Set<String> _groupIds = {};
  Set<String> _years = {};
  Set<String> _types = {};
  Set<String> _regions = {};
  Set<String> _sources = {};
  Set<String> _sourceTypes = {};
  Set<String> _tagIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.groupId != null) _groupIds = {widget.groupId!};
    if (widget.idolId != null) _idolIds = {widget.idolId!};
  }

  bool get _hasFilters =>
      _ownedOnly ||
      _wishlistOnly ||
      _idolIds.isNotEmpty ||
      _groupIds.isNotEmpty ||
      _years.isNotEmpty ||
      _types.isNotEmpty ||
      _regions.isNotEmpty ||
      _sources.isNotEmpty ||
      _sourceTypes.isNotEmpty ||
      _tagIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final collection = ref.watch(collectionProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('小卡图鉴'),
        actions: [
          IconButton(
            tooltip: '搜索小卡',
            onPressed: () => context.push('/search?type=小卡'),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'AI Scan',
            onPressed: () => context.go('/scan'),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '加载失败',
          message: '请稍后重试',
        ),
        data: (data) {
          final cards = _filteredCards(data, collection);
          return Column(
            children: [
              _QuickControls(
                ownedOnly: _ownedOnly,
                wishlistOnly: _wishlistOnly,
                filterCount: _activeFilterCount,
                sort: _sort,
                onOwned: () => setState(() => _ownedOnly = !_ownedOnly),
                onWishlist: () =>
                    setState(() => _wishlistOnly = !_wishlistOnly),
                onFilter: () => _showFilters(data),
                onSort: (value) => setState(() => _sort = value),
              ),
              if (_hasFilters) _activeFilters(data),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Row(
                  children: [
                    Text(
                      '${cards.length} 张小卡',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text('3 列图库', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Expanded(
                child: cards.isEmpty
                    ? FanEmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: '当前筛选条件没有结果',
                        message: '删除单个条件，或清空筛选查看全部小卡。',
                        actionLabel: '清空筛选',
                        onAction: _clearFilters,
                      )
                    : GridView.builder(
                        key: const Key('card-gallery-grid'),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 9,
                              mainAxisSpacing: 16,
                              childAspectRatio: .52,
                            ),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          final card = cards[index];
                          return CollectibleCardTile(
                            card: card,
                            compact: true,
                            badge: _CardRelationBadge(
                              owned: collection.isOwned(card.id),
                              wished: collection.isWished(card.id),
                            ),
                            onTap: () => context.push('/card/${card.id}'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  int get _activeFilterCount =>
      _idolIds.length +
      _groupIds.length +
      _years.length +
      _types.length +
      _regions.length +
      _sources.length +
      _sourceTypes.length +
      _tagIds.length;

  List<CollectibleCard> _filteredCards(
    CatalogBundle data,
    CollectionState collection,
  ) {
    final cards = data.cards.where((card) {
      return (!_ownedOnly || collection.isOwned(card.id)) &&
          (!_wishlistOnly || collection.isWished(card.id)) &&
          (_idolIds.isEmpty || _idolIds.contains(card.idolId)) &&
          (_groupIds.isEmpty || _groupIds.contains(card.groupId)) &&
          (_years.isEmpty ||
              _years.contains(card.releaseDate.split(RegExp(r'[.-]')).first)) &&
          (_types.isEmpty || _types.contains(card.cardType)) &&
          (_regions.isEmpty || _regions.contains(card.region)) &&
          (_sources.isEmpty || _sources.contains(card.sourceEntityId)) &&
          (_sourceTypes.isEmpty ||
              _sourceTypes.contains(card.sourceEntityType)) &&
          _tagIds.every((id) => card.tags.any((t) => t.id == id));
    }).toList();
    switch (_sort) {
      case '最早发行':
        cards.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));
      case 'A–Z':
        cards.sort((a, b) => a.title.compareTo(b.title));
      case '最近收录':
        cards.sort((a, b) => b.id.compareTo(a.id));
      default:
        cards.sort((a, b) => b.releaseDate.compareTo(a.releaseDate));
    }
    return cards;
  }

  Widget _activeFilters(CatalogBundle data) {
    final tags = {
      for (final c in data.cards)
        for (final t in c.tags) t.id: t.name,
    };
    final sourceNames = {
      for (final i in data.albums) i.id: i.displayName,
      for (final i in data.events) i.id: i.displayName,
      for (final i in data.others) i.id: i.displayName,
    };
    final chips = <(String, VoidCallback)>[
      for (final id in _tagIds)
        (tags[id] ?? id, () => setState(() => _tagIds.remove(id))),
      for (final type in _sourceTypes)
        (
          {'ALBUM': '专辑', 'EVENT': '活动', 'OTHER': '其他来源'}[type]!,
          () => setState(() => _sourceTypes.remove(type)),
        ),
      if (_ownedOnly) ('已拥有', () => setState(() => _ownedOnly = false)),
      if (_wishlistOnly)
        ('Wishlist', () => setState(() => _wishlistOnly = false)),
      for (final id in _idolIds)
        (
          data.idols.where((item) => item.id == id).firstOrNull?.name ?? id,
          () => setState(() => _idolIds.remove(id)),
        ),
      for (final id in _groupIds)
        (
          data.groups.where((item) => item.id == id).firstOrNull?.name ?? id,
          () => setState(() => _groupIds.remove(id)),
        ),
      for (final value in _years)
        (value, () => setState(() => _years.remove(value))),
      for (final value in _types)
        (value, () => setState(() => _types.remove(value))),
      for (final value in _regions)
        (value, () => setState(() => _regions.remove(value))),
      for (final value in _sources)
        (
          sourceNames[value] ?? value,
          () => setState(() => _sources.remove(value)),
        ),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          if (index == chips.length) {
            return TextButton(
              onPressed: _clearFilters,
              child: const Text('清空'),
            );
          }
          return InputChip(
            label: Text(chips[index].$1),
            onDeleted: chips[index].$2,
          );
        },
      ),
    );
  }

  Future<void> _showFilters(CatalogBundle data) async {
    var idols = {..._idolIds};
    var groups = {..._groupIds};
    var years = {..._years};
    var types = {..._types};
    var regions = {..._regions};
    var sources = {..._sources};
    var sourceTypes = {..._sourceTypes};
    var tagIds = {..._tagIds};
    final collection = ref.read(collectionProvider);
    final sourceNames = {
      for (final i in data.albums) i.id: i.displayName,
      for (final i in data.events) i.id: i.displayName,
      for (final i in data.others) i.id: i.displayName,
    };
    Iterable<CollectibleCard> contextCards({
      bool withTags = true,
      bool withSources = true,
    }) => data.cards.where(
      (c) =>
          (!_ownedOnly || collection.isOwned(c.id)) &&
          (!_wishlistOnly || collection.isWished(c.id)) &&
          (groups.isEmpty || groups.contains(c.groupId)) &&
          (idols.isEmpty || idols.contains(c.idolId)) &&
          (years.isEmpty ||
              years.contains(c.releaseDate.split(RegExp(r'[.-]')).first)) &&
          (types.isEmpty || types.contains(c.cardType)) &&
          (regions.isEmpty || regions.contains(c.region)) &&
          (sourceTypes.isEmpty || sourceTypes.contains(c.sourceEntityType)) &&
          (!withSources ||
              sources.isEmpty ||
              sources.contains(c.sourceEntityId)) &&
          (!withTags || tagIds.every((id) => c.tags.any((t) => t.id == id))),
    );
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void toggle(Set<String> values, String value) {
            setSheetState(() {
              values.contains(value) ? values.remove(value) : values.add(value);
              if (!identical(values, tagIds)) {
                sources.retainAll(
                  contextCards(
                    withTags: false,
                    withSources: false,
                  ).map((c) => c.sourceEntityId).whereType<String>(),
                );
                tagIds.retainAll(
                  contextCards(withTags: false)
                      .expand((c) => c.tags)
                      .map((t) => t.id),
                );
              }
            });
          }

          final availableTags = {
            for (final c in contextCards())
              for (final t in c.tags) t.id: t.name,
          };
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Text(
                          '筛选小卡',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setSheetState(() {
                            idols.clear();
                            groups.clear();
                            years.clear();
                            types.clear();
                            regions.clear();
                            sources.clear();
                            sourceTypes.clear();
                            tagIds.clear();
                          }),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      children: [
                        _FilterSection(
                          title: '艺人',
                          values: data.idols
                              .map((item) => (item.id, item.name))
                              .toList(),
                          selected: idols,
                          onToggle: (value) => toggle(idols, value),
                        ),
                        _FilterSection(
                          title: '组合',
                          values: data.groups
                              .map((item) => (item.id, item.name))
                              .toList(),
                          selected: groups,
                          onToggle: (value) => toggle(groups, value),
                        ),
                        _FilterSection(
                          title: '年份',
                          values: data.cards
                              .map(
                                (item) => item.releaseDate
                                    .split(RegExp(r'[.-]'))
                                    .first,
                              )
                              .toSet()
                              .map((value) => (value, value))
                              .toList(),
                          selected: years,
                          onToggle: (value) => toggle(years, value),
                        ),
                        _FilterSection(
                          title: '小卡类型',
                          values: data.cards
                              .map((item) => item.cardType)
                              .toSet()
                              .map((value) => (value, value))
                              .toList(),
                          selected: types,
                          onToggle: (value) => toggle(types, value),
                        ),
                        _FilterSection(
                          title: '地区',
                          values: data.cards
                              .map((item) => item.region)
                              .toSet()
                              .map((value) => (value, value))
                              .toList(),
                          selected: regions,
                          onToggle: (value) => toggle(regions, value),
                        ),
                        _FilterSection(
                          title: '来源类型',
                          values: const [
                            ('ALBUM', '专辑'),
                            ('EVENT', '活动'),
                            ('OTHER', '其他来源'),
                          ],
                          selected: sourceTypes,
                          onToggle: (v) => toggle(sourceTypes, v),
                        ),
                        _FilterSection(
                          title: '来源',
                          values:
                              contextCards(withTags: false, withSources: false)
                                  .map((c) => c.sourceEntityId)
                                  .whereType<String>()
                                  .toSet()
                                  .map((id) => (id, sourceNames[id] ?? id))
                                  .toList(),
                          selected: sources,
                          onToggle: (v) => toggle(sources, v),
                        ),
                        _FilterSection(
                          title: 'Card Tags',
                          values: availableTags.entries
                              .map((e) => (e.key, e.value))
                              .toList(),
                          selected: tagIds,
                          onToggle: (v) => toggle(tagIds, v),
                        ),
                        if (availableTags.isEmpty)
                          const Text(
                            '当前结果没有可用 Tag',
                            style: TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: FilledButton(
                      key: const Key('apply-card-filters'),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('查看筛选结果'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _idolIds = idols;
        _groupIds = groups;
        _years = years;
        _types = types;
        _regions = regions;
        _sources = sources;
        _sourceTypes = sourceTypes;
        _tagIds = tagIds;
      });
    }
  }

  void _clearFilters() => setState(() {
    _ownedOnly = false;
    _wishlistOnly = false;
    _idolIds.clear();
    _groupIds.clear();
    _years.clear();
    _types.clear();
    _regions.clear();
    _sources.clear();
    _sourceTypes.clear();
    _tagIds.clear();
  });
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({
    required this.ownedOnly,
    required this.wishlistOnly,
    required this.filterCount,
    required this.sort,
    required this.onOwned,
    required this.onWishlist,
    required this.onFilter,
    required this.onSort,
  });
  final bool ownedOnly;
  final bool wishlistOnly;
  final int filterCount;
  final String sort;
  final VoidCallback onOwned;
  final VoidCallback onWishlist;
  final VoidCallback onFilter;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        children: [
          FilterChip(
            key: const Key('card-filter-owned'),
            selected: ownedOnly,
            label: const Text('Owned'),
            avatar: const Icon(Icons.check_circle_outline_rounded, size: 16),
            onSelected: (_) => onOwned(),
          ),
          const SizedBox(width: 8),
          FilterChip(
            key: const Key('card-filter-wishlist'),
            selected: wishlistOnly,
            label: const Text('Wishlist'),
            avatar: const Icon(Icons.favorite_border_rounded, size: 16),
            onSelected: (_) => onWishlist(),
          ),
          const SizedBox(width: 8),
          ActionChip(
            key: const Key('open-card-filters'),
            avatar: const Icon(Icons.tune_rounded, size: 16),
            label: Text(filterCount == 0 ? '筛选' : '筛选 $filterCount'),
            onPressed: onFilter,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => const [
              PopupMenuItem(value: '最新发行', child: Text('最新发行')),
              PopupMenuItem(value: '最早发行', child: Text('最早发行')),
              PopupMenuItem(value: 'A–Z', child: Text('A–Z')),
              PopupMenuItem(value: '最近收录', child: Text('最近收录')),
            ],
            child: Chip(
              avatar: const Icon(Icons.swap_vert_rounded, size: 16),
              label: Text(sort),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.values,
    required this.selected,
    required this.onToggle,
  });
  final String title;
  final List<(String, String)> values;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: values
                .map(
                  (item) => FilterChip(
                    label: Text(item.$2),
                    selected: selected.contains(item.$1),
                    onSelected: (_) => onToggle(item.$1),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _CardRelationBadge extends StatelessWidget {
  const _CardRelationBadge({required this.owned, required this.wished});
  final bool owned;
  final bool wished;

  @override
  Widget build(BuildContext context) {
    if (!owned && !wished) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        shape: BoxShape.circle,
      ),
      child: Icon(
        owned ? Icons.check_circle_rounded : Icons.favorite_rounded,
        size: 15,
        color: owned ? FanColors.lavender : FanColors.coral,
      ),
    );
  }
}

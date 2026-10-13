import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  String _status = '全部状态';
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      body: SafeArea(
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => FanEmptyState(
            icon: Icons.cloud_off_rounded,
            title: '图鉴暂时无法加载',
            message: '请检查网络后重试',
            actionLabel: '重新加载',
            onAction: () => ref.invalidate(catalogProvider),
          ),
          data: (data) {
            final groups =
                data.groups
                    .where(
                      (group) => _status == '全部状态' || group.status == _status,
                    )
                    .toList()
                  ..sort(
                    (a, b) => _ascending
                        ? a.name.compareTo(b.name)
                        : b.name.compareTo(a.name),
                  );
            return RefreshIndicator(
              onRefresh: () => ref.refresh(catalogProvider.future),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: FanContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CatalogHeader(onScan: () => context.go('/scan')),
                      const SizedBox(height: 14),
                      FanSearchButton(
                        hint: '搜索组合、艺人、专辑、小卡、用户',
                        onTap: () => context.push('/search'),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const Key('catalog-missing-feedback'),
                          onPressed: () => context.push('/catalog/feedback'),
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 15,
                          ),
                          label: const Text(
                            '反馈缺失内容',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      SectionHeader(
                        title: '✦  最近更新',
                        actionLabel: '查看更多',
                        onAction: () => context.push('/cards'),
                      ),
                      const SizedBox(height: 10),
                      _RecentUpdates(data: data),
                      const SizedBox(height: 25),
                      const SectionHeader(title: '✦  分类浏览'),
                      const SizedBox(height: 10),
                      const _CategoryGrid(),
                      const SizedBox(height: 25),
                      SectionHeader(
                        title: '✦  热门组合',
                        actionLabel: '查看全部',
                        onAction: () => context.push('/catalog/groups'),
                      ),
                      const SizedBox(height: 10),
                      _PopularGroups(groups: data.groups),
                      const SizedBox(height: 25),
                      const SectionHeader(title: '✦  全部组合'),
                      const SizedBox(height: 8),
                      _GroupFilters(
                        status: _status,
                        ascending: _ascending,
                        onStatus: (value) => setState(() => _status = value),
                        onSort: () => setState(() => _ascending = !_ascending),
                      ),
                      const SizedBox(height: 10),
                      if (groups.isEmpty)
                        FanEmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: '当前筛选条件没有结果',
                          message: '清空状态筛选后再试。',
                          actionLabel: '清空筛选',
                          onAction: () => setState(() {
                            _status = '全部状态';
                          }),
                        )
                      else
                        Card(
                          child: Column(
                            children: [
                              for (var i = 0; i < groups.length; i++) ...[
                                _GroupRow(
                                  group: groups[i],
                                  cardCount: data.cards
                                      .where(
                                        (card) => card.groupId == groups[i].id,
                                      )
                                      .length,
                                  albumCount: data.albums
                                      .where(
                                        (album) =>
                                            album.groupId == groups[i].id,
                                      )
                                      .length,
                                  onTap: () =>
                                      context.push('/group/${groups[i].id}'),
                                ),
                                if (i != groups.length - 1)
                                  const Divider(height: 1, indent: 82),
                              ],
                            ],
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
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, color: FanColors.lavender),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('图鉴', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(
                'Discover · Collect · For Your Stars',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _HeaderAction(
          tooltip: 'AI Scan',
          label: 'AI Scan',
          icon: Icons.document_scanner_outlined,
          onTap: onScan,
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.label,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: FanColors.lavenderSoft.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? 13 : 11,
              vertical: 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 23),
                if (label != null) ...[
                  const SizedBox(height: 2),
                  Text(label!, style: const TextStyle(fontSize: 9)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentUpdates extends StatelessWidget {
  const _RecentUpdates({required this.data});
  final CatalogBundle data;

  @override
  Widget build(BuildContext context) {
    final items = <_UpdateItem>[
      if (data.cards.isNotEmpty)
        _UpdateItem(
          type: '小卡',
          imageUrl: data.cards.first.imageUrl,
          title: data.cards.first.displayTitle,
          subtitle: data.cards.first.version,
          date: data.cards.first.releaseDate,
          colors: [
            Color(data.cards.first.colorStart),
            Color(data.cards.first.colorEnd),
          ],
          route: '/card/${data.cards.first.id}',
        ),
      if (data.albums.isNotEmpty)
        _UpdateItem(
          type: '专辑',
          imageUrl: data.albums.first.frontImageUrl,
          title: data.albums.first.displayName,
          subtitle: data.albums.first.secondaryName.isNotEmpty
              ? data.albums.first.secondaryName
              : data.albums.first.artistName,
          date: data.albums.first.releaseDate,
          colors: [
            Color(data.albums.first.colorStart),
            Color(data.albums.first.colorEnd),
          ],
          route: '/album/${data.albums.first.id}',
        ),
      if (data.events.isNotEmpty)
        _UpdateItem(
          type: '活动',
          imageUrl: data.events.first.imageUrl,
          title: data.events.first.displayName,
          subtitle: data.events.first.secondaryName.isNotEmpty
              ? data.events.first.secondaryName
              : data.events.first.eventType,
          date: data.events.first.startDate,
          colors: [
            Color(data.events.first.colorStart),
            Color(data.events.first.colorEnd),
          ],
          route: '/event/${data.events.first.id}',
        ),
    ];
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _UpdateCard(item: items[index]),
      ),
    );
  }
}

class _UpdateItem {
  const _UpdateItem({
    this.imageUrl,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.colors,
    required this.route,
  });
  final String type;
  final String? imageUrl;
  final String title;
  final String subtitle;
  final String date;
  final List<Color> colors;
  final String route;
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.item});
  final _UpdateItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FanColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(colors: item.colors),
              ),
              clipBehavior: Clip.antiAlias,
              child: FanImage(
                imageUrl: item.imageUrl,
                fallback: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StatusBadge(label: item.type),
                  const SizedBox(height: 7),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(item.date, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid();
  static const items = <(IconData, String, String)>[
    (Icons.groups_2_outlined, '组合', '/catalog/groups'),
    (Icons.person_search_outlined, '艺人', '/catalog/idols'),
    (Icons.album_outlined, '专辑', '/catalog/albums'),
    (Icons.event_outlined, '活动', '/catalog/events'),
    (Icons.style_outlined, '小卡', '/cards'),
    (Icons.shopping_bag_outlined, '其他来源', '/catalog/others'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisExtent: 76,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => InkWell(
        key: Key('catalog-category-${items[index].$2}'),
        onTap: () => context.push(items[index].$3),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: index.isEven
                  ? const [Color(0xFFF1EDFF), Color(0xFFF7F8FF)]
                  : const [Color(0xFFEAF4FF), Color(0xFFF7F9FF)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(items[index].$1, size: 25, color: FanColors.lavender),
              const SizedBox(height: 7),
              Text(
                items[index].$2,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularGroups extends StatelessWidget {
  const _PopularGroups({required this.groups});
  final List<FanGroup> groups;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final group = groups[index];
          return InkWell(
            onTap: () => context.push('/group/${group.id}'),
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 230,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                gradient: LinearGradient(
                  colors: [Color(group.colorStart), Color(group.colorEnd)],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white.withValues(alpha: .16),
                    child: ClipOval(
                      child: FanImage(
                        imageUrl: group.imageUrl,
                        fallback: Text(
                          group.displayName.characters.first,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (group.secondaryName.isNotEmpty)
                              group.secondaryName,
                            '${group.memberIds.length} 位成员',
                            group.company,
                          ].join(' · '),
                          maxLines: 2,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .76),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupFilters extends StatelessWidget {
  const _GroupFilters({
    required this.status,
    required this.ascending,
    required this.onStatus,
    required this.onSort,
  });
  final String status;
  final bool ascending;
  final ValueChanged<String> onStatus;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.sort_by_alpha_rounded, size: 16),
          label: Text(ascending ? 'A–Z' : 'Z–A'),
          onPressed: onSort,
        ),
        _FilterMenu(
          icon: Icons.radio_button_checked_rounded,
          value: status,
          values: const ['全部状态', 'Active', 'Hiatus', 'Disbanded'],
          onSelected: onStatus,
        ),
      ],
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.icon,
    required this.value,
    required this.values,
    required this.onSelected,
  });
  final IconData icon;
  final String value;
  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => values
          .map((item) => PopupMenuItem(value: item, child: Text(item)))
          .toList(),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(value),
        deleteIcon: const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
        onDeleted: () {},
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.cardCount,
    required this.albumCount,
    required this.onTap,
  });
  final FanGroup group;
  final int cardCount;
  final int albumCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      onTap: onTap,
      leading: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [Color(group.colorStart), Color(group.colorEnd)],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: FanImage(
          imageUrl: group.imageUrl,
          fallback: Text(
            group.displayName.characters.first,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
      title: Text(
        group.displayName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${group.secondaryName.isEmpty ? group.company : '${group.secondaryName} · ${group.company}'}\n${group.memberIds.length} 位成员 · $albumCount 张专辑 · $cardCount 张小卡',
        maxLines: 2,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right_rounded, size: 19),
    );
  }
}

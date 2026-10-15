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
    final data = catalog.asData?.value;
    final groups =
        (data?.groups ?? <FanGroup>[])
            .where((group) => _status == '全部状态' || group.status == _status)
            .toList()
          ..sort(
            (a, b) => _ascending
                ? a.name.compareTo(b.name)
                : b.name.compareTo(a.name),
          );
    void retry() => ref.invalidate(catalogProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            try {
              ref.invalidate(catalogProvider);
              await ref.read(catalogProvider.future);
            } catch (_) {
              /* Inline retry state. */
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: FanContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CatalogHeader(onScan: () => context.go('/scan')),
                  const SizedBox(height: 16),
                  FanSearchButton(
                    hint: '搜索艺人、组合或小卡',
                    onTap: () => context.push('/search'),
                  ),
                  const SizedBox(height: 16),
                  const _CategoryGrid(),
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: '最近更新',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/cards'),
                  ),
                  const SizedBox(height: 12),
                  if (catalog.isLoading)
                    const Card(
                      child: SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (catalog.hasError)
                    FanStatusCard(
                      key: const Key('catalog-load-error'),
                      icon: Icons.cloud_off_outlined,
                      title: '内容暂时未能加载',
                      message: '请检查网络后重试',
                      actionLabel: '重新加载',
                      onAction: retry,
                    )
                  else if (data != null)
                    _RecentUpdates(data: data),
                  if (data != null && data.groups.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: '热门组合',
                      actionLabel: '查看全部',
                      onAction: () => context.push('/catalog/groups'),
                    ),
                    const SizedBox(height: 12),
                    _PopularGroups(groups: data.groups),
                  ],
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: '全部组合',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/catalog/groups'),
                  ),
                  const SizedBox(height: 8),
                  _GroupFilters(
                    status: _status,
                    ascending: _ascending,
                    onStatus: (value) => setState(() => _status = value),
                    onSort: () => setState(() => _ascending = !_ascending),
                  ),
                  const SizedBox(height: 12),
                  if (catalog.isLoading)
                    const Card(
                      child: SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (catalog.hasError)
                    FanStatusCard(
                      title: '组合暂时未能加载',
                      message: '网络恢复后即可继续浏览',
                      vertical: true,
                      actionLabel: '重新加载',
                      onAction: retry,
                    )
                  else if (groups.isEmpty)
                    FanStatusCard(
                      key: const Key('catalog-groups-empty'),
                      vertical: true,
                      title: '暂无组合内容',
                      message: _status != '全部状态'
                          ? '尝试调整筛选条件，发现更多精彩'
                          : '新的组合资料正在陆续收录',
                      actionLabel: _status != '全部状态' ? '清空筛选' : '反馈缺失内容',
                      onAction: _status != '全部状态'
                          ? () => setState(() => _status = '全部状态')
                          : () => context.push('/catalog/feedback'),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < groups.length; i++) ...[
                            _GroupRow(
                              group: groups[i],
                              cardCount: data!.cards
                                  .where((c) => c.groupId == groups[i].id)
                                  .length,
                              albumCount: data.albums
                                  .where((a) => a.belongsToGroup(groups[i].id))
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('catalog-missing-feedback'),
                      onPressed: () => context.push('/catalog/feedback'),
                      icon: const Icon(Icons.add_comment_outlined, size: 16),
                      label: const Text('反馈缺失内容'),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('图鉴', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text('收录每一份热爱', style: Theme.of(context).textTheme.bodySmall),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: Color(0xFF6750CE)),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6750CE),
                    ),
                  ),
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
          imageUrl: data.cards.first.thumbnailUrl ?? data.cards.first.imageUrl,
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
          imageUrl:
              data.albums.first.thumbnailUrl ?? data.albums.first.frontImageUrl,
          title: data.albums.first.displayName,
          subtitle: data.albums.first.secondaryName.isNotEmpty
              ? data.albums.first.secondaryName
              : data.artistLabel(
                  data.albums.first.artists,
                  data.albums.first.artistName,
                ),
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
          imageUrl:
              data.events.first.thumbnailUrl ?? data.events.first.imageUrl,
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
    if (items.isEmpty) {
      return FanStatusCard(
        title: '暂时没有更新',
        message: '去图鉴发现更多值得收藏的美好',
        icon: Icons.style_outlined,
        actionLabel: '逛逛图鉴',
        onAction: () => context.push('/catalog/idols'),
      );
    }
    return SizedBox(
      height:
          142 +
          (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24) * 14,
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
                color: Colors.white,
              ),
              clipBehavior: Clip.antiAlias,
              child: FanImage(
                imageUrl: item.imageUrl,
                fit: BoxFit.contain,
                fallback: const Icon(
                  Icons.photo_outlined,
                  color: FanColors.lavender,
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
                  Text(
                    item.date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
    (Icons.shopping_bag_outlined, '其他', '/catalog/others'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            MediaQuery.sizeOf(context).width < 360 ||
                MediaQuery.textScalerOf(context).scale(12) > 16
            ? 3
            : 6,
        mainAxisExtent:
            76 +
            (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 36) * 4,
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
                textAlign: TextAlign.center,
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
      height:
          132 +
          (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 20) * 7,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final group = groups[index];
          return SizedBox(
            key: ValueKey('popular-group-${group.id}'),
            width: 230,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FanImage(
                    imageUrl:
                        group.thumbnailUrl ??
                        group.coverImageUrl ??
                        group.imageUrl,
                    fallbackImageUrl: group.coverImageUrl ?? group.imageUrl,
                    fallback: const ColoredBox(color: Color(0xFF45465E)),
                  ),
                  // Keep both title and subtitle readable even on a white photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x26000000), Color(0xDB101522)],
                        stops: [0, .68],
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () => context.push('/group/${group.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (group.secondaryName.isNotEmpty)
                                  group.secondaryName,
                                '${group.memberIds.length} 位成员',
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
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
          color: FanColors.lavenderSoft,
        ),
        clipBehavior: Clip.antiAlias,
        child: FanImage(
          imageUrl: group.thumbnailUrl ?? group.imageUrl,
          fallbackImageUrl: group.imageUrl,
          fallback: Text(
            group.displayName.characters.first,
            style: const TextStyle(
              color: FanColors.lavender,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      title: Text(
        group.displayName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [group.secondaryName].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${group.memberIds.length} 位成员 · $albumCount 张专辑 · $cardCount 张小卡',
            key: ValueKey('group-stats-${group.id}'),
            style: const TextStyle(
              fontSize: 12,
              color: FanColors.textSecondary,
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 19),
    );
  }
}

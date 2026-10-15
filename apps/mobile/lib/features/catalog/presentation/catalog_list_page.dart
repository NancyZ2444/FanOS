import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/name_sort.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/widgets/catalog_tags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum CatalogListType { groups, idols, albums, events, others }

extension on CatalogListType {
  String get title => switch (this) {
    CatalogListType.groups => '全部组合',
    CatalogListType.idols => '全部艺人',
    CatalogListType.albums => '全部专辑',
    CatalogListType.events => '全部活动',
    CatalogListType.others => '其他来源',
  };
}

class CatalogListPage extends ConsumerStatefulWidget {
  const CatalogListPage({required this.type, super.key});
  final CatalogListType type;

  @override
  ConsumerState<CatalogListPage> createState() => _CatalogListPageState();
}

class _CatalogListPageState extends ConsumerState<CatalogListPage> {
  String _group = '全部组合';
  String _region = '全部地区';
  String _year = '全部年份';
  String _subtype = '全部类型';
  bool _ascending = true;
  final Set<String> _tagIds = {};

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.type.title),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: () => context.push('/search?type=${_searchType()}'),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '图鉴暂时无法加载',
          message: '请稍后重试。',
        ),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filters(data),
            _tagFilters(data),
            const Divider(height: 1),
            Expanded(child: _body(data)),
          ],
        ),
      ),
    );
  }

  String _searchType() => switch (widget.type) {
    CatalogListType.groups => '组合',
    CatalogListType.idols => '艺人',
    CatalogListType.albums => '专辑',
    CatalogListType.events => '活动',
    CatalogListType.others => '其他来源',
  };

  Widget _filters(CatalogBundle data) {
    final groupNames = ['全部组合', ...data.groups.map((item) => item.name)];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          if (widget.type != CatalogListType.groups)
            _ListFilter(
              value: _group,
              values: groupNames,
              labels: {
                for (final group in data.groups) group.name: group.displayName,
              },
              onSelected: (value) => setState(() {
                _group = value;
                _tagIds.clear();
              }),
            ),
          if (widget.type != CatalogListType.albums &&
              widget.type != CatalogListType.groups &&
              widget.type != CatalogListType.others) ...[
            const SizedBox(width: 8),
            _ListFilter(
              value: _region,
              values: const [
                '全部地区',
                'Korea',
                'Japan',
                'China',
                'Asia',
                'Global',
              ],
              onSelected: (value) => setState(() {
                _region = value;
                _tagIds.clear();
              }),
            ),
          ],
          if (widget.type == CatalogListType.albums ||
              widget.type == CatalogListType.events ||
              widget.type == CatalogListType.others) ...[
            const SizedBox(width: 8),
            _ListFilter(
              value: _year,
              values: [
                '全部年份',
                ...{
                    ...data.albums.map(
                      (i) => i.releaseDate.split(RegExp(r'[.-]')).first,
                    ),
                    ...data.events.map(
                      (i) => i.startDate.split(RegExp(r'[.-]')).first,
                    ),
                    ...data.others.map(
                      (i) => i.startDate.split(RegExp(r'[.-]')).first,
                    ),
                  }.where((y) => y.isNotEmpty).toList()
                  ..sort((a, b) => b.compareTo(a)),
              ],
              onSelected: (value) => setState(() {
                _year = value;
                _tagIds.clear();
              }),
            ),
            if (widget.type != CatalogListType.others) const SizedBox(width: 8),
            if (widget.type != CatalogListType.others)
              _ListFilter(
                value: _subtype,
                values: _typeValues(data),
                onSelected: (value) => setState(() {
                  _subtype = value;
                  _tagIds.clear();
                }),
              ),
          ],
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.sort_by_alpha_rounded, size: 16),
            label: Text(_ascending ? 'A–Z' : 'Z–A'),
            onPressed: () => setState(() => _ascending = !_ascending),
          ),
        ],
      ),
    );
  }

  List<String> _typeValues(CatalogBundle data) => switch (widget.type) {
    CatalogListType.albums => [
      '全部类型',
      ...data.albums.map((item) => item.albumType).toSet(),
    ],
    CatalogListType.events => [
      '全部类型',
      ...data.events.map((item) => item.eventType).toSet(),
    ],
    CatalogListType.others => [
      '全部类型',
      ...data.others.map((item) => item.type).toSet(),
    ],
    _ => const ['全部类型'],
  };

  Widget _body(CatalogBundle data) => switch (widget.type) {
    CatalogListType.groups => _groups(data),
    CatalogListType.idols => _idols(data),
    CatalogListType.albums => _albums(data),
    CatalogListType.events => _events(data),
    CatalogListType.others => _others(data),
  };

  Widget _groups(CatalogBundle data) {
    final items = [...data.groups]..sort(_ascending ? _groupAsc : _groupDesc);
    return _listOrEmpty(
      items,
      (group) => _EntityRow(
        imageUrl: group.thumbnailUrl ?? group.imageUrl,
        title: group.displayName,
        subtitle: [
          if (group.secondaryName.isNotEmpty) group.secondaryName,
          group.status,
        ].join(' · '),
        detail:
            '${group.memberIds.length} 位成员 · '
            '${data.albums.where((a) => a.belongsToGroup(group.id)).length} 张专辑 · '
            '${data.cards.where((c) => c.groupId == group.id).length} 张小卡',
        detailMaxLines: null,
        colors: [Color(group.colorStart), Color(group.colorEnd)],
        icon: Icons.groups_2_outlined,
        onTap: () => context.push('/group/${group.id}'),
      ),
    );
  }

  Widget _idols(CatalogBundle data) {
    final items =
        data.idols.where((item) {
          return (_group == '全部组合' || item.groupName == _group) &&
              (_region == '全部地区' || item.region == _region);
        }).toList()..sort(
          (a, b) => _ascending
              ? compareDisplayNames(a.displayName, b.displayName)
              : compareDisplayNames(b.displayName, a.displayName),
        );
    return _listOrEmpty(
      items,
      (idol) => _EntityRow(
        imageUrl: idol.thumbnailUrl ?? idol.imageUrl,
        title: idol.displayName,
        subtitle: [
          if (idol.secondaryName.isNotEmpty) idol.secondaryName,
          idol.displayGroupName,
          idol.role,
        ].where((s) => s.trim().isNotEmpty).join(' · '),
        detail: [
          idol.company,
          idol.region,
        ].where((s) => s.trim().isNotEmpty).join(' · '),
        colors: [Color(idol.colorStart), Color(idol.colorEnd)],
        icon: Icons.person_outline_rounded,
        onTap: () => context.push('/idol/${idol.id}'),
      ),
    );
  }

  bool _tagsMatch(List<CatalogTag> tags) =>
      _tagIds.every((id) => tags.any((t) => t.id == id));
  bool _albumMatches(CatalogAlbum i, CatalogBundle data) =>
      (_group == '全部组合' ||
          data.groups.any((g) => g.name == _group && i.belongsToGroup(g.id))) &&
      (_year == '全部年份' || i.releaseDate.startsWith(_year)) &&
      (_subtype == '全部类型' || i.albumType == _subtype);
  bool _eventMatches(CatalogEvent i, CatalogBundle data) =>
      (_group == '全部组合' ||
          data.groups.any((g) => g.name == _group && i.belongsToGroup(g.id))) &&
      (_region == '全部地区' || i.region == _region) &&
      (_year == '全部年份' || i.startDate.startsWith(_year)) &&
      (_subtype == '全部类型' || i.eventType == _subtype);
  bool _otherMatches(CatalogOther i, CatalogBundle data) {
    final group = data.groups.where((g) => g.name == _group).firstOrNull;
    return (_group == '全部组合' ||
            i.groupId == group?.id ||
            data.cards.any(
              (c) =>
                  c.groupId == group?.id &&
                  c.sourceEntityType == 'OTHER' &&
                  c.sourceEntityId == i.id,
            )) &&
        (_year == '全部年份' || i.startDate.startsWith(_year));
  }

  Widget _tagFilters(CatalogBundle data) {
    if (![
      CatalogListType.albums,
      CatalogListType.events,
      CatalogListType.others,
    ].contains(widget.type)) {
      return const SizedBox.shrink();
    }
    final tags = switch (widget.type) {
      CatalogListType.albums =>
        data.albums
            .where((i) => _albumMatches(i, data) && _tagsMatch(i.tags))
            .expand((i) => i.tags),
      CatalogListType.events =>
        data.events
            .where((i) => _eventMatches(i, data) && _tagsMatch(i.tags))
            .expand((i) => i.tags),
      _ =>
        data.others
            .where((i) => _otherMatches(i, data) && _tagsMatch(i.tags))
            .expand((i) => i.tags),
    };
    final available = {for (final t in tags) t.id: t};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          const Text('标签  '),
          if (available.isEmpty)
            const Text(
              '当前结果暂无标签',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          for (final t in available.values)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: FilterChip(
                label: Text(t.name),
                selected: _tagIds.contains(t.id),
                onSelected: (v) => setState(
                  () => v ? _tagIds.add(t.id) : _tagIds.remove(t.id),
                ),
              ),
            ),
          if (_tagIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(_tagIds.clear),
              child: const Text('清空标签'),
            ),
        ],
      ),
    );
  }

  Widget _albums(CatalogBundle data) {
    final items =
        data.albums
            .where((i) => _albumMatches(i, data) && _tagsMatch(i.tags))
            .toList()
          ..sort(
            (a, b) => _ascending
                ? a.name.compareTo(b.name)
                : b.name.compareTo(a.name),
          );
    return _listOrEmpty(
      items,
      (i) => _EntityRow(
        imageUrl: i.thumbnailUrl ?? i.frontImageUrl,
        title: i.displayName,
        subtitle: [
          i.secondaryName,
          data.artistLabel(i.artists, i.artistName),
          i.albumType,
        ].where((s) => s.isNotEmpty).join(' · '),
        detail: '${i.releaseDate} · ${i.versions.length} 个版本',
        tags: i.tags,
        colors: [Color(i.colorStart), Color(i.colorEnd)],
        icon: Icons.album_outlined,
        onTap: () => context.push('/album/${i.id}'),
      ),
    );
  }

  Widget _events(CatalogBundle data) {
    final items =
        data.events
            .where((i) => _eventMatches(i, data) && _tagsMatch(i.tags))
            .toList()
          ..sort(
            (a, b) => _ascending
                ? a.name.compareTo(b.name)
                : b.name.compareTo(a.name),
          );
    return _listOrEmpty(
      items,
      (i) => _EntityRow(
        imageUrl: i.thumbnailUrl ?? i.imageUrl,
        title: i.displayName,
        subtitle: [
          i.secondaryName,
          data.artistLabel(i.artists, i.artistName),
          i.eventType,
        ].where((s) => s.isNotEmpty).join(' · '),
        detail: '${i.startDate} · ${i.locationLabel}',
        tags: i.tags,
        colors: [Color(i.colorStart), Color(i.colorEnd)],
        icon: Icons.event_outlined,
        onTap: () => context.push('/event/${i.id}'),
      ),
    );
  }

  Widget _others(CatalogBundle data) {
    final items =
        data.others
            .where((i) => _otherMatches(i, data) && _tagsMatch(i.tags))
            .toList()
          ..sort(
            (a, b) => _ascending
                ? a.name.compareTo(b.name)
                : b.name.compareTo(a.name),
          );
    return _listOrEmpty(
      items,
      (i) => _EntityRow(
        imageUrl: i.thumbnailUrl ?? i.imageUrl,
        title: i.name,
        subtitle: i.originalName,
        detail: [i.startDate, i.endDate].where((s) => s.isNotEmpty).join(' — '),
        tags: i.tags,
        colors: [Color(i.colorStart), Color(i.colorEnd)],
        icon: Icons.book_outlined,
        onTap: () => context.push('/other/${i.id}'),
      ),
    );
  }

  int _groupAsc(FanGroup a, FanGroup b) =>
      a.displayName.compareTo(b.displayName);
  int _groupDesc(FanGroup a, FanGroup b) =>
      b.displayName.compareTo(a.displayName);

  Widget _listOrEmpty<T>(List<T> items, Widget Function(T item) builder) {
    if (items.isEmpty) {
      return FanEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '当前筛选条件没有结果',
        message: '删除部分筛选条件或清空全部筛选。',
        actionLabel: '清空筛选',
        onAction: () => setState(() {
          _group = '全部组合';
          _region = '全部地区';
          _year = '全部年份';
          _subtype = '全部类型';
          _tagIds.clear();
        }),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => builder(items[index]),
    );
  }
}

class _ListFilter extends StatelessWidget {
  const _ListFilter({
    required this.value,
    required this.values,
    required this.onSelected,
    this.labels = const {},
  });
  final String value;
  final List<String> values;
  final ValueChanged<String> onSelected;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => values
          .map(
            (item) =>
                PopupMenuItem(value: item, child: Text(labels[item] ?? item)),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F6),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[value] ?? value, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _EntityRow extends StatelessWidget {
  const _EntityRow({
    this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.colors,
    required this.icon,
    required this.onTap,
    this.tags = const [],
    this.detailMaxLines = 1,
  });
  final List<CatalogTag> tags;
  final String title;
  final String? imageUrl;
  final String subtitle;
  final String detail;
  final int? detailMaxLines;
  final List<Color> colors;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        onTap: onTap,
        leading: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: FanColors.lavenderSoft,
          ),
          clipBehavior: Clip.antiAlias,
          child: FanImage(
            imageUrl: imageUrl,
            fallback: Icon(icon, color: FanColors.lavender),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tags.isNotEmpty) CatalogTagChips(tags: tags, compact: true),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              detail,
              maxLines: detailMaxLines,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

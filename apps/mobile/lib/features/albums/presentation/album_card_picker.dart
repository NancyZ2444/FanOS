import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

AlbumJson albumCardJson(CollectibleCard c) => {
  'id': c.id,
  'title': c.title,
  'title_en': c.titleEn,
  'title_ko': c.titleKo,
  'title_translated': c.titleTranslated,
  'idol_id': c.idolId,
  'idol_name': c.idolName,
  'group_id': c.groupId,
  'group_name': c.groupName,
  'source': c.source,
  'card_type': c.cardType,
  'version': c.version,
  'release_date': c.releaseDate,
  'region': c.region,
  'color_start': c.colorStart,
  'color_end': c.colorEnd,
  'image_url': c.imageUrl,
  'thumbnail_url': c.thumbnailUrl,
  'back_image_url': c.backImageUrl,
  'source_entity_id': c.sourceEntityId,
  'source_entity_type': c.sourceEntityType,
  'available': true,
};

Future<List<CollectibleCard>?> pickAlbumCards(
  BuildContext context, {
  bool single = false,
  int? maxSelected,
}) => Navigator.push<List<CollectibleCard>>(
  context,
  MaterialPageRoute(
    builder: (_) => AlbumCardPicker(single: single, maxSelected: maxSelected),
  ),
);

class AlbumCardPicker extends ConsumerStatefulWidget {
  const AlbumCardPicker({super.key, this.single = false, this.maxSelected});
  final bool single;
  final int? maxSelected;
  @override
  ConsumerState<AlbumCardPicker> createState() => _AlbumCardPickerState();
}

class _AlbumCardPickerState extends ConsumerState<AlbumCardPicker> {
  String _q = '';
  String? _group, _idol, _type, _source;
  bool _ownedOnly = false, _favoritesOnly = false;
  final List<CollectibleCard> _selected = [];
  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider).selectedIds;
    final owned = ref.watch(collectionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('官方图鉴选卡')),
      body: ref
          .watch(catalogProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => FanEmptyState(
              icon: Icons.cloud_off_outlined,
              title: '图鉴加载失败',
              message: e.toString(),
              actionLabel: '重试',
              onAction: () => ref.invalidate(catalogProvider),
            ),
            data: (data) {
              final cards = data.cards
                  .where(
                    (c) =>
                        (!_ownedOnly || owned.isOwned(c.id)) &&
                        (!_favoritesOnly || favorites.contains(c.idolId)) &&
                        (_group == null || c.groupId == _group) &&
                        (_idol == null || c.idolId == _idol) &&
                        (_type == null || c.sourceEntityType == _type) &&
                        (_source == null || c.source == _source) &&
                        ('${c.displayTitle} ${c.idolName} ${c.groupName} ${c.source} ${c.version}'
                            .toLowerCase()
                            .contains(_q.toLowerCase())),
                  )
                  .toList();
              cards.sort((a, b) {
                final priority =
                    (favorites.contains(b.idolId) ? 1 : 0) -
                    (favorites.contains(a.idolId) ? 1 : 0);
                return priority != 0
                    ? priority
                    : b.releaseDate.compareTo(a.releaseDate);
              });
              final sources = data.cards
                  .where(
                    (c) =>
                        (_group == null || c.groupId == _group) &&
                        (_type == null || c.sourceEntityType == _type),
                  )
                  .map((c) => c.source)
                  .toSet();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: '搜索小卡、艺人、来源、版本',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _filter(
                            '组合',
                            _group,
                            {for (final g in data.groups) g.id: g.displayName},
                            (v) => setState(() {
                              _group = v;
                              _idol = null;
                              _source = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _filter('成员', _idol, {
                            for (final i in data.idols.where(
                              (i) =>
                                  _group == null ||
                                  i.groupIds.contains(_group) ||
                                  data.groups.any(
                                    (g) =>
                                        g.id == _group &&
                                        g.memberIds.contains(i.id),
                                  ),
                            ))
                              i.id: i.displayName,
                          }, (v) => setState(() => _idol = v)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _filter(
                            '来源类型',
                            _type,
                            const {
                              'ALBUM': '专辑',
                              'EVENT': '活动',
                              'OTHER': '其他来源',
                            },
                            (v) => setState(() {
                              _type = v;
                              _source = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _filter(
                            '来源',
                            sources.contains(_source) ? _source : null,
                            {for (final s in sources) s: s},
                            (v) => setState(() => _source = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('我的本命'),
                          selected: _favoritesOnly,
                          onSelected: (v) => setState(() => _favoritesOnly = v),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('已收藏'),
                          selected: _ownedOnly,
                          onSelected: (v) => setState(() => _ownedOnly = v),
                        ),
                        const Spacer(),
                        Text(
                          '${cards.length} 张',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: cards.isEmpty
                        ? const FanEmptyState(
                            icon: Icons.search_rounded,
                            title: '没有符合条件的小卡',
                            message: '请调整搜索或筛选条件。',
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: .50,
                                ),
                            itemCount: cards.length,
                            itemBuilder: (context, index) {
                              final c = cards[index],
                                  chosen = _selected.any((s) => s.id == c.id);
                              return Column(
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        InkWell(
                                          onTap: () => setState(() {
                                            if (chosen) {
                                              _selected.removeWhere(
                                                (s) => s.id == c.id,
                                              );
                                            } else {
                                              if (widget.maxSelected != null &&
                                                  _selected.length >=
                                                      widget.maxSelected!) {
                                                showFanToast(
                                                  context,
                                                  '本次最多选择 ${widget.maxSelected} 张',
                                                );
                                                return;
                                              }
                                              if (widget.single) {
                                                _selected.clear();
                                              }
                                              _selected.add(c);
                                            }
                                          }),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: chosen
                                                    ? FanColors.lavender
                                                    : FanColors.line,
                                                width: chosen ? 2 : 1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: AlbumCardImage(c),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: CircleAvatar(
                                            radius: 11,
                                            backgroundColor: chosen
                                                ? FanColors.lavender
                                                : Colors.white,
                                            child: chosen
                                                ? Text(
                                                    '${_selected.indexWhere((s) => s.id == c.id) + 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.circle_outlined,
                                                    size: 16,
                                                    color:
                                                        FanColors.textSecondary,
                                                  ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: IconButton(
                                            tooltip: '查看小卡正反面',
                                            onPressed: () =>
                                                showAlbumCardPreview(
                                                  context,
                                                  c,
                                                ),
                                            icon: const Icon(
                                              Icons.zoom_in_rounded,
                                              color: FanColors.ink,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    c.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    c.source,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: FilledButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, _selected.toList()),
                        child: Text('已选择 ${_selected.length} 张 · 确认添加'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }

  Widget _filter(
    String label,
    String? value,
    Map<String, String> options,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    items: [
      const DropdownMenuItem(value: null, child: Text('全部')),
      for (final e in options.entries)
        DropdownMenuItem(
          value: e.key,
          child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
    key: ValueKey('$label-$value-${options.keys.join()}'),
  );
}

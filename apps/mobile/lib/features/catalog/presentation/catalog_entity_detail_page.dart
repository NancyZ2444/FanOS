import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum CatalogEntityDetailType { album, event, others }

class CatalogEntityDetailPage extends ConsumerWidget {
  const CatalogEntityDetailPage({
    required this.type,
    required this.entityId,
    super.key,
  });
  final CatalogEntityDetailType type;
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return catalog.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('图鉴资料')),
        body: const FanPageSkeleton(),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('图鉴资料')),
        body: FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '内容加载失败',
          message: '请检查网络后重试。',
          actionLabel: '重新加载',
          onAction: () => ref.invalidate(catalogProvider),
        ),
      ),
      data: (data) => _buildDetail(context, data),
    );
  }

  Widget _buildDetail(BuildContext context, CatalogBundle data) {
    return switch (type) {
      CatalogEntityDetailType.album => _album(context, data),
      CatalogEntityDetailType.event => _event(context, data),
      CatalogEntityDetailType.others => _others(context, data),
    };
  }

  Widget _album(BuildContext context, CatalogBundle data) {
    final album = data.albums.where((item) => item.id == entityId).firstOrNull;
    if (album == null) return _missing('没有找到该专辑');
    final artistName = data.artistLabel(album.artists, album.artistName);
    final cards = data.cards
        .where(
          (card) =>
              (card.sourceEntityType == 'ALBUM' &&
                  card.sourceEntityId == album.id) ||
              (card.sourceEntityId == null &&
                  card.groupId == album.groupId &&
                  card.source.toLowerCase() == album.name.toLowerCase()),
        )
        .toList();
    return _EntityScaffold(
      title: album.displayName,
      onFeedback: () =>
          context.push('/catalog-correction?type=albums&id=${album.id}'),
      secondaryTitle: album.secondaryName,
      typeLabel: album.albumType,
      artistName: artistName,
      date: album.releaseDate,
      description: album.description,
      colors: [Color(album.colorStart), Color(album.colorEnd)],
      frontImageUrl: album.frontImageUrl,
      info: [
        ('组合/艺人', artistName),
        ('发行类型', album.albumType),
        ('发行日期', album.releaseDate),
        ('版本', album.versions.join(' · ')),
      ],
      chips: [...album.versions, ...album.tags.map((t) => t.name)],
      cards: cards,
      onArtist: () => context.push('/group/${album.groupId}'),
    );
  }

  Widget _event(BuildContext context, CatalogBundle data) {
    final event = data.events.where((item) => item.id == entityId).firstOrNull;
    if (event == null) return _missing('没有找到该活动');
    final artistName = data.artistLabel(event.artists, event.artistName);
    final children = data.events
        .where((item) => item.parentEventId == event.id)
        .toList();
    final cards = data.cards
        .where(
          (card) =>
              (card.sourceEntityType == 'EVENT' &&
                  card.sourceEntityId == event.id) ||
              (card.sourceEntityId == null &&
                  card.groupId == event.groupId &&
                  card.source.toLowerCase() == event.name.toLowerCase()),
        )
        .toList();
    return _EntityScaffold(
      title: event.displayName,
      onFeedback: () =>
          context.push('/catalog-correction?type=events&id=${event.id}'),
      frontImageUrl: event.imageUrl,
      secondaryTitle: event.secondaryName,
      typeLabel: '',
      artistName: artistName,
      date: event.startDate,
      description: event.description,
      colors: [Color(event.colorStart), Color(event.colorEnd)],
      info: [
        ('组合/艺人', artistName),
        ('日期', event.startDate),
        if (event.isOnline) ('平台', event.locationLabel) else ('城市', event.city),
        if (!event.isOnline) ('场馆', event.venue),
        if (event.isOnline) ('形式', '线上'),
      ],
      chips: [
        event.region,
        if (event.isOnline) '线上',
        ...event.tags.map((t) => t.name),
      ],
      cards: cards,
      children: children,
      onArtist: () => context.push('/group/${event.groupId}'),
    );
  }

  Widget _others(BuildContext context, CatalogBundle data) {
    final item = data.others
        .where((others) => others.id == entityId)
        .firstOrNull;
    if (item == null) return _missing('没有找到该其他来源');
    final artistName = data.artistLabel(item.artists, item.artistName);
    return _EntityScaffold(
      title: item.name,
      onFeedback: () =>
          context.push('/catalog-correction?type=others&id=${item.id}'),
      secondaryTitle: item.originalName,
      typeLabel: '其他',
      artistName: artistName,
      date: [
        item.startDate,
        item.endDate,
      ].where((d) => d.isNotEmpty).join(' – '),
      description: item.description,
      colors: [Color(item.colorStart), Color(item.colorEnd)],
      frontImageUrl: item.imageUrl,
      info: [
        if (artistName.isNotEmpty) ('组合/艺人', artistName),
        ('原始名称', item.originalName),
        ('开始日期', item.startDate),
        ('结束日期', item.endDate),
      ],
      chips: item.tags.map((t) => t.name).toList(),
      cards: data.cards
          .where(
            (c) => c.sourceEntityType == 'OTHER' && c.sourceEntityId == item.id,
          )
          .toList(),
      onArtist: () {
        if (item.groupId.isNotEmpty) {
          context.push('/group/${item.groupId}');
        } else if (item.artists.isNotEmpty) {
          context.push('/idol/${item.artists.first.id}');
        }
      },
    );
  }

  Widget _missing(String title) => Scaffold(
    appBar: AppBar(leading: const BackButton()),
    body: FanEmptyState(
      icon: Icons.inventory_2_outlined,
      title: title,
      message: '该内容可能已下架，但已有收藏关系仍会保留。',
    ),
  );
}

class _EntityScaffold extends StatelessWidget {
  const _EntityScaffold({
    required this.title,
    required this.typeLabel,
    required this.artistName,
    required this.date,
    required this.description,
    required this.colors,
    required this.info,
    required this.chips,
    required this.cards,
    required this.onArtist,
    required this.onFeedback,
    this.children = const [],
    this.secondaryTitle = '',
    this.frontImageUrl,
  });
  final String title;
  final String secondaryTitle;
  final String typeLabel;
  final String artistName;
  final String date;
  final String description;
  final List<Color> colors;
  final List<(String, String)> info;
  final List<String> chips;
  final List<CollectibleCard> cards;
  final List<CatalogEvent> children;
  final VoidCallback onArtist;
  final VoidCallback onFeedback;
  final String? frontImageUrl;

  @override
  Widget build(BuildContext context) {
    final visibleInfo = info.where((row) => row.$2.trim().isNotEmpty).toList();
    final visibleChips = chips.where((chip) => chip.trim().isNotEmpty).toSet();
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: '反馈问题',
            onPressed: onFeedback,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: FanContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox(
                  width: 220,
                  child: FanArtwork(
                    imageUrl: frontImageUrl,
                    startColor: colors.first,
                    endColor: colors.last,
                    label: title.characters.take(2).toString().toUpperCase(),
                    aspectRatio: 1,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (typeLabel.isNotEmpty) ...[
                StatusBadge(label: typeLabel),
                const SizedBox(height: 9),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (secondaryTitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  secondaryTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: const Color(0xFF667085)),
                ),
              ],
              const SizedBox(height: 6),
              if (artistName.isNotEmpty)
                InkWell(
                  onTap: onArtist,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          artistName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              if (description.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (visibleChips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: visibleChips
                      .map((chip) => Chip(label: Text(chip)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < visibleInfo.length;
                        index++
                      ) ...[
                        _DetailInfoRow(
                          label: visibleInfo[index].$1,
                          value: visibleInfo[index].$2,
                        ),
                        if (index != visibleInfo.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 26),
                const SectionHeader(title: '巡演场次'),
                const SizedBox(height: 9),
                for (final child in children)
                  Card(
                    child: ListTile(
                      onTap: () => context.push('/event/${child.id}'),
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(child.name),
                      subtitle: Text(
                        '${child.startDate} · ${child.isOnline ? child.locationLabel : child.venue}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
              ],
              const SizedBox(height: 26),
              SectionHeader(
                title: '相关小卡',
                actionLabel: cards.isEmpty ? null : '查看全部',
                onAction: () => context.push('/cards'),
              ),
              const SizedBox(height: 10),
              if (cards.isEmpty)
                const FanEmptyState(
                  icon: Icons.style_outlined,
                  title: '暂无相关小卡',
                  message: '官方收录后会在这里展示。',
                )
              else
                SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: cards.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 11),
                    itemBuilder: (context, index) => SizedBox(
                      width: 116,
                      child: CollectibleCardTile(
                        card: cards[index],
                        compact: true,
                        onTap: () => context.push('/card/${cards[index].id}'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

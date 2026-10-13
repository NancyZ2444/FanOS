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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(
        body: FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '内容加载失败',
          message: '请稍后重试。',
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
    final cards = data.cards
        .where(
          (card) =>
              (card.sourceEntityType == 'ALBUM' &&
                  card.sourceEntityId == album.id) ||
              (card.sourceEntityId == null &&
                  card.groupId == album.groupId &&
                  card.source.contains(album.name)),
        )
        .toList();
    return _EntityScaffold(
      title: album.displayName,
      secondaryTitle: album.secondaryName,
      typeLabel: album.albumType,
      artistName: album.artistName,
      date: album.releaseDate,
      description: album.description,
      colors: [Color(album.colorStart), Color(album.colorEnd)],
      frontImageUrl: album.frontImageUrl,
      backImageUrl: album.backImageUrl,
      info: [
        ('艺人', album.artistName),
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
                  (card.source.toLowerCase().contains(
                        event.name.split(' ').first.toLowerCase(),
                      ) ||
                      card.region == event.region)),
        )
        .toList();
    return _EntityScaffold(
      title: event.displayName,
      frontImageUrl: event.imageUrl,
      secondaryTitle: event.secondaryName,
      typeLabel: event.eventType,
      artistName: event.artistName,
      date: event.startDate,
      description: event.description,
      colors: [Color(event.colorStart), Color(event.colorEnd)],
      info: [
        ('艺人', event.artistName),
        ('活动类型', event.eventType),
        ('日期', event.startDate),
        if (event.isOnline) ('平台', event.locationLabel) else ('城市', event.city),
        if (!event.isOnline) ('场馆', event.venue),
        if (event.isOnline) ('形式', 'Online'),
      ],
      chips: [
        event.eventType,
        event.region,
        if (event.isOnline) 'Online',
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
    return _EntityScaffold(
      title: item.name,
      secondaryTitle: item.originalName,
      typeLabel: 'Other',
      artistName: '',
      date: [
        item.startDate,
        item.endDate,
      ].where((d) => d.isNotEmpty).join(' – '),
      description: item.description,
      colors: [Color(item.colorStart), Color(item.colorEnd)],
      frontImageUrl: item.imageUrl,
      info: [
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
      onArtist: () {},
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
    this.children = const [],
    this.secondaryTitle = '',
    this.frontImageUrl,
    this.backImageUrl,
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
  final String? frontImageUrl;
  final String? backImageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: '反馈问题',
            onPressed: () => showFanToast(context, '问题反馈入口已记录'),
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
                  child: _TwoSidedArtwork(
                    title: title,
                    colors: colors,
                    frontImageUrl: frontImageUrl,
                    backImageUrl: backImageUrl,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              StatusBadge(label: typeLabel),
              const SizedBox(height: 9),
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
                      Text(
                        artistName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: chips.map((chip) => Chip(label: Text(chip))).toList(),
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (var index = 0; index < info.length; index++) ...[
                        _DetailInfoRow(
                          label: info[index].$1,
                          value: info[index].$2,
                        ),
                        if (index != info.length - 1) const Divider(height: 1),
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
              if (cards.isNotEmpty) ...[
                const SizedBox(height: 26),
                SectionHeader(
                  title: '相关小卡',
                  actionLabel: '查看全部',
                  onAction: () => context.push('/cards'),
                ),
                const SizedBox(height: 10),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _TwoSidedArtwork extends StatefulWidget {
  const _TwoSidedArtwork({
    required this.title,
    required this.colors,
    this.frontImageUrl,
    this.backImageUrl,
  });

  final String title;
  final List<Color> colors;
  final String? frontImageUrl;
  final String? backImageUrl;

  @override
  State<_TwoSidedArtwork> createState() => _TwoSidedArtworkState();
}

class _TwoSidedArtworkState extends State<_TwoSidedArtwork> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    final front = widget.frontImageUrl?.isNotEmpty == true
        ? widget.frontImageUrl
        : null;
    final back = widget.backImageUrl?.isNotEmpty == true
        ? widget.backImageUrl
        : null;
    final selectedUrl = _showBack ? back : front;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: selectedUrl == null
                ? FanArtwork(
                    startColor: widget.colors.first,
                    endColor: widget.colors.last,
                    label: widget.title.characters
                        .take(2)
                        .toString()
                        .toUpperCase(),
                    aspectRatio: 1,
                  )
                : Image.network(
                    selectedUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => FanArtwork(
                      startColor: widget.colors.first,
                      endColor: widget.colors.last,
                      label: widget.title.characters
                          .take(2)
                          .toString()
                          .toUpperCase(),
                      aspectRatio: 1,
                    ),
                  ),
          ),
        ),
        if (back != null || front != null) ...[
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('正面')),
              ButtonSegment(value: true, label: Text('背面')),
            ],
            selected: {_showBack},
            onSelectionChanged: (value) {
              final showBack = value.first;
              if (showBack && back == null) {
                showFanToast(context, '该专辑暂未录入背面素材');
                return;
              }
              if (!showBack && front == null) {
                showFanToast(context, '该专辑暂未录入正面素材');
                return;
              }
              setState(() => _showBack = showBack);
            },
          ),
        ],
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 13),
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

import 'package:fan_os/core/widgets/entity_header.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/config/feature_flags.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feed/presentation/entity_social_feed.dart';
import 'package:flutter/material.dart';
import 'package:fan_os/features/profile/presentation/name_preferences_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({required this.groupId, super.key});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: !catalog.hasValue ? AppBar(title: const Text('组合详情')) : null,
      body: catalog.when(
        loading: () => const FanPageSkeleton(),
        error: (_, _) => FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '加载失败',
          message: '请检查网络后重试',
          actionLabel: '重新加载',
          onAction: () => ref.invalidate(catalogProvider),
        ),
        data: (data) {
          final group = data.groups
              .where((item) => item.id == groupId)
              .firstOrNull;
          if (group == null) {
            return const FanEmptyState(
              icon: Icons.error_outline_rounded,
              title: '组合不存在',
              message: '该内容可能已停止公开展示，但历史收藏不会丢失。',
            );
          }
          return _GroupBody(group: group, data: data);
        },
      ),
    );
  }
}

class _GroupBody extends ConsumerWidget {
  const _GroupBody({required this.group, required this.data});
  final FanGroup group;
  final CatalogBundle data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = data.idols
        .where((idol) => group.memberIds.contains(idol.id))
        .toList();
    final formerMembers = data.idols
        .where((idol) => group.formerMemberIds.contains(idol.id))
        .toList();
    final cards = data.cards.where((card) => card.groupId == group.id).toList();
    final albums = data.albums
        .where((album) => album.belongsToGroup(group.id))
        .toList();
    final events = data.events
        .where((event) => event.belongsToGroup(group.id))
        .toList();
    final others = data.others
        .where(
          (item) =>
              item.belongsToGroup(group.id) ||
              cards.any(
                (c) =>
                    c.sourceEntityType == 'OTHER' &&
                    c.sourceEntityId == item.id,
              ),
        )
        .toList();
    final showFeed = ref.watch(idolFeedEnabledProvider);
    return DefaultTabController(
      length: showFeed ? 6 : 5,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          EntityProfileSliver(
            imageUrl:
                group.coverImageUrl ?? group.imageUrl ?? group.thumbnailUrl,
            actions: [
              IconButton(
                tooltip: '设置备注',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showNameRemarkEditor(
                  context,
                  ref,
                  'groups',
                  group.id,
                  group.nameEn.isNotEmpty ? group.nameEn : group.name,
                ),
              ),
              IconButton(
                tooltip: '反馈问题',
                onPressed: () => context.push(
                  '/catalog-correction?type=groups&id=${group.id}',
                ),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
            hero: _GroupHero(group: group, cardCount: cards.length),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: EntityTabs([
              '成员',
              if (showFeed) '动态',
              '专辑',
              '活动',
              '小卡',
              '其他',
            ], textScale: MediaQuery.textScalerOf(context).scale(14) / 14),
          ),
        ],
        body: TabBarView(
          children: [
            _MembersTab(
              group: group,
              members: members,
              formerMembers: formerMembers,
            ),
            if (showFeed)
              EntitySocialFeed.group(group: group, members: members),
            _AlbumTab(albums: albums),
            _EventTab(events: events),
            _CardTab(group: group, cards: cards, catalog: data),
            _MerchandiseTab(items: others),
          ],
        ),
      ),
    );
  }
}

class _GroupHero extends StatelessWidget {
  const _GroupHero({required this.group, required this.cardCount});
  final FanGroup group;
  final int cardCount;

  @override
  Widget build(BuildContext context) => EntityIdentity(
    name: group.displayName,
    avatar: ClipOval(
      child: SizedBox(
        width: 56,
        height: 56,
        child: FanImage(
          imageUrl: group.thumbnailUrl ?? group.imageUrl,
          fallbackImageUrl: group.imageUrl,
          fallback: ColoredBox(
            color: FanColors.lavenderSoft,
            child: Center(
              child: Text(
                group.displayName.characters.take(2).toString(),
                style: const TextStyle(color: FanColors.lavender, fontSize: 18),
              ),
            ),
          ),
        ),
      ),
    ),
    subtitle: [
      group.secondaryName,
      group.company,
    ].where((s) => s.trim().isNotEmpty).join(' · '),
    details: [
      if (group.debutDate.isNotEmpty) '${group.debutDate} 出道',
      '${group.memberIds.length} 位当前成员',
      '$cardCount 张小卡',
    ],
    description: group.description,
  );
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.group,
    required this.members,
    required this.formerMembers,
  });
  final FanGroup group;
  final List<IdolProfile> members;
  final List<IdolProfile> formerMembers;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      children: [
        SectionHeader(
          title: '当前成员 (${members.length})',
          titleStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                MediaQuery.sizeOf(context).width < 360 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18
                ? 1
                : 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent:
                82 +
                (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 28) *
                    3,
          ),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final idol = members[index];
            return Card(
              child: InkWell(
                onTap: () => context.push('/idol/${idol.id}'),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Row(
                    children: [
                      IdolAvatar(idol: idol, size: 52),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              idol.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              idol.secondaryName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
        if (formerMembers.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(
            title: '过往成员 (${formerMembers.length})',
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          for (final idol in formerMembers)
            ListTile(
              onTap: () => context.push('/idol/${idol.id}'),
              leading: IdolAvatar(idol: idol, size: 46),
              title: Text(idol.displayName),
              subtitle: Text(idol.secondaryName),
            ),
        ],
      ],
    );
  }
}

class _AlbumTab extends StatelessWidget {
  const _AlbumTab({required this.albums});
  final List<CatalogAlbum> albums;

  @override
  Widget build(BuildContext context) {
    final sorted = [...albums]
      ..sort((a, b) => b.releaseDate.compareTo(a.releaseDate));
    return _EntityTabList(
      emptyTitle: '暂时没有专辑资料',
      children: sorted
          .map(
            (album) => _EntityListCard(
              imageUrl: album.thumbnailUrl ?? album.frontImageUrl,
              title: album.displayName,
              subtitle: '${album.albumType} · ${album.releaseDate}',
              detail: [
                if (album.secondaryName.isNotEmpty) album.secondaryName,
                ...album.versions,
              ].join(' · '),
              colors: [Color(album.colorStart), Color(album.colorEnd)],
              icon: Icons.album_outlined,
              onTap: () => context.push('/album/${album.id}'),
            ),
          )
          .toList(),
    );
  }
}

class _EventTab extends StatelessWidget {
  const _EventTab({required this.events});
  final List<CatalogEvent> events;

  @override
  Widget build(BuildContext context) {
    return _EntityTabList(
      emptyTitle: '暂时没有活动资料',
      children: events
          .map(
            (event) => _EntityListCard(
              imageUrl: event.thumbnailUrl ?? event.imageUrl,
              title: event.displayName,
              subtitle: '${event.eventType} · ${event.startDate}',
              detail: [
                if (event.secondaryName.isNotEmpty) event.secondaryName,
                event.locationLabel,
                if (!event.isOnline) event.venue,
              ].join(' · '),
              colors: [Color(event.colorStart), Color(event.colorEnd)],
              icon: Icons.event_outlined,
              onTap: () => context.push('/event/${event.id}'),
            ),
          )
          .toList(),
    );
  }
}

class _CardTab extends StatelessWidget {
  const _CardTab({
    required this.group,
    required this.cards,
    required this.catalog,
  });
  final FanGroup group;
  final List<CollectibleCard> cards;
  final CatalogBundle catalog;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const FanEmptyState(
        icon: Icons.style_outlined,
        title: '暂未收录小卡',
        message: '这个组合的小卡发布后会展示在这里。',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/cards?group=${group.id}'),
              icon: const Icon(Icons.tune_rounded),
              label: Text('筛选全部 ${cards.length} 张小卡'),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            gridDelegate: fanCardGrid(context),
            itemCount: cards.length,
            itemBuilder: (context, index) => CollectibleCardTile(
              card: cards[index],
              caption: CardTileCaption.group,
              sourceLabel: catalog.cardSourceLabel(cards[index]),
              compact: true,
              onTap: () => context.push('/card/${cards[index].id}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MerchandiseTab extends StatelessWidget {
  const _MerchandiseTab({required this.items});
  final List<CatalogOther> items;

  @override
  Widget build(BuildContext context) {
    return _EntityTabList(
      emptyTitle: '暂时没有其他来源',
      children: items
          .map(
            (item) => _EntityListCard(
              imageUrl: item.thumbnailUrl ?? item.imageUrl,
              title: item.displayName,
              subtitle: [
                item.startDate,
                item.endDate,
              ].where((s) => s.isNotEmpty).join(' — '),
              detail: [
                if (item.secondaryName.isNotEmpty) item.secondaryName,
                ...item.tags.map((t) => t.name),
              ].join(' · '),
              colors: [Color(item.colorStart), Color(item.colorEnd)],
              icon: Icons.shopping_bag_outlined,
              onTap: () => context.push('/other/${item.id}'),
            ),
          )
          .toList(),
    );
  }
}

class _EntityTabList extends StatelessWidget {
  const _EntityTabList({required this.emptyTitle, required this.children});
  final String emptyTitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return FanEmptyState(
        icon: Icons.inventory_2_outlined,
        title: emptyTitle,
        message: '官方资料发布后会在这里展示。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _EntityListCard extends StatelessWidget {
  const _EntityListCard({
    this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.colors,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String? imageUrl;
  final String subtitle;
  final String detail;
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
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: FanColors.lavenderSoft,
          ),
          clipBehavior: Clip.antiAlias,
          child: FanImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            fallback: Icon(icon, color: FanColors.lavender),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

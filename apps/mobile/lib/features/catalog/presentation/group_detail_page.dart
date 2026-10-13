import 'package:fan_os/app/theme.dart';
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
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '加载失败',
          message: '请稍后重试',
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
              item.groupId == group.id ||
              cards.any(
                (c) =>
                    c.sourceEntityType == 'OTHER' &&
                    c.sourceEntityId == item.id,
              ),
        )
        .toList();
    return DefaultTabController(
      length: 6,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 354,
            foregroundColor: Colors.white,
            backgroundColor: Color(group.colorStart),
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
                onPressed: () => showFanToast(context, '图鉴问题反馈入口已记录'),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _GroupHero(group: group, cardCount: cards.length),
            ),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: ColoredBox(
                color: FanColors.canvas,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: FanColors.lavender,
                  labelColor: FanColors.ink,
                  unselectedLabelColor: FanColors.textSecondary,
                  tabs: [
                    Tab(text: '成员'),
                    Tab(text: '动态'),
                    Tab(text: '专辑'),
                    Tab(text: '活动'),
                    Tab(text: '小卡'),
                    Tab(text: '其他来源'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _MembersTab(
              group: group,
              members: members,
              formerMembers: formerMembers,
            ),
            EntitySocialFeed.group(group: group, members: members),
            _AlbumTab(albums: albums),
            _EventTab(events: events),
            _CardTab(group: group, cards: cards),
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(group.colorStart), Color(group.colorEnd)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FanImage(
              imageUrl: group.imageUrl,
              fallback: const SizedBox.shrink(),
            ),
          ),
          if (group.imageUrl?.isNotEmpty == true)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD141829)],
                  ),
                ),
              ),
            ),
          const Positioned(
            right: -30,
            top: 70,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 180,
              color: Color(0x18FFFFFF),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 58, 22, 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white.withValues(alpha: .15),
                        child: ClipOval(
                          child: FanImage(
                            imageUrl: group.imageUrl,
                            fallback: Text(
                              group.displayName.characters.first,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              [
                                if (group.secondaryName.isNotEmpty)
                                  group.secondaryName,
                                group.company,
                              ].join(' · '),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .78),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: () =>
                            showFanToast(context, '已关注 ${group.displayName}'),
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 17,
                        ),
                        label: const Text('关注'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${group.debutDate} 出道  ·  ${group.status}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, height: 1.45),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${group.memberIds.length} 位当前成员  ·  $cardCount 张小卡',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
        SectionHeader(title: '当前成员 (${members.length})'),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 82,
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
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              [
                                if (idol.secondaryName.isNotEmpty)
                                  idol.secondaryName,
                                idol.role,
                              ].join(' · '),
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
        const SizedBox(height: 24),
        SectionHeader(title: '过往成员 (${formerMembers.length})'),
        const SizedBox(height: 9),
        if (formerMembers.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: FanColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '暂无过往成员；历史关系会永久保留。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final idol in formerMembers)
            ListTile(
              onTap: () => context.push('/idol/${idol.id}'),
              leading: IdolAvatar(idol: idol, size: 46),
              title: Text(idol.displayName),
              subtitle: const Text('Former Member'),
            ),
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
              imageUrl: album.frontImageUrl,
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
              imageUrl: event.imageUrl,
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
  const _CardTab({required this.group, required this.cards});
  final FanGroup group;
  final List<CollectibleCard> cards;

  @override
  Widget build(BuildContext context) {
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 9,
              mainAxisSpacing: 16,
              childAspectRatio: .52,
            ),
            itemCount: cards.length,
            itemBuilder: (context, index) => CollectibleCardTile(
              card: cards[index],
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
              imageUrl: item.imageUrl,
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
            gradient: LinearGradient(colors: colors),
          ),
          clipBehavior: Clip.antiAlias,
          child: FanImage(
            imageUrl: imageUrl,
            fallback: Icon(icon, color: Colors.white),
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

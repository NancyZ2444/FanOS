import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feed/presentation/entity_social_feed.dart';
import 'package:flutter/material.dart';
import 'package:fan_os/features/profile/presentation/name_preferences_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class IdolDetailPage extends ConsumerWidget {
  const IdolDetailPage({required this.idolId, super.key});
  final String idolId;

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
          final idol = data.idols
              .where((item) => item.id == idolId)
              .firstOrNull;
          if (idol == null) {
            return const FanEmptyState(
              icon: Icons.person_off_outlined,
              title: '成员不存在',
              message: '该资料可能已停止公开展示，但历史收藏不会丢失。',
            );
          }
          return _IdolBody(idol: idol, data: data);
        },
      ),
    );
  }
}

class _IdolBody extends ConsumerWidget {
  const _IdolBody({required this.idol, required this.data});
  final IdolProfile idol;
  final CatalogBundle data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = data.cards.where((card) => card.idolId == idol.id).toList();
    final group = data.groups
        .where((item) => item.name == idol.groupName)
        .firstOrNull;
    final favorites = ref.watch(favoritesProvider);
    final selected = favorites.selectedIds.contains(idol.id);
    final albums = data.albums
        .where(
          (album) =>
              album.belongsToIdol(idol.id) ||
              (group != null && album.belongsToGroup(group.id)) ||
              cards.any(
                (c) =>
                    c.sourceEntityType == 'ALBUM' &&
                    c.sourceEntityId == album.id,
              ),
        )
        .toList();
    final events = data.events
        .where(
          (event) =>
              event.belongsToIdol(idol.id) ||
              (group != null && event.belongsToGroup(group.id)) ||
              cards.any(
                (c) =>
                    c.sourceEntityType == 'EVENT' &&
                    c.sourceEntityId == event.id,
              ),
        )
        .toList();
    final others = data.others
        .where(
          (item) => cards.any(
            (c) => c.sourceEntityType == 'OTHER' && c.sourceEntityId == item.id,
          ),
        )
        .toList();
    return DefaultTabController(
      length: 5,
      initialIndex: 1,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 354,
            foregroundColor: Colors.white,
            backgroundColor: Color(idol.colorStart),
            actions: [
              if (selected)
                IconButton(
                  key: const Key('idol-highlight-star'),
                  tooltip: favorites.primaryId == idol.id
                      ? '取消星标'
                      : '点亮星星，优先展示',
                  icon: Icon(
                    favorites.primaryId == idol.id
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                  ),
                  onPressed: () async {
                    try {
                      await ref
                          .read(favoritesProvider.notifier)
                          .saveSelection(
                            favorites.selectedIds,
                            favorites.primaryId == idol.id ? null : idol.id,
                          );
                    } catch (_) {
                      if (context.mounted) showFanToast(context, '保存失败，请重试');
                    }
                  },
                ),
              IconButton(
                tooltip: '设置备注',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showNameRemarkEditor(
                  context,
                  ref,
                  'idols',
                  idol.id,
                  idol.nameEn.isNotEmpty ? idol.nameEn : idol.name,
                ),
              ),
              IconButton(
                tooltip: '反馈问题',
                onPressed: () => showFanToast(context, '图鉴问题反馈入口已记录'),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _IdolHero(
                idol: idol,
                selected: selected,
                isPrimary: favorites.primaryId == idol.id,
                onFavorite: () {
                  ref.read(favoritesProvider.notifier).toggle(idol.id);
                  showFanToast(
                    context,
                    selected ? '已取消本命' : '已将 ${idol.displayName} 设为本命',
                  );
                },
                onGroup: group == null
                    ? null
                    : () => context.push('/group/${group.id}'),
                onCareer: () => _showCareer(context, idol),
              ),
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
                    Tab(text: '动态'),
                    Tab(text: '小卡'),
                    Tab(text: '专辑'),
                    Tab(text: '活动'),
                    Tab(text: '其他来源'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            EntitySocialFeed.idol(idol: idol),
            _IdolCards(idol: idol, cards: cards),
            _IdolEntityList(
              emptyTitle: '暂时没有专辑资料',
              children: albums
                  .map(
                    (item) => _IdolEntityRow(
                      title: item.displayName,
                      subtitle: [
                        if (item.secondaryName.isNotEmpty) item.secondaryName,
                        item.albumType,
                        item.releaseDate,
                      ].join(' · '),
                      colors: [Color(item.colorStart), Color(item.colorEnd)],
                      icon: Icons.album_outlined,
                      imageUrl: item.frontImageUrl,
                      onTap: () => context.push('/album/${item.id}'),
                    ),
                  )
                  .toList(),
            ),
            _IdolEntityList(
              emptyTitle: '暂时没有活动资料',
              children: events
                  .map(
                    (item) => _IdolEntityRow(
                      title: item.displayName,
                      subtitle: [
                        if (item.secondaryName.isNotEmpty) item.secondaryName,
                        item.eventType,
                        item.startDate,
                      ].join(' · '),
                      colors: [Color(item.colorStart), Color(item.colorEnd)],
                      icon: Icons.event_outlined,
                      imageUrl: item.imageUrl,
                      onTap: () => context.push('/event/${item.id}'),
                    ),
                  )
                  .toList(),
            ),
            _IdolEntityList(
              emptyTitle: '暂时没有其他来源',
              children: others
                  .map(
                    (item) => _IdolEntityRow(
                      title: item.displayName,
                      subtitle: [
                        if (item.secondaryName.isNotEmpty) item.secondaryName,
                        item.startDate,
                        ...item.tags.map((t) => t.name),
                      ].join(' · '),
                      colors: [Color(item.colorStart), Color(item.colorEnd)],
                      icon: Icons.shopping_bag_outlined,
                      imageUrl: item.imageUrl,
                      onTap: () => context.push('/other/${item.id}'),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showCareer(BuildContext context, IdolProfile idol) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${idol.displayName} · 个人经历',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              if (idol.careers.isEmpty)
                const Text('暂无公开经历')
              else
                for (final career in idol.careers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: CircleAvatar(
                            radius: 5,
                            backgroundColor: FanColors.lavender,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                career.period,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                career.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (career.subtitle.isNotEmpty)
                                Text(career.subtitle),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdolHero extends StatelessWidget {
  const _IdolHero({
    required this.idol,
    required this.selected,
    required this.isPrimary,
    required this.onFavorite,
    required this.onCareer,
    this.onGroup,
  });
  final IdolProfile idol;
  final bool selected;
  final bool isPrimary;
  final VoidCallback onFavorite;
  final VoidCallback? onGroup;
  final VoidCallback onCareer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(idol.colorStart), Color(idol.colorEnd)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FanImage(
              imageUrl: idol.imageUrl,
              fallback: const SizedBox.shrink(),
            ),
          ),
          if (idol.imageUrl?.isNotEmpty == true)
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
            right: -28,
            top: 68,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 180,
              color: Color(0x18FFFFFF),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 62, 22, 55),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IdolAvatar(idol: idol, size: 82, selected: isPrimary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              idol.displayName.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 29,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            InkWell(
                              onTap: onGroup,
                              child: Text(
                                [
                                  if (idol.secondaryName.isNotEmpty)
                                    idol.secondaryName,
                                  idol.displayGroupName,
                                  idol.company,
                                ].join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: onFavorite,
                        icon: Icon(
                          selected
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 17,
                        ),
                        label: Text(
                          isPrimary
                              ? '★ 已是本命'
                              : selected
                              ? '已是本命'
                              : '设为本命',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${idol.role}  ·  ${idol.birthDate}  ·  ${idol.region}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .78),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    idol.bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, height: 1.45),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onCareer,
                      icon: const Icon(
                        Icons.timeline_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                      label: const Text(
                        '个人经历',
                        style: TextStyle(color: Colors.white),
                      ),
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

class _IdolCards extends ConsumerStatefulWidget {
  const _IdolCards({required this.idol, required this.cards});
  final IdolProfile idol;
  final List<CollectibleCard> cards;

  @override
  ConsumerState<_IdolCards> createState() => _IdolCardsState();
}

class _IdolCardsState extends ConsumerState<_IdolCards> {
  String _type = '全部';

  @override
  Widget build(BuildContext context) {
    final relation = ref.watch(collectionProvider);
    final types = ['全部', ...widget.cards.map((card) => card.cardType).toSet()];
    final cards =
        widget.cards
            .where((card) => _type == '全部' || card.cardType == _type)
            .toList()
          ..sort((a, b) => b.releaseDate.compareTo(a.releaseDate));
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
            scrollDirection: Axis.horizontal,
            itemCount: types.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) => ChoiceChip(
              label: Text(types[index]),
              selected: _type == types[index],
              onSelected: (_) => setState(() => _type = types[index]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 7, 20, 2),
          child: Row(
            children: [
              Text(
                '${cards.length} 张',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/cards?idol=${widget.idol.id}'),
                child: const Text('完整筛选'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                badge: relation.isOwned(card.id)
                    ? const StatusBadge(label: '✓', dark: true)
                    : relation.isWished(card.id)
                    ? const StatusBadge(label: '♥')
                    : null,
                onTap: () => context.push('/card/${card.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IdolEntityList extends StatelessWidget {
  const _IdolEntityList({required this.emptyTitle, required this.children});
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

class _IdolEntityRow extends StatelessWidget {
  const _IdolEntityRow({
    this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String? imageUrl;
  final String subtitle;
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
          width: 60,
          height: 60,
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
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

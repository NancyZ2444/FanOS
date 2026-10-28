import 'catalog_profile_tab.dart';

import 'package:fan_os/core/widgets/entity_header.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/config/feature_flags.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feed/presentation/entity_social_feed.dart';
import 'package:fan_os/features/feedback/catalog_contributors.dart';
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
      appBar: !catalog.hasValue ? AppBar(title: const Text('艺人详情')) : null,
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

class _IdolBody extends ConsumerStatefulWidget {
  const _IdolBody({required this.idol, required this.data});
  final IdolProfile idol;
  final CatalogBundle data;

  @override
  ConsumerState<_IdolBody> createState() => _IdolBodyState();
}

class _IdolBodyState extends ConsumerState<_IdolBody> {
  String? _profileSection;
  IdolProfile get idol => widget.idol;
  CatalogBundle get data => widget.data;
  @override
  Widget build(BuildContext context) {
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
          (item) =>
              item.belongsToIdol(idol.id) ||
              (group != null && item.belongsToGroup(group.id)) ||
              cards.any(
                (c) =>
                    c.sourceEntityType == 'OTHER' &&
                    c.sourceEntityId == item.id,
              ),
        )
        .toList();
    final showFeed = ref.watch(idolFeedEnabledProvider);
    return DefaultTabController(
      key: ValueKey('idol-tabs-$showFeed'),
      length: showFeed ? 6 : 5,
      initialIndex: showFeed ? 1 : 0,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          EntityProfileSliver(
            imageUrl: idol.coverImageUrl ?? idol.imageUrl ?? idol.thumbnailUrl,
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
              CatalogPersonalRemarkButton(
                onPressed: () => showNameRemarkEditor(
                  context,
                  ref,
                  'idols',
                  idol.id,
                  idol.officialDisplayName,
                ),
              ),
            ],
            hero: _IdolHero(
              idol: idol,
              selected: selected,
              isPrimary: favorites.primaryId == idol.id,
              onFavorite: () {
                if (!ref.read(sessionProvider).isLoggedIn) {
                  context.push('/login');
                  return;
                }
                ref.read(favoritesProvider.notifier).toggle(idol.id);
              },
              onGroup: group == null
                  ? null
                  : () => context.push('/group/${group.id}'),
              onCareer: () {
                setState(() => _profileSection = 'career');
                DefaultTabController.of(context).animateTo(showFeed ? 5 : 4);
              },
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: EntityTabs([
              if (showFeed) '动态',
              '小卡',
              '专辑',
              '活动',
              '其他',
              '资料',
            ], textScale: MediaQuery.textScalerOf(context).scale(14) / 14),
          ),
        ],
        body: TabBarView(
          children: [
            if (showFeed) EntitySocialFeed.idol(idol: idol),
            _IdolCards(idol: idol, cards: cards, catalog: data),
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
                      imageUrl: item.thumbnailUrl ?? item.frontImageUrl,
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
                      imageUrl: item.thumbnailUrl ?? item.imageUrl,
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
                      imageUrl: item.thumbnailUrl ?? item.imageUrl,
                      onTap: () => context.push('/other/${item.id}'),
                    ),
                  )
                  .toList(),
            ),
            CatalogProfileTab(
              kind: 'idols',
              entityId: idol.id,
              section: _profileSection,
            ),
          ],
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
  Widget build(BuildContext context) => EntityIdentity(
    name: idol.displayName,
    avatar: IdolAvatar(idol: idol, size: 56, selected: isPrimary),
    subtitle: [
      idol.secondaryName,
      idol.displayGroupName,
    ].where((s) => s.trim().isNotEmpty).join(' · '),
    details: [idol.role, idol.birthDate, idol.company],
    description: idol.bio,
    contribution: CatalogContributors(kind: 'idols', entityId: idol.id),
    actions: [
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        onPressed: onFavorite,
        icon: Icon(selected ? Icons.favorite : Icons.favorite_border, size: 18),
        label: Text(
          isPrimary
              ? '★ 已是本命'
              : selected
              ? '已是本命'
              : '设为本命',
        ),
      ),
      if (onGroup != null)
        TextButton(onPressed: onGroup, child: const Text('查看组合')),
      TextButton(onPressed: onCareer, child: const Text('个人经历')),
    ],
  );
}

class _IdolCards extends ConsumerStatefulWidget {
  const _IdolCards({
    required this.idol,
    required this.cards,
    required this.catalog,
  });
  final IdolProfile idol;
  final List<CollectibleCard> cards;
  final CatalogBundle catalog;

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
    if (widget.cards.isEmpty) {
      return const FanEmptyState(
        icon: Icons.style_outlined,
        title: '暂未收录小卡',
        message: '这位艺人的小卡发布后会展示在这里。',
      );
    }
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
          child: cards.isEmpty
              ? FanEmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: '没有符合条件的小卡',
                  message: '试试其他类型。',
                  actionLabel: '清空筛选',
                  onAction: () => setState(() => _type = '全部'),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                  gridDelegate: fanCardGrid(context),
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return CollectibleCardTile(
                      card: card,
                      caption: CardTileCaption.idol,
                      sourceLabel: widget.catalog.cardSourceLabel(card),
                      versionLabel: widget.catalog.cardVersionLabel(card),
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
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

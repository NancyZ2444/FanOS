import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({super.key});

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  String _tab = 'Owned';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的收藏')),
        body: FanEmptyState(
          icon: Icons.lock_outline_rounded,
          title: '登录后建立你的收藏',
          message: 'Owned、Wishlist 与数字卡册会安全同步到你的账号。',
          actionLabel: '去登录',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final catalog = ref.watch(catalogProvider);
    final relation = ref.watch(collectionProvider);
    final favorites = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            onPressed: () => context.push('/search?type=小卡'),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '收藏加载失败',
          message: '请稍后重试',
        ),
        data: (data) {
          final cards = _tab == 'Owned'
              ? data.cards.where((card) => relation.isOwned(card.id)).toList()
              : data.cards.where((card) => relation.isWished(card.id)).toList();
          return Column(
            children: [
              FanContent(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: FavoriteIdolsShowcase(
                  idols: data.idols
                      .where((idol) => favorites.selectedIds.contains(idol.id))
                      .toList(),
                  primaryId: favorites.primaryId,
                  onManage: () => context.push('/onboarding/favorites'),
                  onOpen: (idol) => context.push('/idol/${idol.id}'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(
                  children: ['Owned', 'Wishlist', '卡册'].map((label) {
                    final selected = _tab == label;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setState(() => _tab = label),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? FanColors.ink
                                  : const Color(0xFFEDF0F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : FanColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (_tab == '卡册')
                const Expanded(child: AlbumShelfBody())
              else if (cards.isEmpty)
                Expanded(
                  child: FanEmptyState(
                    icon: _tab == 'Owned'
                        ? Icons.style_outlined
                        : Icons.favorite_border_rounded,
                    title: _tab == 'Owned' ? '还没有收藏小卡' : 'Wishlist 还是空的',
                    message: _tab == 'Owned'
                        ? '去逛图鉴或使用 AI Scan 找到第一张卡。'
                        : '看到喜欢的小卡，可以先加入 Wishlist。',
                    actionLabel: '去逛图鉴',
                    onAction: () => context.go('/catalog'),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 18,
                          childAspectRatio: .52,
                        ),
                    itemCount: cards.length,
                    itemBuilder: (context, index) => CollectibleCardTile(
                      card: cards[index],
                      compact: true,
                      badge: _buildBadge(cards[index], relation),
                      onTap: () => context.push('/card/${cards[index].id}'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBadge(CollectibleCard card, CollectionState state) {
    if (_tab == 'Wishlist') return const StatusBadge(label: 'Wish');
    return StatusBadge(label: '×${state.quantity(card.id)}', dark: true);
  }
}

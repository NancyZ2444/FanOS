import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/collection/presentation/collection_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({super.key});
  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  int _tab = 0, _refresh = 0;
  final _lists = [false, false];
  String? _albumView;
  final _visited = <int>{0};
  bool get _list => _tab == 2 ? _albumView == 'LIST' : _lists[_tab];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isLoggedIn) {
      return Scaffold(
        body: SafeArea(
          child: FanEmptyState(
            icon: Icons.lock_outline_rounded,
            title: '登录后建立你的收藏',
            message: '已拥有、心愿单与卡册会同步到你的账号。',
            actionLabel: '去登录',
            onAction: () => context.push('/login'),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('collection-layout'),
                    tooltip: _list ? (_tab == 2 ? '切换书架' : '切换网格') : '切换列表',
                    onPressed: () => setState(() {
                      if (_tab == 2) {
                        _albumView = _list ? 'SHELF' : 'LIST';
                      } else {
                        _lists[_tab] = !_list;
                      }
                    }),
                    icon: Icon(
                      _list
                          ? Icons.view_list_outlined
                          : Icons.grid_view_rounded,
                      color: FanColors.lavender,
                    ),
                  ),
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Semantics(
                        selected: _tab == i,
                        child: InkWell(
                          key: Key('collection-tab-$i'),
                          onTap: () => setState(() {
                            _tab = i;
                            _visited.add(i);
                          }),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  width: 2,
                                  color: _tab == i
                                      ? FanColors.lavender
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Text(
                              ['已拥有', '心愿单', '卡册'][i],
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: _tab == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _tab == i
                                    ? FanColors.lavender
                                    : FanColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    key: const Key('collection-search'),
                    tooltip: '搜索我的收藏',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () async {
                      await context.push('/collection/search');
                      if (mounted) setState(() => _refresh++);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  CollectionCards(
                    key: ValueKey('owned-${session.userId}'),
                    wished: false,
                    list: _lists[0],
                  ),
                  _visited.contains(1)
                      ? CollectionCards(
                          key: ValueKey('wishlist-${session.userId}'),
                          wished: true,
                          list: _lists[1],
                        )
                      : const SizedBox(),
                  _visited.contains(2)
                      ? AlbumShelfBody(
                          key: ValueKey('albums-${session.userId}'),
                          embedded: true,
                          viewMode: _albumView,
                          refreshTick: _refresh,
                          onViewModeChanged: (view) {
                            if (mounted && _albumView != view) {
                              setState(() => _albumView = view);
                            }
                          },
                        )
                      : const SizedBox(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/collection/data/library_search_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LibrarySearchPage extends ConsumerStatefulWidget {
  const LibrarySearchPage({super.key});
  @override
  ConsumerState<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends ConsumerState<LibrarySearchPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _positions = <String, double>{};
  final _loadedCounts = <String, int>{};
  Timer? _debounce;
  String _scope = 'all', _query = '';
  LibrarySearchResult? _result;
  bool _loading = false, _more = false;
  bool _failedMore = false;
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _request++; // Invalidate old requests as soon as the input changes.
    setState(() {
      _query = value.trim();
      _result = null;
      _error = null;
      _more = false;
      _loading = _query.isNotEmpty;
      _positions.clear();
      _loadedCounts.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), _search);
    }
  }

  Future<void> _search({bool more = false}) async {
    if (_query.isEmpty || (more && (_more || _loading || _scope == 'all'))) {
      return;
    }
    final offset = more ? _result?.groups[_scope]?.nextOffset : 0;
    if (offset == null) return;
    final request = ++_request;
    final scope = _scope;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      var result = await ref
          .read(librarySearchRepositoryProvider)
          .search(_query, scope: scope, offset: offset);
      if (!mounted || request != _request) return;
      // Restore all previously loaded pages before restoring a deep scroll
      // position. A return from detail must not collapse the list to page one.
      if (!more && scope != 'all') {
        final target = _loadedCounts[scope] ?? 0;
        while (result.groups[scope]!.items.length < target &&
            result.groups[scope]!.nextOffset != null) {
          final next = await ref
              .read(librarySearchRepositoryProvider)
              .search(
                _query,
                scope: scope,
                offset: result.groups[scope]!.nextOffset!,
              );
          if (!mounted || request != _request) return;
          result = _merge(result, next, scope);
        }
      }
      setState(() {
        if (more && _result != null) {
          _result = _merge(_result!, result, scope);
        } else {
          _result = result;
        }
        _loadedCounts[scope] = _result!.groups[scope]?.items.length ?? 0;
      });
      if (!more) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(
              (_positions[scope] ?? 0).clamp(
                0.0,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = '搜索暂时未能加载，请检查网络后重试';
          _failedMore = more;
        });
      }
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  LibrarySearchResult _merge(
    LibrarySearchResult previous,
    LibrarySearchResult next,
    String scope,
  ) {
    final group = next.groups[scope]!;
    final byId = {
      for (final item in [...previous.groups[scope]!.items, ...group.items])
        item.id: item,
    };
    return LibrarySearchResult({
      ...next.groups,
      scope: LibrarySearchGroup(
        items: byId.values.toList(),
        total: group.total,
        nextOffset: group.nextOffset,
      ),
    });
  }

  void _selectScope(String scope) {
    if (_scope == scope) return;
    _debounce?.cancel();
    if (_scroll.hasClients) _positions[_scope] = _scroll.offset;
    setState(() {
      _scope = scope;
      _result = null;
      _error = null;
      _loading = false;
      _more = false;
    });
    _request++;
    _search();
  }

  Future<void> _open(LibrarySearchItem item) async {
    if (_scroll.hasClients) _positions[_scope] = _scroll.offset;
    final album = item.album;
    await context.push(
      item.card != null
          ? '/card/${item.card!.id}'
          : '/digital-albums/${album!.id}${album.isOwner && album.isDraft ? '/edit' : ''}',
    );
    if (mounted) _search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      titleSpacing: 0,
      title: TextField(
        key: const Key('library-search-input'),
        controller: _input,
        autofocus: true,
        maxLength: 100,
        onChanged: _changed,
        onSubmitted: (_) {
          _debounce?.cancel();
          _search();
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索我的小卡与卡册',
          counterText: '',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _input.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空搜索',
                  onPressed: () {
                    _input.clear();
                    _changed('');
                  },
                  icon: const Icon(Icons.cancel, size: 18),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                for (final e in libraryLabels.entries)
                  Expanded(
                    child: TextButton(
                      key: Key('library-scope-${e.key}'),
                      onPressed: () => _selectScope(e.key),
                      style: TextButton.styleFrom(
                        foregroundColor: _scope == e.key
                            ? FanColors.lavender
                            : FanColors.textSecondary,
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontWeight: _scope == e.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() {
    if (_query.isEmpty) {
      return const FanEmptyState(
        icon: Icons.search_rounded,
        title: '搜索你的收藏',
        message: '仅搜索已拥有、心愿单和卡册\n支持艺人、组合、来源、版本和卡册名称',
      );
    }
    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _result == null) {
      return FanEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '搜索暂时不可用',
        message: _error!,
        actionLabel: '重新加载',
        onAction: _search,
      );
    }
    final result = _result;
    if (result == null) return const SizedBox();
    final count = _scope == 'all'
        ? result.total
        : result.groups[_scope]?.total ?? 0;
    if (count == 0) {
      return const FanEmptyState(
        icon: Icons.search_off,
        title: '没有找到相关收藏',
        message: '试试其他关键词，或切换搜索分类。',
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 200 && _error == null) _search(more: true);
        return false;
      },
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '找到 $count 个结果',
            style: const TextStyle(
              fontSize: 12,
              color: FanColors.textSecondary,
            ),
          ),
          for (final e in result.groups.entries)
            if ((_scope == 'all' || _scope == e.key) && e.value.total > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '${libraryLabels[e.key]} · ${e.value.total}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final item in e.value.items) _row(item, e.key),
              if (_scope == 'all' && e.value.nextOffset != null)
                TextButton(
                  onPressed: () => _selectScope(e.key),
                  child: Text('查看全部${libraryLabels[e.key]}'),
                ),
            ],
          if (_more)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          if (_error != null)
            TextButton(
              onPressed: () => _search(more: _failedMore),
              child: const Text('加载失败，点击重试'),
            ),
          if (_scope != 'all' && result.groups[_scope]?.nextOffset == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '已经到底了',
                  style: TextStyle(
                    fontSize: 12,
                    color: FanColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(LibrarySearchItem item, String kind) {
    final card = item.card, album = item.album;
    final title = card == null
        ? album!.name
        : [
            card.hasIndividualIdol
                ? entityDisplayName(ref, 'idols', card.idolId, card.idolName)
                : card.groupName,
            card.source,
          ].where((s) => s.isNotEmpty).join(' · ');
    final subtitle = card == null
        ? [
            {
                  'created': '我创建的',
                  'draft': '草稿',
                  'favorite': '我收藏的',
                }[item.category] ??
                '卡册',
            '${album!.cardCount} 张',
            if (item.matchType == 'card') '包含匹配的小卡',
          ].join(' · ')
        : [
            card.groupName,
            card.cardType,
            card.version,
            if (kind == 'owned') '已拥有 ×${item.quantity}',
          ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      key: ValueKey('library-result-$kind-${item.id}'),
      onTap: () => _open(item),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: FanColors.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 84,
              child: card == null
                  ? AlbumCoverWidget(album!)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AlbumCardImage(card, thumbnail: true),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlight(title),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: FanColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: FanColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlight(String value) {
    final at = value.toLowerCase().indexOf(_query.toLowerCase());
    return Text.rich(
      TextSpan(
        children: at < 0
            ? [TextSpan(text: value)]
            : [
                TextSpan(text: value.substring(0, at)),
                TextSpan(
                  text: value.substring(at, at + _query.length),
                  style: const TextStyle(color: FanColors.lavender),
                ),
                TextSpan(text: value.substring(at + _query.length)),
              ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

import 'dart:async';

import '../data/album_resources.dart';
import 'album_resource_tile.dart';
import 'album_example_page.dart';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_favorites_repository.dart';
import 'package:fan_os/features/albums/presentation/album_favorite_sheet.dart';
import 'package:fan_os/features/albums/presentation/album_input_scope.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AlbumShelfPage extends StatelessWidget {
  const AlbumShelfPage({super.key, this.userId});
  final String? userId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(userId == null ? '我的相册' : 'TA 的公开相册')),
    body: AlbumShelfBody(userId: userId, showTitle: false),
  );
}

class AlbumShelfBody extends ConsumerStatefulWidget {
  const AlbumShelfBody({
    super.key,
    this.userId,
    this.showTitle = true,
    this.embedded = false,
    this.profileMode = false,
    this.viewMode,
    this.onViewModeChanged,
    this.refreshTick = 0,
  });
  final String? userId;
  final bool showTitle;
  final bool embedded;
  final bool profileMode;
  final String? viewMode;
  final ValueChanged<String>? onViewModeChanged;
  final int refreshTick;
  @override
  ConsumerState<AlbumShelfBody> createState() => _AlbumShelfBodyState();
}

class _AlbumShelfBodyState extends ConsumerState<AlbumShelfBody> {
  List<PhotocardAlbum> _albums = [];
  AlbumQuota? _quota;
  AlbumJson? _shelfSnapshot;
  String _q = '', _sort = 'updated', _theme = 'cream-white', _view = 'SHELF';
  String _workMode = 'ALL';
  bool _favorites = false,
      _loading = true,
      _more = false,
      _preferencesLoaded = false;
  String? _error;
  bool _failedMore = false;
  int? _next;
  int _request = 0;
  Timer? _debounce;
  final _scroll = ScrollController();
  final _positions = <String, double>{};
  final _loadedCounts = <String, int>{};
  bool _drafts = false;
  List<AlbumFavoriteFolder> _folders = [];
  String? _folderId;
  String get _category => _favorites
      ? 'favorite'
      : _drafts
      ? 'draft'
      : 'created';
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant AlbumShelfBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewMode != widget.viewMode &&
        widget.viewMode != null &&
        widget.viewMode != _view) {
      _setView(widget.viewMode!);
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.refreshTick != widget.refreshTick) {
      Future.microtask(() {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_more || _loading || _next == null)) return;
    if (!more) ref.invalidate(albumResourcesProvider);
    final position = _scroll.hasClients ? _scroll.offset : 0.0;
    final category = _category;
    final request = ++_request;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      if (widget.profileMode && _favorites && !more) {
        final folders = await ref
            .read(albumFavoritesRepositoryProvider)
            .folders(userId: widget.userId);
        if (!mounted || request != _request) return;
        _folders = folders;
      }
      final result = await _fetch(more ? _next! : 0);
      if (!mounted || request != _request) return;
      final albums = [...result.albums];
      var next = result.nextOffset;
      final target = _loadedCounts[category] ?? 0;
      while (!more && albums.length < target && next != null) {
        final page = await _fetch(next);
        if (!mounted || request != _request) return;
        albums.addAll(page.albums);
        next = page.nextOffset;
      }
      if (widget.userId == null) ref.invalidate(albumQuotaProvider);
      setState(() {
        _albums = {
          for (final a in [...(more ? _albums : <PhotocardAlbum>[]), ...albums])
            a.id: a,
        }.values.toList();
        _loadedCounts[category] = _albums.length;
        _next = next;
        _quota = result.quota ?? _quota;
        _shelfSnapshot = result.shelfSnapshot ?? _shelfSnapshot;
        if (!_preferencesLoaded) {
          _theme = result.theme;
          _view = widget.profileMode
              ? 'LIST'
              : widget.viewMode ?? result.viewMode;
          _preferencesLoaded = true;
        }
      });
      widget.onViewModeChanged?.call(_view);
      if (!more) _restorePosition(position);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e.toString();
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

  Future<AlbumShelfData> _fetch(int offset) {
    if (widget.profileMode && _favorites) {
      return ref
          .read(albumFavoritesRepositoryProvider)
          .list(
            userId: widget.userId,
            groupId: _folderId,
            offset: offset,
            workMode: _workMode,
          );
    }
    return ref
        .read(albumRepositoryProvider)
        .list(
          q: _q,
          sort: _favorites ? 'created' : _sort,
          offset: offset,
          workMode: _workMode,
          favorites: _favorites,
          status: (widget.embedded || widget.profileMode) && !_favorites
              ? (_drafts ? 'DRAFT' : 'PUBLISHED')
              : 'ALL',
          userId: widget.userId,
        );
  }

  Future<void> _editFolder([AlbumFavoriteFolder? folder]) async {
    final saved = await editAlbumFavoriteFolder(context, folder: folder);
    if (!mounted || saved == null) return;
    setState(() {
      _folderId = saved.id;
      _albums = [];
      _next = null;
    });
    _loadedCounts.remove('favorite');
    await _load();
  }

  Future<void> _open(PhotocardAlbum album) async {
    if (album.unavailable) {
      showFanToast(context, '原作者已设为私密、删除或作品暂不可访问');
      return;
    }
    await context.push('/digital-albums/${album.id}');
    if (mounted) _load();
  }

  Future<void> _create() async {
    if (_quota != null && _quota!.albumCount >= _quota!.maxAlbums) {
      await showAlbumQuotaDialog(context, _quota!);
      return;
    }
    await context.push('/digital-albums/new');
    if (mounted) _load();
  }

  Future<void> _menu(PhotocardAlbum album) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (album.isOwner) ...[
              for (final item in [
                ('edit', '编辑相册', 'Type'),
                ('rename', '重命名', 'Type'),
                ('visibility', album.isPublic ? '设为私密' : '设为公开', 'Heart'),
                ('duplicate', '复制相册', 'BookCopy'),
                ('delete', '删除相册', 'Trash2'),
              ])
                ListTile(
                  leading: AlbumIcon(item.$3),
                  title: Text(item.$2),
                  onTap: () => Navigator.pop(context, item.$1),
                ),
            ] else if (_favorites && widget.userId == null) ...[
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('移动到分组'),
                onTap: () => Navigator.pop(context, 'group'),
              ),
              ListTile(
                leading: const AlbumIcon('Heart'),
                title: const Text('取消收藏相册'),
                onTap: () => Navigator.pop(context, 'unfavorite'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      final repo = ref.read(albumRepositoryProvider);
      if (action == 'edit') {
        await context.push('/digital-albums/${album.id}/edit');
      }
      if (action == 'unfavorite') {
        await ref.read(albumFavoritesRepositoryProvider).remove(album.id);
      }
      if (!mounted) return;
      if (action == 'group') {
        await showAlbumFavoriteSheet(
          context,
          album.id,
          move: true,
          initialGroupId: album.json['favorite_group_id'] as String?,
        );
      }
      if (!mounted) return;
      if (action == 'delete' &&
          await confirmAlbumAction(
            context,
            '删除相册？',
            '会移入已删除状态，且停止公开访问；不会影响你收藏的小卡。',
            action: '删除',
          )) {
        await repo.delete(await repo.get(album.id));
      }
      if (action == 'duplicate') {
        final copy = await repo.duplicate(await repo.get(album.id));
        if (mounted) await context.push('/digital-albums/${copy.id}/edit');
      }
      if (action == 'visibility') {
        final current = await repo.get(album.id);
        await repo.save(
          current.edit(
            (d) => d['visibility'] = album.isPublic ? 'PRIVATE' : 'PUBLIC',
          ),
        );
      }
      if (action == 'rename') {
        if (!mounted) return;
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlbumInputScope(
            initialValues: {'name': album.name},
            builder: (context, inputs) {
              final controller = inputs['name']!;
              return AlertDialog(
                title: const Text('相册名称'),
                content: TextField(controller: controller, maxLength: 50),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          ),
        );
        if (name != null && name.isNotEmpty) {
          final current = await repo.get(album.id);
          await repo.save(current.edit((d) => d['name'] = name));
        }
      }
      if (mounted) await _load();
    } catch (e) {
      if (mounted) showFanToast(context, e.toString());
    }
  }

  Future<void> _setView(String value) async {
    final position = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() => _view = value);
    widget.onViewModeChanged?.call(value);
    _restorePosition(position);
    if (widget.userId == null && !widget.profileMode) {
      try {
        await ref.read(albumRepositoryProvider).preferences(_theme, _view);
      } catch (e) {
        if (mounted) showFanToast(context, e.toString());
      }
    }
  }

  void _restorePosition(double offset) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
        }
      });

  Future<void> _categoryChanged(String value) async {
    if (_category == value) return;
    if (_scroll.hasClients) _positions[_category] = _scroll.offset;
    setState(() {
      _favorites = value == 'favorite';
      _drafts = value == 'draft';
      _albums = [];
      _next = null;
    });
    await _load();
    if (mounted && _category == value) _restorePosition(_positions[value] ?? 0);
  }

  void _clearFilters() {
    setState(() {
      _workMode = 'ALL';
      _sort = 'updated';
    });
    _loadedCounts.clear();
    _positions.clear();
    _load().then((_) {
      if (mounted) _restorePosition(0);
    });
  }

  Future<void> _showFilters() async {
    var mode = _workMode;
    var sort = _sort;
    var folder = _folderId;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '筛选与排序',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('卡册类型', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in {
                        'ALL': '全部',
                        'BOOK': '相册模式',
                        'CARDS': '卡片模式',
                      }.entries)
                        ChoiceChip(
                          key: ValueKey('album-mode-${entry.key}'),
                          label: Text(entry.value),
                          selected: mode == entry.key,
                          onSelected: (_) => update(() => mode = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('排序方式', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_favorites)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '按收藏时间 · 最新收藏在前',
                        style: TextStyle(color: FanColors.textSecondary),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in {
                          'updated': '最近更新',
                          'created': '最近创建',
                          'name': '名称',
                        }.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: sort == entry.key,
                            onSelected: (_) => update(() => sort = entry.key),
                          ),
                      ],
                    ),
                  if (widget.profileMode && _favorites) ...[
                    const SizedBox(height: 24),
                    const Text('收藏分组', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: folder ?? 'all',
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('全部分组'),
                        ),
                        if (widget.userId == null)
                          const DropdownMenuItem(
                            value: 'ungrouped',
                            child: Text('未分组'),
                          ),
                        for (final f in _folders)
                          DropdownMenuItem(value: f.id, child: Text(f.name)),
                      ],
                      onChanged: (v) =>
                          update(() => folder = v == 'all' ? null : v),
                    ),
                    if (widget.userId == null)
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context, false);
                              _editFolder();
                            },
                            child: const Text('新建收藏分组'),
                          ),
                          if (_folders.any((f) => f.id == folder))
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, false);
                                _editFolder(
                                  _folders.firstWhere((f) => f.id == folder),
                                );
                              },
                              child: const Text('编辑分组与可见性'),
                            ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => update(() {
                              mode = 'ALL';
                              sort = 'updated';
                            }),
                            child: const Text('重置'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('确定'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || applied != true) return;
    setState(() {
      _workMode = mode;
      _sort = sort;
      _folderId = folder;
    });
    _loadedCounts.clear();
    _positions.clear();
    await _load();
    if (mounted) _restorePosition(0);
  }

  Future<void> _themes(List<AlbumJson> resources) async {
    final themes = albumResourceChoices(
      resources,
      kinds: {'SHELF'},
      plan: _quota?.plan,
    );
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '书架主题',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                if (themes.isEmpty) const Text('暂无可选书架主题'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final t in themes)
                      SizedBox(
                        width: 94,
                        height: 116,
                        child: AlbumResourceTile(
                          resource: t,
                          plan: _quota?.plan,
                          selected: t['id'] == _theme,
                          onSelected: () =>
                              Navigator.pop(context, t['id'] as String),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      try {
        await ref.read(albumRepositoryProvider).preferences(selected, _view);
        if (!mounted) return;
        setState(() {
          _theme = selected;
          _shelfSnapshot = albumResourceSnapshot(
            themes.firstWhere((t) => t['id'] == selected),
          );
        });
      } catch (e) {
        if (mounted) showFanToast(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null && !ref.watch(sessionProvider).isLoggedIn) {
      return FanEmptyState(
        icon: Icons.lock_outline,
        title: '登录后创建你的相册',
        message: '官方小卡自由排版，未拥有的小卡也可以加入相册。',
        actionLabel: '去登录',
        onAction: () => context.push('/login'),
      );
    }
    ref.listen(albumRepositoryProvider, (previous, next) {
      if (previous != next) {
        _preferencesLoaded = false;
        Future.microtask(_load);
      }
    });
    final resources = ref.watch(albumResourcesProvider).value ?? <AlbumJson>[];
    final matching = resources.where(
      (r) => r['id'] == _theme && r['kind'] == 'SHELF',
    );
    final theme =
        _shelfSnapshot?['id'] == _theme &&
            _shelfSnapshot?['config'] is AlbumJson
        ? _shelfSnapshot!['config'] as AlbumJson
        : matching.isEmpty
        ? {
            'colors': ['#F4EEE7', '#FFFFFF'],
            'ledge': '#DAD0C5',
          }
        : matching.first['config'] as AlbumJson;
    return Column(
      children: [
        if (!widget.embedded && !widget.profileMode) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.showTitle
                        ? (widget.userId == null ? '我的相册' : '公开相册')
                        : '',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.userId == null && _quota != null)
                  Text(
                    '${_quota!.albumCount} / ${_quota!.maxAlbums}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (widget.userId == null)
                  IconButton(
                    tooltip: '书架主题',
                    onPressed: resources.isEmpty
                        ? null
                        : () => _themes(resources),
                    icon: const AlbumIcon('Grid2X2'),
                  ),
                IconButton(
                  tooltip: _view == 'SHELF' ? '切换列表' : '切换书架',
                  onPressed: () =>
                      _setView(_view == 'SHELF' ? 'LIST' : 'SHELF'),
                  icon: AlbumIcon(_view == 'SHELF' ? 'List' : 'LayoutGrid'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索相册名称',
                prefixIcon: Padding(
                  padding: EdgeInsets.all(13),
                  child: AlbumIcon('Search', size: 18),
                ),
              ),
              onChanged: (v) {
                _q = v;
                _loadedCounts.clear();
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<String>(
                      tooltip: '所属范围',
                      initialValue: _category,
                      onSelected: _categoryChanged,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'created',
                          child: Text(
                            widget.userId == null ? '我创建的' : 'TA 创建的',
                          ),
                        ),
                        if (!widget.profileMode)
                          const PopupMenuItem(
                            value: 'draft',
                            child: Text('草稿'),
                          ),
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(
                            widget.userId == null ? '我收藏的' : 'TA 收藏的',
                          ),
                        ),
                      ],
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _favorites
                                  ? (widget.userId == null ? '我收藏的' : 'TA 收藏的')
                                  : _drafts
                                  ? '草稿'
                                  : (widget.userId == null ? '我创建的' : 'TA 创建的'),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.expand_more, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('album-filter'),
                  onPressed: _showFilters,
                  style: TextButton.styleFrom(
                    foregroundColor: _workMode == 'ALL'
                        ? FanColors.textSecondary
                        : FanColors.lavender,
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.tune_outlined, size: 20),
                  label: Text(_workMode == 'ALL' ? '筛选' : '筛选·1'),
                ),
                if (widget.userId == null && !widget.profileMode)
                  PopupMenuButton<String>(
                    tooltip: '卡册管理',
                    onSelected: (value) {
                      if (value == 'theme') _themes(resources);
                      if (value == 'quota' && _quota != null) {
                        showAlbumQuotaDialog(context, _quota!);
                      }
                      if (value == 'folder') _editFolder();
                      if (value == 'edit-folder') {
                        _editFolder(
                          _folders.firstWhere((f) => f.id == _folderId),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      if (!widget.profileMode)
                        const PopupMenuItem(
                          value: 'theme',
                          child: Text('书架主题'),
                        ),
                      if (!widget.profileMode && _quota != null)
                        PopupMenuItem(
                          value: 'quota',
                          child: Text(
                            '卡册额度 ${_quota!.albumCount}/${_quota!.maxAlbums}',
                          ),
                        ),
                      if (_favorites)
                        const PopupMenuItem(
                          value: 'folder',
                          child: Text('新建收藏分组'),
                        ),
                      if (_favorites && _folders.any((f) => f.id == _folderId))
                        const PopupMenuItem(
                          value: 'edit-folder',
                          child: Text('编辑分组与可见性'),
                        ),
                    ],
                    icon: const Icon(Icons.more_horiz, size: 20),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              if (_loading && _albums.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (_error != null && _albums.isEmpty)
                FanEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '相册加载失败',
                  message: _error!,
                  actionLabel: '重新加载',
                  onAction: _load,
                )
              else
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 180 &&
                        !_loading &&
                        !_more &&
                        _error == null &&
                        _next != null) {
                      _load(more: true);
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _albums.isEmpty
                        ? ListView(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 290,
                                child: FanEmptyState(
                                  icon: Icons.collections_bookmark_outlined,
                                  title: _workMode != 'ALL'
                                      ? '没有符合条件的卡册'
                                      : _q.isNotEmpty
                                      ? '没有找到相关相册'
                                      : _favorites
                                      ? '还没有收藏相册'
                                      : widget.embedded && _drafts
                                      ? '还没有草稿'
                                      : widget.userId != null
                                      ? 'TA 还没有公开相册'
                                      : '你的第一本数字小卡册，等待被填满。',
                                  message: _workMode != 'ALL'
                                      ? '试试其他类型，或清除筛选。'
                                      : _q.isNotEmpty
                                      ? '试试其他相册名称。'
                                      : _favorites
                                      ? '浏览他人的公开作品后，可以收藏到这里。'
                                      : '仅引用官方图鉴小卡，不会自动加入 Owned。',
                                  actionLabel: _workMode != 'ALL'
                                      ? '清除筛选'
                                      : widget.userId == null &&
                                            !_favorites &&
                                            !widget.profileMode
                                      ? '创建相册'
                                      : null,
                                  onAction: _workMode != 'ALL'
                                      ? _clearFilters
                                      : _create,
                                ),
                              ),
                            ],
                          )
                        : (widget.profileMode || _view == 'LIST')
                        ? ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                            itemCount: _albums.length + 1,
                            itemBuilder: (context, i) => i == _albums.length
                                ? _footer()
                                : _listTile(_albums[i], resources),
                          )
                        : LayoutBuilder(
                            builder: (context, c) {
                              final cols = c.maxWidth >= 600 ? 3 : 2;
                              return ListView.builder(
                                controller: _scroll,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: (_albums.length / cols).ceil() + 1,
                                itemBuilder: (context, row) {
                                  if (row == (_albums.length / cols).ceil()) {
                                    return _footer();
                                  }
                                  return Container(
                                    decoration: albumDecoration({
                                      ...theme,
                                      'type': theme['image_url'] == null
                                          ? 'GRADIENT'
                                          : 'IMAGE',
                                    }, radius: 0),
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      12,
                                      20,
                                      0,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (int col = 0; col < cols; col++)
                                              Expanded(
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    left: col == 0 ? 0 : 12,
                                                  ),
                                                  child:
                                                      row * cols + col <
                                                          _albums.length
                                                      ? _shelfTile(
                                                          _albums[row * cols +
                                                              col],
                                                          resources,
                                                          theme,
                                                        )
                                                      : const SizedBox(),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ),
              if (!widget.profileMode &&
                  widget.userId == null &&
                  (widget.embedded || !_favorites))
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    heroTag: null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    tooltip: '创建相册',
                    backgroundColor: FanColors.lavender,
                    onPressed: _create,
                    child: const AlbumIcon(
                      'Plus',
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.all(12),
    child: _more
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? TextButton(
            onPressed: () => _load(more: _failedMore),
            child: const Text('加载失败，点击重试'),
          )
        : const SizedBox(height: 12),
  );
  Widget _listTile(PhotocardAlbum album, List<AlbumJson> resources) => ListTile(
    key: ValueKey('album-list-${album.id}'),
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
    minTileHeight: 80,
    horizontalTitleGap: 12,
    onTap: () => _open(album),
    onLongPress: () => _menu(album),
    leading: SizedBox(
      width: 56,
      height: 56,
      child: album.unavailable
          ? const AlbumIcon('CircleOff')
          : AlbumCoverWidget(album, resources: resources),
    ),
    title: Text(
      album.name,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${album.cardCount} 张小卡${album.opensAsCards ? ' · 卡片作品' : ' · ${album.pageCount} 页'}${album.isDraft ? ' · 草稿' : ''}${album.isModerated ? ' · ${album.moderationLabel}' : ''}${!album.isPublic ? ' · 私密' : ''}',
        style: const TextStyle(fontSize: 13, color: FanColors.textSecondary),
      ),
    ),
    trailing: IconButton(
      tooltip: '相册操作',
      icon: const AlbumIcon('Ellipsis'),
      onPressed: () => _menu(album),
    ),
  );
  Widget _shelfTile(
    PhotocardAlbum album,
    List<AlbumJson> resources,
    AlbumJson theme,
  ) => GestureDetector(
    key: ValueKey('album-shelf-${album.id}'),
    onTap: () => _open(album),
    onLongPress: () => _menu(album),
    child: Column(
      children: [
        Container(
          height: 185,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F1EC),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: album.unavailable
                ? const AlbumIcon('CircleOff', size: 44)
                : AlbumCoverWidget(album, resources: resources),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    width: 44,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: '相册操作',
                      onPressed: () => _menu(album),
                      icon: const AlbumIcon('Ellipsis', size: 18),
                    ),
                  ),
                ],
              ),
              Text(
                '${album.cardCount} 张${album.opensAsCards ? ' · 卡片作品' : ' · ${album.pageCount} 页'}${album.isDraft ? ' · 草稿' : ''}${album.isModerated ? ' · ${album.moderationLabel}' : ''}${!album.isPublic ? ' · 私密' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> showAlbumQuotaDialog(
  BuildContext context,
  AlbumQuota quota, {
  bool pages = false,
}) async => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    icon: const AlbumIcon('Crown', size: 40, color: FanColors.lavender),
    title: Text(pages ? '页面数量已达上限' : '相册数量已达上限'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '当前最多${pages ? '创建 ${quota.maxPages} 页' : '创建 ${quota.maxAlbums} 本相册'}。现有作品会保留，不会影响收藏。',
        ),
        const SizedBox(height: 16),
        Text(
          '普通用户：${quota.normalAlbums} 本 / ${quota.normalPages} 页\nPRO：${quota.proAlbums} 本 / ${quota.proPages} 页',
        ),
        const SizedBox(height: 12),
        const Text(
          '会员购买服务暂未接入，本页仅展示权益。',
          style: TextStyle(color: FanColors.textSecondary, fontSize: 12),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);

class AlbumCreatePage extends ConsumerStatefulWidget {
  const AlbumCreatePage({super.key});
  @override
  ConsumerState<AlbumCreatePage> createState() => _AlbumCreatePageState();
}

class _AlbumCreatePageState extends ConsumerState<AlbumCreatePage> {
  final _name = TextEditingController(text: '我的小卡册');
  String _display = 'SINGLE';
  String _mode = 'BOOK';
  bool _configured = false;
  final _description = TextEditingController();
  final _requestId = albumId('create');
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!ref.read(sessionProvider).isLoggedIn) {
      await context.push('/login');
      return;
    }
    if (_name.text.trim().isEmpty) {
      showFanToast(context, '请填写相册名称');
      return;
    }
    setState(() => _busy = true);
    try {
      final album = await ref
          .read(albumRepositoryProvider)
          .create(
            _name.text.trim(),
            _display,
            // No style picker: book pages have fixed pockets, cards stay plain.
            _mode == 'BOOK' ? 'REALISTIC' : 'MINIMAL',
            mode: _mode,
            description: _description.text.trim(),
            requestId: _requestId,
          );
      if (mounted) context.pushReplacement('/digital-albums/${album.id}/edit');
    } catch (e) {
      if (mounted) showFanToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => !_configured
      ? Scaffold(
          appBar: AppBar(title: const Text('选择作品类型')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '创建后无法更换模式。你可以分别创建相册作品和卡片作品。',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                for (final mode in ['BOOK', 'CARDS']) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              mode == 'BOOK'
                                  ? Icons.menu_book_outlined
                                  : Icons.style_outlined,
                            ),
                            title: Text(mode == 'BOOK' ? '相册作品' : '卡片作品'),
                            subtitle: Text(
                              mode == 'BOOK'
                                  ? '自由设计封面，按页整理小卡，单面或双面翻阅。'
                                  : '小卡独立排序，滑动聚焦，轻点放大与翻面。',
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final selected = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            AlbumExamplePage(mode: mode),
                                      ),
                                    );
                                    if (mounted && selected == true) {
                                      setState(() {
                                        _mode = mode;
                                        _configured = true;
                                      });
                                    }
                                  },
                                  child: const Text('预览效果'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => setState(() {
                                    _mode = mode;
                                    _configured = true;
                                  }),
                                  child: const Text('选择此模式'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  '预览为独立示例，不创建作品、不占额度。',
                  style: TextStyle(color: FanColors.textSecondary),
                ),
              ],
            ),
          ),
        )
      : Scaffold(
          appBar: AppBar(
            title: const Text('配置新作品'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _busy
                  ? null
                  : () => setState(() => _configured = false),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Center(
                  child: SizedBox(
                    height: 145,
                    width: 112,
                    child: AlbumCanvasWidget(
                      config: albumCanvas(),
                      album: PhotocardAlbum({
                        'id': 'preview',
                        'name': _name.text,
                      }),
                      showName: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '相册名称',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  maxLength: 50,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                Text(_mode == 'BOOK' ? '相册作品 · 创建后不可更换' : '卡片作品 · 创建后不可更换'),
                const SizedBox(height: 8),
                Text(
                  _mode == 'CARDS' ? '从空作品开始，可添加小卡并设置主图。' : '从空封面开始，支持自定义内页。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: FanColors.textSecondary,
                  ),
                ),
                if (_mode == 'BOOK') ...[
                  const SizedBox(height: 24),
                  const Text(
                    '展示方式',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    key: const Key('album-display-mode'),
                    segments: const [
                      ButtonSegment(
                        value: 'SINGLE',
                        icon: Icon(Icons.book_outlined),
                        label: Text('单面'),
                      ),
                      ButtonSegment(
                        value: 'DOUBLE',
                        icon: Icon(Icons.menu_book_outlined),
                        label: Text('双面'),
                      ),
                    ],
                    selected: {_display},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) =>
                              setState(() => _display = selection.first),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _description,
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '收藏故事（选填）'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: Text(_busy ? '创建中…' : '创建相册'),
                ),
                const SizedBox(height: 10),
                const Text(
                  '默认私密 · 不改变小卡拥有状态',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: FanColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
}

import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
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
  const AlbumShelfBody({super.key, this.userId, this.showTitle = true});
  final String? userId;
  final bool showTitle;
  @override
  ConsumerState<AlbumShelfBody> createState() => _AlbumShelfBodyState();
}

class _AlbumShelfBodyState extends ConsumerState<AlbumShelfBody> {
  List<PhotocardAlbum> _albums = [];
  AlbumQuota? _quota;
  String _q = '', _sort = 'updated', _theme = 'cream-white', _view = 'SHELF';
  bool _favorites = false,
      _loading = true,
      _more = false,
      _preferencesLoaded = false;
  String? _error;
  int? _next;
  int _request = 0;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant AlbumShelfBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_more || _next == null)) return;
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
      final result = await ref
          .read(albumRepositoryProvider)
          .list(
            q: _q,
            sort: _sort,
            offset: more ? _next! : 0,
            favorites: _favorites,
            userId: widget.userId,
          );
      if (!mounted || request != _request) return;
      if (widget.userId == null) ref.invalidate(albumQuotaProvider);
      setState(() {
        _albums = more ? [..._albums, ...result.albums] : result.albums;
        _next = result.nextOffset;
        _quota = result.quota ?? _quota;
        if (!_preferencesLoaded) {
          _theme = result.theme;
          _view = result.viewMode;
          _preferencesLoaded = true;
        }
      });
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _open(PhotocardAlbum album) async {
    if (album.unavailable) {
      showFanToast(context, '原作者已设为私密、删除或作品暂不可访问');
      return;
    }
    await context.push(
      '/digital-albums/${album.id}${album.isOwner && album.isDraft ? '/edit' : ''}',
    );
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
            if (!album.unavailable)
              ListTile(
                leading: const AlbumIcon('BookOpen'),
                title: const Text('查看相册'),
                onTap: () => Navigator.pop(context, 'view'),
              ),
            if (album.isOwner) ...[
              for (final item in [
                ('edit', '编辑相册', 'Type'),
                ('rename', '重命名', 'Type'),
                ('visibility', '修改可见性', 'Heart'),
                ('duplicate', '复制相册', 'BookCopy'),
                ('delete', '删除相册', 'Trash2'),
              ])
                ListTile(
                  leading: AlbumIcon(item.$3),
                  title: Text(item.$2),
                  onTap: () => Navigator.pop(context, item.$1),
                ),
            ] else if (_favorites)
              ListTile(
                leading: const AlbumIcon('Heart'),
                title: const Text('取消收藏相册'),
                onTap: () => Navigator.pop(context, 'unfavorite'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      final repo = ref.read(albumRepositoryProvider);
      if (action == 'view') {
        await _open(album);
        return;
      }
      if (action == 'edit') {
        await context.push('/digital-albums/${album.id}/edit');
      }
      if (action == 'unfavorite') await repo.react(album.id, 'favorite', false);
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
            (d) => d['visibility'] = current.isPublic ? 'PRIVATE' : 'PUBLIC',
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
    setState(() => _view = value);
    if (widget.userId == null) {
      try {
        await ref.read(albumRepositoryProvider).preferences(_theme, _view);
      } catch (e) {
        if (mounted) showFanToast(context, e.toString());
      }
    }
  }

  Future<void> _themes(List<AlbumJson> resources) async {
    final themes = resources.where((r) => r['kind'] == 'SHELF').toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '书架主题',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final t in themes)
                    InkWell(
                      onTap: () => Navigator.pop(context, t['id'] as String),
                      child: SizedBox(
                        width: 94,
                        child: Column(
                          children: [
                            Container(
                              height: 92,
                              decoration: albumDecoration({
                                'colors': (t['config'] as AlbumJson)['colors'],
                                'type': 'GRADIENT',
                                'angle': 90,
                              }),
                              child: Center(
                                child: AlbumIcon(
                                  'Book',
                                  size: 38,
                                  color: t['id'] == _theme
                                      ? FanColors.lavender
                                      : FanColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(t['name'] as String),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _theme = selected);
      try {
        await ref.read(albumRepositoryProvider).preferences(_theme, _view);
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
    final theme = matching.isEmpty
        ? {
            'colors': ['#F4EEE7', '#FFFFFF'],
            'ledge': '#DAD0C5',
          }
        : matching.first['config'] as AlbumJson;
    return Column(
      children: [
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
                onPressed: () => _setView(_view == 'SHELF' ? 'LIST' : 'SHELF'),
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
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              if (widget.userId == null) ...[
                ChoiceChip(
                  label: const Text('我创建的'),
                  selected: !_favorites,
                  onSelected: (_) {
                    setState(() => _favorites = false);
                    _load();
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('我收藏的'),
                  selected: _favorites,
                  onSelected: (_) {
                    setState(() => _favorites = true);
                    _load();
                  },
                ),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                initialValue: _sort,
                tooltip: '排序',
                onSelected: (s) {
                  setState(() => _sort = s);
                  _load();
                },
                itemBuilder: (_) => [
                  for (final s in [
                    ('updated', '最近更新'),
                    ('created', '最近创建'),
                    ('name', '名称'),
                  ])
                    PopupMenuItem(value: s.$1, child: Text(s.$2)),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: AlbumIcon('GripVertical', size: 18),
                ),
              ),
            ],
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
                        _next != null) {
                      _load(more: true);
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _albums.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 290,
                                child: FanEmptyState(
                                  icon: Icons.collections_bookmark_outlined,
                                  title: _q.isNotEmpty
                                      ? '没有找到相关相册'
                                      : _favorites
                                      ? '还没有收藏相册'
                                      : widget.userId != null
                                      ? 'TA 还没有公开相册'
                                      : '你的第一本数字小卡册，等待被填满。',
                                  message: _q.isNotEmpty
                                      ? '试试其他相册名称。'
                                      : _favorites
                                      ? '浏览他人的公开作品后，可以收藏到这里。'
                                      : '仅引用官方图鉴小卡，不会自动加入 Owned。',
                                  actionLabel:
                                      widget.userId == null && !_favorites
                                      ? '创建相册'
                                      : null,
                                  onAction: _create,
                                ),
                              ),
                            ],
                          )
                        : _view == 'LIST'
                        ? ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: _albums.length + 1,
                            itemBuilder: (context, i) => i == _albums.length
                                ? _footer()
                                : _listTile(_albums[i], resources),
                          )
                        : LayoutBuilder(
                            builder: (context, c) {
                              final cols = c.maxWidth >= 600 ? 3 : 2;
                              return ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: (_albums.length / cols).ceil() + 1,
                                itemBuilder: (context, row) {
                                  if (row == (_albums.length / cols).ceil()) {
                                    return _footer();
                                  }
                                  return Container(
                                    color: albumColor(
                                      (theme['colors'] as List).first as String,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
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
                                        Container(
                                          height: 10,
                                          margin: const EdgeInsets.only(
                                            top: 8,
                                            bottom: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: albumColor(
                                              theme['ledge'] as String,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x20866645),
                                                blurRadius: 5,
                                                offset: Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ),
              if (widget.userId == null && !_favorites)
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
            onPressed: () => _load(more: true),
            child: const Text('加载失败，点击重试'),
          )
        : const SizedBox(height: 12),
  );
  Widget _listTile(PhotocardAlbum album, List<AlbumJson> resources) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 10),
    onTap: () => _open(album),
    onLongPress: () => _menu(album),
    leading: SizedBox(
      width: 62,
      child: album.unavailable
          ? const AlbumIcon('CircleOff')
          : AlbumCoverWidget(album, resources: resources),
    ),
    title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${album.cardCount} 张小卡 · ${album.pageCount} 页${album.isDraft ? ' · 草稿' : ''}${!album.isPublic ? ' · 私密' : ''}',
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
    onTap: () => _open(album),
    onLongPress: () => _menu(album),
    child: Column(
      children: [
        Container(
          height: 185,
          padding: const EdgeInsets.all(10),
          decoration: albumDecoration({
            'colors': theme['colors'],
            'type': 'GRADIENT',
            'angle': 90,
          }, radius: 0),
          child: Center(
            child: album.unavailable
                ? const AlbumIcon('CircleOff', size: 44)
                : AlbumCoverWidget(album, resources: resources),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(12),
          ),
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
                    height: 24,
                    width: 28,
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
                '${album.cardCount} 张 · ${album.pageCount} 页${album.isDraft ? ' · 草稿' : ''}${!album.isPublic ? ' · 私密' : ''}',
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
  String _display = 'SINGLE', _style = 'REALISTIC';
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
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
          .create(_name.text.trim(), _display, _style);
      if (mounted) context.pushReplacement('/digital-albums/${album.id}/edit');
    } catch (e) {
      if (mounted) showFanToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新建相册')),
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
                album: PhotocardAlbum({'id': 'preview', 'name': _name.text}),
                showName: true,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '相册名称',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 50,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          const Text(
            '展示方式',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final option in [
                ('SINGLE', '单面翻页', 'Book'),
                ('DOUBLE', '双面翻页', 'BookOpen1'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => setState(() => _display = option.$1),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _display == option.$1
                              ? FanColors.lavenderSoft
                              : const Color(0xFFF0F0F7),
                          border: Border.all(
                            color: _display == option.$1
                                ? FanColors.lavender
                                : FanColors.line,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            AlbumIcon(
                              option.$3,
                              size: 34,
                              color: _display == option.$1
                                  ? FanColors.lavender
                                  : FanColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              option.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '视觉风格',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'REALISTIC',
                label: Text('真实卡册'),
                icon: AlbumIcon('BookOpen'),
              ),
              ButtonSegment(
                value: 'MINIMAL',
                label: Text('极简数字'),
                icon: AlbumIcon('Scan'),
              ),
            ],
            selected: {_style},
            onSelectionChanged: (s) => setState(() => _style = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: Text(_busy ? '创建中…' : '创建相册'),
          ),
          const SizedBox(height: 10),
          const Text(
            '默认私密 · 允许空相册 · 不自动增加 Owned',
            textAlign: TextAlign.center,
            style: TextStyle(color: FanColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

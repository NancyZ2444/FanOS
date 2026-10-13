import 'dart:async';
import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/presentation/album_input_scope.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AlbumViewerPage extends ConsumerWidget {
  const AlbumViewerPage({
    super.key,
    required this.albumId,
    this.previewAlbum,
    this.initialPage = 0,
  });
  final String albumId;
  final PhotocardAlbum? previewAlbum;
  final int initialPage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (previewAlbum != null) {
      return AlbumViewer(
        album: previewAlbum!,
        preview: true,
        initialPage: initialPage,
      );
    }
    return ref
        .watch(albumDetailProvider(albumId))
        .when(
          loading: () => Scaffold(
            appBar: AppBar(title: const Text('相册')),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: const Text('相册')),
            body: FanEmptyState(
              icon: Icons.lock_outline,
              title: '相册暂不可访问',
              message: e.toString(),
              actionLabel: '重新加载',
              onAction: () => ref.invalidate(albumDetailProvider(albumId)),
            ),
          ),
          data: (album) => AlbumViewer(album: album, initialPage: initialPage),
        );
  }
}

class AlbumViewer extends ConsumerStatefulWidget {
  const AlbumViewer({
    super.key,
    required this.album,
    this.preview = false,
    this.initialPage = 0,
  });
  final PhotocardAlbum album;
  final bool preview;
  final int initialPage;
  @override
  ConsumerState<AlbumViewer> createState() => _AlbumViewerState();
}

class _AlbumViewerState extends ConsumerState<AlbumViewer> {
  bool _cards = false, _turning = false, _reacting = false;
  late int _page;
  int _focus = 0;
  double _drag = 0;
  Timer? _flipTimer;
  PageController? _carousel;
  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _carousel?.dispose();
    super.dispose();
  }

  int get _bookSteps =>
      1 + (widget.album.pages.length / (widget.album.isDouble ? 2 : 1)).ceil();
  void _flip(int step) {
    final next = (_page + step).clamp(0, _bookSteps - 1);
    if (_turning || next == _page) return;
    setState(() {
      _page = next;
      _turning = true;
    });
    _flipTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _turning = false);
    });
  }

  void _mode(bool cards) {
    if (cards && _carousel == null) {
      final slots = widget.album.orderedSlots;
      final featured = widget.album.cardView['featured_slot_id'];
      _focus = math.max(0, slots.indexWhere((s) => s['id'] == featured));
      _carousel = PageController(viewportFraction: .60, initialPage: _focus);
    }
    setState(() => _cards = cards);
  }

  Future<void> _contents() async {
    final album = widget.album;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const AlbumIcon('Book'),
              title: const Text('封面'),
              onTap: () => Navigator.pop(context, 0),
            ),
            for (int i = 0; i < album.pages.length; i++)
              ListTile(
                leading: const AlbumIcon('BookOpen'),
                title: Text('第 ${i + 1} 页'),
                subtitle: Text(
                  '${(album.pages[i]['slots'] as List).where((s) => s['card_id'] != null).length} 张小卡',
                ),
                onTap: () =>
                    Navigator.pop(context, 1 + i ~/ (album.isDouble ? 2 : 1)),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        _page = chosen;
        _cards = false;
      });
    }
  }

  Future<void> _reaction(String kind, bool active) async {
    if (!ref.read(sessionProvider).isLoggedIn) {
      await context.push('/login');
      return;
    }
    setState(() => _reacting = true);
    try {
      await ref
          .read(albumRepositoryProvider)
          .react(widget.album.id, kind, active);
      ref.invalidate(albumDetailProvider(widget.album.id));
    } catch (e) {
      if (mounted) showFanToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
  }

  Future<void> _share() async {
    if (!widget.album.isPublic) {
      showFanToast(context, '私密相册链接仍仅创建者可访问');
    }
    await Clipboard.setData(
      ClipboardData(
        text:
            '${widget.album.name}\nfanos://app/digital-albums/${widget.album.id}',
      ),
    );
    if (mounted) showFanToast(context, '相册链接已复制');
  }

  Future<void> _actions() async {
    final album = widget.album;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (album.isOwner)
              ListTile(
                leading: const AlbumIcon('Type'),
                title: const Text('编辑相册'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (album.isOwner)
              ListTile(
                leading: const AlbumIcon('GripVertical'),
                title: const Text('调整轮播顺序与关键卡面'),
                onTap: () => Navigator.pop(context, 'order'),
              ),
            if (album.isOwner)
              ListTile(
                leading: const AlbumIcon('LayoutGrid'),
                title: const Text('相册设置'),
                onTap: () => Navigator.pop(context, 'settings'),
              ),
            ListTile(
              leading: const AlbumIcon('Share'),
              title: const Text('分享相册链接'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            if (!album.isOwner)
              ListTile(
                leading: const AlbumIcon('CircleOff'),
                title: const Text('举报相册'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (['edit', 'order', 'settings'].contains(action)) {
      await context.push(
        '/digital-albums/${album.id}/edit${action == 'edit' ? '' : '?panel=$action'}',
      );
      ref.invalidate(albumDetailProvider(album.id));
    }
    if (action == 'share') await _share();
    if (action == 'report') {
      if (!mounted) return;
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => AlbumInputScope(
          initialValues: const {'reason': ''},
          builder: (context, inputs) {
            final controller = inputs['reason']!;
            return AlertDialog(
              title: const Text('举报相册'),
              content: TextField(
                controller: controller,
                maxLength: 200,
                decoration: const InputDecoration(hintText: '请说明需要运营复核的问题'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('提交'),
                ),
              ],
            );
          },
        ),
      );
      if (reason != null && reason.isNotEmpty && mounted) {
        try {
          await ref.read(albumRepositoryProvider).report(album.id, reason);
          if (mounted) showFanToast(context, '举报已提交运营复核');
        } catch (e) {
          if (mounted) showFanToast(context, e.toString());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final resources = ref.watch(albumResourcesProvider).value ?? <AlbumJson>[];
    final firstSlot = album.orderedSlots.isEmpty
        ? null
        : album.orderedSlots[_focus.clamp(0, album.orderedSlots.length - 1)];
    final focused = album.card(firstSlot?['card_id'] as String?);
    return Scaffold(
      backgroundColor: const Color(0xFFF1EEFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.preview ? '相册预览' : album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!widget.preview)
            IconButton(
              tooltip: '相册操作',
              onPressed: _actions,
              icon: const AlbumIcon('Ellipsis'),
            ),
        ],
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: _cards
              ? albumDecoration(
                  album.cardView['background'] as AlbumJson?,
                  radius: 0,
                )
              : const BoxDecoration(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('相册模式'),
                            icon: AlbumIcon('BookOpen', size: 18),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('卡片模式'),
                            icon: AlbumIcon('RectangleVertical', size: 18),
                          ),
                        ],
                        selected: {_cards},
                        onSelectionChanged: (s) => _mode(s.first),
                      ),
                    ),
                  ],
                ),
              ),
              if (!album.isOwner && !widget.preview)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: InkWell(
                    onTap: () => context.push('/user/${album.json['user_id']}'),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 6),
                        Text(album.json['author_name'] as String? ?? '创建者'),
                        const Spacer(),
                        const Text('查看主页', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _cards ? _cardCarousel(album) : _book(album, resources),
              ),
              if (_cards)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        focused?.displayTitle ??
                            (album.occupiedSlots.isEmpty ? '还没有小卡' : '小卡暂不可用'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text(focused?.source ?? '仅引用官方图鉴')),
                          Text(
                            album.orderedSlots.isEmpty
                                ? '0 / 0'
                                : '${_focus + 1} / ${album.orderedSlots.length}',
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: '下一张',
                            onPressed:
                                album.orderedSlots.isEmpty ||
                                    _focus >= album.orderedSlots.length - 1
                                ? null
                                : () => _carousel!.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                  ),
                            icon: const AlbumIcon('ChevronRight'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton.filledTonal(
                        tooltip: '上一页',
                        onPressed: _page == 0 ? null : () => _flip(-1),
                        icon: const AlbumIcon('ChevronLeft'),
                      ),
                      TextButton(
                        onPressed: _contents,
                        child: Text(
                          _page == 0
                              ? '封面 · ${album.pageCount} 页'
                              : album.isDouble
                              ? '${(_page - 1) * 2 + 1}–${math.min(_page * 2, album.pageCount)} / ${album.pageCount}'
                              : '$_page / ${album.pageCount}',
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: '下一页',
                        onPressed: _page >= _bookSteps - 1
                            ? null
                            : () => _flip(1),
                        icon: const AlbumIcon('ChevronRight'),
                      ),
                    ],
                  ),
                ),
              if (widget.preview)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回编辑'),
                  ),
                )
              else if (album.isOwner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: OutlinedButton.icon(
                    onPressed: _actions,
                    icon: const AlbumIcon('Type', size: 18),
                    label: const Text('编辑与展示设置'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _reacting
                            ? null
                            : () => _reaction('like', !album.liked),
                        icon: AlbumIcon(
                          'Heart',
                          color: album.liked
                              ? FanColors.lavender
                              : FanColors.ink,
                        ),
                        label: Text('${album.likeCount}'),
                      ),
                      TextButton.icon(
                        onPressed: _reacting
                            ? null
                            : () => _reaction('favorite', !album.favorited),
                        icon: AlbumIcon(
                          'BookCopy',
                          color: album.favorited
                              ? FanColors.lavender
                              : FanColors.ink,
                        ),
                        label: Text(album.favorited ? '已收藏相册' : '收藏相册'),
                      ),
                      IconButton(
                        tooltip: '分享链接',
                        onPressed: _share,
                        icon: const AlbumIcon('Share'),
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

  Widget _book(PhotocardAlbum album, List<AlbumJson> resources) =>
      GestureDetector(
        onHorizontalDragStart: (_) => _drag = 0,
        onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
        onHorizontalDragEnd: (d) {
          if (_drag.abs() > MediaQuery.sizeOf(context).width * .15 ||
              d.primaryVelocity!.abs() > 250) {
            _flip(_drag < 0 ? 1 : -1);
          }
        },
        child: LayoutBuilder(
          builder: (context, c) {
            Widget body;
            if (_page == 0) {
              body = SizedBox(
                width: math.min(242, c.maxWidth * .7),
                height: math.min(354, c.maxHeight * .85),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.rotate(
                      angle: -.08,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1C9FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    AlbumCoverWidget(album, resources: resources),
                  ],
                ),
              );
            } else {
              final index = (_page - 1) * (album.isDouble ? 2 : 1);
              final width = math.min(c.maxWidth - 32, 620.0),
                  height = math.min(
                    c.maxHeight * .9,
                    width * (album.isDouble ? .64 : 1.25),
                  );
              body = SizedBox(
                width: width,
                height: height,
                child: Row(
                  children: [
                    for (int side = 0; side < (album.isDouble ? 2 : 1); side++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: side == 0 ? 0 : 3),
                          child: index + side >= album.pages.length
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .45),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                )
                              : Transform(
                                  alignment: Alignment.centerLeft,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, .001)
                                    ..rotateY(album.realistic ? .018 : 0),
                                  child: AlbumBinderWidget(
                                    album: album,
                                    page: album.pages[index + side],
                                    resources: resources,
                                    showBinding: side == 0,
                                    onTapSlot: (s) {
                                      if (s['card_id'] != null) {
                                        showAlbumCardPreview(
                                          context,
                                          album.card(s['card_id'] as String),
                                        );
                                      }
                                    },
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              );
            }
            return Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => Opacity(
                    opacity: animation.value,
                    child: Transform(
                      alignment: Alignment.centerLeft,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .001)
                        ..rotateY((1 - animation.value) * -.9),
                      child: child,
                    ),
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey('${album.isDouble}-$_page'),
                  child: body,
                ),
              ),
            );
          },
        ),
      );
  Widget _cardCarousel(PhotocardAlbum album) {
    final slots = album.orderedSlots;
    if (slots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 200, child: AlbumCoverWidget(album)),
            const SizedBox(height: 20),
            const Text('还没有小卡，先去添加你的第一张吧。'),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) => Center(
        child: SizedBox(
          height: math.min(c.maxHeight * .80, 400),
          child: PageView.builder(
            controller: _carousel,
            onPageChanged: (index) => setState(() => _focus = index),
            itemCount: slots.length,
            itemBuilder: (context, index) => AnimatedBuilder(
              animation: _carousel!,
              builder: (context, _) {
                final current =
                    _carousel!.hasClients &&
                        _carousel!.position.hasContentDimensions
                    ? _carousel!.page ?? _focus.toDouble()
                    : _focus.toDouble();
                final distance = (index - current).clamp(-2.0, 2.0);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .001)
                    ..translateByDouble(0, distance.abs() * 18, 0, 1)
                    ..rotateY(distance * -.16)
                    ..rotateZ(distance * .04)
                    ..scaleByDouble(
                      1 - distance.abs() * .12,
                      1 - distance.abs() * .12,
                      1,
                      1,
                    ),
                  child: GestureDetector(
                    onTap: () {
                      if (index != _focus) {
                        _carousel!.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      } else {
                        showAlbumCardPreview(
                          context,
                          album.card(slots[index]['card_id'] as String),
                        );
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withValues(alpha: .5),
                        boxShadow: [
                          BoxShadow(
                            color: FanColors.ink.withValues(alpha: .14),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AlbumCardImage(
                          album.card(slots[index]['card_id'] as String),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/presentation/album_input_scope.dart';
import 'package:fan_os/features/albums/presentation/album_card_picker.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AlbumEditorPage extends ConsumerStatefulWidget {
  const AlbumEditorPage({super.key, required this.albumId, this.initialPanel});
  final String albumId;
  final String? initialPanel;
  @override
  ConsumerState<AlbumEditorPage> createState() => _AlbumEditorPageState();
}

class _AlbumEditorPageState extends ConsumerState<AlbumEditorPage> {
  late AlbumEditorController _controller;
  int _page = 0;
  String? _element, _slot;
  bool _finishing = false;
  bool _allowPop = false;
  bool _leaving = false;
  PhotocardAlbum get _album => _controller.album!;
  List<AlbumJson> get _resources =>
      ref.read(albumResourcesProvider).value ?? <AlbumJson>[];
  AlbumJson get _canvas => _page == 0
      ? _album.cover
      : _album.pages[_page - 1]['config'] as AlbumJson;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(albumEditorProvider(widget.albumId));
    Future.microtask(() async {
      await _controller.load();
      if (mounted && _controller.album != null) {
        if (widget.initialPanel == 'settings') _settings();
        if (widget.initialPanel == 'order') _cardOrder();
      }
    });
  }

  void _editCanvas(void Function(AlbumJson canvas) change, {String? group}) =>
      _controller.edit((d) {
        final canvas = _page == 0
            ? d['cover'] as AlbumJson
            : ((d['pages'] as List)[_page - 1] as AlbumJson)['config']
                  as AlbumJson;
        change(canvas);
      }, group: group);
  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    await _controller.retainDraft();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/digital-albums');
        }
      }
    });
  }

  Future<void> _finish() async {
    if (_album.name.trim().isEmpty) {
      showFanToast(context, '请填写相册名称');
      await _settings();
      return;
    }
    final pending = (_album.json['_pending_cards'] as List?) ?? [];
    if (pending.isNotEmpty) {
      if (!await confirmAlbumAction(
        context,
        '仍有 ${pending.length} 张待放置小卡',
        '这些小卡尚未放入页面。完成编辑会移除待放置记录，官方图鉴与 Owned 不受影响。',
        action: '确认移除并完成',
      )) {
        return;
      }
      _controller.edit((d) => d.remove('_pending_cards'));
    }
    setState(() => _finishing = true);
    final result = await _controller.finish();
    if (!mounted) return;
    setState(() => _finishing = false);
    if (result != null) {
      ref.invalidate(albumDetailProvider(widget.albumId));
      context.pushReplacement('/digital-albums/${widget.albumId}');
    } else {
      showFanToast(context, _controller.error ?? '保存尚未完成，请重试');
    }
  }

  Future<void> _addPage({int? grid}) async {
    final quota = _controller.quota;
    if (quota == null) {
      showFanToast(context, '请联网获取相册额度后再添加页面');
      return;
    }
    if (_album.pages.length >= quota.maxPages) {
      await showAlbumQuotaDialog(context, quota, pages: true);
      return;
    }
    final count = grid ?? math.min(9, quota.maxSlots);
    final at = _page == 0 ? 0 : _page;
    _controller.edit(
      (d) => (d['pages'] as List).insert(at, blankAlbumPage(count)),
    );
    setState(() {
      _page = at + 1;
      _element = null;
      _slot = null;
    });
  }

  Future<void> _pick({String? slotId}) async {
    final isCover = _page == 0;
    final current = isCover
        ? null
        : (_album.pages[_page - 1]['slots'] as List)
              .cast<AlbumJson>()
              .where((s) => s['id'] == slotId)
              .firstOrNull;
    final selected = await pickAlbumCards(
      context,
      single: isCover || current?['card_id'] != null,
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    if (!isCover) {
      final existing = _album.occupiedSlots
          .where((s) => s['id'] != slotId)
          .map((s) => s['card_id'])
          .toSet();
      final repeated = selected.where((c) => existing.contains(c.id)).toList();
      if (repeated.isNotEmpty &&
          !await confirmAlbumAction(
            context,
            '该小卡已在本相册中',
            '${repeated.length} 张小卡已有放置记录，每次放置仍会独立计数。',
            action: '继续添加',
          )) {
        return;
      }
    }
    if (!mounted) return;
    _controller.edit((d) {
      final cards = (d['cards'] as AlbumJson?) ?? <String, dynamic>{};
      for (final c in selected) {
        cards[c.id] = albumCardJson(c);
      }
      d['cards'] = cards;
    });
    if (isCover) {
      _editCanvas((canvas) {
        final elements = (canvas['elements'] as List).cast<AlbumJson>();
        elements.removeWhere((e) => e['type'] == 'CARD');
        elements.add(
          _newElement(
            'CARD',
            selected.first.id,
            width: .68,
            height: .70,
            x: .16,
            y: .06,
          ),
        );
      });
    } else {
      await _placeCards(
        selected.map((c) => c.id).toList(),
        slotId: slotId,
        replace: current?['card_id'] != null,
      );
    }
  }

  Future<void> _placeCards(
    List<String> cards, {
    String? slotId,
    bool replace = false,
    bool fromPending = false,
  }) async {
    if (_page == 0) {
      await _addPage();
      if (_page == 0) return;
    }
    if (!mounted) return;
    final page = _album.pages[_page - 1];
    final slots = (page['slots'] as List).cast<AlbumJson>();
    final start = slotId == null
        ? 0
        : slots.indexWhere((s) => s['id'] == slotId);
    final empty = [
      for (int i = math.max(0, start); i < slots.length; i++)
        if (slots[i]['card_id'] == null || replace && slots[i]['id'] == slotId)
          slots[i]['id'] as String,
      for (int i = 0; i < math.max(0, start); i++)
        if (slots[i]['card_id'] == null) slots[i]['id'] as String,
    ];
    final overflow = math.max(0, cards.length - empty.length);
    bool addPages = false;
    if (overflow > 0) {
      final quota = _controller.quota;
      final requiredPages = (overflow / (quota?.maxSlots ?? 9)).ceil();
      final canAdd =
          quota != null &&
          _album.pages.length + requiredPages <= quota.maxPages;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('还有 $overflow 张小卡未放置'),
          content: Text(
            canAdd
                ? '可新增 $requiredPages 页继续放置，或将剩余小卡留在待放置区。'
                : '当前页数额度不足。剩余小卡会保存在待放置区，可调整其他页面后继续添加。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'partial'),
              child: const Text('仅填当前页'),
            ),
            if (canAdd)
              FilledButton(
                onPressed: () => Navigator.pop(context, 'pages'),
                child: const Text('继续添加页面'),
              ),
          ],
        ),
      );
      if (action == null || action == 'cancel' || !mounted) return;
      addPages = action == 'pages';
    }
    _controller.edit((d) {
      final pages = (d['pages'] as List).cast<AlbumJson>();
      final target = pages[_page - 1];
      final byId = {
        for (final s in (target['slots'] as List).cast<AlbumJson>()) s['id']: s,
      };
      int used = 0;
      for (final id in empty) {
        if (used >= cards.length) break;
        byId[id]!['card_id'] = cards[used++];
      }
      if (addPages) {
        int at = _page;
        while (used < cards.length) {
          final extra = blankAlbumPage(_controller.quota!.maxSlots);
          for (final s in (extra['slots'] as List).cast<AlbumJson>()) {
            if (used < cards.length) s['card_id'] = cards[used++];
          }
          pages.insert(at++, extra);
        }
      }
      final pending = ((d['_pending_cards'] as List?) ?? [])
          .cast<String>()
          .toList();
      if (fromPending) {
        for (int i = 0; i < used; i++) {
          pending.remove(cards[i]);
        }
      } else if (used < cards.length) {
        pending.addAll(cards.skip(used));
      }
      d['_pending_cards'] = pending;
    });
    setState(() => _slot = null);
  }

  AlbumJson _newElement(
    String type,
    String content, {
    double x = .15,
    double y = .3,
    double width = .55,
    double height = .14,
  }) => {
    'id': albumId('element'),
    'type': type,
    'content': content,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': 0.0,
    'z_index': (((_canvas['elements'] as List?)?.length ?? 0) + 1),
    'style': {
      'color': '#342A56',
      'font_size': type == 'TEXT' ? 24.0 : 48.0,
      'font_family': 'system',
      'bold': type == 'TEXT',
    },
  };
  Future<void> _text({AlbumJson? element}) async {
    final style = cloneAlbumJson(
      (element?['style'] as AlbumJson?) ??
          {
            'color': '#342A56',
            'font_size': 24.0,
            'font_family': 'system',
            'bold': true,
          },
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlbumInputScope(
        initialValues: {'text': element?['content'] as String? ?? ''},
        builder: (context, inputs) {
          final controller = inputs['text']!;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(element == null ? '添加文字' : '编辑文字'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '写下属于这本相册的心情',
                      ),
                    ),
                    Slider(
                      min: 8,
                      max: 96,
                      value: (style['font_size'] as num).toDouble(),
                      label: '${style['font_size']}',
                      onChanged: (v) =>
                          setDialogState(() => style['font_size'] = v),
                    ),
                    DropdownButton<String>(
                      value: style['font_family'] as String,
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('系统字体')),
                        DropdownMenuItem(value: 'serif', child: Text('衬线字体')),
                        DropdownMenuItem(
                          value: 'monospace',
                          child: Text('等宽字体'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => style['font_family'] = v),
                    ),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final hex in [
                          '#342A56',
                          '#FFFFFF',
                          '#8B7CFF',
                          '#FF7897',
                          '#161825',
                        ])
                          InkWell(
                            onTap: () =>
                                setDialogState(() => style['color'] = hex),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: albumColor(hex),
                              child: style['color'] == hex
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('加粗'),
                      value: style['bold'] == true,
                      onChanged: (v) => setDialogState(() => style['bold'] = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    _editCanvas((canvas) {
      final elements = (canvas['elements'] as List).cast<AlbumJson>();
      if (element == null) {
        elements.add(_newElement('TEXT', value)..['style'] = style);
      } else {
        final current = elements.firstWhere((e) => e['id'] == element['id']);
        current['content'] = value;
        current['style'] = style;
      }
    });
  }

  Future<void> _stickers({bool emoji = false}) async {
    final choices = emoji
        ? [
            for (final s in [
              '🎀',
              '💜',
              '✨',
              '🌸',
              '🫶',
              '🦋',
              '⭐',
              '🌙',
              '🍒',
              '☁️',
              '💎',
              '🌈',
            ])
              {'id': s, 'name': s, 'symbol': s},
          ]
        : [
            for (final r in _resources.where((r) => r['kind'] == 'STICKER'))
              {
                'id': r['id'],
                'name': r['name'],
                'symbol': (r['config'] as AlbumJson)['symbol'],
              },
          ];
    final choice = await showModalBottomSheet<AlbumJson>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final c in choices)
                InkWell(
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    width: 70,
                    height: 70,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FanColors.lavenderSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      c['symbol'] as String? ?? '✦',
                      style: const TextStyle(fontSize: 27),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice != null && mounted) {
      _editCanvas(
        (canvas) => (canvas['elements'] as List).add(
          _newElement(
            emoji ? 'EMOJI' : 'STICKER',
            choice['id'] as String,
            width: .25,
            height: .16,
          ),
        ),
      );
    }
  }

  Future<void> _background({bool cardView = false}) async {
    final original = cardView
        ? _album.cardView['background'] as AlbumJson
        : _canvas['background'] as AlbumJson;
    final result = await editAlbumBackground(context, original, _resources);
    if (result == null || !mounted) return;
    if (cardView) {
      _controller.edit(
        (d) => (d['card_view'] as AlbumJson)['background'] = result,
      );
    } else {
      _editCanvas((canvas) => canvas['background'] = result);
    }
  }

  Future<void> _layout() async {
    if (_page == 0) {
      await _addPage();
      return;
    }
    final quota = _controller.quota;
    final count = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (int i = 1; i <= (quota?.maxSlots ?? 9); i++)
                ChoiceChip(
                  label: Text('$i 格'),
                  selected: i == _album.pages[_page - 1]['grid_count'],
                  onSelected: (_) => Navigator.pop(context, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (count == null || !mounted) return;
    final old = (_album.pages[_page - 1]['slots'] as List).cast<AlbumJson>();
    final filled = old.where((s) => s['card_id'] != null).toList(),
        empty = old.where((s) => s['card_id'] == null).toList();
    final lost = math.max(0, filled.length - count);
    if (lost > 0 &&
        !await confirmAlbumAction(
          context,
          '新布局最多放置 $count 张',
          '超出的 $lost 张将移至待放置区，可继续放入其他页面。',
        )) {
      return;
    }
    _controller.edit((d) {
      final p = (d['pages'] as List)[_page - 1] as AlbumJson;
      final ordered = [...filled, ...empty];
      p['grid_count'] = count;
      p['slots'] = [
        ...ordered.take(count),
        for (int i = ordered.length; i < count; i++)
          {'id': albumId('slot'), 'card_id': null},
      ];
      final pending = ((d['_pending_cards'] as List?) ?? [])
          .cast<String>()
          .toList();
      pending.addAll(filled.skip(count).map((s) => s['card_id'] as String));
      d['_pending_cards'] = pending;
    });
    setState(() => _slot = null);
  }

  void _swap(String from, String to) => _controller.edit((d) {
    final slots = [
      for (final p in (d['pages'] as List).cast<AlbumJson>())
        ...(p['slots'] as List).cast<AlbumJson>(),
    ];
    final a = slots.firstWhere((s) => s['id'] == from),
        b = slots.firstWhere((s) => s['id'] == to);
    final card = a['card_id'];
    a['card_id'] = b['card_id'];
    b['card_id'] = card;
  });
  Future<void> _pages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '页面管理 · 长按拖动排序',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: .65,
                        ),
                    itemCount: _album.pages.length + 1,
                    itemBuilder: (context, i) {
                      if (i == _album.pages.length) {
                        return InkWell(
                          onTap: () => _addPage(),
                          child: const Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: AlbumIcon(
                                    'Plus',
                                    size: 34,
                                    color: FanColors.lavender,
                                  ),
                                ),
                              ),
                              Text('添加页面'),
                            ],
                          ),
                        );
                      }
                      final p = _album.pages[i];
                      final thumbnail = Column(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _page = i + 1;
                                  _element = null;
                                  _slot = null;
                                });
                                Navigator.pop(sheetContext);
                              },
                              child: AlbumBinderWidget(
                                album: _album,
                                page: p,
                                showBinding: false,
                                resources: _resources,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('第 ${i + 1} 页'),
                              PopupMenuButton<String>(
                                icon: const AlbumIcon('Ellipsis', size: 17),
                                onSelected: (action) async {
                                  if (action == 'delete' &&
                                      await confirmAlbumAction(
                                        this.context,
                                        '删除第 ${i + 1} 页？',
                                        '只移除页面与放置记录，不会影响小卡收藏。',
                                      )) {
                                    _controller.edit(
                                      (d) => (d['pages'] as List).removeWhere(
                                        (p) => p['id'] == _album.pages[i]['id'],
                                      ),
                                    );
                                    if (mounted) {
                                      setState(
                                        () => _page = _page.clamp(
                                          0,
                                          _album.pages.length,
                                        ),
                                      );
                                    }
                                  }
                                  if (action == 'copy') {
                                    final quota = _controller.quota;
                                    if (quota == null) return;
                                    if (_album.pages.length >= quota.maxPages) {
                                      if (mounted) {
                                        await showAlbumQuotaDialog(
                                          this.context,
                                          quota,
                                          pages: true,
                                        );
                                      }
                                      return;
                                    }
                                    _controller.edit((d) {
                                      final clone = cloneAlbumJson(p)
                                        ..['id'] = albumId('page');
                                      for (final s
                                          in (clone['slots'] as List)
                                              .cast<AlbumJson>()) {
                                        s['id'] = albumId('slot');
                                      }
                                      for (final e
                                          in ((clone['config']
                                                      as AlbumJson)['elements']
                                                  as List)
                                              .cast<AlbumJson>()) {
                                        e['id'] = albumId('element');
                                      }
                                      (d['pages'] as List).insert(i + 1, clone);
                                    });
                                  }
                                  if (!mounted) return;
                                  if (action == 'clear' &&
                                      await confirmAlbumAction(
                                        this.context,
                                        '清空本页小卡？',
                                        '保留页面、布局及装饰，不影响 Owned。',
                                      )) {
                                    _controller.edit((d) {
                                      for (final s
                                          in (((d['pages'] as List)[i]
                                                      as AlbumJson)['slots']
                                                  as List)
                                              .cast<AlbumJson>()) {
                                        s['card_id'] = null;
                                      }
                                    });
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'copy',
                                    child: Text('复制页面'),
                                  ),
                                  PopupMenuItem(
                                    value: 'clear',
                                    child: Text('清空小卡'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除页面'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      );
                      return DragTarget<String>(
                        onAcceptWithDetails: (details) => _controller.edit((d) {
                          final pages = (d['pages'] as List).cast<AlbumJson>();
                          final from = pages.indexWhere(
                            (p) => p['id'] == details.data,
                          );
                          if (from >= 0) {
                            final moved = pages.removeAt(from);
                            pages.insert(i, moved);
                          }
                        }),
                        builder: (context, candidates, rejected) =>
                            LongPressDraggable<String>(
                              data: p['id'] as String,
                              feedback: Material(
                                child: SizedBox(
                                  width: 90,
                                  height: 130,
                                  child: AlbumBinderWidget(
                                    album: _album,
                                    page: p,
                                    showBinding: false,
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: .3,
                                child: thumbnail,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: candidates.isEmpty
                                      ? null
                                      : Border.all(
                                          color: FanColors.lavender,
                                          width: 2,
                                        ),
                                ),
                                child: thumbnail,
                              ),
                            ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('完成页面管理'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => AlbumInputScope(
        initialValues: {'name': _album.name, 'description': _album.description},
        builder: (sheetContext, inputs) {
          final name = inputs['name']!, description = inputs['description']!;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '相册设置',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: name,
                        maxLength: 50,
                        decoration: const InputDecoration(labelText: '相册名称'),
                        onChanged: (v) => _controller.edit(
                          (d) => d['name'] = v,
                          group: 'name',
                        ),
                      ),
                      TextField(
                        controller: description,
                        maxLength: 200,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: '简介'),
                        onChanged: (v) => _controller.edit(
                          (d) => d['description'] = v,
                          group: 'description',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('公开相册'),
                        subtitle: const Text('草稿完成前不会公开，默认私密'),
                        value: _album.isPublic,
                        onChanged: (v) => _controller.edit(
                          (d) => d['visibility'] = v ? 'PUBLIC' : 'PRIVATE',
                        ),
                      ),
                      const Text('展示方式'),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'SINGLE', label: Text('单面')),
                          ButtonSegment(value: 'DOUBLE', label: Text('双面')),
                        ],
                        selected: {_album.isDouble ? 'DOUBLE' : 'SINGLE'},
                        onSelectionChanged: (s) => _controller.edit(
                          (d) => d['display_type'] = s.first,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '单双面只改变浏览编排，不新增页面或小卡。',
                          style: TextStyle(
                            fontSize: 12,
                            color: FanColors.textSecondary,
                          ),
                        ),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'REALISTIC',
                            label: Text('真实卡册'),
                          ),
                          ButtonSegment(value: 'MINIMAL', label: Text('极简数字')),
                        ],
                        selected: {_album.realistic ? 'REALISTIC' : 'MINIMAL'},
                        onSelectionChanged: (s) => _controller.edit(
                          (d) => d['visual_style'] = s.first,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('返回编辑'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _layers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 350,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final elements =
                  ((_canvas['elements'] as List?) ?? [])
                      .cast<AlbumJson>()
                      .toList()
                    ..sort(
                      (a, b) =>
                          (a['z_index'] as num).compareTo(b['z_index'] as num),
                    );
              return ReorderableListView(
                onReorderItem: (from, to) {
                  final e = elements.removeAt(from);
                  elements.insert(to, e);
                  _editCanvas((c) {
                    for (int i = 0; i < elements.length; i++) {
                      (c['elements'] as List).cast<AlbumJson>().firstWhere(
                        (e) => e['id'] == elements[i]['id'],
                      )['z_index'] = i;
                    }
                  });
                },
                children: [
                  for (final e in elements)
                    ListTile(
                      key: ValueKey(e['id']),
                      title: Text(
                        e['type'] == 'CARD' ? '封面小卡' : e['content'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('越靠下越在前景'),
                      leading: const AlbumIcon('GripVertical'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _cardOrder() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final slots = _album.orderedSlots;
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '轮播顺序 · 长按拖动，点击皇冠设置关键卡面',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView(
                      onReorderItem: (from, to) {
                        final ids = slots
                            .map((s) => s['id'] as String)
                            .toList();
                        ids.insert(to, ids.removeAt(from));
                        _controller.edit((d) {
                          final view = d['card_view'] as AlbumJson;
                          view['card_order'] = ids;
                          view['order_customized'] = true;
                        });
                      },
                      children: [
                        for (final s in slots)
                          ListTile(
                            key: ValueKey(s['id']),
                            leading: SizedBox(
                              width: 38,
                              child: AlbumCardImage(
                                _album.card(s['card_id'] as String),
                              ),
                            ),
                            title: Text(
                              _album
                                      .card(s['card_id'] as String)
                                      ?.displayTitle ??
                                  '小卡暂不可用',
                            ),
                            trailing: IconButton(
                              tooltip: '设为关键卡面',
                              onPressed: () => _controller.edit(
                                (d) =>
                                    (d['card_view']
                                            as AlbumJson)['featured_slot_id'] =
                                        _album.cardView['featured_slot_id'] ==
                                            s['id']
                                        ? null
                                        : s['id'],
                              ),
                              icon: AlbumIcon(
                                'Crown',
                                color:
                                    _album.cardView['featured_slot_id'] ==
                                        s['id']
                                    ? FanColors.lavender
                                    : FanColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _controller.edit(
                      (d) => (d['card_view'] as AlbumJson)['order_customized'] =
                          false,
                    ),
                    child: const Text('恢复页面与卡位默认顺序'),
                  ),
                  TextButton.icon(
                    onPressed: () => _background(cardView: true),
                    icon: const AlbumIcon('LayoutGrid'),
                    label: const Text('设置独立轮播背景'),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完成排序'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(albumEditorProvider(widget.albumId));
    final resources = ref.watch(albumResourcesProvider).value ?? <AlbumJson>[];
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _back();
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final album = _controller.album;
          if (_controller.loading || album == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('相册编辑')),
              body: _controller.loading
                  ? const Center(child: CircularProgressIndicator())
                  : FanEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '相册加载失败',
                      message: _controller.error ?? '',
                      actionLabel: '重新加载',
                      onAction: () => _controller.load(),
                    ),
            );
          }
          _page = _page.clamp(0, album.pages.length);
          final elements = ((_canvas['elements'] as List?) ?? [])
              .cast<AlbumJson>();
          final selected = elements
              .where((e) => e['id'] == _element)
              .firstOrNull;
          final pending = ((album.json['_pending_cards'] as List?) ?? [])
              .cast<String>();
          return Scaffold(
            backgroundColor: const Color(0xFFFAFAFF),
            appBar: AppBar(
              leading: IconButton(
                tooltip: '返回书架',
                onPressed: _back,
                icon: const AlbumIcon('ChevronLeft'),
              ),
              title: Text(_page == 0 ? '封面编辑' : '内页编辑'),
              actions: [
                TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: Text(_finishing ? '保存中' : '完成'),
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _controller.status,
                            style: TextStyle(
                              color: _controller.error == null
                                  ? FanColors.textSecondary
                                  : FanColors.coral,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (_controller.error != null || _controller.conflict)
                          TextButton(
                            onPressed: _controller.conflict
                                ? () async {
                                    if (await confirmAlbumAction(
                                      context,
                                      '加载服务器版本？',
                                      '本地未同步版本会保留为备份，不会覆盖服务器版本。',
                                    )) {
                                      await _controller.load(
                                        discardLocal: true,
                                      );
                                    }
                                  }
                                : _controller.save,
                            child: Text(_controller.conflict ? '重新加载' : '重试'),
                          ),
                        IconButton(
                          tooltip: '撤销',
                          onPressed: _controller.canUndo
                              ? _controller.undo
                              : null,
                          icon: const Icon(Icons.undo_rounded, size: 19),
                        ),
                        IconButton(
                          tooltip: '重做',
                          onPressed: _controller.canRedo
                              ? _controller.redo
                              : null,
                          icon: const Icon(Icons.redo_rounded, size: 19),
                        ),
                        IconButton(
                          tooltip: '预览相册',
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumViewerPage(
                                albumId: album.id,
                                previewAlbum: album,
                                initialPage: _page == 0
                                    ? 0
                                    : 1 +
                                          (_page - 1) ~/
                                              (album.isDouble ? 2 : 1),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                        ),
                      ],
                    ),
                  ),
                  if (pending.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${pending.length} 张小卡待放置',
                              style: const TextStyle(
                                color: FanColors.coral,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _placeCards(pending, fromPending: true),
                            child: const Text('放入当前页'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: LayoutBuilder(
                        builder: (context, c) => Center(
                          child: SizedBox(
                            width: math.min(_page == 0 ? 292 : 340, c.maxWidth),
                            height: math.min(
                              c.maxHeight,
                              _page == 0 ? 449 : 420,
                            ),
                            child: _page == 0
                                ? AlbumCanvasWidget(
                                    config: album.cover,
                                    album: album,
                                    showName: true,
                                    resources: resources,
                                    selectedId: _element,
                                    onSelect: (id) => setState(() {
                                      _element = id;
                                      _slot = null;
                                    }),
                                    onTransform: (id, transform) =>
                                        _editCanvas((c) {
                                          (c['elements'] as List)
                                              .cast<AlbumJson>()
                                              .firstWhere((e) => e['id'] == id)
                                              .addAll(transform);
                                        }, group: 'transform-$id'),
                                  )
                                : AlbumBinderWidget(
                                    album: album,
                                    page: album.pages[_page - 1],
                                    resources: resources,
                                    selectedSlot: _slot,
                                    selectedElement: _element,
                                    onTapSlot: (s) {
                                      if (s['card_id'] == null) {
                                        _pick(slotId: s['id'] as String);
                                      } else {
                                        setState(() {
                                          _slot = s['id'] as String;
                                          _element = null;
                                        });
                                      }
                                    },
                                    onSwap: _swap,
                                    onSelectElement: (id) => setState(() {
                                      _element = id;
                                      _slot = null;
                                    }),
                                    onTransformElement: (id, transform) =>
                                        _editCanvas((c) {
                                          (c['elements'] as List)
                                              .cast<AlbumJson>()
                                              .firstWhere((e) => e['id'] == id)
                                              .addAll(transform);
                                        }, group: 'transform-$id'),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (selected != null)
                    _elementTools(selected)
                  else if (_slot != null && _page > 0)
                    _slotTools()
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '上一页',
                            onPressed: _page > 0
                                ? () => setState(() => _page--)
                                : null,
                            icon: const AlbumIcon('ChevronLeft'),
                          ),
                          Text(
                            _page == 0
                                ? '封面'
                                : '$_page / ${album.pages.length}',
                          ),
                          IconButton(
                            tooltip: '下一页',
                            onPressed: _page < album.pages.length
                                ? () => setState(() => _page++)
                                : null,
                            icon: const AlbumIcon('ChevronRight'),
                          ),
                          IconButton(
                            tooltip: '添加页面',
                            onPressed: _addPage,
                            icon: const AlbumIcon(
                              'Plus',
                              color: FanColors.lavender,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _tool('小卡', 'RectangleVertical', () => _pick()),
                            _tool('布局', 'BookOpen', _layout),
                            _tool('文字', 'Type', () => _text()),
                            _tool('贴纸', 'Sticker', _stickers),
                            _tool(
                              'Emoji',
                              'Smile',
                              () => _stickers(emoji: true),
                            ),
                            _tool('背景', 'LayoutGrid', _background),
                            _tool('页面', 'BookCopy', _pages),
                            _tool('图层', 'List', _layers),
                            _tool('设置', 'Ellipsis', _settings),
                            _tool('轮播', 'Move', _cardOrder),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tool(String label, String icon, VoidCallback action) => SizedBox(
    width: 62,
    child: InkWell(
      onTap: action,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AlbumIcon(icon, color: FanColors.ink),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
  Widget _elementTools(AlbumJson selected) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _element = null),
          icon: const AlbumIcon('X', size: 18),
          label: const Text('取消选中'),
        ),
        if (selected['type'] == 'TEXT')
          TextButton(
            onPressed: () => _text(element: selected),
            child: const Text('编辑'),
          ),
        if (selected['type'] == 'CARD')
          TextButton(onPressed: () => _pick(), child: const Text('更换小卡')),
        if (selected['type'] != 'CARD')
          IconButton(
            tooltip: '复制元素',
            onPressed: () => _editCanvas((c) {
              final clone = cloneAlbumJson(selected)
                ..['id'] = albumId('element')
                ..['x'] = ((selected['x'] as num).toDouble() + .04).clamp(
                  -2,
                  2,
                );
              (c['elements'] as List).add(clone);
            }),
            icon: const AlbumIcon('Copy'),
          ),
        IconButton(
          tooltip: '旋转元素',
          onPressed: () => _editCanvas((c) {
            final e = (c['elements'] as List).cast<AlbumJson>().firstWhere(
              (e) => e['id'] == selected['id'],
            );
            e['rotation'] = ((e['rotation'] as num).toDouble() + 15).clamp(
              -3600,
              3600,
            );
          }),
          icon: const AlbumIcon('RotateCw'),
        ),
        IconButton(
          tooltip: '删除元素',
          onPressed: () => _editCanvas(
            (c) => (c['elements'] as List).removeWhere(
              (e) => e['id'] == selected['id'],
            ),
          ),
          icon: const AlbumIcon('Trash2'),
        ),
      ],
    ),
  );
  Widget _slotTools() {
    final current = (_album.pages[_page - 1]['slots'] as List)
        .cast<AlbumJson>()
        .where((s) => s['id'] == _slot)
        .firstOrNull;
    if (current == null || current['card_id'] == null) return const SizedBox();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => setState(() => _slot = null),
          child: const Text('取消选中'),
        ),
        TextButton(
          onPressed: () => _pick(slotId: _slot),
          child: const Text('更换'),
        ),
        IconButton(
          tooltip: '小卡正反面预览',
          onPressed: () => showAlbumCardPreview(
            context,
            _album.card(current['card_id'] as String),
            allowDetail: false,
          ),
          icon: const Icon(Icons.zoom_in_rounded),
        ),
        IconButton(
          tooltip: '清空卡位',
          onPressed: () {
            _controller.edit((d) {
              final slots =
                  (((d['pages'] as List)[_page - 1] as AlbumJson)['slots']
                          as List)
                      .cast<AlbumJson>();
              slots.firstWhere((s) => s['id'] == _slot)['card_id'] = null;
            });
            setState(() => _slot = null);
          },
          icon: const AlbumIcon('Trash2'),
        ),
      ],
    );
  }
}

Future<AlbumJson?> editAlbumBackground(
  BuildContext context,
  AlbumJson original,
  List<AlbumJson> resources,
) async {
  final current = cloneAlbumJson(original);
  final colors = (current['colors'] as List).cast<String>();
  final result = await showModalBottomSheet<AlbumJson>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => AlbumInputScope(
      initialValues: {
        'first': colors.first,
        'second': colors.length > 1 ? colors[1] : colors.first,
      },
      builder: (context, inputs) {
        final first = inputs['first']!, second = inputs['second']!;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '背景设置',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 130,
                      decoration: albumDecoration(current),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'SOLID', label: Text('纯色')),
                        ButtonSegment(value: 'GRADIENT', label: Text('渐变')),
                      ],
                      selected: {current['type'] as String},
                      onSelectionChanged: (s) =>
                          setSheetState(() => current['type'] = s.first),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final r in resources.where(
                          (r) => r['kind'] == 'BACKGROUND',
                        ))
                          InkWell(
                            onTap: () => setSheetState(() {
                              current.clear();
                              current.addAll(
                                cloneAlbumJson(r['config'] as AlbumJson),
                              );
                              first.text =
                                  (current['colors'] as List).first as String;
                              second.text =
                                  (current['colors'] as List).last as String;
                            }),
                            child: Container(
                              width: 55,
                              height: 45,
                              decoration: albumDecoration(
                                r['config'] as AlbumJson,
                              ),
                            ),
                          ),
                        for (final hex in [
                          '#AECDF4',
                          '#FFE7AC',
                          '#FF7897',
                          '#FFDEA8',
                          '#92DBEB',
                          '#C996FF',
                        ])
                          InkWell(
                            onTap: () => setSheetState(() {
                              current['type'] = 'SOLID';
                              current['colors'] = [hex];
                              first.text = hex;
                            }),
                            child: Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                color: albumColor(hex),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: first,
                            decoration: const InputDecoration(
                              labelText: '颜色 1 · #RRGGBB',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: second,
                            decoration: const InputDecoration(
                              labelText: '颜色 2 · #RRGGBB',
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      min: -180,
                      max: 180,
                      divisions: 36,
                      value: ((current['angle'] as num?)?.toDouble() ?? 45)
                          .clamp(-180, 180),
                      label: '${current['angle']}°',
                      onChanged: (v) =>
                          setSheetState(() => current['angle'] = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        final pattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
                        if (!pattern.hasMatch(first.text) ||
                            current['type'] == 'GRADIENT' &&
                                !pattern.hasMatch(second.text)) {
                          showFanToast(context, '请输入有效的 #RRGGBB 颜色');
                          return;
                        }
                        current['colors'] = [
                          first.text,
                          if (current['type'] == 'GRADIENT') second.text,
                        ];
                        Navigator.pop(context, current);
                      },
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  return result;
}

import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native perspective carousel adapted to the Card Atelier interaction model.
/// All selection uses slot IDs, so two placements of the same card stay distinct.
class AlbumCardScene extends ConsumerStatefulWidget {
  const AlbumCardScene({
    super.key,
    required this.album,
    this.onExpandedChanged,
  });
  final PhotocardAlbum album;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  ConsumerState<AlbumCardScene> createState() => AlbumCardSceneState();
}

class AlbumCardSceneState extends ConsumerState<AlbumCardScene>
    with TickerProviderStateMixin {
  late final AnimationController _spread = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _travel =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      )..addListener(() {
        _position =
            _from +
            (_to - _from) * Curves.easeOutCubic.transform(_travel.value);
      });
  late int _selected;
  late double _position;
  double _from = 0, _to = 0, _drag = 0;
  bool _expanded = false, _back = false;
  bool _dragging = false;
  List<AlbumJson> get _slots => widget.album.orderedSlots;
  bool get _busy =>
      _spread.isAnimating || _flip.isAnimating || _travel.isAnimating;
  bool get expanded => _expanded;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _selected = math.max(
      0,
      _slots.indexWhere((s) => s['id'] == widget.album.featuredSlotId),
    );
    _position = _selected.toDouble();
    _from = _to = _position;
    _back = false;
    _flip.value = 0;
  }

  @override
  void didUpdateWidget(covariant AlbumCardScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.orderedSlotIds.join('|') !=
            widget.album.orderedSlotIds.join('|') ||
        oldWidget.album.featuredSlotId != widget.album.featuredSlotId) {
      _travel.stop();
      _reset();
    }
  }

  @override
  void dispose() {
    _spread.dispose();
    _flip.dispose();
    _travel.dispose();
    super.dispose();
  }

  Future<void> _move(int index) async {
    if (_busy || index < 0 || index >= _slots.length) return;
    _from = _position;
    _to = index.toDouble();
    setState(() {
      _selected = index;
      _back = false;
    });
    _flip.value = 0;
    HapticFeedback.selectionClick();
    try {
      await _travel.forward(from: 0).orCancel;
    } on TickerCanceled {
      /* route closed */
    }
  }

  Future<void> _open(int index) async {
    if (_busy) return;
    if (index != _selected) await _move(index);
    if (!mounted) return;
    setState(() => _expanded = true);
    widget.onExpandedChanged?.call(true);
    _spread.forward();
    HapticFeedback.lightImpact();
  }

  void collapse() {
    // Back and close always work, including halfway through a flip/extraction.
    _flip.stop();
    _flip.value = 0;
    setState(() {
      _expanded = false;
      _back = false;
    });
    widget.onExpandedChanged?.call(false);
    _spread.reverse();
  }

  void _turn() {
    if (_busy || _slots.isEmpty) return;
    final card = widget.album.card(_slots[_selected]['card_id'] as String?);
    if (card?.backImageUrl?.trim().isNotEmpty != true) {
      showFanToast(context, '暂无背面');
      return;
    }
    setState(() => _back = !_back);
    _back ? _flip.forward() : _flip.reverse();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) {
      return const FanEmptyState(
        icon: Icons.photo_album_outlined,
        title: '还没有小卡',
        message: '在编辑中选择小卡，开始记录你的收藏。',
      );
    }
    final card = widget.album.card(_slots[_selected]['card_id'] as String?);
    final values = <String, String>{
      'idol': card == null
          ? ''
          : entityDisplayName(ref, 'idols', card.idolId, card.idolName),
      'group': card?.groupName ?? '',
      'source': card?.source ?? '',
      'type': card?.cardType ?? '',
      'version': card?.version ?? '',
      'release': card?.releaseDate ?? '',
      'region': card?.region ?? '',
    };
    final metadata = widget.album.displayFields
        .map((f) => values[f] ?? '')
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .join(' · ');
    final backgroundColors =
        (widget.album.cardView['background']?['colors'] as List?) ?? [];
    final needsTextSurface = backgroundColors.any(
      (color) => albumColor(color as String).computeLuminance() < .55,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxHeight < 430;
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, scene) {
                  final w = scene.maxWidth, h = scene.maxHeight;
                  final cardWidth = math.min(w * .52, h * .53);
                  // Reserve 44pt hit targets on both sides; never crop the full card.
                  final targetWidth = math.min(w - 100, h * .60);
                  return ClipRect(
                    child: GestureDetector(
                      key: const Key('album-card-stage'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => _drag = 0,
                      onHorizontalDragUpdate: (details) {
                        if (_spread.isAnimating || _flip.isAnimating) return;
                        _drag += details.delta.dx;
                        _dragging = true;
                        if (!_expanded) {
                          _travel.stop();
                          setState(
                            () => _position =
                                (_position - details.delta.dx / (w * .27))
                                    .clamp(0.0, (_slots.length - 1).toDouble()),
                          );
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        _dragging = false;
                        if (_expanded) {
                          if (_drag.abs() > 35 ||
                              (details.primaryVelocity ?? 0).abs() > 150) {
                            _move(
                              _selected +
                                  ((_drag == 0
                                              ? details.primaryVelocity ?? 0
                                              : _drag) <
                                          0
                                      ? 1
                                      : -1),
                            );
                          }
                        } else {
                          _move(_position.round());
                        }
                      },
                      onHorizontalDragCancel: () {
                        // A simple tap also cancels the ancestor drag recognizer.
                        // Only settle a real drag; otherwise it blocks extraction.
                        if (!_expanded && _dragging) _move(_position.round());
                        _dragging = false;
                      },
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_spread, _flip, _travel]),
                        builder: (context, _) {
                          final t = Curves.easeInOutCubic.transform(
                            _spread.value,
                          );
                          // Bound image work even for legacy albums with hundreds of slots.
                          final order =
                              List.generate(_slots.length, (i) => i)
                                  .where(
                                    (i) =>
                                        (i - _position).abs() <= 3 ||
                                        i == _selected,
                                  )
                                  .toList()
                                ..sort(
                                  (a, b) => (b - _position).abs().compareTo(
                                    (a - _position).abs(),
                                  ),
                                );
                          if (t > 0) {
                            order.remove(_selected);
                            order.add(_selected);
                          }
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              for (final i in order)
                                _sceneCard(i, w, h, cardWidth, targetWidth, t),
                              if (_expanded || !_busy) ...[
                                Positioned(
                                  left: 2,
                                  top: h / 2 - 22,
                                  child: _nav(false),
                                ),
                                Positioned(
                                  right: 2,
                                  top: h / 2 - 22,
                                  child: _nav(true),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: compact ? 116 : 210),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: needsTextSurface
                      ? Colors.white.withValues(alpha: .85)
                      : Colors.transparent,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 6, 24, compact ? 8 : 18),
                  child: Column(
                    children: [
                      Text(
                        '${(_selected + 1).toString().padLeft(2, '0')} / ${_slots.length.toString().padLeft(2, '0')}',
                        key: const Key('album-card-counter'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: FanColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        card?.displayTitle ?? '小卡暂不可用',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (metadata.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            metadata,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: FanColors.textSecondary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        _expanded ? '轻点小卡翻面 · 左右切换浏览' : '轻点小卡放大 · 左右滑动浏览',
                        style: const TextStyle(
                          fontSize: 11,
                          color: FanColors.textSecondary,
                        ),
                      ),
                      if (!_expanded &&
                          widget.album.description.trim().isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .75),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '收藏故事',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.album.description,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: FanColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _nav(bool next) => IconButton.filledTonal(
    key: Key(next ? 'album-card-next' : 'album-card-previous'),
    tooltip: next ? '下一张小卡' : '上一张小卡',
    style: IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: .85),
      foregroundColor: FanColors.ink,
      minimumSize: const Size(44, 44),
    ),
    onPressed: _busy || (next ? _selected == _slots.length - 1 : _selected == 0)
        ? null
        : () => _move(_selected + (next ? 1 : -1)),
    icon: Icon(next ? Icons.chevron_right : Icons.chevron_left, size: 22),
  );

  Widget _sceneCard(int i, double w, double h, double cw, double tw, double t) {
    final d = i - _position;
    final active = i == _selected;
    final p = active ? t : 0.0;
    final width = cw + (tw - cw) * p;
    final scale = (1 - d.abs() * .13).clamp(.55, 1.0);
    final x = w / 2 + d * w * .265 * (1 - p);
    final y = h / 2 + d.abs() * 8 * (1 - p);
    final angle = active
        ? Curves.easeInOutCubic.transform(_flip.value) * math.pi * p
        : 0.0;
    final back = angle > math.pi / 2;
    final opacity = active ? 1.0 : 1 - t;
    return Positioned(
      left: x - width / 2,
      top: y - width * 1.55 / 2,
      width: width,
      height: width * 1.55,
      child: IgnorePointer(
        ignoring: opacity < .5 || (_expanded && !active),
        child: Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0015)
              ..rotateY(-d.clamp(-2.0, 2.0) * .42 * (1 - p) + angle)
              ..scaleByDouble(
                scale + (1 - scale) * p,
                scale + (1 - scale) * p,
                1,
                1,
              ),
            child: Semantics(
              button: true,
              label:
                  '小卡 ${i + 1}，${back ? '背面' : '正面'}，${_expanded ? '轻点翻面' : '轻点放大'}',
              child: GestureDetector(
                key: ValueKey('album-scene-card-${_slots[i]['id']}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _expanded ? _turn() : _open(i),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(back ? math.pi : 0),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: FanColors.ink.withValues(alpha: .18),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AlbumCardImage(
                        widget.album.card(_slots[i]['card_id'] as String?),
                        back: back,
                        thumbnail: !active,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

class AlbumIcon extends StatelessWidget {
  const AlbumIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.color = FanColors.ink,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/album/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

Color albumColor(String hex) =>
    Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

/// Constant-scale neutral weave, independent of pigment and canvas bounds.
class AlbumMaterial extends StatelessWidget {
  const AlbumMaterial({super.key, this.linen = false});
  final bool linen;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: ExactAssetImage(
            'assets/album/materials/${linen ? 'linen' : 'paper'}.png',
            scale: 8,
          ),
          fit: BoxFit.none,
          repeat: ImageRepeat.repeat,
          opacity: linen ? .22 : .18,
          colorFilter: const ColorFilter.mode(
            Color(0xFFE0DBD3),
            BlendMode.modulate,
          ),
        ),
      ),
    ),
  );
}

BoxDecoration albumDecoration(AlbumJson? background, {double radius = 16}) {
  final bg = background ?? albumBackground();
  final colors = ((bg['colors'] as List?) ?? ['#EDE8FF', '#F9EDF2'])
      .cast<String>()
      .map(albumColor)
      .toList();
  final angle = ((bg['angle'] as num?)?.toDouble() ?? 45) * math.pi / 180;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    color: colors.first,
    gradient: bg['type'] == 'SOLID'
        ? null
        : LinearGradient(
            begin: Alignment(-math.cos(angle), -math.sin(angle)),
            end: Alignment(math.cos(angle), math.sin(angle)),
            colors: colors.length > 1 ? colors : [colors.first, colors.first],
          ),
  );
}

class AlbumCardImage extends StatefulWidget {
  const AlbumCardImage(
    this.card, {
    super.key,
    this.back = false,
    this.thumbnail = false,
  });
  final CollectibleCard? card;
  final bool back;
  final bool thumbnail;
  @override
  State<AlbumCardImage> createState() => _AlbumCardImageState();
}

class _AlbumCardImageState extends State<AlbumCardImage> {
  int retry = 0;
  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    if (card == null) {
      return const Center(
        child: AlbumIcon('CircleOff', color: FanColors.textSecondary),
      );
    }
    final url = widget.back
        ? card.backImageUrl
        : (widget.thumbnail
              ? card.thumbnailUrl ?? card.imageUrl
              : card.imageUrl);
    if (url == null || url.isEmpty) {
      return FanArtwork(
        startColor: Color(card.colorStart),
        endColor: Color(card.colorEnd),
        label: card.idolName.isEmpty ? 'F' : card.idolName.characters.first,
        aspectRatio: 55 / 85,
        showMark: true,
      );
    }
    return FanImage(
      key: ValueKey('$url-$retry'),
      imageUrl: url,
      fit: BoxFit.contain,
      fallback: IconButton(
        tooltip: '图片加载失败，点击重试',
        onPressed: () => setState(() => retry++),
        icon: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}

class AlbumCanvasWidget extends StatelessWidget {
  const AlbumCanvasWidget({
    super.key,
    required this.config,
    required this.album,
    this.selectedId,
    this.onSelect,
    this.onTransform,
    this.resources = const [],
    this.child,
    this.showName = false,
    this.radius = 14,
  });
  final AlbumJson config;
  final PhotocardAlbum album;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final void Function(String id, AlbumJson transform)? onTransform;
  final List<AlbumJson> resources;
  final Widget? child;
  final bool showName;
  final double radius;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final elements =
          ((config['elements'] as List?) ?? []).cast<AlbumJson>().toList()
            ..sort(
              (a, b) => (a['z_index'] as num).compareTo(b['z_index'] as num),
            );
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: albumDecoration(
            config['background'] as AlbumJson?,
            radius: radius,
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: AlbumMaterial(linen: showName)),
              if (showName) ...[
                Positioned(
                  left: 9,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    decoration: BoxDecoration(
                      color: const Color(0xFF786F60).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (elements.isNotEmpty &&
                    !elements.any((e) => e['type'] == 'TEXT'))
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 22,
                    child: Text(
                      album.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: constraints.maxWidth * .08,
                        fontWeight: FontWeight.w500,
                        color: FanColors.ink.withValues(alpha: .75),
                      ),
                    ),
                  ),
              ],
              if (showName && elements.isEmpty && child == null)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_outlined,
                        size: 28,
                        color: FanColors.textSecondary,
                      ),
                      SizedBox(height: 8),
                      Text(
                        '暂无封面',
                        style: TextStyle(
                          fontSize: 14,
                          color: FanColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ?child,
              for (final e in elements)
                Positioned(
                  left: (e['x'] as num).toDouble() * constraints.maxWidth,
                  top: (e['y'] as num).toDouble() * constraints.maxHeight,
                  width: (e['width'] as num).toDouble() * constraints.maxWidth,
                  height:
                      (e['height'] as num).toDouble() * constraints.maxHeight,
                  child: AlbumElementWidget(
                    key: ValueKey(e['id']),
                    element: e,
                    album: album,
                    canvasSize: constraints.biggest,
                    selected: selectedId == e['id'],
                    resources: resources,
                    onSelect: onSelect,
                    onTransform: onTransform,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class AlbumElementWidget extends StatefulWidget {
  const AlbumElementWidget({
    super.key,
    required this.element,
    required this.album,
    required this.canvasSize,
    required this.selected,
    required this.resources,
    this.onSelect,
    this.onTransform,
  });
  final AlbumJson element;
  final PhotocardAlbum album;
  final Size canvasSize;
  final bool selected;
  final List<AlbumJson> resources;
  final ValueChanged<String>? onSelect;
  final void Function(String, AlbumJson)? onTransform;
  @override
  State<AlbumElementWidget> createState() => _AlbumElementWidgetState();
}

class _AlbumElementWidgetState extends State<AlbumElementWidget> {
  AlbumJson? _start;
  Offset _delta = Offset.zero;
  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    final style = (e['style'] as AlbumJson?) ?? {};
    String content = e['content'] as String;
    if (e['type'] == 'STICKER') {
      final matches = widget.resources.where((r) => r['id'] == content);
      content = matches.isEmpty
          ? {
                  'star': '✦',
                  'heart': '♡',
                  'bow': '🎀',
                  'flower': '✿',
                  'stay': 'STAY',
                }[content] ??
                '✦'
          : (matches.first['config'] as AlbumJson)['symbol'] as String? ?? '✦';
    }
    final body = e['type'] == 'STROKE'
        ? CustomPaint(painter: AlbumStrokePainter(e))
        : e['type'] == 'CARD'
        ? AlbumCardImage(widget.album.card(content))
        : FittedBox(
            fit: e['type'] == 'TEXT' ? BoxFit.contain : BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              content,
              style: TextStyle(
                fontSize:
                    ((style['font_size'] as num?)?.toDouble() ?? 24) *
                    widget.canvasSize.width /
                    300,
                fontFamily: style['font_family'] == 'serif'
                    ? 'Georgia'
                    : style['font_family'] == 'monospace'
                    ? 'Courier'
                    : null,
                fontWeight: style['bold'] == true
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: albumColor(style['color'] as String? ?? '#342A56'),
              ),
            ),
          );
    return Transform.rotate(
      angle: (e['rotation'] as num).toDouble() * math.pi / 180,
      child: GestureDetector(
        onTap: widget.onSelect == null
            ? null
            : () => widget.onSelect!(e['id'] as String),
        onScaleStart: widget.onTransform == null
            ? null
            : (_) {
                _start = cloneAlbumJson(e);
                _delta = Offset.zero;
                widget.onSelect?.call(e['id'] as String);
              },
        onScaleUpdate: widget.onTransform == null
            ? null
            : (details) {
                _delta += details.focalPointDelta;
                final start = _start!;
                widget.onTransform!(e['id'] as String, {
                  'x':
                      ((start['x'] as num).toDouble() +
                              _delta.dx / widget.canvasSize.width)
                          .clamp(-2, 2),
                  'y':
                      ((start['y'] as num).toDouble() +
                              _delta.dy / widget.canvasSize.height)
                          .clamp(-2, 2),
                  'width': ((start['width'] as num).toDouble() * details.scale)
                      .clamp(.02, 4),
                  'height':
                      ((start['height'] as num).toDouble() * details.scale)
                          .clamp(.02, 4),
                  'rotation':
                      ((start['rotation'] as num).toDouble() +
                              details.rotation * 180 / math.pi)
                          .clamp(-3600, 3600),
                });
              },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: widget.selected
                ? Border.all(color: FanColors.lavender, width: 2)
                : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: body,
        ),
      ),
    );
  }
}

class AlbumStrokePainter extends CustomPainter {
  AlbumStrokePainter(this.element);
  final AlbumJson element;
  @override
  void paint(Canvas canvas, Size size) {
    final points = (element['points'] as List?) ?? [];
    if (points.length < 2) return;
    final style = element['style'] as AlbumJson? ?? {};
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i] as List;
      final x = (point[0] as num).toDouble() * size.width,
          y = (point[1] as num).toDouble() * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = albumColor(style['color'] ?? '#6D5DD3')
            .withValues(alpha: (style['opacity'] as num?)?.toDouble() ?? 1)
        ..strokeWidth =
            ((style['stroke_width'] as num?)?.toDouble() ?? 3) *
            size.width /
            300
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(AlbumStrokePainter oldDelegate) => true;
}

class AlbumCoverWidget extends StatelessWidget {
  const AlbumCoverWidget(this.album, {super.key, this.resources = const []});
  final PhotocardAlbum album;
  final List<AlbumJson> resources;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 128 / 166,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF756B5E).withValues(alpha: .14),
            blurRadius: 7,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: album.usesStackCover
          ? AlbumStackCover(album: album)
          : AlbumBookCover(album: album, resources: resources),
    ),
  );
}

class AlbumBookCover extends StatelessWidget {
  const AlbumBookCover({
    super.key,
    required this.album,
    this.resources = const [],
  });
  final PhotocardAlbum album;
  final List<AlbumJson> resources;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(1, 1, 2, 3),
    decoration: BoxDecoration(
      color: const Color(0xFFE3DED3),
      borderRadius: BorderRadius.circular(5),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AlbumCanvasWidget(
            config: album.cover,
            album: album,
            resources: resources,
            showName: true,
            radius: 4,
          ),
          if (((album.cover['elements'] as List?) ?? []).isEmpty &&
              album.coverSlots.isNotEmpty)
            DecoratedBox(
              decoration: albumDecoration(
                album.cover['background'] as AlbumJson?,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(child: AlbumMaterial(linen: true)),
                  FractionallySizedBox(
                    widthFactor: .62,
                    heightFactor: .66,
                    alignment: const Alignment(.1, -.18),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF8F2),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22756B5E),
                            blurRadius: 3,
                            offset: Offset(1, 2),
                          ),
                        ],
                      ),
                      child: AlbumCardImage(
                        album.card(album.coverSlots.first['card_id']),
                        thumbnail: true,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF62665E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF756B5E).withValues(alpha: .12),
                    Colors.white.withValues(alpha: .12),
                    const Color(0xFF756B5E).withValues(alpha: .08),
                  ],
                ),
                border: Border(
                  right: BorderSide(
                    color: const Color(0xFF756B5E).withValues(alpha: .14),
                    width: .7,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Fixed STACK_V1 layout: no generated image, randomness or external renderer.
/// Slots, featured ID and background are persisted in the album document.
class AlbumStackCover extends StatelessWidget {
  const AlbumStackCover({super.key, required this.album});
  final PhotocardAlbum album;
  @override
  Widget build(BuildContext context) {
    final slots = album.coverSlots;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: albumDecoration(
          album.cardView['background'] as AlbumJson? ??
              album.cover['background'] as AlbumJson?,
        ),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final w = bounds.maxWidth, h = bounds.maxHeight;
            if (slots.isEmpty) {
              return const Center(
                child: AlbumIcon(
                  'BookOpen',
                  size: 32,
                  color: FanColors.lavender,
                ),
              );
            }
            // Index 0 is always drawn last, in front. Angles are degrees.
            const poses = [
              (0.0, -.025, -3.0, 1.0),
              (-.21, .025, -12.0, .87),
              (.21, .015, 12.0, .87),
              (-.30, -.05, -15.0, .78),
              (.30, -.06, 15.0, .78),
            ];
            final width = math.min(
              w * (slots.length == 1 ? .70 : .53),
              h * .47,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: AlbumMaterial()),
                for (var i = slots.length - 1; i >= 0; i--)
                  Positioned(
                    key: ValueKey('stack-cover-${slots[i]['id']}'),
                    left: w / 2 + poses[i].$1 * w - width * poses[i].$4 / 2,
                    top:
                        h / 2 +
                        poses[i].$2 * h -
                        width * poses[i].$4 * 1.55 / 2,
                    width: width * poses[i].$4,
                    height: width * poses[i].$4 * 1.55,
                    child: Transform.rotate(
                      angle: poses[i].$3 * math.pi / 180,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF756B5E)
                                  .withValues(alpha: .16),
                              blurRadius: 6,
                              offset: const Offset(2, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: AlbumCardImage(
                            album.card(slots[i]['card_id'] as String?),
                            thumbnail: true,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AlbumBinderWidget extends StatelessWidget {
  const AlbumBinderWidget({
    super.key,
    required this.album,
    required this.page,
    this.resources = const [],
    this.selectedSlot,
    this.onTapSlot,
    this.onSwap,
    this.selectedElement,
    this.onSelectElement,
    this.onTransformElement,
    this.showBinding = true,
  });
  final PhotocardAlbum album;
  final AlbumJson page;
  final List<AlbumJson> resources;
  final String? selectedSlot, selectedElement;
  final ValueChanged<AlbumJson>? onTapSlot;
  final void Function(String from, String to)? onSwap;
  final ValueChanged<String>? onSelectElement;
  final void Function(String, AlbumJson)? onTransformElement;
  final bool showBinding;
  @override
  Widget build(BuildContext context) {
    final slots = (page['slots'] as List).cast<AlbumJson>();
    return Container(
      padding: EdgeInsets.all(album.realistic ? 10 : 5),
      decoration: BoxDecoration(
        color: album.realistic
            ? const Color(0xFFE4E0EC)
            : Colors.white.withValues(alpha: .2),
        border: Border.all(color: Colors.white, width: album.realistic ? 3 : 1),
        borderRadius: BorderRadius.circular(15),
        boxShadow: album.realistic
            ? [
                const BoxShadow(
                  color: Color(0x408D83AA),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          if (showBinding && album.realistic)
            SizedBox(
              width: 24,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  3,
                  (_) => Container(
                    height: 9,
                    width: 23,
                    decoration: BoxDecoration(
                      color: const Color(0xFFBBB6C8),
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: AlbumCanvasWidget(
              config: page['config'] as AlbumJson,
              album: album,
              resources: resources,
              selectedId: selectedElement,
              onSelect: onSelectElement,
              onTransform: onTransformElement,
              child: LayoutBuilder(
                builder: (context, c) {
                  final count = slots.length;
                  final columns = count <= 3
                      ? count
                      : count == 4
                      ? 2
                      : 3;
                  final rows = (count / columns).ceil();
                  const gap = 7.0;
                  final width = math
                      .min(
                        (c.maxWidth - 12 - gap * (columns - 1)) / columns,
                        ((c.maxHeight - 12 - gap * (rows - 1)) / rows) *
                            55 /
                            85,
                      )
                      .clamp(1.0, double.infinity);
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int row = 0; row < rows; row++)
                          Padding(
                            padding: EdgeInsets.only(top: row == 0 ? 0 : gap),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (int column = 0; column < columns; column++)
                                  if (row * columns + column < count)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: gap / 2,
                                      ),
                                      child: SizedBox(
                                        width: width,
                                        height: width * 85 / 55,
                                        child: _pocket(
                                          slots[row * columns + column],
                                          width,
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pocket(AlbumJson slot, double width) {
    final image = slot['card_id'] == null
        ? (onTapSlot == null
              ? const SizedBox()
              : const Center(
                  child: AlbumIcon('Plus', size: 20, color: FanColors.lavender),
                ))
        : AlbumCardImage(album.card(slot['card_id'] as String));
    Widget body = GestureDetector(
      onTap: onTapSlot == null ? null : () => onTapSlot!(slot),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .38),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selectedSlot == slot['id']
                ? FanColors.lavender
                : Colors.white.withValues(alpha: .75),
            width: selectedSlot == slot['id'] ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: image),
            if (album.realistic)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0x20FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x10FFFFFF),
                      ],
                      stops: [0, .45, 1],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onSwap == null) return body;
    final pocket = body;
    body = DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != slot['id'],
      onAcceptWithDetails: (d) => onSwap!(d.data, slot['id'] as String),
      builder: (context, candidate, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          border: candidate.isEmpty
              ? null
              : Border.all(color: FanColors.lavender, width: 3),
        ),
        child: pocket,
      ),
    );
    return LongPressDraggable<String>(
      data: slot['id'] as String,
      maxSimultaneousDrags: slot['card_id'] == null ? 0 : 1,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          height: width * 85 / 55,
          child: AlbumCardImage(album.card(slot['card_id'] as String?)),
        ),
      ),
      childWhenDragging: Opacity(opacity: .3, child: body),
      child: body,
    );
  }
}

Future<bool> confirmAlbumAction(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showAlbumCardPreview(
  BuildContext context,
  CollectibleCard? card, {
  bool allowDetail = true,
}) async {
  if (card == null) {
    showFanToast(context, '小卡暂不可用，卡位仍会保留');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _CardPreview(
      card: card,
      allowDetail: allowDetail,
      onDetail: () {
        Navigator.pop(dialogContext);
        context.push('/card/${card.id}');
      },
    ),
  );
}

class _CardPreview extends ConsumerStatefulWidget {
  const _CardPreview({
    required this.card,
    required this.allowDetail,
    required this.onDetail,
  });
  final CollectibleCard card;
  final bool allowDetail;
  final VoidCallback onDetail;
  @override
  ConsumerState<_CardPreview> createState() => _CardPreviewState();
}

class _CardPreviewState extends ConsumerState<_CardPreview>
    with SingleTickerProviderStateMixin {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  bool _back = false;
  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _turn() {
    if (_flip.isAnimating) return;
    if (widget.card.backImageUrl?.trim().isNotEmpty != true) {
      _messenger.currentState?.hideCurrentSnackBar();
      _messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text('暂无背面'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _back = !_back;
    _back ? _flip.forward() : _flip.reverse();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: const Color(0xFFF5F3FC),
    child: ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F3FC),
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      widget.card.displayTitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) => Center(
                    child: SizedBox(
                      width: math.min(
                        bounds.maxWidth - 40,
                        bounds.maxHeight / 1.55 - 16,
                      ),
                      child: AspectRatio(
                        aspectRatio: 1 / 1.55,
                        child: GestureDetector(
                          key: const Key('album-preview-flip'),
                          onTap: _turn,
                          child: AnimatedBuilder(
                            animation: _flip,
                            builder: (context, _) {
                              final angle =
                                  Curves.easeInOutCubic.transform(_flip.value) *
                                  math.pi;
                              final back = angle > math.pi / 2;
                              return Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, .001)
                                  ..rotateY(angle),
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.rotationY(
                                    back ? math.pi : 0,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: FanColors.ink.withValues(
                                            alpha: .14,
                                          ),
                                          blurRadius: 22,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: AlbumCardImage(
                                        widget.card,
                                        back: back,
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
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Text(
                  [
                    entityDisplayName(
                      ref,
                      'idols',
                      widget.card.idolId,
                      widget.card.idolName,
                    ),
                    widget.card.source,
                    widget.card.version,
                  ].where((s) => s.trim().isNotEmpty).join(' · '),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: FanColors.textSecondary,
                  ),
                ),
              ),
              const Text(
                '轻点小卡翻面',
                style: TextStyle(fontSize: 12, color: FanColors.textSecondary),
              ),
              if (widget.allowDetail)
                TextButton(
                  onPressed: widget.onDetail,
                  child: const Text('查看官方图鉴详情'),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

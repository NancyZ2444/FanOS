import 'dart:io';
import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/card_geometry.dart';
import 'package:flutter/material.dart';

/// Coordinates always refer to the displayed image, never its letterboxing.
class FeedbackCropPage extends StatefulWidget {
  const FeedbackCropPage({required this.url, required this.side, super.key});
  final String url, side;
  @override
  State<FeedbackCropPage> createState() => _FeedbackCropPageState();
}

class _FeedbackCropPageState extends State<FeedbackCropPage> {
  late final ImageProvider _image = widget.url.startsWith('http')
      ? NetworkImage(widget.url)
      : FileImage(File(widget.url));
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  double? _ratio;
  bool _failed = false;
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(
      (info, _) {
        if (mounted) {
          setState(() {
            _ratio = info.image.width / info.image.height;
            _crop = initialPhotocardCrop(_ratio!);
          });
        }
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream = _image.resolve(ImageConfiguration.empty)..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('裁剪${widget.side}'),
      actions: [
        TextButton(
          onPressed: () =>
              setState(() => _crop = initialPhotocardCrop(_ratio ?? 1)),
          child: const Text('重置'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text('固定小卡比例 55:85，拖动角点缩放，拖动框内移动选区'),
          ),
          Expanded(
            child: _failed
                ? const Center(child: Text('图片加载失败，请返回后重试'))
                : _ratio == null
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        final width = math.min(
                          bounds.maxWidth,
                          bounds.maxHeight * _ratio!,
                        );
                        return Center(
                          child: SizedBox(
                            width: width,
                            height: width / _ratio!,
                            child: FeedbackCropCanvas(
                              crop: _crop,
                              aspectRatio: photocardAspectRatio,
                              onChanged: (value) =>
                                  setState(() => _crop = value),
                              child: Image(
                                image: _image,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const Key('feedback-crop-confirm'),
                onPressed: _ratio == null || _failed
                    ? null
                    : () => Navigator.pop(context, [
                        _crop.left,
                        _crop.top,
                        _crop.width,
                        _crop.height,
                      ]),
                child: const Text('使用裁剪图'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Normalized coordinates keep the requested ratio in source pixels, even on
/// square/landscape photos. The backend applies these bounds to the real image.
Rect initialPhotocardCrop(double imageRatio) {
  final ratio = photocardAspectRatio / imageRatio;
  final width = math.min(1.0, ratio);
  final height = width / ratio;
  return Rect.fromLTWH((1 - width) / 2, (1 - height) / 2, width, height);
}

class FeedbackCropCanvas extends StatefulWidget {
  const FeedbackCropCanvas({
    required this.crop,
    required this.onChanged,
    required this.child,
    this.aspectRatio,
    super.key,
  });
  final Rect crop;
  final ValueChanged<Rect> onChanged;
  final Widget child;
  final double? aspectRatio;
  @override
  State<FeedbackCropCanvas> createState() => _FeedbackCropCanvasState();
}

class _FeedbackCropCanvasState extends State<FeedbackCropCanvas> {
  Offset? _start;
  late Rect _initial;
  bool _left = false, _right = false, _top = false, _bottom = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = bounds.biggest;
      return GestureDetector(
        key: const Key('feedback-crop-canvas'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          final p = details.localPosition;
          _initial = widget.crop;
          final rect = Rect.fromLTWH(
            _initial.left * size.width,
            _initial.top * size.height,
            _initial.width * size.width,
            _initial.height * size.height,
          );
          _start = rect.inflate(24).contains(p) ? p : null;
          _left = (p.dx - rect.left).abs() <= 24;
          _right = !_left && (p.dx - rect.right).abs() <= 24;
          _top = (p.dy - rect.top).abs() <= 24;
          _bottom = !_top && (p.dy - rect.bottom).abs() <= 24;
        },
        onPanUpdate: (details) {
          if (_start == null) return;
          final delta = details.localPosition - _start!;
          final dx = delta.dx / size.width, dy = delta.dy / size.height;
          final minW = math.min(.25, 48 / size.width);
          final minH = math.min(.25, 48 / size.height);
          if (!_left && !_right && !_top && !_bottom) {
            widget.onChanged(
              Rect.fromLTWH(
                (_initial.left + dx).clamp(0, 1 - _initial.width),
                (_initial.top + dy).clamp(0, 1 - _initial.height),
                _initial.width,
                _initial.height,
              ),
            );
          } else if (widget.aspectRatio != null) {
            final normalizedRatio =
                widget.aspectRatio! * size.height / size.width;
            final anchorX = _left
                ? _initial.right
                : _right
                ? _initial.left
                : _initial.center.dx;
            final anchorY = _top
                ? _initial.bottom
                : _bottom
                ? _initial.top
                : _initial.center.dy;
            // Project the finger movement onto a proportional resize vector.
            final byWidth = _left
                ? -delta.dx
                : _right
                ? delta.dx
                : 0.0;
            final byHeight = _top
                ? -delta.dy
                : _bottom
                ? delta.dy
                : 0.0;
            final pixelWidthChange = (_left || _right) && (_top || _bottom)
                ? (byWidth + byHeight / widget.aspectRatio!) /
                      (1 + 1 / math.pow(widget.aspectRatio!, 2))
                : (_left || _right)
                ? byWidth
                : byHeight * widget.aspectRatio!;
            final desiredWidth = _initial.width + pixelWidthChange / size.width;
            final maxWidth = _left
                ? anchorX
                : _right
                ? 1 - anchorX
                : 2 * math.min(anchorX, 1 - anchorX);
            final maxHeight = _top
                ? anchorY
                : _bottom
                ? 1 - anchorY
                : 2 * math.min(anchorY, 1 - anchorY);
            final maximum = math.min(maxWidth, maxHeight * normalizedRatio);
            final minimum = math.min(
              maximum,
              math.max(minW, minH * normalizedRatio),
            );
            final width = desiredWidth.clamp(minimum, maximum).toDouble();
            final height = width / normalizedRatio;
            widget.onChanged(
              Rect.fromLTWH(
                _left
                    ? anchorX - width
                    : _right
                    ? anchorX
                    : anchorX - width / 2,
                _top
                    ? anchorY - height
                    : _bottom
                    ? anchorY
                    : anchorY - height / 2,
                width,
                height,
              ),
            );
          } else {
            widget.onChanged(
              Rect.fromLTRB(
                _left
                    ? (_initial.left + dx).clamp(0, _initial.right - minW)
                    : _initial.left,
                _top
                    ? (_initial.top + dy).clamp(0, _initial.bottom - minH)
                    : _initial.top,
                _right
                    ? (_initial.right + dx).clamp(_initial.left + minW, 1)
                    : _initial.right,
                _bottom
                    ? (_initial.bottom + dy).clamp(_initial.top + minH, 1)
                    : _initial.bottom,
              ),
            );
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            IgnorePointer(
              child: CustomPaint(painter: _CropPainter(widget.crop)),
            ),
          ],
        ),
      );
    },
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.crop);
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect),
      Paint()..color = Colors.black45,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final grid = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(rect.left + rect.width * i / 3, rect.top),
        Offset(rect.left + rect.width * i / 3, rect.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top + rect.height * i / 3),
        Offset(rect.right, rect.top + rect.height * i / 3),
        grid,
      );
    }
    for (final p in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(p, 7, Paint()..color = FanColors.lavender);
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.crop != crop;
}

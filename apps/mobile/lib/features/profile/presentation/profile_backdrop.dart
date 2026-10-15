import 'dart:ui' as ui;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';

/// Clear at the status bar, softly blurred and faded toward the profile body.
/// All layers share the same image bounds and cached image source.
class ProfileBackdrop extends StatelessWidget {
  const ProfileBackdrop({super.key, required this.imageUrl});
  final String imageUrl;

  Widget _image() => FanImage(
    imageUrl: imageUrl,
    fallback: const ColoredBox(color: FanColors.lavenderSoft),
  );

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _image(),
            for (final layer in [(2.0, .25, .65), (4.0, .55, 1.0)])
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Colors.transparent, Colors.white],
                  stops: [layer.$2, layer.$3],
                ).createShader(bounds),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: layer.$1,
                    sigmaY: layer.$1,
                    tileMode: TileMode.clamp,
                  ),
                  child: _image(),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .18, .48, .78, 1],
                  colors: [
                    FanColors.canvas.withValues(alpha: 0),
                    FanColors.canvas.withValues(alpha: .08),
                    FanColors.canvas.withValues(alpha: .4),
                    FanColors.canvas.withValues(alpha: .88),
                    FanColors.canvas,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

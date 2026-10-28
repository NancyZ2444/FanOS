import 'dart:io';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:flutter/material.dart';

/// The photo and normalized boxes share one fitted coordinate system.
class ScanOriginalProgress extends StatelessWidget {
  const ScanOriginalProgress({
    required this.detection,
    required this.imageSize,
    this.localImagePath,
    super.key,
  });
  final ScanDetection? detection;
  final Size imageSize;
  final String? localImagePath;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final ratio = detection?.aspectRatio ?? imageSize.aspectRatio;
      final width = bounds.maxWidth < bounds.maxHeight * ratio
          ? bounds.maxWidth
          : bounds.maxHeight * ratio;
      final height = width / ratio;
      final regions = detection?.regions ?? [];
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (localImagePath != null)
                Image.file(
                  File(localImagePath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Text(
                      '原图暂不可用',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else if (detection?.imagePath != null)
                Image.network(
                  detection!.imagePath!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              for (var i = 0; i < regions.length; i++)
                Positioned(
                  left: regions[i].cropRegion.x * width,
                  top: regions[i].cropRegion.y * height,
                  width: regions[i].cropRegion.width * width,
                  height: regions[i].cropRegion.height * height,
                  child: Container(
                    key: ValueKey('progress-region-${regions[i].id}'),
                    decoration: BoxDecoration(
                      border: Border.all(color: FanColors.lavender, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.topLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      color: FanColors.lavender,
                      child: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

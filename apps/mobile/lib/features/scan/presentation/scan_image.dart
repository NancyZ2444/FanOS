import 'dart:io';

import 'package:flutter/material.dart';

/// Scan media may be a just-captured local file or a persisted API crop URL.
class ScanImage extends StatelessWidget {
  const ScanImage({
    required this.path,
    required this.fallback,
    this.quarterTurns = 0,
    this.aspectRatio = .74,
    super.key,
  });
  final String? path;
  final Widget fallback;

  /// Rotate pixels inside the portrait frame, not the frame itself.
  final int quarterTurns;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final source = path;
    if (source == null || source.isEmpty) return fallback;
    final uri = Uri.tryParse(source);
    final network = uri?.scheme == 'http' || uri?.scheme == 'https';
    if (!network && !File(source).existsSync()) return fallback;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: network
              ? Image.network(
                  source,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => fallback,
                )
              : Image.file(
                  File(source),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

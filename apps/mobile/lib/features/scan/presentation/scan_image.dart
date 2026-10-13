import 'dart:io';

import 'package:flutter/material.dart';

/// Scan media may be a just-captured local file or a persisted API crop URL.
class ScanImage extends StatelessWidget {
  const ScanImage({required this.path, required this.fallback, super.key});
  final String? path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final source = path;
    if (source == null || source.isEmpty) return fallback;
    final uri = Uri.tryParse(source);
    final network = uri?.scheme == 'http' || uri?.scheme == 'https';
    if (!network && !File(source).existsSync()) return fallback;
    return AspectRatio(
      aspectRatio: .74,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
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
    );
  }
}

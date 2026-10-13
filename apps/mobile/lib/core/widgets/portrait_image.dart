import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Only small public catalog thumbnails are persisted, never private user media.
class PortraitCache {
  PortraitCache({required this.directory, required this.download});

  final Future<Directory> Function() directory;
  final Future<List<int>> Function(String) download;
  final Map<String, Future<File>> _pending = {};

  static final shared = PortraitCache(
    directory: () async => Directory(
      '${(await getTemporaryDirectory()).path}/catalog-portraits-v1',
    ),
    download: (url) async {
      final response = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 25),
        ),
      );
      return response.data!;
    },
  );

  Future<File> get(String url) => _pending.putIfAbsent(url, () async {
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/${sha256.convert(utf8.encode(url))}.webp');
      if (await file.exists() &&
          DateTime.now().difference(await file.lastModified()).inDays < 7) {
        return file;
      }
      final bytes = await download(url);
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Invalid portrait size');
      }
      await file.writeAsBytes(bytes, flush: true);
      // A bounded cache also evicts old versions when an admin replaces a portrait.
      final files = await dir
          .list()
          .where((item) => item is File)
          .cast<File>()
          .toList();
      if (files.length > 200) {
        final dated = await Future.wait(
          files.map((f) async => (f, await f.lastModified())),
        );
        dated.sort((a, b) => a.$2.compareTo(b.$2));
        for (final entry in dated.take(dated.length - 200)) {
          if (entry.$1.path != file.path) {
            try {
              await entry.$1.delete();
            } on FileSystemException {
              /* Concurrent eviction. */
            }
          }
        }
      }
      return file;
    } finally {
      _pending.remove(url);
    }
  });

  Future<void> evict(String url) async {
    final dir = await directory();
    final file = File('${dir.path}/${sha256.convert(utf8.encode(url))}.webp');
    if (await file.exists()) await file.delete();
  }
}

class PortraitImage extends StatefulWidget {
  const PortraitImage({
    required this.url,
    required this.fallback,
    required this.fit,
    super.key,
  });
  final String url;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<PortraitImage> createState() => _PortraitImageState();
}

class _PortraitImageState extends State<PortraitImage> {
  late Future<File> _image;

  @override
  void initState() {
    super.initState();
    _image = PortraitCache.shared.get(widget.url);
  }

  @override
  void didUpdateWidget(PortraitImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _image = PortraitCache.shared.get(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: _image,
    builder: (context, snapshot) {
      if (!snapshot.hasData ||
          snapshot.connectionState != ConnectionState.done) {
        return widget.fallback;
      }
      return Image.file(
        snapshot.data!,
        width: double.infinity,
        height: double.infinity,
        fit: widget.fit,
        cacheWidth: 384,
        frameBuilder: (_, child, frame, synchronous) =>
            synchronous || frame != null ? child : widget.fallback,
        errorBuilder: (_, _, _) {
          // Remove an interrupted/corrupt cache entry so the next visit can retry.
          PortraitCache.shared.evict(widget.url).ignore();
          return widget.fallback;
        },
      );
    },
  );
}

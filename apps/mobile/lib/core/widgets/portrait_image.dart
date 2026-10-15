import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Only small public catalog thumbnails are persisted, never private user media.
class PortraitCache extends ChangeNotifier {
  PortraitCache({required this.directory, required this.download});

  final Future<Directory> Function() directory;
  final Future<List<int>> Function(String) download;
  final Map<String, Future<File>> _pending = {};
  final Map<String, (File, DateTime)> _ready = {};
  File? peek(String url) {
    final entry = _ready[url];
    if (entry == null || DateTime.now().difference(entry.$2).inDays >= 7) {
      return null;
    }
    return entry.$1;
  }

  static final _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 5)),
  );

  static final shared = PortraitCache(
    directory: () async => Directory(
      '${(await getTemporaryDirectory()).path}/catalog-portraits-v1',
    ),
    download: (url) async {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return response.data!;
    },
  );

  Future<File> get(String url) {
    final ready = peek(url);
    if (ready != null) return Future.value(ready);
    return _pending.putIfAbsent(url, () async {
      try {
        final dir = await directory();
        await dir.create(recursive: true);
        final file = File(
          '${dir.path}/${sha256.convert(utf8.encode(url))}.webp',
        );
        if (await file.exists() &&
            DateTime.now().difference(await file.lastModified()).inDays < 7) {
          _remember(url, file, await file.lastModified());
          return file;
        }
        final bytes = await download(url);
        if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Invalid portrait size');
        }
        await file.writeAsBytes(bytes, flush: true);
        _remember(url, file, DateTime.now());
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
  }

  void _remember(String url, File file, DateTime modified) {
    _ready[url] = (file, modified);
    if (_ready.length > 150) _ready.remove(_ready.keys.first);
    // A detail page can recover an image that failed in the still-mounted
    // profile tab. Notify that tab instead of leaving its failed Future pinned.
    notifyListeners();
  }

  Future<void> evict(String url) async {
    _ready.remove(url);
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
    this.errorFallback,
    this.cache,
    super.key,
  });
  final String url;
  final Widget fallback;
  final Widget? errorFallback;
  final BoxFit fit;
  final PortraitCache? cache;

  @override
  State<PortraitImage> createState() => _PortraitImageState();
}

class _PortraitImageState extends State<PortraitImage>
    with WidgetsBindingObserver {
  late Future<File> _image;
  PortraitCache get _cache => widget.cache ?? PortraitCache.shared;
  Timer? _retryTimer;
  int _request = 0;
  int _retryCount = 0;
  bool _failed = false;

  void _load() {
    _retryTimer?.cancel();
    _failed = false;
    final request = ++_request;
    _image = _cache.get(widget.url);
    unawaited(
      _image.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (!mounted || request != _request) return;
          _failed = true;
          // One bounded retry for a transient connection failure, never a loop.
          if (_retryCount++ == 0) {
            _retryTimer = Timer(const Duration(seconds: 1), () {
              if (mounted && request == _request && _failed) setState(_load);
            });
          }
        },
      ),
    );
  }

  void _cacheUpdated() {
    if (!_failed || !mounted) return;
    final recovered = _cache.peek(widget.url);
    if (recovered == null) return;
    _retryTimer?.cancel();
    _request++;
    setState(() {
      _failed = false;
      _image = Future.value(recovered);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _failed) {
      setState(_load);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cache.addListener(_cacheUpdated);
    _load();
  }

  @override
  void didUpdateWidget(PortraitImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache) {
      (oldWidget.cache ?? PortraitCache.shared).removeListener(_cacheUpdated);
      _cache.addListener(_cacheUpdated);
    }
    if (oldWidget.url != widget.url || oldWidget.cache != widget.cache) {
      _retryCount = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _retryTimer?.cancel();
    _cache.removeListener(_cacheUpdated);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: _image,
    initialData: _cache.peek(widget.url),
    builder: (context, snapshot) {
      if (snapshot.hasError) return widget.errorFallback ?? widget.fallback;
      if (!snapshot.hasData) {
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
          _cache.evict(widget.url).ignore();
          return widget.errorFallback ?? widget.fallback;
        },
      );
    },
  );
}

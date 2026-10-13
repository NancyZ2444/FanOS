import 'dart:convert';
import 'dart:io';

import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:path_provider/path_provider.dart';

/// Account-isolated files, flushed before an atomic rename. Never stores auth tokens.
class AlbumDraftStore {
  AlbumDraftStore(this.userId, {Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final String userId;
  final Future<Directory> Function() _directory;
  Future<void> _queue = Future.value();

  Future<File> _file(String key) async {
    final root = await _directory();
    final folder = Directory(
      '${root.path}/digital-albums/account-${Uri.encodeComponent(userId)}',
    );
    await folder.create(recursive: true);
    return File('${folder.path}/${Uri.encodeComponent(key)}.json');
  }

  Future<AlbumJson?> read(String key) async {
    await _queue;
    final file = await _file(key);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as AlbumJson;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String key, AlbumJson data) {
    final snapshot = jsonEncode(data);
    final operation = _queue.then((_) async {
      final file = await _file(key);
      final temp = File('${file.path}.pending');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(file.path);
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> remove(String key) {
    final operation = _queue.then((_) async {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> archive(String id, AlbumJson data) =>
      write('backup-$id-${DateTime.now().millisecondsSinceEpoch}', data);
}

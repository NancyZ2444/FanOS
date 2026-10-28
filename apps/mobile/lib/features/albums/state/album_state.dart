import 'dart:async';

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  final session = ref.watch(
    sessionProvider.select((s) => (s.userId, s.isLoggedIn)),
  );
  return useMockApi
      ? MockAlbumRepository(store: AlbumDraftStore('mock-${session.$1}'))
      : ApiAlbumRepository(ref.watch(apiClientProvider));
});
final albumDraftStoreProvider = Provider<AlbumDraftStore>(
  (ref) => AlbumDraftStore(ref.watch(sessionProvider.select((s) => s.userId))),
);
final albumResourcesProvider = FutureProvider<List<AlbumJson>>(
  (ref) => ref.watch(albumRepositoryProvider).resources(),
);
final albumQuotaProvider = FutureProvider<AlbumQuota>(
  (ref) => ref.watch(albumRepositoryProvider).quota(),
);
final albumDetailProvider = FutureProvider.autoDispose
    .family<PhotocardAlbum, String>(
      (ref, id) => ref.watch(albumRepositoryProvider).get(id),
    );
final albumEditorProvider = Provider.autoDispose
    .family<AlbumEditorController, String>((ref, id) {
      final controller = AlbumEditorController(
        id,
        ref.watch(albumRepositoryProvider),
        ref.watch(albumDraftStoreProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class AlbumEditorController extends ChangeNotifier {
  AlbumEditorController(this.id, this.repository, this.store);
  final String id;
  final AlbumRepository repository;
  final AlbumDraftStore store;
  PhotocardAlbum? album;
  AlbumQuota? quota;
  bool loading = true,
      saving = false,
      dirty = false,
      conflict = false,
      disposed = false;
  String? error;
  String status = '正在加载…';
  Timer? _timer;
  Future<void>? _inFlight;
  int _generation = 0;
  final _undo = <AlbumJson>[], _redo = <AlbumJson>[];
  String? _editGroup;
  DateTime? _lastGroupedEdit;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void _notify() {
    if (!disposed) notifyListeners();
  }

  Future<void> load({bool discardLocal = false}) async {
    loading = true;
    error = null;
    _notify();
    try {
      final local = await store.read('draft-$id');
      if (discardLocal && local != null) {
        await store.archive(id, local);
        await store.remove('draft-$id');
      }
      PhotocardAlbum? remote;
      try {
        remote = await repository.get(id);
      } catch (e) {
        if (local == null || discardLocal) rethrow;
        error = e.toString();
      }
      if (remote != null && !remote.isOwner) {
        throw const ApiException('ALBUM_FORBIDDEN', '只有创建者可以编辑相册');
      }
      if (!discardLocal && local != null) {
        var restored = cloneAlbumJson(local['album'] as AlbumJson);
        if (remote != null &&
            remote.json['work_mode'] != null &&
            restored['work_mode'] == null) {
          // Preserve the old draft before adapting its data to the confirmed fixed type.
          await store.archive(id, local);
          restored['work_mode'] = remote.workMode;
          if (remote.opensAsCards) {
            final placements = [
              for (final p in restored['pages'] as List? ?? [])
                for (final s in p['slots'] as List)
                  if (s['card_id'] != null) s,
            ];
            restored['card_instances'] = placements;
            restored['pages'] = <AlbumJson>[];
            restored['cover'] = <String, dynamic>{};
          }
          synchronizeAlbum(restored);
        }
        album = PhotocardAlbum(restored);
        if (remote != null) {
          album = album!.edit((data) {
            for (final key in [
              'is_moderated',
              'publication_blocked',
              'moderation_status',
              'moderation_reason',
              'moderation_note',
              'review_status',
            ]) {
              if (remote!.json.containsKey(key)) data[key] = remote.json[key];
            }
          });
        }
        final ids = {
          ...album!.occupiedSlots.map((s) => s['card_id'] as String),
          ...((album!.cover['elements'] as List?) ?? [])
              .cast<AlbumJson>()
              .where((e) => e['type'] == 'CARD')
              .map((e) => e['content'] as String),
          ...((album!.json['_pending_cards'] as List?) ?? []).cast<String>(),
        }.toList();
        try {
          final freshAssets = await repository.cardAssets(ids);
          album = album!.edit(
            (d) => (d['cards'] as AlbumJson).addAll(freshAssets),
          );
        } catch (_) {
          // Preserve layout offline, but never display cached official images without
          // checking their current copyright availability after restoring a draft.
          album = album!.edit(
            (d) => d['cards'] = {
              for (final id in ids)
                id: {'id': id, 'available': false, 'title': '联网后查看小卡'},
            },
          );
        }
        dirty = true;
        conflict = remote != null && album!.revision != remote.revision;
        status = conflict ? '版本冲突 · 本地草稿已保留' : '已恢复本地草稿';
      } else {
        album = remote;
        dirty = false;
        conflict = false;
        status = '已保存';
      }
      try {
        quota = await repository.quota();
      } catch (_) {
        /* Existing pages remain editable offline. */
      }
      if (dirty && !conflict && remote != null) _schedule();
    } catch (e) {
      error = e.toString();
      status = '加载失败';
    } finally {
      loading = false;
      _notify();
    }
  }

  void edit(void Function(AlbumJson data) change, {String? group}) {
    if (album == null) return;
    final now = DateTime.now();
    if (group == null ||
        group != _editGroup ||
        _lastGroupedEdit == null ||
        now.difference(_lastGroupedEdit!).inMilliseconds > 800) {
      _undo.add(cloneAlbumJson(album!.json));
    }
    _editGroup = group;
    _lastGroupedEdit = now;
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    album = album!.edit(change);
    _changed();
  }

  void _changed() {
    _generation++;
    dirty = true;
    error = null;
    status = conflict ? '版本冲突 · 本地草稿已保留' : '保存中…';
    unawaited(_persist());
    _schedule();
    _notify();
  }

  Future<void> _persist() async {
    final current = album;
    if (current == null) return;
    try {
      await store.write('draft-$id', {
        'album': current.json,
        'saved_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      error = '本地草稿保存失败，请重试';
      status = error!;
      _notify();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!conflict) {
      _timer = Timer(
        const Duration(milliseconds: 700),
        () => unawaited(save()),
      );
    }
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(cloneAlbumJson(album!.json));
    final data = _undo.removeLast()..['revision'] = album!.revision;
    album = PhotocardAlbum(data);
    _editGroup = null;
    _changed();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(cloneAlbumJson(album!.json));
    final data = _redo.removeLast()..['revision'] = album!.revision;
    album = PhotocardAlbum(data);
    _editGroup = null;
    _changed();
  }

  Future<void> save() {
    _timer?.cancel();
    if (_inFlight != null) return _inFlight!;
    _inFlight = _save().whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<void> _save() async {
    if (album == null || !dirty || conflict) return;
    saving = true;
    _notify();
    try {
      await _persist();
      final snapshot = album!;
      final generation = _generation;
      final result = await repository.save(snapshot);
      if (generation == _generation) {
        final pending = snapshot.json['_pending_cards'];
        album = pending is List && pending.isNotEmpty
            ? result.edit((d) {
                d['_pending_cards'] = pending;
                final cards = d['cards'] as AlbumJson;
                final cached = snapshot.json['cards'] as AlbumJson;
                for (final id in pending) {
                  if (!cards.containsKey(id) && cached.containsKey(id)) {
                    cards[id as String] = cached[id];
                  }
                }
              })
            : result;
        dirty = false;
        status = '已自动保存';
        error = null;
        if (pending is List && pending.isNotEmpty) {
          await _persist();
        } else {
          await store.remove('draft-$id');
        }
      } else {
        album = album!.edit((data) => data['revision'] = result.revision);
        await _persist();
        _schedule();
      }
    } catch (e) {
      conflict = e is ApiException && e.code == 'ALBUM_REVISION_CONFLICT';
      status = conflict ? '版本冲突 · 本地草稿已保留' : '保存失败 · 本地草稿已保留';
      error = e.toString();
      await _persist();
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<PhotocardAlbum?> finish() async {
    await save();
    if (dirty) {
      await save();
      if (dirty) return null;
    }
    try {
      album = await repository.publish(album!);
      status = '已完成';
      _notify();
      return album;
    } catch (e) {
      error = e.toString();
      status = '发布失败，请重试';
      _notify();
      return null;
    }
  }

  Future<bool> requestReview() async {
    await save();
    if (dirty) {
      await save();
      if (dirty) return false;
    }
    if (album == null) return false;
    try {
      album = await repository.requestReview(album!);
      error = null;
      status = '复核已提交';
      _notify();
      return true;
    } catch (e) {
      error = e.toString();
      status = '复核提交失败';
      _notify();
      return false;
    }
  }

  Future<void> retainDraft() async {
    _timer?.cancel();
    if (dirty) await _persist();
  }

  @override
  void dispose() {
    _timer?.cancel();
    disposed = true;
    super.dispose();
  }
}

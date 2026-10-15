import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AlbumFavoriteFolder {
  const AlbumFavoriteFolder({
    required this.id,
    required this.name,
    this.isPublic = false,
    this.count = 0,
  });
  final String id, name;
  final bool isPublic;
  final int count;
  factory AlbumFavoriteFolder.fromJson(AlbumJson json) => AlbumFavoriteFolder(
    id: json['id'] as String,
    name: json['name'] as String,
    isPublic: json['is_public'] == true,
    count: (json['album_count'] as num?)?.toInt() ?? 0,
  );
  AlbumJson get json => {
    'id': id,
    'name': name,
    'is_public': isPublic,
    'album_count': count,
  };
}

abstract class AlbumFavoritesRepository {
  Future<List<AlbumFavoriteFolder>> folders({String? userId});
  Future<AlbumFavoriteFolder> saveFolder(
    String name,
    bool isPublic, {
    String? id,
  });
  Future<AlbumShelfData> list({
    String? userId,
    String? groupId,
    int offset = 0,
  });
  Future<void> save(String albumId, String? groupId, {bool move = false});
  Future<void> remove(String albumId);
}

final albumFavoritesRepositoryProvider = Provider<AlbumFavoritesRepository>((
  ref,
) {
  final userId = ref.watch(sessionProvider.select((s) => s.userId));
  if (useMockApi) {
    return LocalAlbumFavoritesRepository(AlbumDraftStore('mock-$userId'), ref);
  }
  return ApiAlbumFavoritesRepository(ref.watch(apiClientProvider), userId);
});

class ApiAlbumFavoritesRepository implements AlbumFavoritesRepository {
  ApiAlbumFavoritesRepository(this.client, this.userId);
  final ApiClient client;
  final String userId;
  @override
  Future<void> remove(String albumId) async {
    await client.deleteData('/albums/$albumId/favorite');
  }

  @override
  Future<List<AlbumFavoriteFolder>> folders({String? userId}) async =>
      ((await client.getData('/users/${userId ?? 'me'}/album-favorite-groups')
                  as AlbumJson)['items']
              as List)
          .map((j) => AlbumFavoriteFolder.fromJson(j as AlbumJson))
          .toList();
  @override
  Future<AlbumFavoriteFolder> saveFolder(
    String name,
    bool isPublic, {
    String? id,
  }) async {
    final body = {'name': name, 'is_public': isPublic};
    final data = id == null
        ? await client.postData('/users/me/album-favorite-groups', data: body)
        : await client.putData(
            '/users/me/album-favorite-groups/$id',
            data: body,
          );
    return AlbumFavoriteFolder.fromJson(data as AlbumJson);
  }

  @override
  Future<AlbumShelfData> list({
    String? userId,
    String? groupId,
    int offset = 0,
  }) async => AlbumShelfData.fromJson(
    await client.getData(
      '/users/${userId ?? this.userId}/favorite-albums',
      query: {'offset': offset, 'group_id': ?groupId},
    ) as AlbumJson,
  );
  @override
  Future<void> save(
    String albumId,
    String? groupId, {
    bool move = false,
  }) async {
    if (move) {
      await client.putData(
        '/users/me/favorite-albums/$albumId/group',
        data: {'group_id': groupId},
      );
    } else {
      await client.postData(
        '/albums/$albumId/favorite',
        data: {'group_id': groupId},
      );
    }
  }
}

/// Isolated local persistence for the mock environment, never shared with API accounts.
class LocalAlbumFavoritesRepository implements AlbumFavoritesRepository {
  LocalAlbumFavoritesRepository(this.store, this.ref);
  final AlbumDraftStore store;
  final Ref ref;
  @override
  Future<void> remove(String albumId) async {
    final data = await _load();
    (data['albums'] as List).removeWhere((a) => a['id'] == albumId);
    await store.write('favorite-folders', data);
  }

  Future<AlbumJson> _load() async =>
      await store.read('favorite-folders') ?? {'folders': [], 'albums': []};
  @override
  Future<List<AlbumFavoriteFolder>> folders({String? userId}) async {
    if (userId != null) return [];
    final data = await _load();
    return (data['folders'] as List)
        .map(
          (j) => AlbumFavoriteFolder.fromJson({
            ...j as AlbumJson,
            'album_count': (data['albums'] as List)
                .where((a) => a['favorite_group_id'] == j['id'])
                .length,
          }),
        )
        .toList();
  }

  @override
  Future<AlbumFavoriteFolder> saveFolder(
    String name,
    bool isPublic, {
    String? id,
  }) async {
    final data = await _load();
    final folders = (data['folders'] as List).cast<AlbumJson>();
    if (folders.any(
      (f) =>
          f['id'] != id &&
          (f['name'] as String).toLowerCase() == name.trim().toLowerCase(),
    )) {
      throw const ApiException('FAVORITE_GROUP_DUPLICATE', '已存在同名收藏分组');
    }
    final folder = AlbumFavoriteFolder(
      id: id ?? 'folder-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      isPublic: isPublic,
    );
    folders.removeWhere((f) => f['id'] == id);
    folders.add(folder.json);
    data['folders'] = folders;
    await store.write('favorite-folders', data);
    return folder;
  }

  @override
  Future<AlbumShelfData> list({
    String? userId,
    String? groupId,
    int offset = 0,
  }) async {
    if (userId != null) return AlbumShelfData([]);
    final data = await _load();
    final albums =
        (data['albums'] as List)
            .cast<AlbumJson>()
            .where(
              (a) =>
                  groupId == null ||
                  (groupId == 'ungrouped'
                      ? a['favorite_group_id'] == null
                      : a['favorite_group_id'] == groupId),
            )
            .toList()
          ..sort(
            (a, b) => (b['favorited_at'] as String).compareTo(
              a['favorited_at'] as String,
            ),
          );
    return AlbumShelfData(
      albums.skip(offset).take(20).map(PhotocardAlbum.new).toList(),
      nextOffset: albums.length > offset + 20 ? offset + 20 : null,
    );
  }

  @override
  Future<void> save(
    String albumId,
    String? groupId, {
    bool move = false,
  }) async {
    final data = await _load();
    final albums = (data['albums'] as List).cast<AlbumJson>();
    final existing = albums.where((a) => a['id'] == albumId).firstOrNull;
    final album =
        existing ?? (await ref.read(albumRepositoryProvider).get(albumId)).json;
    if (album['is_owner'] == true) {
      throw const ApiException('ALBUM_SELF_REACTION', '自己的作品无需收藏');
    }
    album['favorite_group_id'] = groupId;
    album['favorited_at'] ??= DateTime.now().toIso8601String();
    if (existing == null) albums.add(album);
    data['albums'] = albums;
    await store.write('favorite-folders', data);
  }
}

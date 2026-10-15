import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';

abstract interface class AlbumRepository {
  Future<AlbumShelfData> list({
    String q = '',
    String sort = 'updated',
    int offset = 0,
    bool favorites = false,
    String status = 'ALL',
    String? userId,
  });
  Future<PhotocardAlbum> get(String id);
  Future<AlbumJson> cardAssets(List<String> cardIds);
  Future<PhotocardAlbum> create(String name, String display, String style);
  Future<PhotocardAlbum> save(PhotocardAlbum album);
  Future<PhotocardAlbum> publish(PhotocardAlbum album);
  Future<PhotocardAlbum> duplicate(PhotocardAlbum album);
  Future<void> delete(PhotocardAlbum album);
  Future<AlbumQuota> quota();
  Future<List<AlbumJson>> resources();
  Future<void> preferences(String theme, String viewMode);
  Future<void> react(String id, String kind, bool active);
  Future<void> report(String id, String reason);
}

class ApiAlbumRepository implements AlbumRepository {
  ApiAlbumRepository(this.client);
  final ApiClient client;
  @override
  Future<AlbumShelfData> list({
    String q = '',
    String sort = 'updated',
    int offset = 0,
    bool favorites = false,
    String status = 'ALL',
    String? userId,
  }) async {
    final path = favorites
        ? '/users/me/favorite-albums'
        : userId != null
        ? '/users/$userId/albums'
        : '/albums';
    return AlbumShelfData.fromJson(
      await client.getData(
        path,
        query: {'q': q, 'sort': sort, 'offset': offset, 'status': status},
      ) as AlbumJson,
    );
  }

  @override
  Future<PhotocardAlbum> get(String id) async =>
      PhotocardAlbum(await client.getData('/albums/$id') as AlbumJson);
  @override
  Future<AlbumJson> cardAssets(List<String> cardIds) async =>
      (await client.postData('/albums/card-assets', data: {'card_ids': cardIds})
              as AlbumJson)['cards']
          as AlbumJson;
  @override
  Future<PhotocardAlbum> create(
    String name,
    String display,
    String style,
  ) async => PhotocardAlbum(
    await client.postData(
      '/albums',
      data: {'name': name, 'display_type': display, 'visual_style': style},
    ) as AlbumJson,
  );
  @override
  Future<PhotocardAlbum> save(PhotocardAlbum album) async => PhotocardAlbum(
    await client.patchData('/albums/${album.id}', data: album.patch)
        as AlbumJson,
  );
  @override
  Future<PhotocardAlbum> publish(PhotocardAlbum album) async => PhotocardAlbum(
    await client.postData(
      '/albums/${album.id}/publish',
      data: {'revision': album.revision},
    ) as AlbumJson,
  );
  @override
  Future<PhotocardAlbum> duplicate(PhotocardAlbum album) async =>
      PhotocardAlbum(
        await client.postData(
          '/albums/${album.id}/duplicate',
          data: {'revision': album.revision},
        ) as AlbumJson,
      );
  @override
  Future<void> delete(PhotocardAlbum album) async {
    await client.deleteData('/albums/${album.id}?revision=${album.revision}');
  }

  @override
  Future<AlbumQuota> quota() async =>
      AlbumQuota.fromJson(await client.getData('/albums/quota') as AlbumJson);
  @override
  Future<List<AlbumJson>> resources() async =>
      ((await client.getData('/albums/resources') as AlbumJson)['items']
              as List)
          .cast<AlbumJson>();
  @override
  Future<void> preferences(String theme, String viewMode) async {
    await client.putData(
      '/albums/preferences',
      data: {'shelf_theme': theme, 'view_mode': viewMode},
    );
  }

  @override
  Future<void> react(String id, String kind, bool active) async {
    if (active) {
      await client.postData('/albums/$id/$kind');
    } else {
      await client.deleteData('/albums/$id/$kind');
    }
  }

  @override
  Future<void> report(String id, String reason) async {
    await client.postData('/albums/$id/report', data: {'reason': reason});
  }
}

class MockAlbumRepository implements AlbumRepository {
  MockAlbumRepository({this.store});
  final AlbumDraftStore? store;
  Future<void>? _ready;
  Future<void> _load() => _ready ??= (() async {
    final data = await store?.read('mock-library');
    if (data == null) return;
    for (final row in (data['albums'] as List? ?? [])) {
      final album = PhotocardAlbum(row as AlbumJson);
      _albums[album.id] = album;
    }
    _theme = data['theme'] as String? ?? _theme;
    _view = data['view'] as String? ?? _view;
  })();
  Future<void> _persist() async => store?.write('mock-library', {
    'albums': _albums.values.map((a) => a.json).toList(),
    'theme': _theme,
    'view': _view,
  });
  final _albums = <String, PhotocardAlbum>{};
  String _theme = 'cream-white', _view = 'SHELF';
  @override
  Future<AlbumQuota> quota() async {
    await _load();
    return AlbumQuota(
      albumCount: _albums.length,
      maxAlbums: 10,
      maxPages: 10,
      maxSlots: 9,
    );
  }

  @override
  Future<AlbumShelfData> list({
    String q = '',
    String sort = 'updated',
    int offset = 0,
    bool favorites = false,
    String status = 'ALL',
    String? userId,
  }) async {
    await _load();
    final rows = favorites || userId != null
        ? <PhotocardAlbum>[]
        : _albums.values
              .where(
                (a) =>
                    a.name.toLowerCase().contains(q.toLowerCase()) &&
                    (status == 'ALL' || a.json['status'] == status),
              )
              .toList();
    if (sort == 'name') {
      rows.sort((a, b) => a.name.compareTo(b.name));
    } else {
      rows.sort(
        (a, b) =>
            (b.json[sort == 'created' ? 'created_at' : 'updated_at'] as String)
                .compareTo(
                  a.json[sort == 'created' ? 'created_at' : 'updated_at']
                      as String,
                ),
      );
    }
    return AlbumShelfData(
      rows.skip(offset).take(20).toList(),
      nextOffset: rows.length > offset + 20 ? offset + 20 : null,
      quota: await quota(),
      theme: _theme,
      viewMode: _view,
    );
  }

  @override
  Future<PhotocardAlbum> get(String id) async {
    await _load();
    return _albums[id] ??
        (throw const ApiException('ALBUM_NOT_FOUND', '相册不存在或已删除'));
  }

  @override
  Future<AlbumJson> cardAssets(List<String> cardIds) async {
    await _load();
    return {
      for (final a in _albums.values)
        for (final id in cardIds)
          if ((a.json['cards'] as AlbumJson?)?.containsKey(id) == true)
            id: (a.json['cards'] as AlbumJson)[id],
    };
  }

  @override
  Future<PhotocardAlbum> create(
    String name,
    String display,
    String style,
  ) async {
    await _load();
    if (_albums.length >= 10) {
      throw const ApiException('ALBUM_QUOTA_EXCEEDED', '相册数量已达上限');
    }
    final album = PhotocardAlbum({
      'id': albumId('album'),
      'user_id': 'current-user',
      'author_name': '星河收藏家',
      'is_owner': true,
      'name': name,
      'description': '',
      'display_type': display,
      'visual_style': style,
      'visibility': 'PRIVATE',
      'status': 'DRAFT',
      'revision': 1,
      'cover': albumCanvas(),
      'pages': <AlbumJson>[],
      'card_view': <String, dynamic>{},
      'cards': {
        for (final c in DemoCatalog.cards)
          c.id: {
            'id': c.id,
            'title': c.title,
            'idol_id': c.idolId,
            'idol_name': c.idolName,
            'group_id': c.groupId,
            'group_name': c.groupName,
            'source': c.source,
            'card_type': c.cardType,
            'version': c.version,
            'release_date': c.releaseDate,
            'region': c.region,
            'color_start': c.colorStart,
            'color_end': c.colorEnd,
            'image_url': c.imageUrl,
            'back_image_url': c.backImageUrl,
          },
      },
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    _albums[album.id] = album.edit((_) {});
    await _persist();
    return _albums[album.id]!;
  }

  @override
  Future<PhotocardAlbum> save(PhotocardAlbum album) async {
    final previous = await get(album.id);
    if (previous.revision != album.revision) {
      throw const ApiException('ALBUM_REVISION_CONFLICT', '相册已更新，请重新加载');
    }
    if (album.pages.length > 10 && album.pages.length > previous.pages.length) {
      throw const ApiException('ALBUM_PAGE_QUOTA_EXCEEDED', '当前相册已达到页数上限');
    }
    _albums[album.id] = album.edit((d) {
      d['revision'] = album.revision + 1;
      d['updated_at'] = DateTime.now().toIso8601String();
    });
    await _persist();
    return _albums[album.id]!;
  }

  @override
  Future<PhotocardAlbum> publish(PhotocardAlbum album) async =>
      save(album.edit((d) => d['status'] = 'PUBLISHED'));
  @override
  Future<PhotocardAlbum> duplicate(PhotocardAlbum album) async {
    final target = await create(
      '${album.name} 副本',
      album.isDouble ? 'DOUBLE' : 'SINGLE',
      album.realistic ? 'REALISTIC' : 'MINIMAL',
    );
    final data = cloneAlbumJson(album.json)
      ..['id'] = target.id
      ..['revision'] = target.revision
      ..['visibility'] = 'PRIVATE'
      ..['status'] = 'DRAFT';
    final mapping = <String, String>{};
    for (final p in (data['pages'] as List).cast<AlbumJson>()) {
      p['id'] = albumId('page');
      for (final s in (p['slots'] as List).cast<AlbumJson>()) {
        mapping[s['id'] as String] = albumId('slot');
        s['id'] = mapping[s['id']];
      }
    }
    final view = data['card_view'] as AlbumJson;
    view['card_order'] = [
      for (final id in view['card_order'] as List)
        if (mapping.containsKey(id)) mapping[id],
    ];
    view['featured_slot_id'] = mapping[view['featured_slot_id']];
    return save(PhotocardAlbum(data));
  }

  @override
  Future<void> delete(PhotocardAlbum album) async {
    await _load();
    if ((await get(album.id)).revision != album.revision) {
      throw const ApiException('ALBUM_REVISION_CONFLICT', '相册已更新，请重新加载');
    }
    _albums.remove(album.id);
    await _persist();
  }

  @override
  Future<void> preferences(String theme, String viewMode) async {
    await _load();
    _theme = theme;
    _view = viewMode;
    await _persist();
  }

  @override
  Future<void> react(String id, String kind, bool active) async {}
  @override
  Future<void> report(String id, String reason) async {}
  @override
  Future<List<AlbumJson>> resources() async => [
    for (final r in [
      ('cream-white', '奶油白', '#F4EEE7', '#FFFFFF', '#DAD0C5'),
      ('soft-pink', '浅粉色', '#F4DCE5', '#FFF6FA', '#D7B5C3'),
      ('natural-wood', '浅木色', '#D7C7BB', '#F5E6D7', '#C8B5A5'),
      ('silver-metal', '银色金属', '#CDD0DC', '#F5F6FB', '#A9AEBB'),
      ('minimal', '极简', '#F0EDFF', '#FAFAFF', '#DED8F7'),
    ])
      {
        'id': r.$1,
        'name': r.$2,
        'kind': 'SHELF',
        'config': {
          'colors': [r.$3, r.$4],
          'ledge': r.$5,
        },
      },
    for (final r in [
      ('star', '星光', '✦'),
      ('heart', '热爱', '♡'),
      ('bow', '蝴蝶结', '🎀'),
      ('flower', '花朵', '✿'),
      ('stay', '陪伴', 'STAY'),
    ])
      {
        'id': r.$1,
        'name': r.$2,
        'kind': 'STICKER',
        'config': {'symbol': r.$3},
      },
    {
      'id': 'dream',
      'name': '梦境',
      'kind': 'BACKGROUND',
      'config': albumBackground(),
    },
  ];
}

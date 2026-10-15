import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const libraryLabels = {
  'all': '全部',
  'owned': '已拥有',
  'wishlist': '心愿单',
  'albums': '卡册',
};

class LibrarySearchItem {
  const LibrarySearchItem({
    this.card,
    this.album,
    this.quantity = 0,
    this.category = '',
    this.matchType = '',
  });
  final CollectibleCard? card;
  final PhotocardAlbum? album;
  final int quantity;
  final String category, matchType;
  String get id => card?.id ?? album!.id;
  factory LibrarySearchItem.fromJson(AlbumJson j) => LibrarySearchItem(
    card: j['card'] is AlbumJson ? CollectibleCard.fromJson(j['card']) : null,
    album: j['album'] is AlbumJson ? PhotocardAlbum(j['album']) : null,
    quantity: (j['quantity'] as num?)?.toInt() ?? 0,
    category: j['category'] as String? ?? '',
    matchType: j['match_type'] as String? ?? '',
  );
}

class LibrarySearchGroup {
  const LibrarySearchGroup({
    this.items = const [],
    this.total = 0,
    this.nextOffset,
  });
  final List<LibrarySearchItem> items;
  final int total;
  final int? nextOffset;
}

class LibrarySearchResult {
  const LibrarySearchResult(this.groups);
  final Map<String, LibrarySearchGroup> groups;
  int get total => groups.values.fold(0, (n, g) => n + g.total);
  factory LibrarySearchResult.fromJson(AlbumJson j) => LibrarySearchResult({
    for (final e in (j['groups'] as AlbumJson).entries)
      e.key: LibrarySearchGroup(
        items: (e.value['items'] as List)
            .map((i) => LibrarySearchItem.fromJson(i as AlbumJson))
            .toList(),
        total: (e.value['total'] as num).toInt(),
        nextOffset: (e.value['next_offset'] as num?)?.toInt(),
      ),
  });
}

abstract interface class LibrarySearchRepository {
  Future<LibrarySearchResult> search(
    String query, {
    String scope = 'all',
    int offset = 0,
  });
}

class ApiLibrarySearchRepository implements LibrarySearchRepository {
  ApiLibrarySearchRepository(this.client);
  final ApiClient client;
  @override
  Future<LibrarySearchResult> search(
    String query, {
    String scope = 'all',
    int offset = 0,
  }) async => LibrarySearchResult.fromJson(
    await client.getData(
      '/me/library/search',
      query: {'q': query.trim(), 'scope': scope, 'offset': offset},
    ) as AlbumJson,
  );
}

String libraryCardSearchText(CollectibleCard c) =>
    '${c.cardNumber} ${c.title} ${c.titleEn} ${c.titleKo} ${c.titleTranslated} ${c.idolName} ${c.groupName} ${c.source} ${c.version} ${c.cardType}'
        .toLowerCase();

/// Demo-only counterpart. Production always searches the authenticated API.
class MockLibrarySearchRepository implements LibrarySearchRepository {
  MockLibrarySearchRepository(this.catalog, this.relations, this.albums);
  final Future<CatalogBundle> Function() catalog;
  final CollectionState Function() relations;
  final AlbumRepository albums;
  @override
  Future<LibrarySearchResult> search(
    String query, {
    String scope = 'all',
    int offset = 0,
  }) async {
    final q = query.trim().toLowerCase();
    final buckets = {
      for (final k in ['owned', 'wishlist', 'albums']) k: <LibrarySearchItem>[],
    };
    if (q.isEmpty) {
      return LibrarySearchResult({
        for (final k in buckets.keys) k: const LibrarySearchGroup(),
      });
    }
    final all = (await catalog()).cards;
    final matching = all
        .where((c) => libraryCardSearchText(c).contains(q))
        .toList();
    final state = relations();
    buckets['owned']!.addAll(
      matching
          .where((c) => state.isOwned(c.id))
          .map(
            (c) => LibrarySearchItem(card: c, quantity: state.quantity(c.id)),
          ),
    );
    buckets['wishlist']!.addAll(
      matching
          .where((c) => state.isWished(c.id))
          .map((c) => LibrarySearchItem(card: c)),
    );
    for (final favorite in [false, true]) {
      int? at = 0;
      while (at != null) {
        final page = await albums.list(favorites: favorite, offset: at);
        for (final a in page.albums) {
          if (a.unavailable) continue;
          final doc = await albums.get(a.id);
          final title = a.name.toLowerCase().contains(q);
          if (title ||
              doc.occupiedSlots.any(
                (s) => matching.any((c) => c.id == s['card_id']),
              )) {
            buckets['albums']!.add(
              LibrarySearchItem(
                album: a,
                category: favorite
                    ? 'favorite'
                    : a.isDraft
                    ? 'draft'
                    : 'created',
                matchType: title ? 'name' : 'card',
              ),
            );
          }
        }
        at = page.nextOffset;
      }
    }
    return LibrarySearchResult({
      for (final e in buckets.entries)
        e.key: LibrarySearchGroup(
          items: scope == 'all' || scope == e.key
              ? e.value.skip(offset).take(20).toList()
              : [],
          total: e.value.length,
          nextOffset: e.value.length > offset + 20 ? offset + 20 : null,
        ),
    });
  }
}

final librarySearchRepositoryProvider = Provider<LibrarySearchRepository>((
  ref,
) {
  if (!useMockApi) {
    return ApiLibrarySearchRepository(ref.watch(apiClientProvider));
  }
  return MockLibrarySearchRepository(
    () => ref.read(catalogProvider.future),
    () => ref.read(collectionProvider),
    ref.watch(albumRepositoryProvider),
  );
});

import 'dart:convert';
import 'dart:math';

import 'package:fan_os/core/data/models.dart';

typedef AlbumJson = Map<String, dynamic>;

AlbumJson cloneAlbumJson(AlbumJson value) =>
    jsonDecode(jsonEncode(value)) as AlbumJson;
String albumId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

AlbumJson albumBackground([List<String> colors = const ['#E8EBE3']]) => {
  'type': colors.length > 1 ? 'GRADIENT' : 'SOLID',
  'colors': colors,
  'angle': 45.0,
};
AlbumJson albumCanvas() => {
  'background': albumBackground(),
  'elements': <AlbumJson>[],
};
AlbumJson blankAlbumPage(int gridCount) => {
  'id': albumId('page'),
  'grid_count': gridCount,
  'config': albumCanvas(),
  'slots': List.generate(
    gridCount,
    (_) => {'id': albumId('slot'), 'card_id': null},
  ),
};

class PhotocardAlbum {
  PhotocardAlbum(AlbumJson json) : json = cloneAlbumJson(json);
  final AlbumJson json;
  String get id => json['id'] as String;
  String get name => json['name'] as String? ?? '我的小卡册';
  String get description => json['description'] as String? ?? '';
  int get revision => (json['revision'] as num?)?.toInt() ?? 1;
  bool get isOwner => json['is_owner'] == true;
  bool get isDraft => json['status'] == 'DRAFT';
  bool get isPublic => json['visibility'] == 'PUBLIC';
  bool get unavailable => json['unavailable'] == true;
  bool get isDouble => json['display_type'] == 'DOUBLE';
  bool get realistic => json['visual_style'] != 'MINIMAL';
  bool get liked => json['liked'] == true;
  bool get favorited => json['favorited'] == true;
  int get likeCount => (json['like_count'] as num?)?.toInt() ?? 0;
  int get pageCount => (json['page_count'] as num?)?.toInt() ?? pages.length;
  int get cardCount =>
      (json['card_count'] as num?)?.toInt() ?? occupiedSlots.length;
  AlbumJson get cover => (json['cover'] as AlbumJson?) ?? albumCanvas();
  AlbumJson get cardView => (json['card_view'] as AlbumJson?) ?? {};
  List<AlbumJson> get pages =>
      ((json['pages'] as List?) ?? []).cast<AlbumJson>();
  List<AlbumJson> get occupiedSlots => [
    for (final p in pages)
      for (final s in (p['slots'] as List).cast<AlbumJson>())
        if (s['card_id'] != null) s,
  ];
  List<AlbumJson> get orderedSlots {
    final byId = {for (final s in occupiedSlots) s['id']: s};
    if (cardView['order_customized'] != true) return occupiedSlots;
    final order = ((cardView['card_order'] as List?) ?? []).cast<String>();
    return [
      for (final id in order)
        if (byId.containsKey(id)) byId[id]!,
      for (final s in occupiedSlots)
        if (!order.contains(s['id'])) s,
    ];
  }

  List<String> get orderedSlotIds =>
      orderedSlots.map((s) => s['id'] as String).toList();
  bool get opensAsCards => cardView['default_mode'] == 'CARDS';
  String? get featuredSlotId {
    final slots = orderedSlots;
    final saved = cardView['featured_slot_id'];
    return slots.any((s) => s['id'] == saved)
        ? saved as String
        : slots.firstOrNull?['id'] as String?;
  }

  /// Featured front first, then the current order. Shelf summaries provide
  /// only these slots instead of downloading all inner pages.
  List<AlbumJson> get coverSlots {
    if (!json.containsKey('pages')) {
      return ((json['cover_slots'] as List?) ?? [])
          .cast<AlbumJson>()
          .take(5)
          .toList();
    }
    final slots = orderedSlots;
    final featured = featuredSlotId;
    return [
      ...slots.where((s) => s['id'] == featured),
      ...slots.where((s) => s['id'] != featured),
    ].take(5).toList();
  }

  bool get usesStackCover =>
      cardView['cover_style'] == 'STACK_V1' ||
      (cardView['cover_style'] != 'CUSTOM' &&
          ((cover['elements'] as List?) ?? []).isEmpty &&
          coverSlots.isNotEmpty);
  List<String> get displayFields =>
      ((cardView['display_fields'] as List?) ?? ['idol', 'group', 'source'])
          .cast<String>();

  CollectibleCard? card(String? id) {
    if (id == null) return null;
    final raw = (json['cards'] as AlbumJson?)?[id];
    if (raw is! AlbumJson || raw['available'] == false) return null;
    return CollectibleCard.fromJson(raw);
  }

  PhotocardAlbum edit(void Function(AlbumJson data) change) {
    final data = cloneAlbumJson(json);
    change(data);
    synchronizeAlbum(data);
    return PhotocardAlbum(data);
  }

  AlbumJson get patch => {
    for (final key in [
      'name',
      'description',
      'display_type',
      'visual_style',
      'visibility',
      'cover',
      'pages',
      'card_view',
    ])
      if (json.containsKey(key)) key: json[key],
    'revision': revision,
    'confirm_removal': true,
    'confirm_duplicates': true,
  };
}

void synchronizeAlbum(AlbumJson data) {
  final pages = ((data['pages'] as List?) ?? []).cast<AlbumJson>();
  final occupied = [
    for (final p in pages)
      for (final s in (p['slots'] as List).cast<AlbumJson>())
        if (s['card_id'] != null) s['id'] as String,
  ];
  final view = (data['card_view'] as AlbumJson?) ?? <String, dynamic>{};
  final custom = view['order_customized'] == true;
  final order = ((view['card_order'] as List?) ?? [])
      .cast<String>()
      .where(occupied.contains)
      .toSet()
      .toList();
  view['card_order'] = custom
      ? [...order, ...occupied.where((s) => !order.contains(s))]
      : occupied;
  if (!occupied.contains(view['featured_slot_id'])) {
    view['featured_slot_id'] = null;
  }
  view['order_customized'] = custom;
  view['background'] ??= albumBackground(['#F4F1FF', '#E5DEFA']);
  view['animation_style'] = 'STACK';
  data['card_view'] = view;
  data['page_count'] = pages.length;
  data['card_count'] = occupied.length;
}

class AlbumQuota {
  const AlbumQuota({
    required this.albumCount,
    required this.maxAlbums,
    required this.maxPages,
    required this.maxSlots,
    this.plan = 'NORMAL',
    this.normalAlbums = 10,
    this.proAlbums = 30,
    this.normalPages = 10,
    this.proPages = 20,
  });
  final int albumCount,
      maxAlbums,
      maxPages,
      maxSlots,
      normalAlbums,
      proAlbums,
      normalPages,
      proPages;
  final String plan;
  factory AlbumQuota.fromJson(AlbumJson json) => AlbumQuota(
    albumCount: (json['album_count'] as num).toInt(),
    maxAlbums: (json['max_album_count'] as num).toInt(),
    maxPages: (json['max_page_per_album'] as num).toInt(),
    maxSlots: (json['max_card_per_page'] as num).toInt(),
    plan: json['plan'] as String? ?? 'NORMAL',
    normalAlbums: (json['normal_albums'] as num?)?.toInt() ?? 10,
    proAlbums: (json['pro_albums'] as num?)?.toInt() ?? 30,
    normalPages: (json['normal_pages'] as num?)?.toInt() ?? 10,
    proPages: (json['pro_pages'] as num?)?.toInt() ?? 20,
  );
}

class AlbumShelfData {
  const AlbumShelfData(
    this.albums, {
    this.nextOffset,
    this.quota,
    this.theme = 'cream-white',
    this.viewMode = 'SHELF',
  });
  final List<PhotocardAlbum> albums;
  final int? nextOffset;
  final AlbumQuota? quota;
  final String theme, viewMode;
  factory AlbumShelfData.fromJson(AlbumJson data) => AlbumShelfData(
    ((data['items'] as List?) ?? [])
        .cast<AlbumJson>()
        .map(PhotocardAlbum.new)
        .toList(),
    nextOffset: (data['next_offset'] as num?)?.toInt(),
    quota: data['quota'] is AlbumJson
        ? AlbumQuota.fromJson(data['quota'] as AlbumJson)
        : null,
    theme:
        (data['preferences'] as AlbumJson?)?['shelf_theme'] as String? ??
        'cream-white',
    viewMode:
        (data['preferences'] as AlbumJson?)?['view_mode'] as String? ?? 'SHELF',
  );
}

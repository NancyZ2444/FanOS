class IdolProfile {
  const IdolProfile({
    required this.id,
    required this.name,
    required this.groupName,
    required this.initials,
    required this.colorStart,
    required this.colorEnd,
    this.bio = '',
    this.company = '',
    this.birthDate = '',
    this.region = '',
    this.role = 'Member',
    this.careers = const [],
    this.nameEn = '',
    this.nameKo = '',
    this.nameTranslated = '',
    this.imageUrl,
    this.thumbnailUrl,
    this.groupIds = const [],
  });

  final String id;
  final String name;
  final String groupName;
  final String initials;
  final int colorStart;
  final int colorEnd;
  final String bio;
  final String company;
  final String birthDate;
  final String region;
  final String role;
  final List<IdolCareer> careers;
  final String nameEn;
  final String nameKo;
  final String nameTranslated;
  final String? imageUrl;
  final String? thumbnailUrl;
  final List<String> groupIds;
  String get displayGroupName => groupName;

  String get displayName => nameEn.isNotEmpty
      ? nameEn
      : (name.isNotEmpty
            ? name
            : (nameTranslated.isNotEmpty ? nameTranslated : nameKo));
  String get secondaryName => nameKo.isNotEmpty && nameKo != displayName
      ? nameKo
      : (nameTranslated.isNotEmpty && nameTranslated != displayName
            ? nameTranslated
            : '');

  factory IdolProfile.fromJson(Map<String, dynamic> json) => IdolProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    groupName: (json['group_name'] as String?) ?? '',
    initials: (json['initials'] as String?) ?? '?',
    colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFF8B7CFF,
    colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF3843A8,
    bio: (json['bio'] as String?) ?? '',
    company: (json['company'] as String?) ?? '',
    birthDate: (json['birth_date'] as String?) ?? '',
    region: (json['region'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'Member',
    careers: (json['careers'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(IdolCareer.fromJson)
        .toList(),
    nameEn: (json['name_en'] as String?) ?? '',
    nameKo: (json['name_ko'] as String?) ?? '',
    nameTranslated: (json['name_translated'] as String?) ?? '',
    imageUrl: json['image_url'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    groupIds: (json['group_ids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  );
}

class IdolCareer {
  const IdolCareer({
    required this.period,
    required this.title,
    this.subtitle = '',
  });

  final String period;
  final String title;
  final String subtitle;

  factory IdolCareer.fromJson(Map<String, dynamic> json) => IdolCareer(
    period: (json['period'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    subtitle: (json['subtitle'] as String?) ?? '',
  );
}

class FanGroup {
  const FanGroup({
    required this.id,
    required this.name,
    required this.company,
    required this.status,
    required this.memberIds,
    required this.colorStart,
    required this.colorEnd,
    this.description = '',
    this.debutDate = '',
    this.region = '',
    this.formerMemberIds = const [],
    this.imageUrl,
    this.nameEn = '',
    this.nameKo = '',
    this.nameTranslated = '',
  });

  final String id;
  final String name;
  final String company;
  final String status;
  final List<String> memberIds;
  final int colorStart;
  final int colorEnd;
  final String description;
  final String debutDate;
  final String region;
  final List<String> formerMemberIds;
  final String? imageUrl;
  final String nameEn;
  final String nameKo;
  final String nameTranslated;

  String get displayName => nameEn.isNotEmpty
      ? nameEn
      : (name.isNotEmpty
            ? name
            : (nameTranslated.isNotEmpty ? nameTranslated : nameKo));
  String get secondaryName => nameKo.isNotEmpty && nameKo != displayName
      ? nameKo
      : (nameTranslated.isNotEmpty && nameTranslated != displayName
            ? nameTranslated
            : '');

  factory FanGroup.fromJson(Map<String, dynamic> json) => FanGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    company: (json['company'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'Active',
    memberIds: (json['member_ids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFF8B7CFF,
    colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF3843A8,
    description: (json['description'] as String?) ?? '',
    debutDate: (json['debut_date'] as String?) ?? '',
    region: (json['region'] as String?) ?? '',
    formerMemberIds: (json['former_member_ids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    imageUrl: json['image_url'] as String?,
    nameEn: (json['name_en'] as String?) ?? '',
    nameKo: (json['name_ko'] as String?) ?? '',
    nameTranslated: (json['name_translated'] as String?) ?? '',
  );
}

class CollectibleCard {
  const CollectibleCard({
    required this.id,
    this.tags = const [],
    required this.title,
    required this.idolId,
    required this.idolName,
    required this.groupId,
    required this.groupName,
    required this.source,
    required this.cardType,
    required this.version,
    required this.releaseDate,
    required this.region,
    required this.colorStart,
    required this.colorEnd,
    this.titleEn = '',
    this.titleKo = '',
    this.titleTranslated = '',
    this.imageUrl,
    this.backImageUrl,
    this.sourceEntityId,
    this.sourceEntityType,
    this.entityVersionId,
    this.cardNumber = '',
  });

  final List<CatalogTag> tags;
  final String id;
  final String title;
  final String? imageUrl;
  final String? backImageUrl;
  final String? sourceEntityId;
  final String? sourceEntityType;
  final String? entityVersionId;
  final String cardNumber;
  final String idolId;
  final String idolName;
  final String groupId;
  final String groupName;
  final String source;
  final String cardType;
  final String version;
  final String releaseDate;
  final String region;
  final int colorStart;
  final int colorEnd;
  final String titleEn;
  final String titleKo;
  final String titleTranslated;

  String get displayTitle => titleEn.isNotEmpty
      ? titleEn
      : (title.isNotEmpty
            ? title
            : (titleTranslated.isNotEmpty ? titleTranslated : titleKo));
  String get secondaryTitle => titleKo.isNotEmpty && titleKo != displayTitle
      ? titleKo
      : (titleTranslated.isNotEmpty && titleTranslated != displayTitle
            ? titleTranslated
            : '');

  factory CollectibleCard.fromJson(Map<String, dynamic> json) =>
      CollectibleCard(
        tags: catalogTags(json, 'CARD'),
        id: json['id'] as String,
        title: json['title'] as String,
        imageUrl: json['image_url'] as String?,
        backImageUrl: json['back_image_url'] as String?,
        sourceEntityId: json['source_entity_id'] as String?,
        sourceEntityType: json['source_entity_type'] as String?,
        entityVersionId: json['entity_version_id'] as String?,
        cardNumber: (json['card_number'] as String?) ?? '',
        idolId: json['idol_id'] as String,
        idolName: json['idol_name'] as String,
        groupId: (json['group_id'] as String?) ?? '',
        groupName: json['group_name'] as String,
        source: json['source'] as String,
        cardType: json['card_type'] as String,
        version: json['version'] as String,
        releaseDate: json['release_date'] as String,
        region: json['region'] as String,
        colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFF8B7CFF,
        colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF3843A8,
        titleEn: (json['title_en'] as String?) ?? '',
        titleKo: (json['title_ko'] as String?) ?? '',
        titleTranslated: (json['title_translated'] as String?) ?? '',
      );
}

class CatalogBundle {
  const CatalogBundle({
    required this.idols,
    required this.groups,
    required this.cards,
    this.albums = const [],
    this.events = const [],
    this.others = const [],
  });

  final List<IdolProfile> idols;
  final List<FanGroup> groups;
  final List<CollectibleCard> cards;
  final List<CatalogAlbum> albums;
  final List<CatalogEvent> events;
  final List<CatalogOther> others;
}

class CatalogAlbum {
  const CatalogAlbum({
    required this.id,
    this.tags = const [],
    this.artists = const [],
    this.versionDetails = const [],
    required this.name,
    required this.artistName,
    required this.groupId,
    required this.releaseDate,
    required this.albumType,
    required this.versions,
    required this.colorStart,
    required this.colorEnd,
    this.description = '',
    this.nameEn = '',
    this.nameKo = '',
    this.nameTranslated = '',
    this.frontImageUrl,
    this.backImageUrl,
  });

  final List<CatalogTag> tags;
  final List<CatalogArtist> artists;
  bool belongsToGroup(String id) =>
      groupId == id || artists.any((a) => a.type == "groups" && a.id == id);
  bool belongsToIdol(String id) =>
      artists.any((a) => a.type == "idols" && a.id == id);
  final String id;
  final String name;
  final String artistName;
  final String groupId;
  final String releaseDate;
  final String albumType;
  final List<String> versions;
  final List<CatalogVersion> versionDetails;
  final int colorStart;
  final int colorEnd;
  final String description;
  final String nameEn;
  final String nameKo;
  final String nameTranslated;
  final String? frontImageUrl;
  final String? backImageUrl;

  String get displayName => nameEn.isNotEmpty
      ? nameEn
      : (name.isNotEmpty
            ? name
            : (nameTranslated.isNotEmpty ? nameTranslated : nameKo));
  String get secondaryName => nameKo.isNotEmpty && nameKo != displayName
      ? nameKo
      : (nameTranslated.isNotEmpty && nameTranslated != displayName
            ? nameTranslated
            : '');
  bool get supportsTwoSidedArtwork =>
      frontImageUrl?.isNotEmpty == true || backImageUrl?.isNotEmpty == true;

  factory CatalogAlbum.fromJson(Map<String, dynamic> json) => CatalogAlbum(
    tags: catalogTags(json, 'ALBUM'),
    artists: (json['artists'] as List? ?? [])
        .map(
          (a) =>
              CatalogArtist(type: a['type'] as String, id: a['id'] as String),
        )
        .toList(),
    versionDetails: (json['entity_versions'] as List? ?? [])
        .map(
          (v) => CatalogVersion(
            id: v['id'] as String,
            name: v['name'] as String? ?? '',
          ),
        )
        .toList(),
    id: json['id'] as String,
    name: json['name'] as String,
    artistName: (json['artist_name'] as String?) ?? '',
    groupId: (json['group_id'] as String?) ?? '',
    releaseDate: (json['release_date'] as String?) ?? '',
    albumType: (json['album_type'] as String?) ?? 'Album',
    versions: (json['versions'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFF8B7CFF,
    colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF3843A8,
    description: (json['description'] as String?) ?? '',
    nameEn: (json['name_en'] as String?) ?? '',
    nameKo: (json['name_ko'] as String?) ?? '',
    nameTranslated: (json['name_translated'] as String?) ?? '',
    frontImageUrl: (json['front_image_url'] ?? json['image_url']) as String?,
    backImageUrl: json['back_image_url'] as String?,
  );
}

class CatalogEvent {
  const CatalogEvent({
    required this.id,
    this.tags = const [],
    this.artists = const [],
    required this.name,
    required this.artistName,
    required this.groupId,
    required this.eventType,
    required this.startDate,
    required this.region,
    required this.city,
    required this.venue,
    required this.colorStart,
    required this.colorEnd,
    this.parentEventId,
    this.imageUrl,
    this.isOnline = false,
    this.platform = '',
    this.description = '',
    this.nameEn = '',
    this.nameKo = '',
    this.nameTranslated = '',
  });

  final List<CatalogTag> tags;
  final List<CatalogArtist> artists;
  bool belongsToGroup(String id) =>
      groupId == id || artists.any((a) => a.type == "groups" && a.id == id);
  bool belongsToIdol(String id) =>
      artists.any((a) => a.type == "idols" && a.id == id);
  final String id;
  final String name;
  final String artistName;
  final String groupId;
  final String eventType;
  final String startDate;
  final String region;
  final String city;
  final String venue;
  final String? parentEventId;
  final String? imageUrl;
  final bool isOnline;
  final String platform;
  String get locationLabel =>
      isOnline ? (platform.isEmpty ? '线上活动' : platform) : city;
  final int colorStart;
  final int colorEnd;
  final String description;
  final String nameEn;
  final String nameKo;
  final String nameTranslated;

  String get displayName => nameEn.isNotEmpty
      ? nameEn
      : (name.isNotEmpty
            ? name
            : (nameTranslated.isNotEmpty ? nameTranslated : nameKo));
  String get secondaryName => nameKo.isNotEmpty && nameKo != displayName
      ? nameKo
      : (nameTranslated.isNotEmpty && nameTranslated != displayName
            ? nameTranslated
            : '');

  factory CatalogEvent.fromJson(Map<String, dynamic> json) => CatalogEvent(
    tags: catalogTags(json, 'EVENT'),
    artists: (json['artists'] as List? ?? [])
        .map(
          (a) =>
              CatalogArtist(type: a['type'] as String, id: a['id'] as String),
        )
        .toList(),
    id: json['id'] as String,
    name: json['name'] as String,
    artistName: (json['artist_name'] as String?) ?? '',
    groupId: (json['group_id'] as String?) ?? '',
    eventType: (json['event_type'] as String?) ?? 'Other',
    startDate: (json['start_date'] as String?) ?? '',
    region: (json['region'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    venue: (json['venue'] as String?) ?? '',
    parentEventId: json['parent_event_id'] as String?,
    imageUrl: json['image_url'] as String?,
    isOnline: (json['is_online'] as bool?) ?? false,
    platform: (json['platform'] as String?) ?? '',
    colorStart: (json['color_start'] as num?)?.toInt() ?? 0xFF8B7CFF,
    colorEnd: (json['color_end'] as num?)?.toInt() ?? 0xFF3843A8,
    description: (json['description'] as String?) ?? '',
    nameEn: (json['name_en'] as String?) ?? '',
    nameKo: (json['name_ko'] as String?) ?? '',
    nameTranslated: (json['name_translated'] as String?) ?? '',
  );
}

class CatalogOther {
  const CatalogOther({
    required this.id,
    required this.name,
    this.originalName = '',
    this.startDate = '',
    this.endDate = '',
    this.description = '',
    this.tags = const [],
    this.imageUrl,
    this.groupId = '',
    this.artistName = '',
    this.type = '',
    this.releaseDate = '',
    this.region = '',
    this.colorStart = 0xFF8B7CFF,
    this.colorEnd = 0xFF3843A8,
    this.source = '',
    this.nameEn = '',
    this.nameKo = '',
    this.nameTranslated = '',
  });
  final String id, name, originalName, startDate, endDate, description;
  final List<CatalogTag> tags;
  final String? imageUrl;
  // Read-only legacy presentation fields; new Other forms use the six stable fields.
  final String groupId,
      artistName,
      type,
      releaseDate,
      region,
      source,
      nameEn,
      nameKo,
      nameTranslated;
  final int colorStart, colorEnd;
  String get displayName => name;
  String get secondaryName => originalName;
  factory CatalogOther.fromJson(Map<String, dynamic> json) => CatalogOther(
    id: json['id'] as String,
    name: json['name'] as String,
    originalName: json['original_name'] as String? ?? '',
    startDate: json['start_date'] as String? ?? '',
    endDate: json['end_date'] as String? ?? '',
    description: json['description'] as String? ?? '',
    imageUrl: json['image_url'] as String?,
    groupId: json['group_id'] as String? ?? '',
    tags: catalogTags(json, 'OTHER'),
  );
}

class CatalogTag {
  const CatalogTag({
    required this.id,
    required this.name,
    required this.entityType,
    this.status = 'ACTIVE',
    this.source = 'INTERNAL',
  });
  final String id, name, entityType, status, source;
  factory CatalogTag.fromJson(Map<String, dynamic> json) => CatalogTag(
    id: json['id'] as String,
    name: json['name'] as String,
    entityType: json['entity_type'] as String,
    status: json['status'] as String? ?? 'ACTIVE',
    source: json['source'] as String? ?? 'INTERNAL',
  );
}

List<CatalogTag> catalogTags(Map<String, dynamic> json, String type) =>
    (json['tag_details'] as List<dynamic>? ?? const [])
        .map((t) => CatalogTag.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList();

enum ScanRecognitionStatus { recommended, needsConfirmation, unrecognized }

class ScanCropRegion {
  const ScanCropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  factory ScanCropRegion.fromJson(Map<String, dynamic> json) => ScanCropRegion(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num?)?.toDouble() ?? 1,
    height: (json['height'] as num?)?.toDouble() ?? 1,
  );

  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class ScanCandidate {
  const ScanCandidate({required this.card, required this.similarity});

  final CollectibleCard card;
  final double similarity;

  factory ScanCandidate.fromJson(Map<String, dynamic> json) => ScanCandidate(
    card: CollectibleCard.fromJson(json['card'] as Map<String, dynamic>),
    similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
  );
}

class DetectedScanCard {
  const DetectedScanCard({
    required this.id,
    required this.cropRegion,
    required this.candidates,
    required this.status,
    this.cropImagePath,
    this.userConfirmedCardId,
    this.ownedAdded = false,
  });

  final String id;
  final String? cropImagePath;
  final ScanCropRegion cropRegion;
  final List<ScanCandidate> candidates;
  final ScanRecognitionStatus status;
  final String? userConfirmedCardId;
  final bool ownedAdded;

  ScanCandidate? get topCandidate => candidates.firstOrNull;

  factory DetectedScanCard.fromJson(Map<String, dynamic> json) {
    final status = switch (json['recognition_status']) {
      'recommended' || 'high_confidence' => ScanRecognitionStatus.recommended,
      'needs_confirmation' ||
      'medium_confidence' => ScanRecognitionStatus.needsConfirmation,
      _ => ScanRecognitionStatus.unrecognized,
    };
    return DetectedScanCard(
      id: json['detected_card_id'] as String,
      cropImagePath: json['crop_image_path'] as String?,
      cropRegion: ScanCropRegion.fromJson(
        (json['crop_region'] as Map<String, dynamic>?) ?? const {},
      ),
      candidates: (json['candidates'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ScanCandidate.fromJson)
          .toList(),
      status: status,
      userConfirmedCardId: json['user_confirmed_card_id'] as String?,
      ownedAdded: json['owned_added'] == true,
    );
  }
}

class ScanSession {
  const ScanSession({
    required this.id,
    required this.detectedCards,
    this.originalImagePath,
  });

  final String id;
  final String? originalImagePath;
  final List<DetectedScanCard> detectedCards;

  int get detectedCount => detectedCards.length;

  factory ScanSession.fromJson(
    Map<String, dynamic> json, {
    String? localImagePath,
  }) => ScanSession(
    id: json['session_id'] as String,
    originalImagePath:
        (json['original_image_path'] as String?) ?? localImagePath,
    detectedCards: (json['detected_cards'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DetectedScanCard.fromJson)
        .toList(),
  );
}

class ScanConfirmation {
  const ScanConfirmation({
    required this.detectedCardId,
    required this.cardId,
    this.selected = true,
    this.addToWishlist = false,
  });

  final String detectedCardId;
  final String cardId;
  final bool selected;
  final bool addToWishlist;

  Map<String, dynamic> toJson() => {
    'detected_card_id': detectedCardId,
    'card_id': cardId,
    'selected': selected,
    'add_to_wishlist': addToWishlist,
  };
}

class ScanFeedbackRequest {
  const ScanFeedbackRequest({
    required this.sessionId,
    required this.detectedCardId,
    required this.cropRegion,
    required this.candidates,
    this.originalImagePath,
    this.userId,
    this.groupId,
    this.idolId,
    this.source,
    this.sourceMode = 'KNOWN',
    this.sourceEntityType,
    this.sourceEntityId,
    this.sourceVersionId,
    this.notes,
  });

  final String sessionId;
  final String detectedCardId;
  final String? originalImagePath;
  final ScanCropRegion cropRegion;
  final List<ScanCandidate> candidates;
  final String? userId;
  final String? groupId;
  final String? idolId;
  final String? source;
  final String sourceMode;
  final String? sourceEntityType;
  final String? sourceEntityId;
  final String? sourceVersionId;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'scan_session_id': sessionId,
    'detected_card_id': detectedCardId,
    'crop_region': cropRegion.toJson(),
    'ai_candidates': candidates
        .map(
          (candidate) => {
            'card_id': candidate.card.id,
            'similarity': candidate.similarity,
          },
        )
        .toList(),
    'user_id': userId,
    'group_id': groupId,
    'idol_id': idolId,
    'source': source,
    'source_mode': sourceMode,
    'source_entity_type': sourceEntityType,
    'source_entity_id': sourceEntityId,
    'source_version_id': sourceVersionId,
    'notes': notes,
  };
}

class CatalogVersion {
  const CatalogVersion({required this.id, required this.name});
  final String id, name;
}

class CatalogArtist {
  const CatalogArtist({required this.type, required this.id});
  final String type, id;
}

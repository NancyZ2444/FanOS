/// Phase 2 community wire contracts.
///
/// These types deliberately do not reuse [SocialFeedPost]: third-party Idol
/// updates and user-generated community posts have different ownership,
/// moderation, and lifecycle rules.
enum CommunitySubjectType { idol, group, custom }

enum CommunityMediaType { image, video }

class CommunityEntityReference {
  const CommunityEntityReference({
    required this.type,
    required this.targetId,
    this.version = 1,
  });

  final String type;
  final String targetId;
  final int version;

  Map<String, dynamic> toJson() => {
    'type': type,
    'target_id': targetId,
    'version': version,
  };

  factory CommunityEntityReference.fromJson(Map<String, dynamic> json) =>
      CommunityEntityReference(
        type: json['type'] as String,
        targetId: json['target_id'] as String,
        version: (json['version'] as num?)?.toInt() ?? 1,
      );
}

class CommunityMediaDraft {
  const CommunityMediaDraft({
    required this.type,
    required this.url,
    this.coverUrl,
    this.width,
    this.height,
    this.durationMs,
  });

  final CommunityMediaType type;
  final String url;
  final String? coverUrl;
  final int? width;
  final int? height;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
    'media_type': type.name,
    'url': url,
    if (coverUrl != null) 'cover_url': coverUrl,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'duration_ms': durationMs,
  };
}

class CommunityPostDraft {
  const CommunityPostDraft({
    this.content = '',
    this.subjectType,
    this.subjectId,
    this.media = const [],
  });

  final String content;
  final CommunitySubjectType? subjectType;
  final String? subjectId;
  final List<CommunityMediaDraft> media;

  Map<String, dynamic> toJson() => {
    'content': content,
    if (subjectType != null) 'subject_type': subjectType!.name,
    if (subjectId != null) 'subject_id': subjectId,
    'media': media.map((item) => item.toJson()).toList(),
  };
}

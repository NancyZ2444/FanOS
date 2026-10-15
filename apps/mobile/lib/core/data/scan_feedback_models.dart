import 'package:fan_os/core/data/models.dart';

class ScanFeedbackRecord {
  const ScanFeedbackRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.cropImageUrl,
    this.originalImageUrl,
    this.groupName,
    this.idolName,
    this.idolId,
    this.source,
    this.sourceMode = 'KNOWN',
    this.sourceEntityType,
    this.sourceEntityId,
    this.sourceVersionId,
    this.sourceName,
    this.sourceVersionName,
    this.notes,
    this.reviewReason,
    this.matchedCard,
  });
  final String id;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? cropImageUrl;
  final String? originalImageUrl;
  final String? groupName;
  final String? idolName;
  final String? idolId;
  final String? source;
  final String sourceMode;
  final String? sourceEntityType;
  final String? sourceEntityId;
  final String? sourceVersionId;
  final String? sourceName;
  final String? sourceVersionName;
  final String? notes;
  final String? reviewReason;
  final CollectibleCard? matchedCard;
  String get statusLabel => switch (status) {
    'reviewing' => '处理中',
    'resolved' => '已完成',
    'rejected' => '未采纳',
    'ignored' => '暂未收录',
    _ => '待处理',
  };
  factory ScanFeedbackRecord.fromJson(Map<String, dynamic> json) =>
      ScanFeedbackRecord(
        id: json['id'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        cropImageUrl: json['crop_image_url'] as String?,
        originalImageUrl: json['original_image_url'] as String?,
        groupName: json['group_name'] as String?,
        idolName: json['idol_name'] as String?,
        idolId: json['idol_id'] as String?,
        source: json['source'] as String?,
        sourceMode: (json['source_mode'] as String?) ?? 'KNOWN',
        sourceEntityType: json['source_entity_type'] as String?,
        sourceEntityId: json['source_entity_id'] as String?,
        sourceVersionId: json['source_version_id'] as String?,
        sourceName: json['source_name'] as String?,
        sourceVersionName: json['source_version_name'] as String?,
        notes: json['notes'] as String?,
        reviewReason: json['review_reason'] as String?,
        matchedCard: json['matched_card'] is Map<String, dynamic>
            ? CollectibleCard.fromJson(
                json['matched_card'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ScanFeedbackPageData {
  const ScanFeedbackPageData({required this.items, this.nextOffset});
  final List<ScanFeedbackRecord> items;
  final int? nextOffset;
}

class ScanFeedbackSourceVersion {
  const ScanFeedbackSourceVersion({required this.id, required this.name});
  final String id;
  final String name;

  factory ScanFeedbackSourceVersion.fromJson(Map<String, dynamic> json) =>
      ScanFeedbackSourceVersion(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class ScanFeedbackSourceOption {
  const ScanFeedbackSourceOption({
    required this.id,
    required this.name,
    required this.entityType,
    this.subtitle = '',
    this.versions = const [],
  });

  final String id;
  final String name;
  final String entityType;
  final String subtitle;
  final List<ScanFeedbackSourceVersion> versions;

  factory ScanFeedbackSourceOption.fromJson(Map<String, dynamic> json) =>
      ScanFeedbackSourceOption(
        id: json['id'] as String,
        name: json['name'] as String,
        entityType: json['entity_type'] as String,
        subtitle: (json['subtitle'] as String?) ?? '',
        versions: (json['versions'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ScanFeedbackSourceVersion.fromJson)
            .toList(),
      );
}

/// Operational suggestion only; submitting this must never publish a catalog
/// entity or create a card in the user's collection.
class CatalogMissingFeedbackRequest {
  const CatalogMissingFeedbackRequest({
    required this.entityType,
    required this.reason,
    required this.suggested,
    this.entityId,
  });
  final String entityType;
  final String? entityId;
  final String reason;
  final Map<String, dynamic> suggested;

  Map<String, dynamic> toJson() => {
    'entity_type': entityType,
    'entity_id': entityId ?? '',
    'reason': reason,
    'suggested': suggested,
  };
}

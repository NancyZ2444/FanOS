import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';

abstract interface class ScanFeedbackOptionsRepository {
  Future<List<ScanFeedbackSourceOption>> fetchOptions({
    required String source,
    String? groupId,
    String? idolId,
  });

  Future<void> submitCatalogMissing(CatalogMissingFeedbackRequest request);
}

class ApiScanFeedbackOptionsRepository
    implements ScanFeedbackOptionsRepository {
  ApiScanFeedbackOptionsRepository(this._client);
  final ApiClient _client;

  @override
  Future<List<ScanFeedbackSourceOption>> fetchOptions({
    required String source,
    String? groupId,
    String? idolId,
  }) async {
    final data = await _client.getData(
      '/scan/feedback-options',
      query: {'source': source, 'group_id': ?groupId, 'idol_id': ?idolId},
    ) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ScanFeedbackSourceOption.fromJson)
        .toList();
  }

  @override
  Future<void> submitCatalogMissing(CatalogMissingFeedbackRequest request) =>
      _client
          .postData('/catalog/feedback', data: request.toJson())
          .then((_) {});
}

class MockScanFeedbackOptionsRepository
    implements ScanFeedbackOptionsRepository {
  MockScanFeedbackOptionsRepository({this.catalog = DemoCatalog.bundle});
  final CatalogBundle catalog;
  final List<CatalogMissingFeedbackRequest> suggestions = [];

  @override
  Future<List<ScanFeedbackSourceOption>> fetchOptions({
    required String source,
    String? groupId,
    String? idolId,
  }) async {
    // Mock version IDs are intentionally confined to the mock repository. The
    // real client obtains canonical version IDs from the options endpoint.
    final idolGroups = idolId == null
        ? null
        : catalog.groups
              .where(
                (group) =>
                    group.memberIds.contains(idolId) ||
                    group.formerMemberIds.contains(idolId),
              )
              .map((group) => group.id)
              .toSet();
    bool accepts(String value) =>
        (groupId == null || value == groupId) &&
        (idolGroups == null || idolGroups.contains(value));
    if (source == '专辑') {
      return catalog.albums.where((item) => accepts(item.groupId)).map((item) {
        return ScanFeedbackSourceOption(
          id: item.id,
          name: item.displayName,
          entityType: 'ALBUM',
          subtitle: '${item.artistName} · ${item.releaseDate}',
          versions: [
            for (var index = 0; index < item.versions.length; index++)
              ScanFeedbackSourceVersion(
                id: 'mock-${item.id}-version-$index',
                name: item.versions[index],
              ),
          ],
        );
      }).toList();
    }
    if (source == '其他') {
      return catalog.others
          .map(
            (item) => ScanFeedbackSourceOption(
              id: item.id,
              name: item.displayName,
              entityType: 'OTHER',
              subtitle: '${item.originalName} · ${item.startDate}',
            ),
          )
          .toList();
    }
    if (!['签售', '演唱会', '活动'].contains(source)) return [];
    bool eventMatches(CatalogEvent item) {
      final kind = item.eventType.toLowerCase();
      return switch (source) {
        '签售' => kind.contains('sign'),
        '演唱会' => kind.contains('concert') || kind.contains('tour'),
        _ => true,
      };
    }

    return catalog.events
        .where((item) => accepts(item.groupId) && eventMatches(item))
        .map(
          (item) => ScanFeedbackSourceOption(
            id: item.id,
            name: item.displayName,
            entityType: 'EVENT',
            subtitle: '${item.artistName} · ${item.startDate}',
          ),
        )
        .toList();
  }

  @override
  Future<void> submitCatalogMissing(
    CatalogMissingFeedbackRequest request,
  ) async {
    suggestions.add(request);
  }
}

import 'album_models.dart';

bool albumResourceAvailable(AlbumJson resource, {String? plan}) =>
    resource['available'] is bool
    ? resource['available'] == true
    : resource['membership'] != 'PRO' || plan == 'PRO';

List<AlbumJson> albumResourceChoices(
  List<AlbumJson> resources, {
  required Set<String> kinds,
  String scene = 'BOTH',
  String? plan,
}) => resources.where((resource) {
  if (!kinds.contains(resource['kind'])) return false;
  if (resource['status'] != null && resource['status'] != 'PUBLISHED') {
    return false;
  }
  if (!albumResourceAvailable(resource, plan: plan) &&
      resource['locked_preview'] == false) {
    return false;
  }
  final target = resource['scene'] as String?;
  return scene == 'BOTH' || target == scene;
}).toList();

AlbumJson albumResourceSnapshot(AlbumJson resource) => cloneAlbumJson({
  for (final key in ['id', 'name', 'kind', 'config']) key: resource[key],
});

AlbumJson albumResourceBackground(AlbumJson resource) => {
  ...cloneAlbumJson(resource['config'] as AlbumJson),
  'resource_id': resource['id'],
  'resource_snapshot': albumResourceSnapshot(resource),
};

/// Read saved visuals first: edits/offline changes must not alter past creations.
AlbumJson albumResourceConfig(
  AlbumJson value, {
  List<AlbumJson> resources = const [],
}) {
  final snapshot = value['resource_snapshot'];
  if (snapshot is AlbumJson && snapshot['config'] is AlbumJson) {
    return snapshot['config'] as AlbumJson;
  }
  final id = value['resource_id'] ?? value['content'];
  final match = resources.where((r) => r['id'] == id).firstOrNull;
  return match?['config'] as AlbumJson? ?? value;
}

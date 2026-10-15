import 'package:fan_os/core/data/models.dart';

enum NameDisplayMode {
  official('official', '官方名'),
  remark('remark', '仅备注名'),
  combined('combined', '官方名（备注名）');

  const NameDisplayMode(this.value, this.label);
  final String value;
  final String label;
}

class NamePreferences {
  const NamePreferences({
    this.mode = NameDisplayMode.official,
    this.aliases = const {},
  });
  final NameDisplayMode mode;
  final Map<String, Map<String, String>> aliases;

  factory NamePreferences.fromJson(Map<String, dynamic> json) =>
      NamePreferences(
        mode:
            NameDisplayMode.values
                .where((v) => v.value == json['mode'])
                .firstOrNull ??
            NameDisplayMode.official,
        aliases: (json['aliases'] as Map<String, dynamic>? ?? {}).map(
          (kind, names) =>
              MapEntry(kind, Map<String, String>.from(names as Map)),
        ),
      );

  String remark(String kind, String id) => aliases[kind]?[id]?.trim() ?? '';
  String display(String kind, String id, String official) {
    final value = remark(kind, id);
    if (value.isEmpty || mode == NameDisplayMode.official) return official;
    return mode == NameDisplayMode.remark ? value : '$official（$value）';
  }

  CatalogBundle apply(CatalogBundle data) => CatalogBundle(
    idols: data.idols
        .map(
          (i) => _NamedIdol(
            i,
            this,
            data.groups.where((g) => g.name == i.groupName).firstOrNull,
          ),
        )
        .toList(),
    groups: data.groups.map((g) => _NamedGroup(g, this)).toList(),
    cards: data.cards.map((c) {
      final idol = data.idols.where((i) => i.id == c.idolId).firstOrNull;
      return idol == null || !c.hasIndividualIdol
          ? c
          : c.withIdolName(display('idols', idol.id, idol.officialDisplayName));
    }).toList(),
    albums: data.albums,
    events: data.events,
    others: data.others,
  );
}

// Only presentation changes. IDs and official names remain intact for relationships/search.
class _NamedIdol extends IdolProfile {
  _NamedIdol(this.original, this.preferences, this.group)
    : super(
        id: original.id,
        name: original.name,
        groupName: original.groupName,
        initials: original.initials,
        colorStart: original.colorStart,
        colorEnd: original.colorEnd,
        bio: original.bio,
        company: original.company,
        birthDate: original.birthDate,
        region: original.region,
        role: original.role,
        careers: original.careers,
        nameEn: original.nameEn,
        nameKo: original.nameKo,
        nameTranslated: original.nameTranslated,
        realName: original.realName,
        imageUrl: original.imageUrl,
        thumbnailUrl: original.thumbnailUrl,
        coverImageUrl: original.coverImageUrl,
        groupIds: original.groupIds,
      );
  final IdolProfile original;
  final NamePreferences preferences;
  final FanGroup? group;
  @override
  String get displayGroupName => group == null
      ? groupName
      : preferences.display('groups', group!.id, group!.displayName);
  @override
  String get displayName =>
      preferences.display('idols', id, original.displayName);
  @override
  String get secondaryName =>
      preferences.mode == NameDisplayMode.remark &&
          preferences.remark('idols', id).isNotEmpty
      ? ''
      : original.secondaryName;
}

class _NamedGroup extends FanGroup {
  _NamedGroup(this.original, this.preferences)
    : super(
        id: original.id,
        name: original.name,
        company: original.company,
        status: original.status,
        memberIds: original.memberIds,
        colorStart: original.colorStart,
        colorEnd: original.colorEnd,
        description: original.description,
        debutDate: original.debutDate,
        region: original.region,
        formerMemberIds: original.formerMemberIds,
        imageUrl: original.imageUrl,
        coverImageUrl: original.coverImageUrl,
        thumbnailUrl: original.thumbnailUrl,
        nameEn: original.nameEn,
        nameKo: original.nameKo,
        nameTranslated: original.nameTranslated,
      );
  final FanGroup original;
  final NamePreferences preferences;
  @override
  String get displayName =>
      preferences.display('groups', id, original.displayName);
  @override
  String get secondaryName =>
      preferences.mode == NameDisplayMode.remark &&
          preferences.remark('groups', id).isNotEmpty
      ? ''
      : original.secondaryName;
}

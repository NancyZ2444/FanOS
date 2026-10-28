import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_profile_tab.dart';
import 'profile_reading_widgets.dart';
import 'profile_text_diff.dart';

AppBar _navigation(String title) => AppBar(
  title: Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  ),
  backgroundColor: FanColors.canvas,
  surfaceTintColor: Colors.transparent,
  scrolledUnderElevation: 0,
);
String _author(FeedbackJson data) => data['source'] == 'INITIAL'
    ? '系统整理'
    : '${(data['author'] as Map?)?['name'] ?? '来源未记录'}';
bool _initial(FeedbackJson data) =>
    data['source'] == 'INITIAL' ||
    (data.containsKey('parent_version') && data['parent_version'] == null);

class _VersionBadge extends StatelessWidget {
  const _VersionBadge(this.version);
  final dynamic version;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: FanColors.lavenderSoft,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      'V${version ?? '—'}',
      style: const TextStyle(fontSize: 12, color: FanColors.lavender),
    ),
  );
}

class CatalogProfileHistory extends ConsumerStatefulWidget {
  const CatalogProfileHistory({
    required this.kind,
    required this.entityId,
    super.key,
  });
  final String kind, entityId;
  @override
  ConsumerState<CatalogProfileHistory> createState() =>
      _CatalogProfileHistoryState();
}

class _CatalogProfileHistoryState extends ConsumerState<CatalogProfileHistory> {
  final _items = <FeedbackJson>[];
  final _scroll = ScrollController();
  String _section = '';
  int? _next = 0;
  int? _total;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy || (!reset && _next == null)) return;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _items.clear();
        _next = 0;
        _total = null;
      }
    });
    try {
      final data = await ref
          .read(apiClientProvider)
          .getData(
            '/catalog/profiles/${widget.kind}/${widget.entityId}/history',
            query: {'offset': _next ?? 0, 'section_key': _section},
          );
      if (mounted) {
        setState(() {
          for (final item in feedbackItems(data['items'])) {
            if (!_items.any((old) => old['id'] == item['id'])) _items.add(item);
          }
          _next = data['next_offset'];
          _total = data['total'] is int ? data['total'] as int : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _filter(String value) {
    if (_section == value || _busy) return;
    _section = value;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _navigation('修订历史'),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    tooltip: '选择板块',
                    enabled: !_busy,
                    initialValue: _section,
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: '', child: Text('全部板块')),
                      for (final entry in profileSections.entries)
                        PopupMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onSelected: _filter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profileSections[_section] ?? '全部板块',
                            style: profileBodyStyle,
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_total != null)
                    Text('$_total 条记录', style: profileNoteStyle),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (_items.isNotEmpty)
                  ProfileSurface(
                    child: Column(
                      children: [
                        for (var i = 0; i < _items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _historyRow(_items[i]),
                        ],
                      ],
                    ),
                  ),
                if (_items.isEmpty && !_busy && _error == null) ...[
                  Text(
                    _section.isEmpty ? '暂无修订记录' : '该板块暂无修订记录',
                    style: profileBodyStyle,
                  ),
                  if (_section.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _filter(''),
                        child: const Text('清除筛选'),
                      ),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('修订记录加载失败', style: profileBodyStyle),
                        const SizedBox(height: 4),
                        Text(_error!, style: profileNoteStyle),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_next != null && _error == null)
                  TextButton(onPressed: _load, child: const Text('加载更多')),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _historyRow(FeedbackJson item) => InkWell(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogProfileVersion(
          kind: widget.kind,
          entityId: widget.entityId,
          versionId: item['id'],
        ),
      ),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VersionBadge(item['version']),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item['summary'] ?? '资料修订'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_author(item), style: profileNoteStyle),
                  const SizedBox(height: 4),
                  Text(
                    profileTime(item['published_at']),
                    style: profileNoteStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: FanColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class CatalogProfileVersion extends ConsumerWidget {
  const CatalogProfileVersion({
    required this.kind,
    required this.entityId,
    required this.versionId,
    super.key,
  });
  final String kind, entityId, versionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = '$kind/$entityId/history/$versionId';
    return Scaffold(
      appBar: _navigation('修订详情'),
      body: SafeArea(
        top: false,
        child: ref
            .watch(catalogProfileProvider(path))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('无法读取修订记录', style: profileBodyStyle),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(catalogProfileProvider(path)),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (data) {
                final initial = _initial(data);
                final fields = feedbackItems(data['fields']);
                final changes = feedbackItems(data['changes'])
                    .where(
                      (c) =>
                          !c.containsKey('before') ||
                          !profileEqual(c['before'], c['after']),
                    )
                    .toList();
                final populated = fields
                    .where((f) => profileHasValue(f['current']))
                    .toList();
                final sections = changes
                    .map((c) => profileSections[c['section']])
                    .whereType<String>()
                    .toSet();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VersionBadge(data['version']),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${data['summary'] ?? '资料修订'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_author(data), style: profileNoteStyle),
                    const SizedBox(height: 4),
                    Text(
                      profileTime(data['published_at'], seconds: true),
                      style: profileNoteStyle,
                    ),
                    if (data['platform_adjusted'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('平台核实调整后采用', style: profileNoteStyle),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      initial
                          ? '初始资料 · ${populated.length} 个有效字段'
                          : '变更 ${changes.length} 项${sections.isEmpty ? '' : ' · ${sections.join('、')}'}',
                      style: profileNoteStyle,
                    ),
                    const SizedBox(height: 24),
                    if (initial)
                      for (final field in populated) ...[
                        _SnapshotField(field: field),
                        const SizedBox(height: 12),
                      ]
                    else ...[
                      if (changes.isEmpty)
                        const Text('本次记录没有字段变化', style: profileNoteStyle),
                      for (final change in changes) ...[
                        _ChangeCard(change: change),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      ProfileSurface(
                        padding: EdgeInsets.zero,
                        child: ExpansionTile(
                          title: const Text(
                            '查看该版完整资料',
                            style: profileBodyStyle,
                          ),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            for (var i = 0; i < fields.length; i++) ...[
                              if (i > 0) const Divider(height: 24),
                              _SnapshotField(field: fields[i], surface: false),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (initial && populated.isEmpty)
                      const Text('初始记录没有已填写的资料', style: profileNoteStyle),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _SnapshotField extends StatelessWidget {
  const _SnapshotField({required this.field, this.surface = true});
  final FeedbackJson field;
  final bool surface;
  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          field['label'],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (field['type'] == 'relations') ...[
          if (!profileHasValue(field['current']))
            const Text('未填写', style: profileNoteStyle),
          for (final record in feedbackItems(field['current']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ProfileRelationRecord(record: record),
            ),
        ] else if (field['type'] == 'image')
          Align(
            alignment: Alignment.centerLeft,
            child: ProfileImage(url: field['current']),
          )
        else
          ProfileReadingText(
            text: profileFieldValue(field, field['current']),
            lines: 6,
          ),
      ],
    );
    return surface ? ProfileSurface(child: child) : child;
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});
  final FeedbackJson change;
  @override
  Widget build(BuildContext context) {
    final known =
        change.containsKey('before') && change['before_available'] != false;
    final old = change['before'], next = change['after'];
    final label = !known
        ? '修改'
        : !profileHasValue(old)
        ? '新增'
        : !profileHasValue(next)
        ? '已删除'
        : '修改';
    return ProfileSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  change['label'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(label, style: profileNoteStyle),
            ],
          ),
          const SizedBox(height: 12),
          if (!known) ...[
            const Text('原始内容不可用', style: profileNoteStyle),
            const SizedBox(height: 8),
          ],
          if (change['type'] == 'relations')
            _RelationChanges(
              before: known ? feedbackItems(old) : null,
              after: feedbackItems(next),
            )
          else if (change['type'] == 'image')
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                if (known) _imageSide('修改前', old, '原值未填写'),
                _imageSide('修改后', next, label == '已删除' ? '图片已删除' : '未上传图片'),
              ],
            )
          else ...[
            if (known) ...[
              if (profileHasValue(old)) ...[
                const Text('修改前', style: profileNoteStyle),
                const SizedBox(height: 4),
                ProfileReadingText(
                  text: profileFieldValue(change, old),
                  lines: 6,
                  spans: profileHasValue(next)
                      ? profileDiffSpans(
                          profileFieldValue(change, old),
                          profileFieldValue(change, next),
                          old: true,
                        )
                      : null,
                ),
              ] else
                const Text('原值未填写', style: profileNoteStyle),
              const SizedBox(height: 8),
            ],
            if (profileHasValue(next)) ...[
              Text(label == '新增' ? '新增内容' : '修改后', style: profileNoteStyle),
              const SizedBox(height: 4),
              ProfileReadingText(
                text: profileFieldValue(change, next),
                lines: 6,
                spans: known && profileHasValue(old)
                    ? profileDiffSpans(
                        profileFieldValue(change, old),
                        profileFieldValue(change, next),
                        old: false,
                      )
                    : null,
              ),
            ] else
              const Text('修改后：未填写', style: profileNoteStyle),
          ],
        ],
      ),
    );
  }

  Widget _imageSide(String label, dynamic url, String empty) => SizedBox(
    width: 104,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: profileNoteStyle),
        const SizedBox(height: 8),
        ProfileImage(url: url, emptyLabel: empty),
      ],
    ),
  );
}

class _RelationChanges extends StatelessWidget {
  const _RelationChanges({required this.before, required this.after});
  final List<FeedbackJson>? before;
  final List<FeedbackJson> after;
  @override
  Widget build(BuildContext context) {
    if (before == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('修改后', style: profileNoteStyle),
          for (final record in after)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ProfileRelationRecord(record: record),
            ),
        ],
      );
    }
    final old = {for (final r in before!) r['id']: r};
    final next = {for (final r in after) r['id']: r};
    final ids = {
      ...old.keys,
      ...next.keys,
    }.where((id) => !profileEqual(old[id], next[id])).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ids.length; i++) ...[
          if (i > 0) const Divider(height: 24),
          _RelationChange(before: old[ids[i]], after: next[ids[i]]),
        ],
      ],
    );
  }
}

class _RelationChange extends StatelessWidget {
  const _RelationChange({this.before, this.after});
  final FeedbackJson? before, after;
  @override
  Widget build(BuildContext context) {
    final record = after ?? before!;
    const labels = {
      'name': '名称',
      'start_date': '开始日期',
      'end_date': '结束日期',
      'status': '业务状态',
      'role': '角色',
      'platform': '平台',
      'handle': '账号名称',
      'platform_account_id': '账号标识',
    };
    String value(String key, dynamic v) =>
        key == 'status' ? profileStatus(v) : feedbackValue(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          before == null
              ? '新增记录'
              : after == null
              ? '已移除记录'
              : '修改记录',
          style: profileNoteStyle,
        ),
        const SizedBox(height: 8),
        if (before == null || after == null)
          ProfileRelationRecord(record: record)
        else ...[
          Text(
            '${record['name'] ?? record['handle'] ?? '官方账号'}',
            style: profileBodyStyle,
          ),
          for (final entry in labels.entries)
            if (!profileEqual(before![entry.key], after![entry.key])) ...[
              const SizedBox(height: 8),
              Text(entry.value, style: profileNoteStyle),
              Text(
                '修改前：${value(entry.key, before![entry.key])}',
                style: profileBodyStyle,
              ),
              Text(
                '修改后：${value(entry.key, after![entry.key])}',
                style: profileBodyStyle,
              ),
            ],
        ],
      ],
    );
  }
}

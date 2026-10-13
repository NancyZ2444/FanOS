import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/core/widgets/catalog_tags.dart';
import 'package:fan_os/features/scan/state/scan_feedback_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CatalogMissingFeedbackRouteArgs {
  const CatalogMissingFeedbackRouteArgs({
    this.scanSession,
    this.detectedCard,
    this.source,
    this.groupId,
    this.idolId,
    this.sourceOption,
    this.missingVersion = false,
    this.initialNotes = '',
  });
  final ScanSession? scanSession;
  final DetectedScanCard? detectedCard;
  final String? source;
  final String? groupId;
  final String? idolId;
  final ScanFeedbackSourceOption? sourceOption;
  final bool missingVersion;
  final String initialNotes;
}

enum _MissingKind {
  card('小卡', 'cards', 'CARD'),
  album('专辑', 'albums', 'ALBUM'),
  albumVersion('专辑版本', 'albums', 'ALBUM_VERSION'),
  event('活动', 'events', 'EVENT'),
  others('其他来源', 'others', 'OTHER');

  const _MissingKind(this.label, this.entityType, this.code);
  final String label;
  final String entityType;
  final String code;
}

class CatalogMissingFeedbackPage extends ConsumerStatefulWidget {
  const CatalogMissingFeedbackPage({this.args, super.key});
  final CatalogMissingFeedbackRouteArgs? args;
  @override
  ConsumerState<CatalogMissingFeedbackPage> createState() =>
      _CatalogMissingFeedbackPageState();
}

class _CatalogMissingFeedbackPageState
    extends ConsumerState<CatalogMissingFeedbackPage> {
  final _name = TextEditingController();
  final _originalName = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _missingGroup = TextEditingController();
  final _missingIdol = TextEditingController();
  final _missingSource = TextEditingController();
  late final TextEditingController _notes;
  late _MissingKind _kind;
  String? _groupId, _idolId, _targetId, _sourceId, _versionId;
  String _sourceType = 'ALBUM';
  List<String> _tags = [];
  bool _submitting = false;
  bool get _other => _kind == _MissingKind.others;
  String get _tagType =>
      _kind == _MissingKind.albumVersion ? 'ALBUM' : _kind.code;
  @override
  void initState() {
    super.initState();
    final args = widget.args;
    _notes = TextEditingController(text: args?.initialNotes ?? '');
    _groupId = args?.groupId;
    _idolId = args?.idolId;
    _kind = args?.missingVersion == true
        ? _MissingKind.albumVersion
        : args?.source == '专辑'
        ? _MissingKind.album
        : args?.source == '其他'
        ? _MissingKind.others
        : args?.source == '活动'
        ? _MissingKind.event
        : _MissingKind.card;
    if (_kind == _MissingKind.albumVersion) _targetId = args?.sourceOption?.id;
    _sourceId = args?.sourceOption?.id;
    _sourceType = args?.sourceOption?.entityType ?? 'ALBUM';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _notes,
      _originalName,
      _start,
      _end,
      _missingGroup,
      _missingIdol,
      _missingSource,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!ref.read(sessionProvider).isLoggedIn) {
      await context.push('/login');
      return;
    }
    final name = _name.text.trim(), notes = _notes.text.trim();
    if ((_targetId == null || _kind == _MissingKind.albumVersion) &&
        name.isEmpty) {
      showFanToast(context, '请填写缺失内容的名称');
      return;
    }
    if (_kind == _MissingKind.albumVersion && _targetId == null) {
      showFanToast(context, '请先选择版本所属的官方专辑');
      return;
    }
    if (_other) {
      for (final text in [_start.text, _end.text]) {
        if (text.isNotEmpty &&
            (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
                DateTime.tryParse(text) == null ||
                DateTime.parse(text).toIso8601String().substring(0, 10) !=
                    text)) {
          showFanToast(context, '日期请使用 YYYY-MM-DD');
          return;
        }
      }
      if (_start.text.isNotEmpty &&
          _end.text.isNotEmpty &&
          _end.text.compareTo(_start.text) < 0) {
        showFanToast(context, '结束日期不能早于开始日期');
        return;
      }
    }
    setState(() => _submitting = true);
    final args = widget.args;
    try {
      await ref
          .read(scanFeedbackOptionsRepositoryProvider)
          .submitCatalogMissing(
            CatalogMissingFeedbackRequest(
              entityType: _kind.entityType,
              entityId: _targetId,
              reason:
                  '${_targetId == null ? '补充' : '反馈'}${_kind.label}：${name.isEmpty ? _targetId : name}\n$notes',
              suggested: {
                'missing_kind': _kind.code,
                if (_targetId == null || _kind == _MissingKind.albumVersion)
                  (_kind == _MissingKind.card ? 'title' : 'name'): name,
                if (_kind != _MissingKind.card) 'description': notes,
                'tags': _tags,
                if (_other) ...{
                  'original_name': _originalName.text.trim(),
                  'start_date': _start.text.trim(),
                  'end_date': _end.text.trim(),
                },
                if (!_other && _kind != _MissingKind.albumVersion) ...{
                  if ((_targetId == null || _kind == _MissingKind.card) &&
                      _groupId != null &&
                      _groupId != 'missing')
                    'group_id': _groupId,
                  if ((_targetId == null || _kind == _MissingKind.card) &&
                      _idolId != null &&
                      _idolId != 'missing')
                    'idol_id': _idolId,
                  if (_targetId == null &&
                      _kind != _MissingKind.card &&
                      (_groupId != null || _idolId != null))
                    'artists': [
                      if (_idolId != null && _idolId != 'missing')
                        {'type': 'idols', 'id': _idolId}
                      else if (_groupId != null && _groupId != 'missing')
                        {'type': 'groups', 'id': _groupId},
                    ],
                  'missing_references': {
                    if (_groupId == 'missing')
                      'group_name': _missingGroup.text.trim(),
                    if (_idolId == 'missing')
                      'idol_name': _missingIdol.text.trim(),
                    if (_kind == _MissingKind.card && _sourceId == null)
                      'source_name': _missingSource.text.trim(),
                  },
                },
                if (_kind == _MissingKind.card) ...{
                  'source_entity_type': _sourceType,
                  if (_sourceId != null) 'source_entity_id': _sourceId,
                  if (_versionId != null) 'entity_version_id': _versionId,
                },
                if (args?.scanSession != null)
                  'scan_session_id': args!.scanSession!.id,
                if (args?.detectedCard != null) ...{
                  'detected_card_id': args!.detectedCard!.id,
                  'crop_region': args.detectedCard!.cropRegion.toJson(),
                  if (args.detectedCard!.cropImagePath?.startsWith('http') ==
                      true)
                    'crop_image_url': args.detectedCard!.cropImagePath,
                },
              },
            ),
          );
      if (!mounted) return;
      showFanToast(context, '已提交图鉴补充，资料和新 Tag 将一起审核');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFanToast(
        context,
        error is ApiException ? error.message : '提交失败，填写内容已保留，请重试',
      );
    }
  }

  Widget _select(
    String key,
    String label,
    String? value,
    List<(String, String)> options,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: LayoutBuilder(
      builder: (context, size) => DropdownMenu<String>(
        key: ValueKey('$key-${value ?? ""}'),
        width: size.maxWidth,
        menuHeight: 300,
        enableFilter: true,
        enableSearch: true,
        label: Text(label),
        initialSelection: value ?? '',
        dropdownMenuEntries: options
            .map((i) => DropdownMenuEntry(value: i.$1, label: i.$2))
            .toList(),
        onSelected: (v) => changed(v == '' ? null : v),
      ),
    ),
  );
  Widget _text(
    TextEditingController c,
    String label, {
    String? key,
    int lines = 1,
    int max = 180,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: key == null ? null : Key(key),
      controller: c,
      maxLines: lines,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
    ),
  );
  void _selectTarget(String? id, CatalogBundle data) {
    setState(() {
      _targetId = id;
      _tags = [];
      if (_kind == _MissingKind.albumVersion) return;
      final tags = switch (_kind) {
        _MissingKind.card =>
          data.cards.where((i) => i.id == id).firstOrNull?.tags,
        _MissingKind.album =>
          data.albums.where((i) => i.id == id).firstOrNull?.tags,
        _MissingKind.event =>
          data.events.where((i) => i.id == id).firstOrNull?.tags,
        _ => data.others.where((i) => i.id == id).firstOrNull?.tags,
      };
      _tags = tags?.map((t) => t.name).toList() ?? [];
      if (_kind == _MissingKind.album) {
        _notes.text =
            data.albums.where((i) => i.id == id).firstOrNull?.description ?? '';
      }
      if (_kind == _MissingKind.event) {
        _notes.text =
            data.events.where((i) => i.id == id).firstOrNull?.description ?? '';
      }
      if (_other) {
        final other = data.others.where((i) => i.id == id).firstOrNull;
        _originalName.text = other?.originalName ?? '';
        _start.text = other?.startDate ?? '';
        _end.text = other?.endDate ?? '';
        _notes.text = other?.description ?? '';
      }
      if (_kind == _MissingKind.card && id != null) {
        final card = data.cards.firstWhere((i) => i.id == id);
        _groupId = card.groupId;
        _idolId = card.idolId;
        _sourceType = card.sourceEntityType ?? 'ALBUM';
        _sourceId = card.sourceEntityId;
        _versionId = card.entityVersionId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(sessionProvider).isLoggedIn;
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('反馈图鉴缺失内容')),
      body: !loggedIn
          ? FanEmptyState(
              icon: Icons.lock_outline_rounded,
              title: '登录后反馈图鉴缺失',
              message: '补充资料将交由运营核实。',
              actionLabel: '登录 / 注册',
              onAction: () => context.push('/login'),
            )
          : catalog.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => FanEmptyState(
                icon: Icons.cloud_off,
                title: '图鉴加载失败',
                message: '请加载已有资料后继续填写。',
                actionLabel: '重试',
                onAction: () => ref.invalidate(catalogProvider),
              ),
              data: (data) {
                final selectedGroup = data.groups
                    .where((i) => i.id == _groupId)
                    .firstOrNull;
                final idolOptions = data.idols.where(
                  (i) =>
                      selectedGroup == null ||
                      selectedGroup.memberIds.contains(i.id) ||
                      selectedGroup.formerMemberIds.contains(i.id),
                );
                final options = switch (_kind) {
                  _MissingKind.card =>
                    data.cards
                        .where(
                          (i) =>
                              _groupId == null ||
                              _groupId == 'missing' ||
                              i.groupId == _groupId,
                        )
                        .where(
                          (i) =>
                              _idolId == null ||
                              _idolId == 'missing' ||
                              i.idolId == _idolId,
                        )
                        .map((i) => (i.id, i.title))
                        .toList(),
                  _MissingKind.album || _MissingKind.albumVersion =>
                    data.albums
                        .where(
                          (i) =>
                              _groupId == null ||
                              _groupId == 'missing' ||
                              i.belongsToGroup(_groupId!),
                        )
                        .map((i) => (i.id, i.displayName))
                        .toList(),
                  _MissingKind.event =>
                    data.events
                        .where(
                          (i) =>
                              _groupId == null ||
                              _groupId == 'missing' ||
                              i.belongsToGroup(_groupId!),
                        )
                        .map((i) => (i.id, i.displayName))
                        .toList(),
                  _MissingKind.others =>
                    data.others.map((i) => (i.id, i.displayName)).toList(),
                };
                final sourceOptions = switch (_sourceType) {
                  'ALBUM' =>
                    data.albums.map((i) => (i.id, i.displayName)).toList(),
                  'EVENT' =>
                    data.events.map((i) => (i.id, i.displayName)).toList(),
                  _ => data.others.map((i) => (i.id, i.displayName)).toList(),
                };
                final album = data.albums
                    .where((i) => i.id == _sourceId)
                    .firstOrNull;
                return SingleChildScrollView(
                  child: FanContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('优先选择平台已有资料；没有找到时再补充。资料和新 Tag 共用一次审核。'),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<_MissingKind>(
                          key: const Key('catalog-missing-kind'),
                          initialValue: _kind,
                          decoration: const InputDecoration(
                            labelText: '补充内容类型',
                          ),
                          items: _MissingKind.values
                              .map(
                                (k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(k.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            _kind = v!;
                            _targetId = null;
                            _tags = [];
                            _name.clear();
                            _originalName.clear();
                            _start.clear();
                            _end.clear();
                          }),
                        ),
                        const SizedBox(height: 14),
                        if (!_other) ...[
                          _select(
                            'missing-group',
                            '组合',
                            _groupId,
                            [
                              ('', '不指定组合 / 个人发行'),
                              ...data.groups.map((i) => (i.id, i.displayName)),
                              ('missing', '未收录，补充组合名称'),
                            ],
                            (v) => setState(() {
                              _groupId = v;
                              _idolId = null;
                              _targetId = null;
                              _tags = [];
                            }),
                          ),
                          if (_groupId == 'missing')
                            _text(_missingGroup, '缺失组合名称'),
                          _select('missing-idol', '艺人', _idolId, [
                            ('', '团体 / 不指定艺人'),
                            ...idolOptions.map((i) => (i.id, i.displayName)),
                            ('missing', '未收录，补充艺人名称'),
                          ], (v) => setState(() => _idolId = v)),
                          if (_idolId == 'missing')
                            _text(_missingIdol, '缺失艺人名称'),
                        ],
                        _select(
                          'missing-target',
                          _kind == _MissingKind.albumVersion
                              ? '所属官方专辑'
                              : '已有${_kind.label}',
                          _targetId,
                          [
                            (
                              '',
                              _kind == _MissingKind.albumVersion
                                  ? '请选择已有专辑'
                                  : '未收录，补充新资料',
                            ),
                            ...options,
                          ],
                          (v) => _selectTarget(v, data),
                        ),
                        if (_targetId == null ||
                            _kind == _MissingKind.albumVersion)
                          _text(
                            _name,
                            _kind == _MissingKind.albumVersion
                                ? '缺失版本名称（必填）'
                                : '名称（必填）',
                            key: 'catalog-missing-name',
                          ),
                        if (_other) ...[
                          _text(_originalName, 'Original Name（原始名称）'),
                          _text(_start, 'Start Date（YYYY-MM-DD）', max: 10),
                          _text(_end, 'End Date（YYYY-MM-DD）', max: 10),
                        ],
                        if (_kind == _MissingKind.card) ...[
                          _select(
                            'missing-source-type',
                            '来源类型',
                            _sourceType,
                            const [
                              ('ALBUM', '专辑'),
                              ('EVENT', '活动'),
                              ('OTHER', '其他来源'),
                            ],
                            (v) => setState(() {
                              _sourceType = v!;
                              _sourceId = null;
                              _versionId = null;
                            }),
                          ),
                          _select(
                            'missing-source',
                            '已有来源',
                            _sourceId,
                            [('', '未收录，补充名称'), ...sourceOptions],
                            (v) => setState(() {
                              _sourceId = v;
                              _versionId = null;
                            }),
                          ),
                          if (_sourceId == null)
                            _text(_missingSource, '缺失来源名称'),
                          if (_sourceType == 'ALBUM' && album != null)
                            _select('missing-version', '专辑版本', _versionId, [
                              ('', '版本不确定'),
                              ...album.versionDetails.map(
                                (i) => (i.id, i.name),
                              ),
                            ], (v) => setState(() => _versionId = v)),
                        ],
                        _text(
                          _notes,
                          _other ? 'Description（来源说明）' : '备注说明 / 公开资料线索',
                          key: 'catalog-missing-notes',
                          lines: 4,
                          max: 600,
                        ),
                        UserTagPicker(
                          key: ValueKey(_tagType),
                          entityType: _tagType,
                          values: _tags,
                          onChanged: (v) => setState(() => _tags = v),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          key: const Key('submit-catalog-missing-feedback'),
                          onPressed: _submitting ? null : _submit,
                          child: Text(_submitting ? '提交中…' : '提交缺失反馈'),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '审核通过后才会发布正式资料和新 Tag；驳回不会将新 Tag 加入正式库。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

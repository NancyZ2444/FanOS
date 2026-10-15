import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feedback_center.dart';
import 'feedback_data.dart';

Future<FeedbackJson?> chooseFeedbackObject(
  BuildContext context,
  String kind, {
  bool switchable = false,
  String? parentId,
}) => showModalBottomSheet<FeedbackJson>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _ObjectPicker(kind: kind, switchable: switchable, parentId: parentId),
);

class _ObjectPicker extends ConsumerStatefulWidget {
  const _ObjectPicker({
    required this.kind,
    this.switchable = false,
    this.parentId,
  });
  final String? parentId;
  final String kind;
  final bool switchable;
  @override
  ConsumerState<_ObjectPicker> createState() => _ObjectPickerState();
}

class _ObjectPickerState extends ConsumerState<_ObjectPicker> {
  late String _kind = widget.kind;
  List<FeedbackJson> _items = [];
  bool _busy = true;
  String? _error;
  int _generation = 0;
  final _query = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(feedbackRepositoryProvider)
          .get(
            '/objects',
            query: {
              'entity_type': _kind,
              'q': _query.text.trim(),
              if (widget.parentId != null) 'parent_id': widget.parentId,
            },
          );
      if (mounted && generation == _generation) {
        setState(() => _items = feedbackItems(data['items']));
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = feedbackError(e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height:
          (MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              MediaQuery.viewPaddingOf(context).top) *
          .82,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择关联资料',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (widget.switchable)
              DropdownButtonFormField<String>(
                initialValue: _kind,
                items: feedbackObjectKinds.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _kind = v);
                    _load();
                  }
                },
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _query,
              decoration: InputDecoration(
                hintText: '搜索名称',
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              TextButton(onPressed: _load, child: Text('$_error · 重试')),
            Expanded(
              child: ListView(
                children: [
                  if (!_busy && _items.isEmpty)
                    const ListTile(title: Text('没有找到对应内容')),
                  for (final item in _items)
                    ListTile(
                      leading: FeedbackMedia(item['image_url'], width: 35),
                      title: Text(item['name']),
                      subtitle: Text(
                        feedbackObjectKinds[item['entity_type']] ?? '',
                      ),
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CorrectionPage extends ConsumerStatefulWidget {
  const CorrectionPage({
    required this.entityType,
    required this.entityId,
    super.key,
  });
  final String entityType, entityId;
  @override
  ConsumerState<CorrectionPage> createState() => _CorrectionPageState();
}

class _CorrectionPageState extends ConsumerState<CorrectionPage> {
  FeedbackJson? _object;
  final Map<String, FeedbackJson> _changes = {};
  final _notes = TextEditingController();
  final _links = TextEditingController();
  final List<FeedbackJson> _evidence = [];
  final _key = FeedbackRequestKey();
  bool _busy = false, _uploading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(widget.entityType, widget.entityId);
  }

  @override
  void dispose() {
    _notes.dispose();
    _links.dispose();
    super.dispose();
  }

  Future<void> _load(String kind, String id) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final obj = await ref
          .read(feedbackRepositoryProvider)
          .get('/objects/$kind/$id');
      if (mounted) {
        setState(() {
          _object = obj;
          _changes.clear();
          _notes.clear();
          _links.clear();
          _evidence.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switch() async {
    if (_changes.isNotEmpty ||
        _notes.text.isNotEmpty ||
        _evidence.isNotEmpty ||
        _links.text.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('切换反馈对象？'),
          content: const Text('当前字段建议、备注和附件将清空。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('切换'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final selected = await chooseFeedbackObject(
      context,
      _object?['entity_type'] ?? widget.entityType,
      switchable: true,
    );
    if (selected != null && mounted) {
      _load(selected['entity_type'], selected['entity_id']);
    }
  }

  Future<void> _uploadEvidence() async {
    setState(() => _uploading = true);
    try {
      final image = await ref.read(feedbackRepositoryProvider).pickImage();
      if (image != null && mounted) setState(() => _evidence.add(image));
    } catch (e) {
      if (mounted) showFanToast(context, feedbackError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_object == null || _busy || _uploading) return;
    if (_changes.isEmpty) {
      showFanToast(context, '请选择至少一个问题字段');
      return;
    }
    for (final entry in _changes.entries) {
      final v = entry.value;
      final field = feedbackItems(_object!['fields'])
          .firstWhere((f) => f['key'] == entry.key);
      if (v['mode'] == 'UNKNOWN' &&
          (v['reason'] ?? '').toString().trim().isEmpty) {
        showFanToast(context, '请说明“${field['label']}”的问题');
        return;
      }
      if (v['mode'] == 'SET' &&
          (v['value'] == null ||
              v['value'] == '' ||
              v['value'] is List && (v['value'] as List).isEmpty)) {
        showFanToast(context, '请填写“${field['label']}”的建议值');
        return;
      }
      if (v['mode'] == 'SET' && v['value'] == field['current']) {
        showFanToast(context, '“${field['label']}”与当前值相同');
        return;
      }
    }
    final preview = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('预览纠错反馈'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_object!['name']),
              for (final f in feedbackItems(
                _object!['fields'],
              ).where((f) => _changes.containsKey(f['key'])))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${f['label']}：${_changes[f['key']]!['mode'] == 'CLEAR'
                        ? '应为空/应删除'
                        : _changes[f['key']]!['mode'] == 'UNKNOWN'
                        ? '未知正确值，已说明问题'
                        : f['type'] == 'image'
                        ? '已上传建议图片'
                        : _changes[f['key']]!['display'] ?? feedbackValue(_changes[f['key']]!['value'])}',
                  ),
                ),
              const Text('提交不会直接修改正式图鉴，将由平台审核。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (preview != true || !mounted) return;
    setState(() => _busy = true);
    final body = <String, dynamic>{
      'kind': 'CORRECTION',
      'entity_type': _object!['entity_type'],
      'entity_id': _object!['entity_id'],
      'object_version': _object!['version'],
      'fields': _changes.entries
          .map((e) => {'key': e.key, ...Map.of(e.value)..remove('display')})
          .toList(),
      'notes': _notes.text.trim(),
      'links': _links.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'evidence_ids': _evidence.map((e) => e['id']).toList(),
    };
    try {
      final row = await ref.read(feedbackRepositoryProvider).post('', {
        ...body,
        'request_key': _key.forPayload(body),
      });
      if (mounted) {
        showFanToast(context, '反馈已提交');
        context.pushReplacement('/feedback/${row['id']}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = feedbackError(e));
        showFanToast(context, feedbackError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('图鉴信息纠错')),
    bottomNavigationBar: _object == null
        ? null
        : SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy || _uploading || _changes.isEmpty
                    ? null
                    : _submit,
                child: Text(_busy ? '正在提交…' : '预览并提交'),
              ),
            ),
          ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null)
          ListTile(
            title: Text(_error!),
            subtitle: const Text('资料变化时请重新载入并核对建议。'),
            trailing: IconButton(
              onPressed: () => _load(
                _object?['entity_type'] ?? widget.entityType,
                _object?['entity_id'] ?? widget.entityId,
              ),
              icon: const Icon(Icons.refresh),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_object != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: FeedbackMedia(_object!['image_url'], width: 48),
            title: Text(
              _object!['name'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              feedbackObjectKinds[_object!['entity_type']] ?? '图鉴对象',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy || _uploading ? null : _switch,
              child: const Text('切换反馈对象'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '哪些资料需要更正？',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('仅反馈详情页的客观资料；选择后填写建议或说明。', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 16),
          for (final f in feedbackItems(_object!['fields']))
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(f['label']),
                    subtitle: Text(
                      f['type'] == 'image'
                          ? '当前图片'
                          : '当前：${feedbackValue(f['current_display'] ?? f['current'])}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: _changes.containsKey(f['key']),
                    onChanged: _busy || _uploading
                        ? null
                        : (checked) => setState(() {
                            if (checked == true) {
                              _changes[f['key']] = {
                                'mode': 'SET',
                                'value': f['type'] == 'boolean' ? false : null,
                                'reason': '',
                              };
                            } else {
                              _changes.remove(f['key']);
                            }
                          }),
                  ),
                  if (_changes.containsKey(f['key']))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _FieldSuggestion(
                        key: ValueKey('${_object!['entity_id']}-${f['key']}'),
                        field: {
                          ...f,
                          if (f['key'] == 'entity_version_id' &&
                              _changes['source_entity_id']?['mode'] == 'SET')
                            'parent_id': _changes['source_entity_id']!['value'],
                        },
                        change: _changes[f['key']]!,
                        onChange: (v) => setState(() => _changes[f['key']] = v),
                        onBusy: (v) => setState(() => _uploading = v),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: '补充备注（选填）'),
          ),
          TextField(
            controller: _links,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '参考链接（选填，每行一条，最多6条）'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final e in _evidence)
                Column(
                  children: [
                    FeedbackMedia(e['image_url']),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _evidence.remove(e)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _uploading || _busy || _evidence.length >= 6
                ? null
                : _uploadEvidence,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_uploading ? '正在上传…' : '添加证明图片（最多6张）'),
          ),
          const Text(
            '图片支持 JPG、PNG、WebP，单张不超过10MB。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class _FieldSuggestion extends ConsumerStatefulWidget {
  const _FieldSuggestion({
    required this.field,
    required this.change,
    required this.onChange,
    required this.onBusy,
    super.key,
  });
  final FeedbackJson field, change;
  final ValueChanged<FeedbackJson> onChange;
  final ValueChanged<bool> onBusy;
  @override
  ConsumerState<_FieldSuggestion> createState() => _FieldSuggestionState();
}

class _FieldSuggestionState extends ConsumerState<_FieldSuggestion> {
  final _text = TextEditingController();
  String? _imageUrl, _referenceName;
  void _set(String key, dynamic value) =>
      widget.onChange({...widget.change, key: value});
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _reference() async {
    final picked = await chooseFeedbackObject(
      context,
      widget.field['reference_type'],
      parentId: widget.field['parent_id'],
    );
    if (picked == null || !mounted) return;
    if (widget.field['type'] == 'multi_reference') {
      final list = feedbackItems(widget.change['value']);
      if (!list.any((v) => v['id'] == picked['entity_id'])) {
        list.add({
          'id': picked['entity_id'],
          'type': picked['entity_type'],
          'name': picked['name'],
        });
      }
      _set('value', list);
    } else {
      setState(() => _referenceName = picked['name']);
      widget.onChange({
        ...widget.change,
        'value': picked['entity_id'],
        'display': picked['name'],
      });
    }
  }

  Future<void> _image() async {
    widget.onBusy(true);
    try {
      final image = await ref.read(feedbackRepositoryProvider).pickImage();
      if (image != null && mounted) {
        setState(() => _imageUrl = image['image_url']);
        _set('value', image['id']);
      }
    } catch (e) {
      if (mounted) showFanToast(context, feedbackError(e));
    } finally {
      if (mounted) widget.onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field, change = widget.change;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field['type'] == 'image')
          FeedbackMedia(field['current'], width: 100),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: change['mode'],
          items: const [
            DropdownMenuItem(value: 'SET', child: Text('建议更正为')),
            DropdownMenuItem(value: 'CLEAR', child: Text('应为空 / 应删除')),
            DropdownMenuItem(value: 'UNKNOWN', child: Text('不确定，仅说明问题')),
          ],
          onChanged: (v) => _set('mode', v),
        ),
        const SizedBox(height: 12),
        if (change['mode'] == 'SET') ...[
          if (field['type'] == 'boolean')
            SwitchListTile(
              title: const Text('建议值'),
              value: change['value'] == true,
              onChanged: (v) => _set('value', v),
            )
          else if (field['type'] == 'enum')
            DropdownButtonFormField<String>(
              initialValue: change['value'],
              items: (field['options'] as List)
                  .map((v) => DropdownMenuItem(value: '$v', child: Text('$v')))
                  .toList(),
              onChanged: (v) => _set('value', v),
            )
          else if (field['type'] == 'image') ...[
            if (_imageUrl != null) FeedbackMedia(_imageUrl, width: 120),
            OutlinedButton(onPressed: _image, child: const Text('上传建议图片')),
          ] else if (field['type'] == 'reference' ||
              field['type'] == 'multi_reference') ...[
            if (field['type'] == 'multi_reference')
              Wrap(
                spacing: 6,
                children: [
                  for (final v in feedbackItems(change['value']))
                    InputChip(
                      label: Text(v['name'] ?? v['id']),
                      onDeleted: () => _set(
                        'value',
                        feedbackItems(change['value'])
                            .where((e) => e['id'] != v['id'])
                            .toList(),
                      ),
                    ),
                ],
              ),
            OutlinedButton(
              onPressed: _reference,
              child: Text(_referenceName ?? '搜索并选择关联对象'),
            ),
          ] else if (field['type'] == 'date')
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  initialDate:
                      DateTime.tryParse('${change['value']}') ?? DateTime.now(),
                );
                if (date != null && mounted) {
                  _set('value', date.toIso8601String().substring(0, 10));
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(change['value'] ?? '选择日期'),
            )
          else
            TextField(
              controller: _text,
              maxLength: 2000,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: field['type'] == 'list'
                    ? '每行一项，最多30项，每项120字'
                    : '填写建议值',
              ),
              onChanged: (v) => _set(
                'value',
                field['type'] == 'list'
                    ? v.split('\n').where((e) => e.trim().isNotEmpty).toList()
                    : v,
              ),
            ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          initialValue: change['reason'],
          maxLength: 1000,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: change['mode'] == 'UNKNOWN' ? '问题说明（必填）' : '问题说明（选填）',
          ),
          onChanged: (v) => _set('reason', v),
        ),
      ],
    );
  }
}

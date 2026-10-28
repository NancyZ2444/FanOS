import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feedback_center.dart';
import 'profile_relation_editor.dart';
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
                      title: FanEntityName(
                        kind: item['entity_type'],
                        id: item['entity_id'],
                        officialName: item['name'],
                      ),
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
    this.section,
    this.resubmit,
    super.key,
  });
  final String entityType, entityId;
  final String? section;
  final FeedbackJson? resubmit;
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
  String? _section;
  late final String _owner;
  bool _allowPop = false;
  final _draftStore = const FlutterSecureStorage();
  String get _draftKey =>
      'profile-edit-${ApiClient.baseUrl}-$_owner-${_object?['entity_type']}-${_object?['entity_id']}';
  bool get _profile => _object?['profile'] == true;
  String? _error;
  String? _linksError, _notesError;
  bool _requiresReload = false;
  final _linksAnchor = GlobalKey();
  final _notesAnchor = GlobalKey();
  final Map<String, GlobalKey> _fieldAnchors = {};
  final Map<String, String> _fieldErrors = {};

  void _revealError() {
    if (_fieldErrors.isNotEmpty) {
      final field = feedbackItems(_object?['fields'])
          .where((f) => f['key'] == _fieldErrors.keys.first)
          .firstOrNull;
      if (field != null && _section != null && field['section'] != _section) {
        setState(() => _section = field['section']);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final anchor = _fieldErrors.isNotEmpty
          ? _fieldAnchors[_fieldErrors.keys.first]
          : _notesError != null
          ? _notesAnchor
          : _linksError != null
          ? _linksAnchor
          : null;
      final target = anchor?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.15,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  bool _validate() {
    final errors = <String, String>{};
    for (final entry in _changes.entries) {
      final value = entry.value;
      final field = feedbackItems(_object!['fields'])
          .firstWhere((f) => f['key'] == entry.key);
      if ((value['mode'] == 'UNKNOWN' ||
              _profile && value['mode'] == 'CLEAR') &&
          (value['reason'] ?? '').toString().trim().isEmpty) {
        errors[entry.key] = '请说明“${field['label']}”的问题';
      } else if (value['mode'] == 'SET' &&
          (value['value'] == null ||
              value['value'] is String &&
                  (value['value'] as String).trim().isEmpty ||
              value['value'] is List && (value['value'] as List).isEmpty)) {
        errors[entry.key] = '请填写“${field['label']}”的建议值';
      } else if (value['mode'] == 'SET' && value['value'] == field['current']) {
        errors[entry.key] = '“${field['label']}”与当前值相同';
      }
    }
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _linksError = feedbackLinkError(_links.text);
      _notesError = _profile && _notes.text.trim().isEmpty
          ? '请填写修订说明及可核实出处'
          : null;
      _requiresReload = false;
      _error = errors.isNotEmpty || _linksError != null || _notesError != null
          ? '请检查标出的字段后重试'
          : null;
    });
    if (_error != null) {
      _revealError();
    }
    return _error == null;
  }

  void _showRequestError(Object error) {
    setState(() {
      _error = feedbackError(error);
      _requiresReload = error is ApiException && error.code == 'OBJECT_CHANGED';
      if (error is! ApiException) {
        return;
      }
      final details = error.details['details'];
      for (final detail in details is List ? details : const []) {
        if (detail is! Map) {
          continue;
        }
        final loc = detail['loc'] is List ? detail['loc'] as List : const [];
        final raw = '${detail['msg'] ?? error.message}'.replaceFirst(
          RegExp(r'^Value error,\s*'),
          '',
        );
        // Server field errors are shown beside the original input, not as a
        // generic toast or a prompt that would discard the user's suggestions.
        final message = RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)
            ? raw
            : '填写内容不符合要求，请检查格式或长度';
        if (loc.contains('links')) {
          _linksError = feedbackLinkError(_links.text) ?? message;
        } else if (loc.contains('notes')) {
          _notesError = message;
        } else {
          String? key = detail['field'] as String?;
          final index = loc.indexOf('fields');
          if (key == null && index >= 0 && loc.length > index + 1) {
            final row = loc[index + 1];
            if (row is int && row >= 0 && row < _changes.length) {
              key = _changes.keys.elementAt(row);
            }
          }
          if (key != null && _changes.containsKey(key)) {
            _fieldErrors[key] = message;
          }
        }
      }
      if (_linksError != null ||
          _notesError != null ||
          _fieldErrors.isNotEmpty) {
        _error = '请检查标出的字段后重试';
      }
    });
    _revealError();
  }

  @override
  void initState() {
    super.initState();
    _owner = ref.read(sessionProvider).userId;
    _section = widget.section;
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
      _linksError = null;
      _notesError = null;
      _fieldErrors.clear();
      _requiresReload = false;
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
          if (widget.resubmit != null) {
            final submission = widget.resubmit!['submission'] as Map;
            for (final f in feedbackItems(submission['fields'])) {
              _changes[f['key']] = {
                'mode': f['mode'],
                'value': f['type'] == 'image' ? f['image_id'] : f['suggested'],
                'reason': f['reason'] ?? '',
              };
            }
            _notes.text = submission['notes'] ?? '';
            _links.text = (submission['links'] as List? ?? []).join('\n');
            _evidence.addAll(feedbackItems(submission['evidence']));
          }
        });
      }
      if (mounted && _profile && widget.resubmit == null) await _restoreDraft();
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final encoded = await _draftStore.read(key: _draftKey);
      if (encoded == null || !mounted) return;
      final saved = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      final restore = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现未提交的资料草稿'),
          content: Text(
            saved['version'] == _object!['version']
                ? '是否继续上次编辑？'
                : '正式资料已更新。恢复后请逐项对照当前值，重新确认建议。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('不恢复'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复草稿'),
            ),
          ],
        ),
      );
      if (restore == true && mounted) {
        setState(() {
          _changes.addAll({
            for (final e in (saved['changes'] as Map).entries)
              e.key.toString(): Map<String, dynamic>.from(e.value as Map),
          });
          _notes.text = saved['notes'] ?? '';
          _links.text = saved['links'] ?? '';
          _evidence.addAll(feedbackItems(saved['evidence']));
        });
      }
    } catch (_) {
      /* The current editor remains usable if local storage is unavailable. */
    }
  }

  Future<void> _reload() async {
    if (_object != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重新载入当前资料？'),
          content: const Text('资料已发生变化。重新载入将清除本页尚未提交的建议，请先保留需要的内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重新载入'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await _load(
      _object?['entity_type'] ?? widget.entityType,
      _object?['entity_id'] ?? widget.entityId,
    );
  }

  Future<void> _leave() async {
    if (_busy || _uploading) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保留资料修订草稿？'),
        content: const Text('未提交内容仅保存到当前账号的本机草稿，不会更新公开资料。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保留草稿'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'save') {
        await _draftStore.write(
          key: _draftKey,
          value: jsonEncode({
            'version': _object?['version'],
            'changes': _changes,
            'notes': _notes.text,
            'links': _links.text,
            'evidence': _evidence,
          }),
        );
      } else {
        await _draftStore.delete(key: _draftKey);
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (_) {
      if (mounted) showFanToast(context, '本机草稿保存失败，请继续编辑或重试');
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
    FocusScope.of(context).unfocus();
    if (ref.read(sessionProvider).userId != _owner) {
      setState(() => _error = '账号已切换，请重新打开资料编辑');
      return;
    }
    if (_changes.isEmpty) {
      showFanToast(context, '请选择至少一个问题字段');
      return;
    }
    if (!_validate()) {
      return;
    }
    final preview = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_profile ? '预览资料修订' : '预览纠错反馈'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FanEntityName(
                kind: _object!['entity_type'],
                id: _object!['entity_id'],
                officialName: _object!['name'],
              ),
              for (final f in feedbackItems(
                _object!['fields'],
              ).where((f) => _changes.containsKey(f['key'])))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_profile ? "当前${f['label']}：${feedbackValue(f['current_display'] ?? f['current'])}\n建议" : ""}${f['label']}：${_changes[f['key']]!['mode'] == 'CLEAR'
                        ? '应为空/应删除'
                        : _changes[f['key']]!['mode'] == 'UNKNOWN'
                        ? '未知正确值，已说明问题'
                        : f['type'] == 'image'
                        ? '已上传建议图片'
                        : _changes[f['key']]!['display'] ?? feedbackValue(_changes[f['key']]!['value'])}',
                  ),
                ),
              Text(
                _profile
                    ? '审核通过后更新资料，公开修订记录包含昵称和生效时间；证明附件不公开。'
                    : '提交不会直接修改正式图鉴，将由平台审核。',
              ),
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
      final row = await ref.read(feedbackRepositoryProvider).post(
        widget.resubmit == null
            ? ''
            : '/records/${widget.resubmit!['id']}/resubmit',
        {
          if (widget.resubmit != null) 'revision': widget.resubmit!['revision'],
          ...body,
          'request_key': _key.forPayload(body),
        },
      );
      if (_profile) {
        try {
          await _draftStore.delete(key: _draftKey);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _allowPop = true);
        showFanToast(context, '反馈已提交');
        context.pushReplacement('/feedback/${row['id']}');
      }
    } catch (e) {
      if (mounted) {
        _showRequestError(e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        _allowPop ||
        !_profile ||
        _changes.isEmpty &&
            _notes.text.isEmpty &&
            _links.text.isEmpty &&
            _evidence.isEmpty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(_profile ? '资料修订' : '图鉴信息纠错')),
      bottomNavigationBar: _object == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy || _uploading || _changes.isEmpty
                          ? null
                          : _submit,
                      child: Text(_busy ? '正在提交…' : '预览并提交'),
                    ),
                  ),
                ],
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null && (_object == null || _requiresReload))
            ListTile(
              title: Text(_error!),
              subtitle: const Text('资料变化时请重新载入并核对建议。'),
              trailing: IconButton(
                tooltip: '重新载入资料',
                onPressed: _busy ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_object != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: FeedbackMedia(_object!['image_url'], width: 48),
              title: FanEntityName(
                kind: _object!['entity_type'],
                id: _object!['entity_id'],
                officialName: _object!['name'],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                feedbackObjectKinds[_object!['entity_type']] ?? '图鉴对象',
              ),
            ),
            if (widget.resubmit == null)
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
            const Text(
              '仅反馈详情页的客观资料；选择后填写建议或说明。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            if (_profile) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('profile-section-$_section'),
                initialValue: _section ?? '',
                items: const [
                  DropdownMenuItem(value: '', child: Text('全部资料字段')),
                  DropdownMenuItem(value: 'intro', child: Text('简介')),
                  DropdownMenuItem(value: 'basic', child: Text('基本资料')),
                  DropdownMenuItem(value: 'career', child: Text('从艺历程')),
                  DropdownMenuItem(value: 'honors', child: Text('荣誉记录')),
                ],
                onChanged: (v) => setState(() => _section = v == '' ? null : v),
              ),
              const SizedBox(height: 16),
            ],
            for (final f in feedbackItems(
              _object!['fields'],
            ).where((f) => _section == null || f['section'] == _section))
              Card(
                key: _fieldAnchors.putIfAbsent(f['key'], () => GlobalKey()),
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
                                  'value': f['type'] == 'boolean'
                                      ? false
                                      : _profile &&
                                            ![
                                              'image',
                                              'relations',
                                            ].contains(f['type'])
                                      ? f['current']
                                      : null,
                                  'reason': '',
                                };
                              } else {
                                _changes.remove(f['key']);
                              }
                              _fieldErrors.remove(f['key']);
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
                              'parent_id':
                                  _changes['source_entity_id']!['value'],
                          },
                          change: _changes[f['key']]!,
                          error: _fieldErrors[f['key']],
                          onChange: (v) => setState(() {
                            _changes[f['key']] = v;
                            _fieldErrors.remove(f['key']);
                            _error = null;
                          }),
                          onBusy: (v) => setState(() => _uploading = v),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              key: _notesAnchor,
              controller: _notes,
              onChanged: (_) => setState(() {
                _notesError = null;
                _error = null;
              }),
              maxLines: 3,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: _profile ? '修订说明 / 可核实出处（必填）' : '补充备注（选填）',
                errorText: _notesError,
                errorMaxLines: 3,
              ),
            ),
            TextField(
              key: _linksAnchor,
              controller: _links,
              onChanged: (_) => setState(() {
                _linksError = null;
                _error = null;
              }),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '参考链接（选填，每行一条，最多6条）',
                errorText: _linksError,
                errorMaxLines: 3,
              ),
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
    ),
  );
}

class _FieldSuggestion extends ConsumerStatefulWidget {
  const _FieldSuggestion({
    required this.field,
    required this.change,
    required this.onChange,
    required this.onBusy,
    this.error,
    super.key,
  });
  final FeedbackJson field, change;
  final String? error;
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
  void initState() {
    super.initState();
    final v = widget.change['value'];
    _text.text = v is List ? v.join('\n') : v?.toString() ?? '';
  }

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
        if (widget.error != null) ...[
          Text(
            widget.error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (field['type'] == 'image')
          FeedbackMedia(field['current'], width: 100),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: change['mode'],
          items: [
            const DropdownMenuItem(value: 'SET', child: Text('建议更正为')),
            if (field['type'] != 'relations')
              const DropdownMenuItem(value: 'CLEAR', child: Text('应为空 / 应删除')),
            const DropdownMenuItem(value: 'UNKNOWN', child: Text('不确定，仅说明问题')),
          ],
          onChanged: (v) => _set('mode', v),
        ),
        const SizedBox(height: 12),
        if (change['mode'] == 'SET') ...[
          if (field['type'] == 'relations')
            ProfileRelationEditor(
              field: field,
              operations: feedbackItems(change['value']),
              onChanged: (v) => widget.onChange({
                ...widget.change,
                'value': v,
                'display': v
                    .map(
                      (op) => [
                        {
                          'ADD': '新增',
                          'UPDATE': '修改',
                          'DELETE': '作废',
                        }[op['operation']],
                        op['name'],
                        ...(op['data'] as Map? ?? {}).entries
                            .where((e) => e.key != 'target_id' && e.value != '')
                            .map((e) => e.value),
                        op['reason'],
                      ].where((v) => v != null && v != '').join(' · '),
                    )
                    .join('\n'),
              }),
              pick: (kind) => chooseFeedbackObject(context, kind),
            )
          else if (field['type'] == 'boolean')
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
                      label: FanEntityName(
                        kind: v['type'] ?? field['reference_type'],
                        id: v['id'],
                        officialName: v['name'] ?? v['id'],
                      ),
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
              child: _referenceName == null
                  ? const Text('搜索并选择关联对象')
                  : FanEntityName(
                      kind: field['reference_type'],
                      id: change['value'] is String ? change['value'] : '',
                      officialName: _referenceName!,
                    ),
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
              maxLength: field['max_length'] as int? ?? 2000,
              minLines: field['type'] == 'long_text' ? 5 : 1,
              maxLines: field['type'] == 'long_text' ? 12 : 3,
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

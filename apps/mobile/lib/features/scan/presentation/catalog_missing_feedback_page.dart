import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feedback/correction_page.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Kept compatible with source pickers that route here from an existing scan.
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

const missingCatalogKinds = {
  'groups': '组合',
  'idols': '艺人',
  'albums': '专辑',
  'versions': '专辑版本',
  'events': '活动',
  'others': '其他来源',
};

class CatalogMissingFeedbackPage extends ConsumerStatefulWidget {
  const CatalogMissingFeedbackPage({this.args, super.key});
  final CatalogMissingFeedbackRouteArgs? args;
  @override
  ConsumerState<CatalogMissingFeedbackPage> createState() =>
      _CatalogMissingFeedbackPageState();
}

class _CatalogMissingFeedbackPageState
    extends ConsumerState<CatalogMissingFeedbackPage> {
  final _form = GlobalKey<FormState>();
  final _values = <String, FeedbackJson>{};
  final _images = <String, FeedbackJson>{};
  final _references = <String, List<FeedbackJson>>{};
  final _controllers = <String, TextEditingController>{};
  final _links = TextEditingController();
  final _requestKey = FeedbackRequestKey();
  late final TextEditingController _notes;
  late String _kind;
  List<FeedbackJson> _fields = [];
  bool _loading = true, _submitting = false, _authenticating = false;
  String? _error, _uploading;
  int _generation = 0;
  FeedbackJson get _current => _values.putIfAbsent(_kind, () => {});
  @override
  void initState() {
    super.initState();
    final args = widget.args;
    _kind = args?.missingVersion == true
        ? 'versions'
        : {'专辑': 'albums', '活动': 'events', '其他': 'others'}[args?.source] ??
              'groups';
    _notes = TextEditingController(text: args?.initialNotes ?? '');
    if (_kind == 'versions' && args?.sourceOption != null) {
      _current['album_id'] = args!.sourceOption!.id;
    }
    if (['albums', 'events', 'others'].contains(_kind)) {
      _current['artists'] = [
        if (args?.idolId != null && args!.idolId != 'missing')
          {'type': 'idols', 'id': args.idolId}
        else if (args?.groupId != null && args!.groupId != 'missing')
          {'type': 'groups', 'id': args.groupId},
      ];
    }
    if (ref.read(sessionProvider).isLoggedIn) {
      _load();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _login();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [..._controllers.values, _notes, _links]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!ref.read(sessionProvider).isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
      _fields = [];
    });
    try {
      final data = await ref
          .read(feedbackRepositoryProvider)
          .get('/missing-catalog/schema', query: {'entity_type': _kind});
      if (!mounted || generation != _generation) return;
      setState(() => _fields = feedbackItems(data['fields']));
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = feedbackError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _login() async {
    if (_authenticating) return;
    if (ref.read(sessionProvider).isLoggedIn) {
      await _load();
      return;
    }
    setState(() => _authenticating = true);
    final router = GoRouter.of(context);
    final origin = router.state.uri;
    showFanToast(context, '请先登录后反馈缺失内容');
    try {
      await context.push('/login?from=/catalog/feedback');
      if (mounted &&
          ref.read(sessionProvider).isLoggedIn &&
          router.state.uri == origin) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  TextEditingController _controller(FeedbackJson field) =>
      _controllers.putIfAbsent('$_kind:${field['key']}', () {
        final value = _current[field['key']];
        return TextEditingController(
          text: value is List ? value.join('\n') : '${value ?? ''}',
        );
      });

  Future<void> _pickReference(FeedbackJson field) async {
    final key = field['key'] as String;
    final kind = _kind;
    final selected = await chooseFeedbackObject(
      context,
      field['reference'] as String,
    );
    if (!mounted || selected == null || kind != _kind) return;
    setState(() {
      final storedKey = '$_kind:$key';
      if (field['type'] == 'multi_reference') {
        final existing = feedbackItems(_current[key]);
        if (existing.any((v) => v['id'] == selected['id'])) return;
        _current[key] = [
          ...existing,
          {'type': selected['entity_type'], 'id': selected['id']},
        ];
        _references[storedKey] = [...?_references[storedKey], selected];
      } else {
        _current[key] = selected['id'];
        _references[storedKey] = [selected];
      }
    });
  }

  Future<void> _pickImage(FeedbackJson field) async {
    final storageKey = '$_kind:${field['key']}';
    setState(() {
      _uploading = storageKey;
      _error = null;
    });
    try {
      final image = await ref.read(feedbackRepositoryProvider).pickImage();
      if (!mounted || image == null) return;
      setState(() {
        _images[storageKey] = image;
        _current[field['key']] = image['id'];
      });
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _uploading != null) return;
    if (!ref.read(sessionProvider).isLoggedIn) {
      await _login();
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    for (final field in _fields) {
      if (field['required'] == true &&
          (_current[field['key']] == null ||
              '${_current[field['key']]}'.trim().isEmpty)) {
        setState(() => _error = '请填写${field['label']}');
        return;
      }
    }
    final linkError = feedbackLinkError(_links.text);
    if (linkError != null) {
      setState(() => _error = linkError);
      return;
    }
    final body = <String, dynamic>{
      'kind': 'MISSING_CATALOG',
      'entity_type': _kind,
      if (widget.args?.scanSession != null && widget.args?.detectedCard != null)
        'missing': {
          'scan_session_id': widget.args!.scanSession!.id,
          'detected_card_id': widget.args!.detectedCard!.id,
        },
      'fields': [
        for (final entry in _current.entries)
          if (entry.value != null &&
              entry.value != '' &&
              !(entry.value is List && (entry.value as List).isEmpty))
            {'key': entry.key, 'mode': 'SET', 'value': entry.value},
      ],
      'notes': _notes.text.trim(),
      'links': _links.text
          .split('\n')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
    };
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(feedbackRepositoryProvider).post('', {
        ...body,
        'request_key': _requestKey.forPayload(body),
      });
      if (mounted) {
        showFanToast(context, '反馈已提交');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _field(FeedbackJson field) {
    final key = field['key'] as String, type = field['type'] as String;
    final label = '${field['label']}${field['required'] == true ? ' *' : ''}';
    final storageKey = '$_kind:$key';
    Widget editor;
    if (type == 'image') {
      final image = _images[storageKey];
      editor = Row(
        children: [
          if (image != null) ...[
            FeedbackMedia(image['image_url'] as String?, width: 72),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _uploading != null || _submitting
                  ? null
                  : () => _pickImage(field),
              icon: _uploading == storageKey
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(image == null ? '上传图片' : '更换图片'),
            ),
          ),
          if (image != null)
            IconButton(
              tooltip: '移除${field['label']}',
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _images.remove(storageKey);
                      _current.remove(key);
                    }),
              icon: const Icon(Icons.close),
            ),
        ],
      );
    } else if (type == 'reference' || type == 'multi_reference') {
      final selected = _references[storageKey] ?? [];
      final values = type == 'multi_reference'
          ? feedbackItems(_current[key])
          : [];
      editor = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (values.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in values)
                  InputChip(
                    label: Text(
                      selected
                                  .where((v) => v['id'] == value['id'])
                                  .firstOrNull?['name']
                              as String? ??
                          '已选关联资料',
                    ),
                    onDeleted: _submitting
                        ? null
                        : () => setState(
                            () => _current[key] = values
                                .where((v) => v['id'] != value['id'])
                                .toList(),
                          ),
                  ),
              ],
            ),
          OutlinedButton.icon(
            onPressed: _submitting ? null : () => _pickReference(field),
            icon: const Icon(Icons.search),
            label: Text(
              type == 'reference' && _current[key] != null
                  ? (selected.firstOrNull?['name'] as String? ?? '已选择，点击更换')
                  : '选择${field['label']}',
            ),
          ),
        ],
      );
    } else if (type == 'boolean') {
      editor = Row(
        children: [
          for (final value in [true, false])
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ChoiceChip(
                label: Text(value ? '是' : '否'),
                selected: _current[key] == value,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() => _current[key] = value),
              ),
            ),
        ],
      );
    } else {
      editor = TextFormField(
        key: key == 'name'
            ? const Key('catalog-missing-name')
            : ValueKey(storageKey),
        controller: _controller(field),
        enabled: !_submitting,
        maxLength: type == 'list' ? 3600 : field['max_length'] as int? ?? 180,
        minLines: key == 'description' ? 3 : 1,
        maxLines: type == 'list' || key == 'description' ? 5 : 2,
        decoration: InputDecoration(
          hintText: type == 'date'
              ? 'YYYY-MM-DD'
              : type == 'list'
              ? '每行一项'
              : '填写${field['label']}',
          counterText: '',
        ),
        onChanged: (value) => _current[key] = type == 'list'
            ? value
                  .split('\n')
                  .map((v) => v.trim())
                  .where((v) => v.isNotEmpty)
                  .toList()
            : value.trim(),
        validator: (value) {
          if (field['required'] == true && (value ?? '').trim().isEmpty) {
            return '请填写${field['label']}';
          }
          if (type == 'date' && (value ?? '').isNotEmpty) {
            final date = DateTime.tryParse(value!);
            if (date == null ||
                date.toIso8601String().substring(0, 10) != value) {
              return '请填写有效日期 YYYY-MM-DD';
            }
          }
          return null;
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          editor,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('反馈缺失内容')),
    body: SafeArea(
      top: false,
      child: !ref.watch(sessionProvider).isLoggedIn
          ? ListView(
              key: const Key('catalog-missing-login-required'),
              padding: const EdgeInsets.all(20),
              children: [
                const Text('登录后提交反馈', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                const Text('登录后可补充图鉴资料和图片，并查看处理进度。'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _authenticating ? null : _login,
                  child: Text(_authenticating ? '正在登录' : '去登录'),
                ),
              ],
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: '内容类型'),
                    items: missingCatalogKinds.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting || _uploading != null
                        ? null
                        : (value) {
                            if (value != null && value != _kind) {
                              setState(() => _kind = value);
                              _load();
                            }
                          },
                  ),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_fields.isEmpty && _error != null)
                    TextButton(onPressed: _load, child: const Text('重新加载字段'))
                  else ...[
                    for (final field in _fields) _field(field),
                    TextFormField(
                      key: const Key('catalog-missing-notes'),
                      controller: _notes,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 5,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: '补充说明（选填）',
                        hintText: '可填写资料出处及需要核对的信息',
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _links,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_submitting,
                      validator: (v) => feedbackLinkError(v ?? ''),
                      decoration: const InputDecoration(
                        labelText: '参考链接（选填）',
                        hintText: '每行一条完整的 http:// 或 https:// 链接',
                      ),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('submit-catalog-missing-feedback'),
                    onPressed:
                        _loading ||
                            _fields.isEmpty ||
                            _submitting ||
                            _uploading != null
                        ? null
                        : _submit,
                    child: Text(_submitting ? '正在提交…' : '提交反馈'),
                  ),
                ],
              ),
            ),
    ),
  );
}

import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/state/scan_feedback_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feedback_center.dart';
import 'feedback_data.dart';
import 'feedback_crop_page.dart';

class MissingCardFeedbackPage extends ConsumerStatefulWidget {
  const MissingCardFeedbackPage({this.args, this.feedbackId, super.key});
  final ScanFeedbackRouteArgs? args;
  final String? feedbackId;
  @override
  ConsumerState<MissingCardFeedbackPage> createState() =>
      _MissingCardFeedbackState();
}

class _MissingCardFeedbackState extends ConsumerState<MissingCardFeedbackPage> {
  String? _groupId, _idolId, _sourceType, _version;
  ScanFeedbackSourceOption? _source;
  List<ScanFeedbackSourceOption> _options = [];
  FeedbackJson? _front, _back;
  FeedbackJson? _record;
  bool _loadingRecord = false;
  String? _recordError;
  bool _groupCard = false,
      _double = false,
      _missing = false,
      _busy = false,
      _optionsBusy = false;
  String? _optionsError;
  String? _formError, _linksError;
  final _missingName = TextEditingController(),
      _notes = TextEditingController(),
      _links = TextEditingController();
  final _key = FeedbackRequestKey();
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.feedbackId != null) {
      _loadRecord();
      return;
    }
    final candidate = widget.args?.detectedCard.candidates.firstOrNull?.card;
    if (candidate != null) {
      _groupId = candidate.groupId.isEmpty ? null : candidate.groupId;
      _idolId = candidate.idolId.isEmpty ? null : candidate.idolId;
      _groupCard = candidate.isGroupCard;
    }
  }

  FeedbackJson get _submission =>
      Map<String, dynamic>.from(_record?['submission'] as Map? ?? {});
  FeedbackJson get _scan =>
      Map<String, dynamic>.from(_submission['scan'] as Map? ?? {});
  String? get _detectedId =>
      widget.args?.detectedCard.id ?? _scan['detected_card_id'] as String?;
  String? get _cropUrl =>
      widget.args?.detectedCard.cropImagePath ??
      _scan['crop_image_url'] as String?;
  String? get _originalUrl =>
      widget.args?.session.originalImagePath ??
      _scan['original_image_url'] as String?;

  Future<void> _loadRecord() async {
    setState(() {
      _loadingRecord = true;
      _recordError = null;
    });
    try {
      final record = await ref
          .read(feedbackRepositoryProvider)
          .get('/records/${widget.feedbackId}');
      if (!mounted) return;
      final submission = Map<String, dynamic>.from(
        record['submission'] as Map? ?? {},
      );
      final missing = Map<String, dynamic>.from(
        submission['missing'] as Map? ?? {},
      );
      setState(() {
        _record = record;
        _groupId = missing['group_id'] as String?;
        _idolId = missing['idol_id'] as String?;
        _groupCard = missing['is_group_pc'] == true;
        _double = missing['is_double_sided'] == true;
        _sourceType = missing['source_entity_type'] as String?;
        _missingName.text = missing['missing_source_name'] as String? ?? '';
        _missing = (missing['source_entity_id'] as String?)?.isNotEmpty != true;
        _front = submission['front'] is Map
            ? Map<String, dynamic>.from(submission['front'] as Map)
            : null;
        _back = submission['back'] is Map
            ? Map<String, dynamic>.from(submission['back'] as Map)
            : null;
        _notes.text = submission['notes'] as String? ?? '';
        _links.text = (submission['links'] as List? ?? []).join('\n');
      });
      await _optionsLoad(
        restoreSourceId: missing['source_entity_id'] as String?,
        restoreVersionId: missing['source_version_id'] as String?,
        restoreVersionName: missing['source_version_name'] as String?,
      );
    } catch (e) {
      if (mounted) setState(() => _recordError = feedbackError(e));
    } finally {
      if (mounted) setState(() => _loadingRecord = false);
    }
  }

  @override
  void dispose() {
    _missingName.dispose();
    _notes.dispose();
    _links.dispose();
    super.dispose();
  }

  Future<void> _optionsLoad({
    String? restoreSourceId,
    String? restoreVersionId,
    String? restoreVersionName,
  }) async {
    final generation = ++_generation;
    setState(() {
      _source = null;
      _version = null;
      _options = [];
      _optionsError = null;
      _optionsBusy = false;
    });
    if (_sourceType == null || _groupId == null) return;
    setState(() => _optionsBusy = true);
    try {
      final options = await ref
          .read(scanFeedbackOptionsRepositoryProvider)
          .fetchOptions(
            source: {'ALBUM': '专辑', 'EVENT': '活动', 'OTHER': '其他'}[_sourceType]!,
            groupId: _groupId,
            idolId: _groupCard ? null : _idolId,
          );
      if (mounted && generation == _generation) {
        setState(() {
          _options = options;
          if (restoreSourceId != null) {
            _source = options.where((o) => o.id == restoreSourceId).firstOrNull;
            _version =
                _source?.versions.any((v) => v.id == restoreVersionId) == true
                ? restoreVersionId
                : null;
            // Older feedback can still refer to a read-only version ID that
            // became a canonical record while an operator saved the draft.
            // Only a unique name within the same album may bridge that change.
            if (_version == null && restoreVersionName?.isNotEmpty == true) {
              String normalize(String name) =>
                  name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
              final matches = _source?.versions
                  .where(
                    (v) => normalize(v.name) == normalize(restoreVersionName!),
                  )
                  .toList();
              if (matches?.length == 1) _version = matches!.single.id;
            }
          }
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _optionsError = feedbackError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _optionsBusy = false);
      }
    }
  }

  Future<void> _picture(bool back) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final image = await ref.read(feedbackRepositoryProvider).pickImage();
      if (!mounted || image == null) return;
      final url = image['image_url'] as String?;
      if (url == null || url.isEmpty) {
        throw StateError('Missing uploaded image');
      }
      final bounds = await Navigator.of(context).push<List<double>>(
        MaterialPageRoute(
          builder: (_) => FeedbackCropPage(url: url, side: back ? '背面' : '正面'),
        ),
      );
      if (!mounted || bounds == null) return;
      final cropped = await ref.read(feedbackRepositoryProvider).post(
        '/images/crop',
        {'image_id': image['id'], 'crop': bounds},
      );
      if (mounted) {
        setState(() {
          if (back) {
            _back = cropped;
          } else {
            _front = cropped;
          }
        });
      }
    } catch (e) {
      if (mounted) showFanToast(context, feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop(bool back) async {
    final current = back ? _back : _front;
    final url = current?['image_url'] as String? ?? (back ? null : _cropUrl);
    if (_busy || url == null) return;
    final bounds = await Navigator.of(context).push<List<double>>(
      MaterialPageRoute(
        builder: (_) => FeedbackCropPage(url: url, side: back ? '背面' : '正面'),
      ),
    );
    if (bounds == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final image = await ref.read(feedbackRepositoryProvider).post(
        '/images/crop',
        {
          if (current?['id'] != null)
            'image_id': current!['id']
          else
            'detected_card_id': _detectedId,
          'crop': bounds,
        },
      );
      if (mounted) {
        setState(() {
          if (back) {
            _back = image;
          } else {
            _front = image;
          }
        });
      }
    } catch (e) {
      if (mounted) showFanToast(context, feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final args = widget.args;
    if ((args == null && _record == null) || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_groupId == null || !_groupCard && _idolId == null) {
      setState(() => _formError = '请选择组合及艺人；团体小卡可免选艺人');
      return;
    }
    if (_sourceType == null ||
        (!_missing && _source == null) ||
        (_missing && _missingName.text.trim().isEmpty)) {
      setState(() => _formError = '请选择来源，或填写缺失的来源名称');
      return;
    }
    if (_double && _back == null) {
      setState(() => _formError = '双面小卡必须补充背面图片');
      return;
    }
    final linkError = feedbackLinkError(_links.text);
    setState(() => _linksError = linkError);
    if (linkError != null) {
      setState(() => _formError = linkError);
      return;
    }
    final body = <String, dynamic>{
      'kind': 'MISSING_CARD',
      'missing': {
        ...Map<String, dynamic>.from(_submission['missing'] as Map? ?? {}),
        'scan_session_id': args?.session.id ?? _scan['scan_session_id'],
        'detected_card_id': _detectedId,
        'group_id': _groupId,
        'idol_id': _groupCard ? null : _idolId,
        'is_group_pc': _groupCard,
        'is_double_sided': _double,
        'source_entity_type': _sourceType,
        'source_entity_id': _missing ? null : _source?.id,
        'source_version_id': _missing ? null : _version,
        'missing_source_name': _missing ? _missingName.text.trim() : '',
        'front_image_id': _front?['id'],
        'back_image_id': _back?['id'],
      },
      'notes': _notes.text.trim(),
      if (_record != null) 'revision': _record!['revision'],
      if (_record != null)
        'evidence_ids': feedbackItems(_submission['evidence'])
            .map((e) => e['id'])
            .whereType<String>()
            .toList(),
      'links': _links.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final row = await ref.read(feedbackRepositoryProvider).post(
        _record == null ? '' : '/records/${widget.feedbackId}/resubmit',
        {...body, 'request_key': _key.forPayload(body)},
      );
      if (mounted) {
        if (args?.returnToResult == true && _record == null) {
          showFanToast(context, '反馈已提交');
          Navigator.of(context).pop(true);
          return;
        }
        showFanToast(
          context,
          _record == null ? '反馈已提交，可查看处理进度' : '补充信息已提交，等待平台重新核实',
        );
        if (_record != null && context.canPop()) {
          context.pop(true);
        } else {
          context.pushReplacement('/feedback/${row['id']}');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _formError = feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    if (_loadingRecord || _recordError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('补充小卡信息')),
        body: _loadingRecord
            ? const Center(child: CircularProgressIndicator())
            : FanEmptyState(
                icon: Icons.cloud_off_outlined,
                title: '反馈加载失败',
                message: _recordError!,
                actionLabel: '重试',
                onAction: _loadRecord,
              ),
      );
    }
    if (_record != null && _record!['can_resubmit'] != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('补充小卡信息')),
        body: const FanEmptyState(
          icon: Icons.info_outline,
          title: '当前反馈无需补充',
          message: '反馈状态已更新，请返回反馈进度查看最新结果。',
        ),
      );
    }
    if (args == null && _record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('我要反馈')),
        body: const FanEmptyState(
          icon: Icons.feedback_outlined,
          title: '扫描信息已失效',
          message: '请返回扫描结果选择一张小卡。',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_record == null ? '我要反馈' : '补充小卡信息')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _formError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const Key('submit-missing-feedback'),
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? '处理中…'
                        : _record == null
                        ? '确认提交反馈'
                        : '重新提交信息',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ref
          .watch(catalogProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => FanEmptyState(
              icon: Icons.cloud_off_outlined,
              title: '资料加载失败',
              message: feedbackError(e),
              actionLabel: '重试',
              onAction: () => ref.invalidate(catalogProvider),
            ),
            data: (catalog) {
              final group = catalog.groups
                  .where((g) => g.id == _groupId)
                  .firstOrNull;
              final members = catalog.idols
                  .where(
                    (i) =>
                        group != null &&
                        {
                          ...group.memberIds,
                          ...group.formerMemberIds,
                        }.contains(i.id),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_record != null) ...[
                    Text(
                      '平台需要你补充：${_record!['public_note'] ?? '请补充可核实的图片或来源信息'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text('原提交记录与图片已保留，修改后可重新提交审核。'),
                    const SizedBox(height: 12),
                  ],
                  const Text('将附带扫描原图、裁剪图及候选信息'),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text('正面图片（必填）'),
                            Semantics(
                              button: true,
                              label: '点击更换正面图片',
                              child: InkWell(
                                key: const Key('missing-upload-front'),
                                onTap: _busy ? null : () => _picture(false),
                                borderRadius: BorderRadius.circular(12),
                                child: FeedbackMedia(
                                  _front?['image_url'] ?? _cropUrl,
                                  key: const Key('missing-front-preview'),
                                  width: 140,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key('missing-crop-front'),
                              onPressed: _busy ? null : () => _crop(false),
                              child: const Text('裁剪正面'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(_double ? '背面图片（必填）' : '背面图片（选填）'),
                            Semantics(
                              button: true,
                              label: '点击更换背面图片',
                              child: InkWell(
                                key: const Key('missing-upload-back'),
                                onTap: _busy ? null : () => _picture(true),
                                borderRadius: BorderRadius.circular(12),
                                child: FeedbackMedia(
                                  _back?['image_url'],
                                  key: const Key('missing-back-preview'),
                                  width: 140,
                                ),
                              ),
                            ),
                            if (_back != null)
                              TextButton(
                                key: const Key('missing-crop-back'),
                                onPressed: _busy ? null : () => _crop(true),
                                child: const Text('裁剪背面'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('扫描原图与检测上下文'),
                    children: [
                      FeedbackMedia(_originalUrl, width: 210),
                      const Text('原图、检测区域、候选结果会自动保留给审核人员。'),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('双面小卡'),
                    value: _double,
                    onChanged: (v) => setState(() => _double = v),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('group-$_groupId'),
                    initialValue: group?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '所属组合 *'),
                    items: catalog.groups
                        .map(
                          (g) => DropdownMenuItem(
                            value: g.id,
                            child: Text(
                              g.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _groupId = v;
                        _idolId = null;
                        _missingName.clear();
                      });
                      _optionsLoad();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('团体小卡'),
                    value: _groupCard,
                    onChanged: (v) {
                      setState(() {
                        _groupCard = v;
                        _idolId = null;
                      });
                      _optionsLoad();
                    },
                  ),
                  if (!_groupCard)
                    DropdownButtonFormField<String>(
                      key: ValueKey('idol-$_groupId-$_idolId'),
                      initialValue: members.any((i) => i.id == _idolId)
                          ? _idolId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '所属艺人 *'),
                      items: members
                          .map(
                            (i) => DropdownMenuItem(
                              value: i.id,
                              child: Text(i.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() => _idolId = v);
                        _optionsLoad();
                      },
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('missing-feedback-source-type'),
                    initialValue: _sourceType,
                    decoration: const InputDecoration(labelText: '来源类型 *'),
                    items: const [
                      DropdownMenuItem(value: 'ALBUM', child: Text('专辑')),
                      DropdownMenuItem(value: 'EVENT', child: Text('活动')),
                      DropdownMenuItem(value: 'OTHER', child: Text('其他来源')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _sourceType = v;
                        _missingName.clear();
                      });
                      _optionsLoad();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('官方列表中没有这个来源'),
                    value: _missing,
                    onChanged: (v) => setState(() {
                      _missing = v;
                      _source = null;
                      _version = null;
                    }),
                  ),
                  if (_missing)
                    TextField(
                      controller: _missingName,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: '缺失来源名称 *',
                        helperText: '运营补建正式来源后才能发布小卡。',
                      ),
                    )
                  else ...[
                    if (_optionsBusy) const LinearProgressIndicator(),
                    if (_optionsError != null)
                      TextButton(
                        onPressed: _optionsLoad,
                        child: Text('$_optionsError · 重试'),
                      ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'source-$_sourceType-$_groupId-$_idolId-${_source?.id}',
                      ),
                      initialValue: _source?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '来源对象 *'),
                      items: _options
                          .map(
                            (o) => DropdownMenuItem(
                              value: o.id,
                              child: Text(
                                o.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _source = _options.where((o) => o.id == v).firstOrNull;
                        _version = null;
                      }),
                    ),
                    if (_source?.versions.isNotEmpty == true)
                      DropdownButtonFormField<String>(
                        key: ValueKey('version-${_source?.id}'),
                        initialValue: _version,
                        decoration: const InputDecoration(
                          labelText: '来源版本（选填）',
                        ),
                        isExpanded: true,
                        items: _source!.versions
                            .map(
                              (v) => DropdownMenuItem(
                                value: v.id,
                                child: Text(
                                  v.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _version = v),
                      ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('missing-feedback-notes'),
                    controller: _notes,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '备注（选填）',
                      hintText: '获取渠道、小卡类型或其他线索',
                    ),
                  ),
                  TextField(
                    key: const Key('missing-feedback-links'),
                    controller: _links,
                    maxLines: 2,
                    onChanged: (_) {
                      if (_linksError != null) {
                        setState(
                          () => _linksError = feedbackLinkError(_links.text),
                        );
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '来源链接（选填，最多6条，每行一条）',
                      errorText: _linksError,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
    );
  }
}

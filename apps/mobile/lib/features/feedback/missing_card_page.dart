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

class MissingCardFeedbackPage extends ConsumerStatefulWidget {
  const MissingCardFeedbackPage({required this.args, super.key});
  final ScanFeedbackRouteArgs? args;
  @override
  ConsumerState<MissingCardFeedbackPage> createState() =>
      _MissingCardFeedbackState();
}

class _MissingCardFeedbackState extends ConsumerState<MissingCardFeedbackPage> {
  String? _groupId, _idolId, _sourceType, _version;
  ScanFeedbackSourceOption? _source;
  List<ScanFeedbackSourceOption> _options = [];
  FeedbackJson? _front, _back;
  bool _groupCard = false,
      _double = false,
      _missing = false,
      _busy = false,
      _optionsBusy = false;
  String? _optionsError;
  final _missingName = TextEditingController(),
      _notes = TextEditingController(),
      _links = TextEditingController();
  final _key = FeedbackRequestKey();
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    final candidate = widget.args?.detectedCard.candidates.firstOrNull?.card;
    if (candidate != null) {
      _groupId = candidate.groupId.isEmpty ? null : candidate.groupId;
      _idolId = candidate.idolId.isEmpty ? null : candidate.idolId;
      _groupCard = candidate.isGroupCard;
    }
  }

  @override
  void dispose() {
    _missingName.dispose();
    _notes.dispose();
    _links.dispose();
    super.dispose();
  }

  Future<void> _optionsLoad() async {
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
        setState(() => _options = options);
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
    setState(() => _busy = true);
    try {
      final image = await ref.read(feedbackRepositoryProvider).pickImage();
      if (mounted && image != null) {
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

  Future<void> _crop() async {
    final args = widget.args;
    if (args == null) return;
    final bounds = await showModalBottomSheet<List<double>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _FeedbackCrop(url: args.detectedCard.cropImagePath),
    );
    if (bounds == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final image = await ref.read(feedbackRepositoryProvider).post(
        '/images/crop',
        {'detected_card_id': args.detectedCard.id, 'crop': bounds},
      );
      if (mounted) setState(() => _front = image);
    } catch (e) {
      if (mounted) showFanToast(context, feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final args = widget.args;
    if (args == null || _busy) return;
    if (_groupId == null || !_groupCard && _idolId == null) {
      showFanToast(context, '请选择组合及艺人；团体小卡可免选艺人');
      return;
    }
    if (_sourceType == null ||
        (!_missing && _source == null) ||
        (_missing && _missingName.text.trim().isEmpty)) {
      showFanToast(context, '请选择来源，或填写缺失的来源名称');
      return;
    }
    if (_double && _back == null) {
      showFanToast(context, '双面小卡必须补充背面图片');
      return;
    }
    final body = <String, dynamic>{
      'kind': 'MISSING_CARD',
      'missing': {
        'scan_session_id': args.session.id,
        'detected_card_id': args.detectedCard.id,
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
      'links': _links.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };
    setState(() => _busy = true);
    try {
      final row = await ref.read(feedbackRepositoryProvider).post('', {
        ...body,
        'request_key': _key.forPayload(body),
      });
      if (mounted) {
        showFanToast(context, '反馈已提交，可查看处理进度');
        context.pushReplacement('/feedback/${row['id']}');
      }
    } catch (e) {
      if (mounted) showFanToast(context, feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('小卡缺失反馈')),
        body: const FanEmptyState(
          icon: Icons.feedback_outlined,
          title: '扫描信息已失效',
          message: '请返回扫描结果选择一张小卡。',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('小卡缺失反馈')),
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
                  const Text('未匹配不一定是图鉴缺失，平台会先核对是否已有对应小卡。'),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text('正面图片（必填）'),
                            FeedbackMedia(
                              _front?['image_url'] ??
                                  args.detectedCard.cropImagePath,
                              width: 140,
                            ),
                            TextButton(
                              onPressed: _busy ? null : () => _picture(false),
                              child: const Text('更换正面'),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _crop,
                              child: const Text('调整检测图裁剪'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(_double ? '背面图片（必填）' : '背面图片（选填）'),
                            FeedbackMedia(_back?['image_url'], width: 140),
                            TextButton(
                              onPressed: _busy ? null : () => _picture(true),
                              child: const Text('补充背面'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('扫描原图与检测上下文'),
                    children: [
                      FeedbackMedia(args.session.originalImagePath, width: 210),
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
                    controller: _notes,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '备注（选填）',
                      hintText: '获取渠道、小卡类型或其他线索',
                    ),
                  ),
                  TextField(
                    controller: _links,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '来源链接（选填，最多6条，每行一条）',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? '处理中…' : '确认提交反馈'),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.push('/feedback?kind=MISSING_CARD'),
                    child: const Text('查看我的反馈进度'),
                  ),
                ],
              );
            },
          ),
    );
  }
}

class _FeedbackCrop extends StatefulWidget {
  const _FeedbackCrop({this.url});
  final String? url;
  @override
  State<_FeedbackCrop> createState() => _FeedbackCropState();
}

class _FeedbackCropState extends State<_FeedbackCrop> {
  RangeValues _x = const RangeValues(0, 1), _y = const RangeValues(0, 1);
  double _ratio = .74;
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener((image, _) {
      if (mounted) {
        setState(() => _ratio = image.image.width / image.image.height);
      }
    });
    if (widget.url?.startsWith('http') == true) {
      _stream = NetworkImage(widget.url!).resolve(ImageConfiguration.empty);
      _stream!.addListener(_listener);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('调整裁剪范围'),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: AspectRatio(
              aspectRatio: _ratio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.url?.startsWith('http') == true)
                    Image.network(
                      widget.url!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    )
                  else
                    FeedbackMedia(widget.url, width: 220),
                  LayoutBuilder(
                    builder: (context, size) => Stack(
                      children: [
                        Positioned(
                          left: size.maxWidth * _x.start,
                          top: size.maxHeight * _y.start,
                          width: size.maxWidth * (_x.end - _x.start),
                          height: size.maxHeight * (_y.end - _y.start),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.deepPurple,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Text('左右边界'),
          RangeSlider(
            values: _x,
            onChanged: (v) {
              if (v.end - v.start >= .05) setState(() => _x = v);
            },
          ),
          const Text('上下边界'),
          RangeSlider(
            values: _y,
            onChanged: (v) {
              if (v.end - v.start >= .05) setState(() => _y = v);
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              _x.start,
              _y.start,
              _x.end - _x.start,
              _y.end - _y.start,
            ]),
            child: const Text('使用裁剪图'),
          ),
        ],
      ),
    ),
  );
}

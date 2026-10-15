import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:fan_os/features/scan/state/scan_feedback_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ScanFeedbackRouteArgs {
  const ScanFeedbackRouteArgs({
    required this.session,
    required this.detectedCard,
  });

  final ScanSession session;
  final DetectedScanCard detectedCard;
}

class ScanFeedbackPage extends ConsumerStatefulWidget {
  const ScanFeedbackPage({required this.args, super.key});

  final ScanFeedbackRouteArgs? args;

  @override
  ConsumerState<ScanFeedbackPage> createState() => _ScanFeedbackPageState();
}

class _ScanFeedbackPageState extends ConsumerState<ScanFeedbackPage> {
  static const _sources = ['专辑', '活动', '其他', '不确定'];

  final _notesController = TextEditingController();
  FanGroup? _group;
  IdolProfile? _idol;
  String? _source;
  String _sourceMode = 'KNOWN';
  ScanFeedbackSourceOption? _sourceOption;
  ScanFeedbackSourceVersion? _sourceVersion;
  List<ScanFeedbackSourceOption> _options = [];
  bool _loadingOptions = false;
  String? _optionsError;
  int _optionsGeneration = 0;
  bool _submitting = false;

  Future<void> _loadOptions() async {
    final source = _source;
    final generation = ++_optionsGeneration;
    if (source == null || !['专辑', '活动', '其他'].contains(source)) {
      setState(() {
        _options = [];
        _optionsError = null;
        _loadingOptions = false;
      });
      return;
    }
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
      _options = [];
    });
    try {
      final options = await ref
          .read(scanFeedbackOptionsRepositoryProvider)
          .fetchOptions(source: source, groupId: _group?.id, idolId: _idol?.id);
      if (!mounted || generation != _optionsGeneration) return;
      setState(() {
        _options = options;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted || generation != _optionsGeneration) return;
      setState(() {
        _optionsError = '官方来源加载失败，请重试或反馈缺失内容。';
        _loadingOptions = false;
      });
    }
  }

  void _filtersChanged({FanGroup? group, IdolProfile? idol}) {
    setState(() {
      _group = group;
      _idol = idol;
      _sourceOption = null;
      _sourceVersion = null;
    });
    _loadOptions();
  }

  void _sourceChanged(String? source) {
    setState(() {
      _source = source;
      _sourceMode = source == '不确定' ? 'UNCERTAIN' : 'KNOWN';
      _sourceOption = null;
      _sourceVersion = null;
    });
    _loadOptions();
  }

  Future<void> _chooseOfficialSource() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<ScanFeedbackSourceOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OfficialSourcePicker(
        source: _source!,
        options: _options,
        selectedId: _sourceOption?.id,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _sourceOption = picked;
      _sourceVersion = null;
      _sourceMode = 'KNOWN';
    });
  }

  Future<void> _feedbackMissing({bool version = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CatalogMissingFeedbackPage(
          args: CatalogMissingFeedbackRouteArgs(
            scanSession: widget.args?.session,
            detectedCard: widget.args?.detectedCard,
            source: _source,
            groupId: _group?.id,
            idolId: _idol?.id,
            sourceOption: _sourceOption,
            missingVersion: version,
            initialNotes: _notesController.text.trim(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final args = widget.args;
    if (args == null || _submitting) return;
    if (!ref.read(sessionProvider).isLoggedIn) {
      context.push('/login');
      return;
    }
    final notes = _notesController.text.trim();
    if (_sourceMode != 'KNOWN' && notes.isEmpty) {
      showFanToast(context, '请补充备注，帮助我们核实小卡来源');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(scanRepositoryProvider)
          .submitFeedback(
            ScanFeedbackRequest(
              sessionId: args.session.id,
              detectedCardId: args.detectedCard.id,
              originalImagePath: args.session.originalImagePath,
              cropRegion: args.detectedCard.cropRegion,
              candidates: args.detectedCard.candidates,
              groupId: _group?.id,
              idolId: _idol?.id,
              source: _source,
              sourceMode: _sourceMode,
              sourceEntityType: _sourceMode == 'KNOWN'
                  ? _sourceOption?.entityType
                  : null,
              sourceEntityId: _sourceMode == 'KNOWN' ? _sourceOption?.id : null,
              sourceVersionId: _sourceMode == 'KNOWN'
                  ? _sourceVersion?.id
                  : null,
              notes: notes.isEmpty ? null : notes,
            ),
          );
      if (!mounted) return;
      showFanToast(context, '感谢反馈，我们会尽快补充图鉴。');
      context.pushReplacement('/scan-feedback-history');
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFanToast(
        context,
        error is ApiException ? error.message : '反馈提交失败，请稍后重试',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('主动反馈')),
        body: FanEmptyState(
          icon: Icons.info_outline_rounded,
          title: '反馈信息已失效',
          message: '请从扫描结果中重新选择未识别的小卡。',
          actionLabel: '返回扫描',
          onAction: () => context.go('/scan'),
        ),
      );
    }

    final session = ref.watch(sessionProvider);
    if (!session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('主动反馈')),
        body: FanEmptyState(
          icon: Icons.lock_outline_rounded,
          title: '登录后提交反馈',
          message: '登录后可跟踪这张小卡的收录状态。',
          actionLabel: '登录 / 注册',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('主动反馈')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const FanEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '选项加载失败',
          message: '请稍后重试',
        ),
        data: (data) => SingleChildScrollView(
          child: FanContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '帮助我们补充官方图鉴',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '扫描记录、原始图片、裁剪区域和 AI 候选会自动随反馈提交。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                _FeedbackContextCard(args: args),
                const SizedBox(height: 22),
                Text('补充来源信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _SearchAutocomplete<FanGroup>(
                  label: '所属组合',
                  hint: '搜索组合',
                  options: data.groups,
                  displayString: (group) => group.displayName,
                  onQueryChanged: (value) {
                    if (_group != null && value != _group!.displayName) {
                      _filtersChanged();
                    }
                  },
                  onSelected: (group) => _filtersChanged(group: group),
                ),
                const SizedBox(height: 12),
                _SearchAutocomplete<IdolProfile>(
                  key: ValueKey(_group?.id),
                  label: 'Idol',
                  hint: '搜索 Idol',
                  options: data.idols
                      .where(
                        (idol) =>
                            _group == null ||
                            {
                              ..._group!.memberIds,
                              ..._group!.formerMemberIds,
                            }.contains(idol.id),
                      )
                      .toList(),
                  displayString: (idol) =>
                      '${idol.displayName} · ${idol.groupName}',
                  onQueryChanged: (value) {
                    if (_idol != null &&
                        value !=
                            '${_idol!.displayName} · ${_idol!.groupName}') {
                      _filtersChanged(group: _group);
                    }
                  },
                  onSelected: (idol) =>
                      _filtersChanged(group: _group, idol: idol),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('scan-feedback-source'),
                  initialValue: _source,
                  decoration: const InputDecoration(labelText: '卡片来源'),
                  hint: const Text('请选择来源'),
                  items: _sources
                      .map(
                        (source) => DropdownMenuItem(
                          value: source,
                          child: Text(source),
                        ),
                      )
                      .toList(),
                  onChanged: _sourceChanged,
                ),
                if (_source != null) ...[
                  const SizedBox(height: 12),
                  _sourceFields(),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const Key('scan-feedback-notes'),
                  controller: _notesController,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: _sourceMode == 'KNOWN' ? '备注（选填）' : '备注（必填）',
                    hintText: '可以补充版本、获取渠道或其他线索',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('submit-scan-feedback'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('提交反馈'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceFields() {
    final concreteSource = ['专辑', '活动', '其他'].contains(_source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (concreteSource) ...[
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const Key('scan-feedback-known'),
                label: const Text('从官方数据选择'),
                selected: _sourceMode == 'KNOWN',
                onSelected: (_) => setState(() => _sourceMode = 'KNOWN'),
              ),
              ChoiceChip(
                key: const Key('scan-feedback-other'),
                label: const Text('平台暂未收录'),
                selected: _sourceMode == 'OTHER',
                onSelected: (_) => setState(() => _sourceMode = 'OTHER'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_sourceMode == 'UNCERTAIN')
          const Text('不知道具体来源也可以反馈，请在备注中描述获取渠道、时间或其他线索。'),
        if (_sourceMode == 'OTHER') ...[
          const Text('知道来源但官方暂无对应内容？请补充备注，也可以反馈缺失的专辑、版本或活动。'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('scan-feedback-missing-catalog'),
              onPressed: () => _feedbackMissing(),
              icon: const Icon(Icons.library_add_outlined, size: 18),
              label: const Text('反馈图鉴缺失内容'),
            ),
          ),
        ],
        if (concreteSource && _sourceMode == 'KNOWN') ...[
          if (_loadingOptions)
            const LinearProgressIndicator(minHeight: 2)
          else if (_optionsError != null)
            Row(
              children: [
                Expanded(child: Text(_optionsError!)),
                TextButton(onPressed: _loadOptions, child: const Text('重试')),
              ],
            )
          else if (_options.isEmpty)
            const Text('当前筛选下暂无已收录的官方来源，可反馈缺失内容。')
          else
            ListTile(
              key: const Key('scan-feedback-official-picker'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: const Color(0xFFF0F2F6),
              title: Text(
                _sourceOption?.name ??
                    '选择官方${_source == '专辑'
                        ? '专辑'
                        : _source == '其他'
                        ? 'Other 来源'
                        : '活动'}（选填）',
              ),
              subtitle: _sourceOption?.subtitle.isNotEmpty == true
                  ? Text(_sourceOption!.subtitle)
                  : Text('已收录 ${_options.length} 项 · 支持搜索'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _chooseOfficialSource,
            ),
          if (_sourceOption?.entityType == 'ALBUM') ...[
            const SizedBox(height: 10),
            if (_sourceOption!.versions.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('source-version-${_sourceOption!.id}'),
                initialValue: _sourceVersion?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '官方专辑版本（选填）'),
                hint: const Text('选择版本'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('不指定版本')),
                  for (final version in _sourceOption!.versions)
                    DropdownMenuItem(
                      value: version.id,
                      child: Text(
                        version.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _sourceVersion = value == null || value.isEmpty
                      ? null
                      : _sourceOption!.versions.firstWhere(
                          (item) => item.id == value,
                        );
                }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('scan-feedback-missing-version'),
                onPressed: () => _feedbackMissing(version: true),
                child: const Text('没有所需版本？反馈缺失版本'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _OfficialSourcePicker extends StatefulWidget {
  const _OfficialSourcePicker({
    required this.source,
    required this.options,
    this.selectedId,
  });
  final String source;
  final List<ScanFeedbackSourceOption> options;
  final String? selectedId;

  @override
  State<_OfficialSourcePicker> createState() => _OfficialSourcePickerState();
}

class _OfficialSourcePickerState extends State<_OfficialSourcePicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.options
        .where(
          (item) => '${item.name} ${item.subtitle}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选择官方${widget.source}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭来源选择',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('scan-feedback-source-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索官方名称',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('没有符合搜索的官方来源'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          key: ValueKey('official-source-${item.id}'),
                          title: Text(item.name),
                          subtitle: item.subtitle.isEmpty
                              ? null
                              : Text(item.subtitle),
                          trailing: item.id == widget.selectedId
                              ? const Icon(Icons.check_circle_rounded)
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackContextCard extends StatelessWidget {
  const _FeedbackContextCard({required this.args});

  final ScanFeedbackRouteArgs args;

  @override
  Widget build(BuildContext context) {
    final imagePath =
        args.detectedCard.cropImagePath ?? args.session.originalImagePath;
    final topCandidate = args.detectedCard.topCandidate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: ScanImage(
                path: imagePath,
                fallback: const FanArtwork(
                  startColor: Color(0xFF756D65),
                  endColor: Color(0xFF292621),
                  label: 'SCAN',
                  borderRadius: 12,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '扫描图片已附带',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    topCandidate == null
                        ? '可补充已知资料，帮助完善图鉴。'
                        : '已附上相似结果（${(topCandidate.similarity * 100).round()}%）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchAutocomplete<T extends Object> extends StatelessWidget {
  const _SearchAutocomplete({
    super.key,
    required this.label,
    required this.hint,
    required this.options,
    required this.displayString,
    required this.onSelected,
    this.onQueryChanged,
  });

  final String label;
  final String hint;
  final List<T> options;
  final String Function(T option) displayString;
  final ValueChanged<T> onSelected;
  final ValueChanged<String>? onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<T>(
      displayStringForOption: displayString,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return options;
        return options.where(
          (option) => [
            displayString(option),
            if (option is IdolProfile)
              '${option.name} ${option.nameTranslated} ${option.nameKo} ${option.nameEn} ${option.realName}',
          ].join(' ').toLowerCase().contains(query),
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          onChanged: onQueryChanged,
          focusNode: focusNode,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(labelText: label, hintText: hint),
        );
      },
    );
  }
}

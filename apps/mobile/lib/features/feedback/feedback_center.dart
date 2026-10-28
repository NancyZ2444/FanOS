import '../catalog/presentation/catalog_profile_tab.dart';

import 'package:fan_os/core/widgets/card_geometry.dart';

import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feedback_data.dart';

class FeedbackMedia extends StatelessWidget {
  const FeedbackMedia(this.url, {super.key, this.width = 72});
  final String? url;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width / photocardAspectRatio,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: FanColors.surface,
        child: ScanImage(
          path: url,
          aspectRatio: photocardAspectRatio,
          fallback: const Center(child: Icon(Icons.photo_outlined)),
        ),
      ),
    ),
  );
}

class FeedbackCenterPage extends ConsumerStatefulWidget {
  const FeedbackCenterPage({super.key, this.initialKind});
  final String? initialKind;
  @override
  ConsumerState<FeedbackCenterPage> createState() => _FeedbackCenterState();
}

class _FeedbackCenterState extends ConsumerState<FeedbackCenterPage> {
  List<FeedbackJson> _items = [];
  String? _kind, _error;
  int? _next;
  bool _busy = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(feedbackRepositoryProvider)
          .get(
            '',
            query: {
              if (_kind != null) 'kind': _kind,
              'offset': more ? _next ?? 0 : 0,
            },
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [if (more) ..._items, ...feedbackItems(data['items'])];
        _next = data['next_offset'] as int?;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = feedbackError(e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的反馈')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                '': '全部',
                'MISSING_CARD': '扫描缺失',
                'MISSING_CATALOG': '图鉴补充',
                'CORRECTION': '数据纠错',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: (_kind ?? '') == entry.key,
                  onSelected: (_) {
                    setState(
                      () => _kind = entry.key.isEmpty ? null : entry.key,
                    );
                    _load();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_error != null)
                  ListTile(
                    title: Text(_error!),
                    trailing: IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (!_busy && _error == null && _items.isEmpty)
                  const FanEmptyState(
                    icon: Icons.feedback_outlined,
                    title: '还没有反馈记录',
                    message: '',
                  ),
                for (final row in _items)
                  Card(
                    child: ListTile(
                      leading: FeedbackMedia(row['image_url'], width: 45),
                      title: FanEntityName(
                        kind: row['entity_type'] ?? '',
                        id: row['entity_id'] ?? '',
                        officialName: row['name'] ?? '图鉴反馈',
                      ),
                      subtitle: Text(
                        '${row['kind'] == 'MISSING_CARD'
                            ? '扫描缺失'
                            : row['kind'] == 'MISSING_CATALOG'
                            ? '图鉴补充'
                            : '数据纠错'} · ${row['status_label']}\n${feedbackDate(row['created_at'])}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push('/feedback/${row['id']}');
                        if (mounted) _load();
                      },
                    ),
                  ),
                if (_next != null)
                  TextButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('加载更多'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class FeedbackDetailPage extends ConsumerStatefulWidget {
  const FeedbackDetailPage({required this.id, super.key});
  final String id;
  @override
  ConsumerState<FeedbackDetailPage> createState() => _FeedbackDetailState();
}

class _FeedbackDetailState extends ConsumerState<FeedbackDetailPage> {
  FeedbackJson? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(feedbackRepositoryProvider)
          .get('/records/${widget.id}');
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _data;
    final submission = row?['submission'] as Map? ?? {};
    final frontImage = (row?['image_url'] as String?)?.trim();
    final backImage = (submission['back']?['image_url'] as String?)?.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('反馈进度'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null) Text(_error!),
            if (row == null && _error == null) const LinearProgressIndicator(),
            if (row != null) ...[
              Text(
                row['status_label'],
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '反馈编号 ${row['id']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '提交 ${feedbackDate(row['created_at'])}\n更新 ${feedbackDate(row['updated_at'])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FanEntityName(
                kind: row['entity_type'] ?? '',
                id: row['entity_id'] ?? '',
                officialName: row['name'],
              ),
              // Correction details already show submitted image fields below.
              // A target's (possibly unavailable) cover is not feedback evidence.
              if (row['kind'] != 'CORRECTION' &&
                  ((frontImage?.isNotEmpty ?? false) ||
                      (backImage?.isNotEmpty ?? false)))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (frontImage?.isNotEmpty ?? false)
                        FeedbackMedia(frontImage, width: 104),
                      if (backImage?.isNotEmpty ?? false)
                        FeedbackMedia(backImage, width: 104),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (row['result'] == 'NOT_INCLUDED' &&
                  row['kind'] == 'CORRECTION')
                const Text(
                  '本次建议未采纳',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              Text(
                (row['public_note'] as String?)?.isNotEmpty == true
                    ? row['public_note']
                    : '已收到反馈，等待平台核实。',
              ),
              if (row['kind'] == 'MISSING_CARD' &&
                  row['result'] == 'NOT_INCLUDED')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('本次反馈无法采用，你提交的图片、信息及处理记录仍保留在这里。'),
                ),
              if (row['kind'] == 'MISSING_CARD' &&
                  row['result'] == 'INCLUDED' &&
                  row['target_available'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('已采用并登记为官方图鉴，可查看收录结果。'),
                ),
              if (row['can_resubmit'] == true) ...[
                const SizedBox(height: 12),
                const Text('原提交记录已保留，请根据处理说明补充信息后重新提交。'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('supplement-feedback'),
                  onPressed: () async {
                    if (row['kind'] == 'CORRECTION') {
                      await context.push(
                        Uri(
                          path: '/catalog-correction',
                          queryParameters: {
                            'type': row['entity_type'],
                            'id': row['entity_id'],
                          },
                        ).toString(),
                        extra: row,
                      );
                    } else {
                      await context.push('/feedback/${row['id']}/supplement');
                    }
                    if (mounted) {
                      ref.invalidate(feedbackInboxProvider);
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('补充信息并重新提交'),
                ),
              ],
              if (row['result'] == 'PENDING' && row['status'] == 'PROCESSED')
                const Text('审核已处理，尚未正式发布。'),
              if (row['profile_version'] != null &&
                  row['target_available'] == true)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CatalogProfileVersion(
                        kind: row['entity_type'],
                        entityId: row['entity_id'],
                        versionId: row['profile_version'],
                      ),
                    ),
                  ),
                  child: const Text('查看已生效资料修订'),
                ),
              for (final f in feedbackItems(submission['fields']))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['label'],
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (row['kind'] != 'MISSING_CATALOG') ...[
                          const Text('提交时当前值'),
                          if (f['type'] == 'image')
                            FeedbackMedia(f['current'])
                          else
                            Text(
                              feedbackValue(
                                f['current_display'] ?? f['current'],
                              ),
                            ),
                        ],
                        Text(
                          row['kind'] == 'MISSING_CATALOG' ? '提交内容' : '用户建议',
                        ),
                        if (f['mode'] == 'SET' && f['type'] == 'image')
                          FeedbackMedia(f['suggested'])
                        else
                          Text(
                            f['mode'] == 'CLEAR'
                                ? '应为空/应删除'
                                : f['mode'] == 'UNKNOWN'
                                ? '未知正确值'
                                : feedbackValue(
                                    f['suggested_display'] ?? f['suggested'],
                                  ),
                          ),
                        Text(f['reason'] ?? ''),
                      ],
                    ),
                  ),
                ),
              for (final d in feedbackItems(row['decisions']))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${feedbackItems(submission['fields']).where((f) => f['key'] == d['key']).firstOrNull?['label'] ?? d['key']} · ${{'ACCEPT': '采纳', 'MODIFY': '修改后采纳', 'REJECT': '未采纳'}[d['decision']]}',
                        ),
                        if (d['reason'] != null) Text(d['reason']),
                        if (d['decision'] != 'REJECT')
                          Text(
                            '采用值：${feedbackValue(d['value_display'] ?? d['value'])}',
                          ),
                      ],
                    ),
                  ),
                ),
              if (submission['notes'] != null && submission['notes'] != '') ...[
                const Divider(),
                const Text('补充说明'),
                Text(submission['notes']),
              ],
              Wrap(
                spacing: 8,
                children: [
                  for (final e in feedbackItems(submission['evidence']))
                    FeedbackMedia(e['image_url'], width: 110),
                ],
              ),
              for (final link in submission['links'] as List? ?? [])
                SelectableText('$link'),
              if (row['entity_id'] != null && row['entity_id'] != '') ...[
                const SizedBox(height: 12),
                if (row['target_available'] == true &&
                    row['entity_type'] == 'versions' &&
                    row['kind'] == 'MISSING_CATALOG')
                  OutlinedButton(
                    onPressed: () {
                      ref.invalidate(catalogProvider);
                      context.push(
                        feedbackRoute(
                          'albums',
                          (row['target_parent_id'] ??
                                  (submission['catalog'] as Map)['album_id'])
                              as String,
                        ),
                      );
                    },
                    child: const Text('查看所属专辑'),
                  )
                else if (row['target_available'] == true &&
                    !['versions', 'companies'].contains(row['entity_type']))
                  OutlinedButton(
                    onPressed: () {
                      ref.invalidate(catalogProvider);
                      context.push(
                        feedbackRoute(row['entity_type'], row['entity_id']),
                      );
                    },
                    child: const Text('查看图鉴内容'),
                  )
                else
                  Text(
                    row['result'] == 'INCLUDED'
                        ? '历史收录记录已保留，目标内容当前不可访问。'
                        : '目标内容尚未发布或暂不可用。',
                  ),
              ],
              const Divider(),
              const Text('处理时间线'),
              for (final h in feedbackItems(row['history']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(h['note'] ?? ''),
                  subtitle: Text(feedbackDate(h['at'])),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class ContributionShelf extends ConsumerStatefulWidget {
  const ContributionShelf({super.key, this.userId = 'me'});
  final String userId;
  @override
  ConsumerState<ContributionShelf> createState() => _ContributionShelfState();
}

class _ContributionShelfState extends ConsumerState<ContributionShelf> {
  List<FeedbackJson> _items = [];
  int? _next;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (useMockApi) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(feedbackRepositoryProvider)
          .get(
            '/users/${widget.userId}/contributions',
            query: {'offset': more ? _next ?? 0 : 0},
          );
      if (mounted) {
        setState(() {
          _items = [if (more) ..._items, ...feedbackItems(data['items'])];
          _next = data['next_offset'];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = feedbackError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        if (!_busy && _items.isEmpty && _error == null)
          FanEmptyState(
            icon: Icons.volunteer_activism_outlined,
            title: widget.userId == 'me' ? '还没有收录的贡献小卡' : 'TA 还没有公开的贡献小卡',
            message: '仅展示实际采用图片并正式发布的小卡。',
            actionLabel: widget.userId == 'me' ? '查看我的反馈' : null,
            onAction: widget.userId == 'me'
                ? () => context.push('/feedback')
                : null,
          ),
        for (final item in _items)
          Card(
            child: ListTile(
              leading: FeedbackMedia(item['card']['image_url'], width: 45),
              title: Text(
                item['card']['display_title'] ??
                    item['card']['source'] ??
                    '已收录小卡',
              ),
              subtitle: Text('收录于 ${feedbackDate(item['included_at'])}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ref.invalidate(catalogProvider);
                context.push('/card/${item['card']['id']}');
              },
            ),
          ),
        if (_next != null)
          TextButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: const Text('加载更多'),
          ),
      ],
    ),
  );
}

class FeedbackInbox extends ConsumerWidget {
  const FeedbackInbox({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(feedbackInboxProvider)
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => ListTile(
          title: Text(feedbackError(e)),
          trailing: IconButton(
            onPressed: () => ref.invalidate(feedbackInboxProvider),
            icon: const Icon(Icons.refresh),
          ),
        ),
        data: (items) => Column(
          children: [
            ListTile(
              title: const Text('我的反馈'),
              trailing: IconButton(
                onPressed: () => ref.invalidate(feedbackInboxProvider),
                icon: const Icon(Icons.refresh),
              ),
              onTap: () => context.push('/feedback'),
            ),
            for (final item in items)
              ListTile(
                leading: Icon(
                  item['read_at'] == null
                      ? Icons.mark_email_unread_outlined
                      : Icons.drafts_outlined,
                ),
                title: Text(item['title'] ?? '反馈进度'),
                subtitle: Text(item['content'] ?? ''),
                onTap: () async {
                  try {
                    await ref
                        .read(apiClientProvider)
                        .postData('/notifications/inbox/${item['id']}/read');
                  } catch (_) {
                    /* Reading a message must not block its feedback detail. */
                  }
                  ref.invalidate(feedbackInboxProvider);
                  if (context.mounted &&
                      item['payload']?['feedback_id'] != null) {
                    context.push('/feedback/${item['payload']['feedback_id']}');
                  }
                },
              ),
          ],
        ),
      );
}

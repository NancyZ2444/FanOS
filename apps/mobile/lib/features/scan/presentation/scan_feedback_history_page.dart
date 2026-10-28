import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ScanFeedbackHistoryPage extends ConsumerStatefulWidget {
  const ScanFeedbackHistoryPage({super.key});
  @override
  ConsumerState<ScanFeedbackHistoryPage> createState() =>
      _ScanFeedbackHistoryPageState();
}

class _ScanFeedbackHistoryPageState
    extends ConsumerState<ScanFeedbackHistoryPage> {
  List<ScanFeedbackRecord> _items = [];
  int? _nextOffset;
  bool _loading = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    if (ref.read(sessionProvider).isLoggedIn) _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(scanRepositoryProvider)
          .fetchFeedbackHistory(offset: refresh ? 0 : (_nextOffset ?? 0));
      if (!mounted) return;
      setState(() {
        _items = refresh ? page.items : [..._items, ...page.items];
        _nextOffset = page.nextOffset;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(sessionProvider).isLoggedIn;
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('我的扫描反馈')),
      body: !loggedIn
          ? FanEmptyState(
              icon: Icons.lock_outline,
              title: '登录后查看反馈进度',
              message: '反馈记录会跟随账号保存。',
              actionLabel: '登录 / 注册',
              onAction: () async {
                await context.push('/login');
                if (mounted && ref.read(sessionProvider).isLoggedIn) {
                  _load(refresh: true);
                }
              },
            )
          : _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  const Text(
                    '提交后可在这里查看待处理、处理中和最终结果。下拉刷新获取最新进度。',
                    style: TextStyle(
                      color: FanColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_failed)
                    FanEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '反馈记录加载失败',
                      message: '已有记录保留，请重试。',
                      actionLabel: '重新加载',
                      onAction: () => _load(refresh: _items.isEmpty),
                    ),
                  if (!_failed && _items.isEmpty)
                    const FanEmptyState(
                      icon: Icons.inbox_outlined,
                      title: '暂时没有反馈记录',
                      message: '在未识别小卡的扫描结果中点击“我要反馈”。',
                    ),
                  for (final record in _items)
                    _FeedbackRecordCard(record: record),
                  if (_nextOffset != null && !_failed)
                    TextButton(
                      onPressed: _loading ? null : _load,
                      child: Text(_loading ? '加载中…' : '加载更多'),
                    ),
                ],
              ),
            ),
    );
  }
}

class _FeedbackRecordCard extends StatelessWidget {
  const _FeedbackRecordCard({required this.record});
  final ScanFeedbackRecord record;
  String _date(DateTime date) => date.toLocal().toString().substring(0, 16);
  @override
  Widget build(BuildContext context) {
    final matched = record.matchedCard;
    return Card(
      child: ExpansionTile(
        key: ValueKey(record.id),
        leading: SizedBox(
          width: 44,
          height: 62,
          child: FanArtwork(
            startColor: FanColors.lavender,
            endColor: FanColors.ink,
            imageUrl: record.cropImageUrl ?? record.originalImageUrl,
            borderRadius: 8,
            showMark: false,
          ),
        ),
        title: record.idolId != null
            ? FanEntityName(
                kind: 'idols',
                id: record.idolId!,
                officialName: record.idolName ?? '未识别小卡',
              )
            : FanEntityName(
                kind: record.idolName != null ? 'idols' : 'groups',
                id: '',
                officialName: record.idolName ?? record.groupName ?? '未识别小卡',
              ),
        subtitle: Text('${record.statusLabel} · ${_date(record.createdAt)}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(label: record.statusLabel),
          const SizedBox(height: 8),
          Text('提交：${_date(record.createdAt)}'),
          Text('最近更新：${_date(record.updatedAt)}'),
          if (record.groupName != null)
            FanEntityName(
              kind: 'groups',
              id: '',
              officialName: record.groupName!,
              prefix: '组合：',
            ),
          if (record.source != null) Text('来源：${record.source}'),
          if (record.sourceName != null) Text('官方来源：${record.sourceName}'),
          if (record.sourceVersionName != null)
            Text('专辑版本：${record.sourceVersionName}'),
          if (record.sourceMode == 'OTHER') const Text('来源状态：其他 / 官方暂缺'),
          if (record.sourceMode == 'UNCERTAIN') const Text('来源状态：不确定'),
          if (record.notes?.isNotEmpty == true) Text('我的备注：${record.notes}'),
          const SizedBox(height: 8),
          Text(
            record.reviewReason?.isNotEmpty == true
                ? '处理说明：${record.reviewReason}'
                : (record.status == 'pending'
                      ? '已收到反馈，等待图鉴团队处理。'
                      : record.status == 'reviewing'
                      ? '图鉴团队正在核实卡片信息。'
                      : record.status == 'resolved'
                      ? '处理已完成。'
                      : '本次反馈暂未收录。'),
          ),
          if (matched != null) ...[
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 40,
                height: 58,
                child: FanArtwork(
                  startColor: Color(matched.colorStart),
                  endColor: Color(matched.colorEnd),
                  imageUrl: matched.imageUrl,
                  borderRadius: 8,
                ),
              ),
              title: Text('已收录：${matched.displayTitle}'),
              subtitle: FanEntityName(
                kind: 'idols',
                id: matched.idolId,
                officialName: matched.idolName,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/card/${matched.id}'),
            ),
          ],
        ],
      ),
    );
  }
}

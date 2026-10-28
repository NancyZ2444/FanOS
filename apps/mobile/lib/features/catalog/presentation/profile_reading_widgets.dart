import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';

const profileBodyStyle = TextStyle(
  fontSize: 15,
  height: 1.5,
  color: FanColors.ink,
);
const profileNoteStyle = TextStyle(
  fontSize: 13,
  height: 1.45,
  color: FanColors.textSecondary,
);

bool profileHasValue(dynamic value) =>
    value != null &&
    (value is String
        ? value.trim().isNotEmpty
        : value is Iterable
        ? value.isNotEmpty
        : true);

bool profileEqual(dynamic a, dynamic b) {
  if (!profileHasValue(a) && !profileHasValue(b)) return true;
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && profileEqual(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => profileEqual(a[i], b[i]));
  }
  return a == b;
}

String profileTime(dynamic value, {bool seconds = false}) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '时间未记录';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}${seconds ? ':${pad(date.second)}' : ''}';
}

String profileStatus(dynamic value) => switch ('$value'.toLowerCase()) {
  'active' => '活动中',
  'inactive' || 'hiatus' => '暂停活动',
  'former' => '历史成员',
  'disbanded' => '已解散',
  'void' => '已作废',
  '' || 'null' => '状态未填写',
  _ =>
    RegExp(r'^[a-z_]+$', caseSensitive: false).hasMatch('$value')
        ? '状态待确认'
        : '$value',
};

String profileFieldValue(FeedbackJson field, dynamic value) {
  if (!profileHasValue(value)) return '未填写';
  if (field['key'] == 'business_status') return profileStatus(value);
  if (field['key'] == 'gender') {
    return const {
          'male': '男',
          'female': '女',
          'other': '其他',
          'unknown': '未填写',
        }['$value'.toLowerCase()] ??
        '$value';
  }
  return feedbackValue(value);
}

class ProfileSurface extends StatelessWidget {
  const ProfileSurface({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: FanColors.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class ProfileReadingText extends StatefulWidget {
  const ProfileReadingText({
    required this.text,
    this.lines = 5,
    this.spans,
    super.key,
  });
  final String text;
  final int lines;
  final List<InlineSpan>? spans;
  @override
  State<ProfileReadingText> createState() => _ProfileReadingTextState();
}

class _ProfileReadingTextState extends State<ProfileReadingText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final span = TextSpan(
        style: profileBodyStyle,
        children: widget.spans ?? [TextSpan(text: widget.text)],
      );
      final painter = TextPainter(
        text: span,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: widget.lines,
      )..layout(maxWidth: box.maxWidth);
      final exceeds = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            span,
            maxLines: _expanded ? null : widget.lines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (exceeds)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '展开'),
            ),
        ],
      );
    },
  );
}

class ProfileImage extends StatelessWidget {
  const ProfileImage({required this.url, this.emptyLabel = '未上传图片', super.key});
  final String? url;
  final String emptyLabel;
  Widget _image() => FanImage(
    imageUrl: url,
    fit: BoxFit.contain,
    loadingPlaceholder: const Center(
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    fallback: const Center(
      child: Text(
        '图片加载失败',
        style: profileNoteStyle,
        textAlign: TextAlign.center,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!profileHasValue(url)) return Text(emptyLabel, style: profileNoteStyle);
    return Semantics(
      label: '放大查看图片',
      button: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('查看图片')),
              body: SafeArea(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Center(child: _image()),
                ),
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 88, height: 88, child: _image()),
        ),
      ),
    );
  }
}

class ProfileRelationRecord extends StatelessWidget {
  const ProfileRelationRecord({required this.record, super.key});
  final FeedbackJson record;
  @override
  Widget build(BuildContext context) {
    final account = record.containsKey('platform');
    final name = account
        ? (profileHasValue(record['handle'])
              ? '${record['handle']}'
              : profileFieldValue({}, record['platform_account_id']))
        : (profileHasValue(record['name']) ? '${record['name']}' : '名称未填写');
    String date(dynamic value) =>
        value == null || value == 'None' || value == 'null' ? '' : '$value';
    final start = date(record['start_date']);
    final end = date(record['end_date']);
    final dates = start.isEmpty && end.isEmpty
        ? '日期未填写'
        : end.isEmpty
        ? '开始：$start'
        : start.isEmpty
        ? '结束：$end'
        : '$start — $end';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(name, style: profileBodyStyle),
            if (record.containsKey('status'))
              Text(profileStatus(record['status']), style: profileNoteStyle),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          account ? '${record['platform'] ?? '平台未填写'}' : dates,
          style: profileNoteStyle,
        ),
        if (profileHasValue(record['role'])) ...[
          const SizedBox(height: 4),
          Text('角色：${record['role']}', style: profileNoteStyle),
        ],
      ],
    );
  }
}

class ProfileRelations extends StatefulWidget {
  const ProfileRelations({
    required this.label,
    required this.records,
    super.key,
  });
  final String label;
  final List<FeedbackJson> records;
  @override
  State<ProfileRelations> createState() => _ProfileRelationsState();
}

class _ProfileRelationsState extends State<ProfileRelations> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.label} (${widget.records.length})',
                  style: profileBodyStyle,
                ),
              ),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
      if (_expanded)
        if (widget.records.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('未填写', style: profileNoteStyle),
          )
        else
          for (var i = 0; i < widget.records.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ProfileRelationRecord(record: widget.records[i]),
            ),
          ],
    ],
  );
}

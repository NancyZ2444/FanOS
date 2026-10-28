import 'package:flutter/material.dart';

import 'feedback_data.dart';

/// Submit operations against stable IDs, never replace the relationship array.
class ProfileRelationEditor extends StatelessWidget {
  const ProfileRelationEditor({
    required this.field,
    required this.operations,
    required this.onChanged,
    required this.pick,
    super.key,
  });
  final FeedbackJson field;
  final List<FeedbackJson> operations;
  final ValueChanged<List<FeedbackJson>> onChanged;
  final Future<FeedbackJson?> Function(String) pick;
  Future<void> _edit(BuildContext context, [FeedbackJson? current]) async {
    final account = field['key'] == 'official_accounts';
    FeedbackJson? target;
    if (current == null && !account) {
      target = await pick(
        field['key'] == 'company_relations'
            ? 'companies'
            : field['entity_type'] == 'groups'
            ? 'idols'
            : 'groups',
      );
      if (target == null || !context.mounted) return;
    }
    final name = current?['name'] ?? target?['name'] ?? '官方账号';
    final prior = operations
        .where((o) => current != null && o['id'] == current['id'])
        .firstOrNull;
    final data = Map<String, dynamic>.from(prior?['data'] ?? current ?? {});
    final controllers = {
      for (final key
          in account
              ? ['platform', 'handle', 'platform_account_id']
              : ['start_date', 'end_date', 'role'])
        key: TextEditingController(text: '${data[key] ?? ''}'),
    };
    var status = data['status'] ?? 'active';
    final reason = TextEditingController(text: prior?['reason'] ?? '');
    final value = await showModalBottomSheet<FeedbackJson>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${current == null ? '新增' : '修订'} · $name',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final entry in controllers.entries)
                    if (entry.key != 'role' ||
                        field['key'] == 'memberships') ...[
                      TextField(
                        controller: entry.value,
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: const {
                            'platform': '平台',
                            'handle': '显示名称',
                            'platform_account_id': '账号标识',
                            'start_date': '开始日期 YYYY-MM-DD',
                            'end_date': '结束日期 YYYY-MM-DD（选填）',
                            'role': '组合内角色（选填）',
                          }[entry.key],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (field['key'] == 'memberships') ...[
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('活动中')),
                        DropdownMenuItem(
                          value: 'inactive',
                          child: Text('暂停活动'),
                        ),
                        DropdownMenuItem(value: 'former', child: Text('历史成员')),
                      ],
                      onChanged: (v) => update(() => status = v),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: '关系修订原因（作废时必填）',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (current != null)
                    TextButton(
                      onPressed: () {
                        if (reason.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请填写作废原因')),
                          );
                          return;
                        }
                        Navigator.pop(context, {
                          'operation': 'DELETE',
                          'name': name,
                          'id': current['id'],
                          'reason': reason.text.trim(),
                        });
                      },
                      child: const Text('建议作废错误关系（保留历史）'),
                    ),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'operation': current == null ? 'ADD' : 'UPDATE',
                        'name': name,
                        if (current != null) 'id': current['id'],
                        'reason': reason.text.trim(),
                        'data': {
                          if (!account)
                            'target_id':
                                current?['target_id'] ?? target!['entity_id'],
                          for (final c in controllers.entries)
                            if (c.key != 'role' ||
                                field['key'] == 'memberships')
                              c.key: c.value.text.trim(),
                          if (field['key'] == 'memberships') 'status': status,
                        },
                      }),
                      child: const Text('保留建议'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    reason.dispose();
    if (value != null) {
      onChanged([
        ...operations.where((o) => current == null || o['id'] != current['id']),
        value,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('正常退出请修订有效期；错误关系可建议作废，审核后生效。'),
      for (final row in feedbackItems(field['current']))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(row['name'] ?? '${row['platform']} · ${row['handle']}'),
          subtitle: Text(
            [
              row['start_date'],
              row['end_date'],
              row['role'],
            ].where((v) => v != null && v != '').join(' · '),
          ),
          trailing: IconButton(
            tooltip: '修订关系',
            onPressed: () => _edit(context, row),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ),
      if (operations.isNotEmpty) ...[
        Text('已填写 ${operations.length} 项关系建议'),
        for (var i = 0; i < operations.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${{'ADD': '新增', 'UPDATE': '修改', 'DELETE': '作废'}[operations[i]['operation']]} · ${operations[i]['name'] ?? '关系'}',
            ),
            trailing: IconButton(
              tooltip: '移除建议',
              onPressed: () => onChanged([...operations]..removeAt(i)),
              icon: const Icon(Icons.close),
            ),
          ),
      ],
      OutlinedButton.icon(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('新增关系建议'),
      ),
    ],
  );
}

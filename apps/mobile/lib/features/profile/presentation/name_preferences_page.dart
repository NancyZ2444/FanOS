import 'package:fan_os/core/data/name_preferences.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NamePreferencesPage extends ConsumerStatefulWidget {
  const NamePreferencesPage({super.key});
  @override
  ConsumerState<NamePreferencesPage> createState() =>
      _NamePreferencesPageState();
}

class _NamePreferencesPageState extends ConsumerState<NamePreferencesPage> {
  String _query = '';
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(namePreferencesProvider);
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('名称与备注')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '艺人、组合名称展示',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<NameDisplayMode>(
            key: ValueKey(preferences.mode),
            initialValue: preferences.mode,
            items: NameDisplayMode.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: _saving
                ? null
                : (mode) async {
                    if (mode == null) return;
                    setState(() => _saving = true);
                    try {
                      await ref
                          .read(namePreferencesProvider.notifier)
                          .setMode(mode);
                    } catch (_) {
                      if (context.mounted) showFanToast(context, '保存失败，请重试');
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('未填写备注时，始终展示官方名。备注仅自己可见。'),
          ),
          TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: '搜索艺人、组合或备注',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          ...catalog.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (_, _) => [
              TextButton(
                onPressed: () => ref.invalidate(catalogProvider),
                child: const Text('加载失败，重试'),
              ),
            ],
            data: (data) {
              final rows =
                  [
                    ...data.groups.map(
                      (g) => (
                        kind: 'groups',
                        id: g.id,
                        name: g.nameEn.isNotEmpty ? g.nameEn : g.name,
                        search: '${g.name} ${g.nameKo} ${g.nameTranslated}',
                      ),
                    ),
                    ...data.idols.map(
                      (i) => (
                        kind: 'idols',
                        id: i.id,
                        name: i.nameEn.isNotEmpty ? i.nameEn : i.name,
                        search: '${i.name} ${i.nameKo} ${i.nameTranslated}',
                      ),
                    ),
                  ].where(
                    (r) =>
                        '${r.name} ${r.search} ${preferences.remark(r.kind, r.id)}'
                            .toLowerCase()
                            .contains(_query),
                  );
              return rows
                  .map(
                    (r) => ListTile(
                      key: ValueKey('name-remark-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r.kind == 'groups'
                            ? Icons.groups_outlined
                            : Icons.person_outline,
                      ),
                      title: Text(r.name),
                      subtitle: Text(
                        preferences.remark(r.kind, r.id).isEmpty
                            ? '添加备注'
                            : preferences.remark(r.kind, r.id),
                      ),
                      trailing: const Icon(Icons.edit_outlined, size: 20),
                      onTap: () => showNameRemarkEditor(
                        context,
                        ref,
                        r.kind,
                        r.id,
                        r.name,
                      ),
                    ),
                  )
                  .toList();
            },
          ),
        ],
      ),
    );
  }
}

Future<void> showNameRemarkEditor(
  BuildContext context,
  WidgetRef ref,
  String kind,
  String id,
  String officialName,
) async {
  if (!ref.read(sessionProvider).isLoggedIn) {
    showFanToast(context, '登录后可设置专属备注');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) =>
        _RemarkDialog(kind: kind, id: id, officialName: officialName),
  );
}

class _RemarkDialog extends ConsumerStatefulWidget {
  const _RemarkDialog({
    required this.kind,
    required this.id,
    required this.officialName,
  });
  final String kind;
  final String id;
  final String officialName;
  @override
  ConsumerState<_RemarkDialog> createState() => _RemarkDialogState();
}

class _RemarkDialogState extends ConsumerState<_RemarkDialog> {
  late final TextEditingController _text;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: ref.read(namePreferencesProvider).remark(widget.kind, widget.id),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('备注 · ${widget.officialName}'),
      content: TextField(
        key: const Key('name-remark-input'),
        controller: _text,
        maxLength: 40,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '留空可清除备注',
          helperText: '仅自己可见，官方资料不会改变',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('name-remark-save'),
          onPressed: _saving
              ? null
              : () async {
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    await ref
                        .read(namePreferencesProvider.notifier)
                        .setRemark(widget.kind, widget.id, _text.text);
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (mounted) setState(() => _error = '保存失败，请重试');
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}

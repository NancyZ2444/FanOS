import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CatalogTagChips extends StatelessWidget {
  const CatalogTagChips({required this.tags, super.key, this.compact = false});
  final List<CatalogTag> tags;
  final bool compact;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    runSpacing: 5,
    children: tags
        .map(
          (t) => Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 9,
              vertical: compact ? 2 : 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EAFE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              t.name,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: const Color(0xFF7154B6),
              ),
            ),
          ),
        )
        .toList(),
  );
}

final catalogTagOptionsProvider =
    FutureProvider.family<List<CatalogTag>, String>((ref, type) async {
      if (useMockApi) {
        final data = await ref.watch(catalogProvider.future);
        final all = switch (type) {
          'ALBUM' => data.albums.expand((i) => i.tags),
          'EVENT' => data.events.expand((i) => i.tags),
          'OTHER' => data.others.expand((i) => i.tags),
          _ => data.cards.expand((i) => i.tags),
        };
        return {
          for (final tag in all.where((t) => t.status == 'ACTIVE')) tag.id: tag,
        }.values.toList();
      }
      final data =
          await ref
                  .watch(apiClientProvider)
                  .getData('/catalog/tags', query: {'entity_type': type})
              as Map<String, dynamic>;
      return (data['items'] as List)
          .map((i) => CatalogTag.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList();
    });

class UserTagPicker extends ConsumerStatefulWidget {
  const UserTagPicker({
    required this.entityType,
    required this.values,
    required this.onChanged,
    super.key,
  });
  final String entityType;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  @override
  ConsumerState<UserTagPicker> createState() => _UserTagPickerState();
}

class _UserTagPickerState extends ConsumerState<UserTagPicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String normalized(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  void add(String name) {
    if (widget.values.length >= 30) return;
    if (!widget.values.any((v) => normalized(v) == normalized(name))) {
      widget.onChanged([
        ...widget.values,
        name.trim().replaceAll(RegExp(r'\s+'), ' '),
      ]);
    }
    _search.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(catalogTagOptionsProvider(widget.entityType));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tags（可多选）', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: widget.values
              .map(
                (v) => InputChip(
                  label: Text(v),
                  onDeleted: () => widget.onChanged(
                    widget.values.where((t) => t != v).toList(),
                  ),
                ),
              )
              .toList(),
        ),
        TextField(
          key: const Key('catalog-tag-search'),
          controller: _search,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '搜索已有 Tag 或填写新 Tag'),
          onChanged: (_) => setState(() {}),
        ),
        options.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () =>
                ref.invalidate(catalogTagOptionsProvider(widget.entityType)),
            child: const Text('Tag 加载失败，点击重试'),
          ),
          data: (items) {
            final query = normalized(_search.text);
            final matching = items
                .where(
                  (t) =>
                      normalized(t.name).contains(query) &&
                      !widget.values.any(
                        (v) => normalized(v) == normalized(t.name),
                      ),
                )
                .take(15);
            final known = items
                .where((t) => normalized(t.name) == query)
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: matching
                      .map(
                        (t) => ActionChip(
                          label: Text(t.name),
                          onPressed: () => add(t.name),
                        ),
                      )
                      .toList(),
                ),
                if (query.isNotEmpty && known == null)
                  TextButton.icon(
                    key: const Key('catalog-add-tag'),
                    onPressed: () => add(_search.text),
                    icon: const Icon(Icons.add),
                    label: Text('随本次资料提交「${_search.text.trim()}」'),
                  ),
              ],
            );
          },
        ),
        const Text(
          '新 Tag 随本次资料一起审核，无需单独申请。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

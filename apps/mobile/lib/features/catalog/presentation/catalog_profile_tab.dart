import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'profile_reading_widgets.dart';
import 'catalog_profile_history.dart';
export 'catalog_profile_history.dart';

const profileSections = {
  'intro': '简介',
  'basic': '基本资料',
  'career': '从艺历程',
  'honors': '荣誉记录',
};
final catalogProfileProvider = FutureProvider.autoDispose
    .family<FeedbackJson, String>((ref, path) async {
      final result = await ref
          .watch(apiClientProvider)
          .getData('/catalog/profiles/$path');
      return Map<String, dynamic>.from(result as Map);
    }, retry: (_, _) => null);

Future<void> openCatalogProfileEditor(
  BuildContext context,
  WidgetRef ref,
  String kind,
  String id,
) async {
  // Public corrections retain the existing login and server review permissions.
  if (!ref.read(sessionProvider).isLoggedIn) {
    context.push('/login');
    return;
  }
  final section = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: FanColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '资料反馈',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in profileSections.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value, style: profileBodyStyle),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    ),
  );
  if (section == null || !context.mounted) return;
  await context.push(
    Uri(
      path: '/catalog-correction',
      queryParameters: {'type': kind, 'id': id, 'section': section},
    ).toString(),
  );
  if (context.mounted) ref.invalidate(catalogProfileProvider('$kind/$id'));
}

class CatalogPersonalRemarkButton extends StatelessWidget {
  const CatalogPersonalRemarkButton({required this.onPressed, super.key});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '个人备注',
    icon: const Icon(Icons.edit_outlined, size: 22),
    onPressed: onPressed,
  );
}

class CatalogProfileActions extends ConsumerWidget {
  const CatalogProfileActions({
    required this.kind,
    required this.entityId,
    super.key,
  });
  final String kind, entityId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(72, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: () => openCatalogProfileEditor(context, ref, kind, entityId),
        child: const Text('资料反馈'),
      ),
      IconButton(
        tooltip: '修订历史',
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: const Icon(Icons.history_outlined, size: 22),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CatalogProfileHistory(kind: kind, entityId: entityId),
          ),
        ),
      ),
    ],
  );
}

class CatalogProfileTab extends ConsumerStatefulWidget {
  const CatalogProfileTab({
    required this.kind,
    required this.entityId,
    this.section,
    super.key,
  });
  final String kind, entityId;
  final String? section;
  @override
  ConsumerState<CatalogProfileTab> createState() => _CatalogProfileTabState();
}

class _CatalogProfileTabState extends ConsumerState<CatalogProfileTab>
    with AutomaticKeepAliveClientMixin {
  final _anchors = {for (final key in profileSections.keys) key: GlobalKey()};
  String? _lastJump;
  @override
  bool get wantKeepAlive => true;

  void _jump(String? section) {
    if (section == null || section == _lastJump) return;
    _lastJump = section;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _anchors[section]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final path = '${widget.kind}/${widget.entityId}';
    return ref
        .watch(catalogProfileProvider(path))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => FanEmptyState(
            icon: Icons.cloud_off_outlined,
            title: '资料暂时无法加载',
            message: '请稍后重试',
            actionLabel: '重新加载',
            onAction: () => ref.invalidate(catalogProfileProvider(path)),
          ),
          data: (profile) {
            final fields = feedbackItems(profile['fields']);
            _jump(widget.section);
            final empty = !fields.any((f) => profileHasValue(f['current']));
            return ListView(
              key: PageStorageKey('profile-$path'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  key: const Key('catalog-profile-toolbar'),
                  children: [
                    Expanded(
                      child: Text(
                        profile['published_at'] == null
                            ? '更新时间未记录'
                            : '更新于 ${profileTime(profile['published_at'])}',
                        style: profileNoteStyle.copyWith(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 4),
                    CatalogProfileActions(
                      kind: widget.kind,
                      entityId: widget.entityId,
                    ),
                  ],
                ),
                if (profile['pending_feedback_id'] != null)
                  Padding(
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () => context.push(
                        '/feedback/${profile['pending_feedback_id']}',
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '你有一条资料修订待处理',
                                style: profileNoteStyle,
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (empty) ...[
                  const Text(
                    '暂无资料',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('尚未收录公开资料', style: profileNoteStyle),
                ] else
                  for (final entry in profileSections.entries) ...[
                    if (entry.key != 'intro') const SizedBox(height: 24),
                    Text(
                      entry.value,
                      key: _anchors[entry.key],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (entry.key == 'basic')
                      _BasicProfile(
                        fields: fields
                            .where((f) => f['section'] == 'basic')
                            .toList(),
                      )
                    else
                      _SectionText(
                        label: entry.value,
                        text:
                            '${fields.where((f) => f['section'] == entry.key).firstOrNull?['current'] ?? ''}',
                      ),
                  ],
              ],
            );
          },
        );
  }
}

class _SectionText extends StatelessWidget {
  const _SectionText({required this.label, required this.text});
  final String label, text;
  @override
  Widget build(BuildContext context) => text.trim().isEmpty
      ? Text('暂无$label', style: profileNoteStyle)
      : ProfileReadingText(text: text);
}

class _BasicProfile extends StatefulWidget {
  const _BasicProfile({required this.fields});
  final List<FeedbackJson> fields;
  @override
  State<_BasicProfile> createState() => _BasicProfileState();
}

class _BasicProfileState extends State<_BasicProfile> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    final fields = widget.fields
        .where((f) => _all || profileHasValue(f['current']))
        .toList();
    final hasHidden = widget.fields.any((f) => !profileHasValue(f['current']));
    return ProfileSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fields.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('未填写', style: profileNoteStyle),
            ),
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            if (fields[i]['type'] == 'relations')
              ProfileRelations(
                key: ValueKey(fields[i]['key']),
                label: fields[i]['label'],
                records: feedbackItems(fields[i]['current']),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          fields[i]['label'],
                          style: profileNoteStyle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: fields[i]['type'] == 'image'
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: ProfileImage(url: fields[i]['current']),
                              )
                            : SelectableText(
                                profileFieldValue(
                                  fields[i],
                                  fields[i]['current'],
                                ),
                                style: profileBodyStyle,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (hasHidden) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(() => _all = !_all),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _all ? '收起未填写字段' : '查看全部基本字段',
                        style: profileNoteStyle,
                      ),
                    ),
                    Icon(
                      _all ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

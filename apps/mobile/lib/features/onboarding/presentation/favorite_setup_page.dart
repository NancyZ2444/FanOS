import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/profile/presentation/name_preferences_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FavoriteSetupPage extends ConsumerStatefulWidget {
  const FavoriteSetupPage({super.key});

  @override
  ConsumerState<FavoriteSetupPage> createState() => _FavoriteSetupPageState();
}

class _FavoriteSetupPageState extends ConsumerState<FavoriteSetupPage> {
  late Set<String> _selected;
  String? _primary;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final favorites = ref.read(favoritesProvider);
    _selected = {...favorites.selectedIds};
    _primary = favorites.primaryId;
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _save() async {
    final data = ref.read(catalogProvider).asData?.value;
    if (_saving || data == null) return;
    final visibleIds = data.idols.map((idol) => idol.id).toSet();
    setState(() => _saving = true);
    try {
      await ref
          .read(favoritesProvider.notifier)
          .saveSelection(_selected.intersection(visibleIds), _primary);
      if (mounted) _close();
    } catch (_) {
      if (mounted) showFanToast(context, '本命保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final validIds =
        catalog.asData?.value.idols.map((idol) => idol.id).toSet() ??
        <String>{};
    final selectedCount = _selected.intersection(validIds).length;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NamePreferencesPage(),
              ),
            ),
            child: const Text('名称与备注'),
          ),
        ],
      ),
      body: SafeArea(
        child: FanContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text('选择你的本命', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '选择 0–20 位艺人。点亮星星可优先展示一位，再点可取消，也可以不设置。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: FanColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: '搜索艺人或组合',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: catalog.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const FanEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: '加载失败',
                    message: '请稍后重试',
                  ),
                  data: (data) {
                    final idols = data.idols
                        .where(
                          (idol) =>
                              '${idol.displayName} ${idol.secondaryName} ${idol.groupName}'
                                  .toLowerCase()
                                  .contains(_query),
                        )
                        .toList();
                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 14,
                            mainAxisExtent: 172,
                          ),
                      itemCount: idols.length,
                      itemBuilder: (context, index) {
                        final idol = idols[index];
                        return _IdolChoice(
                          idol: idol,
                          selected: _selected.contains(idol.id),
                          primary: _primary == idol.id,
                          onStar: _saving || !_selected.contains(idol.id)
                              ? null
                              : () => setState(
                                  () => _primary = _primary == idol.id
                                      ? null
                                      : idol.id,
                                ),
                          onTap: _saving
                              ? () {}
                              : () => setState(() {
                                  _selected = _selected.intersection(validIds);
                                  if (_selected.contains(idol.id)) {
                                    _selected.remove(idol.id);
                                  } else if (_selected.length < 20) {
                                    _selected.add(idol.id);
                                  }
                                  if (!_selected.contains(_primary)) {
                                    _primary = null;
                                  }
                                }),
                        );
                      },
                    );
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: _saving || catalog.asData == null ? null : _save,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(_saving ? '正在保存…' : '完成（已选 $selectedCount）'),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _close,
                  child: const Text('暂时跳过'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdolChoice extends StatelessWidget {
  const _IdolChoice({
    required this.idol,
    required this.selected,
    required this.primary,
    required this.onTap,
    required this.onStar,
  });

  final IdolProfile idol;
  final bool selected;
  final bool primary;
  final VoidCallback onTap;
  final VoidCallback? onStar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IdolAvatar(idol: idol, size: 72, selected: selected),
              if (selected)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 23,
                    height: 23,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: FanColors.ink,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            idol.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            idol.displayGroupName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primary ? FanColors.lavender : FanColors.textSecondary,
              fontSize: 11,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          SizedBox(
            height: 36,
            child: IconButton(
              key: ValueKey('favorite-star-${idol.id}'),
              tooltip: primary ? '取消星标' : '点亮星星，优先展示',
              onPressed: onStar,
              padding: EdgeInsets.zero,
              icon: Icon(
                primary ? Icons.star_rounded : Icons.star_outline_rounded,
                color: primary ? FanColors.lavender : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:fan_os/app/theme.dart';

import 'dart:async';

import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialType});
  final String? initialType;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  String _selectedType = '全部';
  String _query = '';
  Timer? _debounce;

  static const types = ['全部', '组合', '艺人', '专辑', '活动', '小卡', '其他来源', '用户'];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    if (types.contains(widget.initialType)) _selectedType = widget.initialType!;
    _controller.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() => _query = _controller.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        titleSpacing: 0,
        title: TextField(
          key: const Key('catalog-search-input'),
          controller: _controller,
          autofocus: widget.initialType == null,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索组合、艺人、专辑、小卡、用户',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.cancel_rounded, size: 19),
                  ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('取消')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: types.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(types[index]),
                  selected: _selectedType == types[index],
                  onSelected: (_) =>
                      setState(() => _selectedType = types[index]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _selectedType == '用户'
                  ? _userResults()
                  : catalog.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => const FanEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: '搜索暂时不可用',
                        message: '请稍后再试',
                      ),
                      data: _buildResults,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(CatalogBundle data) {
    if (_query.isEmpty && _selectedType == '全部') return _searchLanding();
    bool matches(String text) =>
        _query.isEmpty || text.toLowerCase().contains(_query);
    final groups = data.groups
        .where(
          (item) => matches(
            '${item.displayName} ${item.name} ${item.nameEn} ${item.nameKo} ${item.nameTranslated} ${item.company}',
          ),
        )
        .toList();
    final idols = data.idols
        .where(
          (item) => matches(
            '${item.displayName} ${item.name} ${item.nameEn} ${item.nameKo} ${item.nameTranslated} ${item.realName} ${item.groupName} ${item.company} ${item.role}',
          ),
        )
        .toList();
    final cards = data.cards
        .where(
          (item) => matches(
            '${item.cardNumber} ${item.title} ${item.titleEn} ${item.titleKo} ${item.titleTranslated} ${item.idolName} ${item.groupName} ${item.source} ${item.version} ${item.tags.map((t) => t.name).join(" ")}',
          ),
        )
        .toList();
    final albums = data.albums
        .where(
          (item) => matches(
            '${item.name} ${item.nameEn} ${item.nameKo} ${item.nameTranslated} ${item.artistName} ${item.albumType} ${item.tags.map((t) => t.name).join(" ")}',
          ),
        )
        .toList();
    final events = data.events
        .where(
          (item) => matches(
            '${item.name} ${item.nameEn} ${item.nameKo} ${item.nameTranslated} ${item.artistName} ${item.eventType} ${item.tags.map((t) => t.name).join(" ")} ${item.city} ${item.platform}',
          ),
        )
        .toList();
    final others = data.others
        .where(
          (item) => matches(
            '${item.name} ${item.nameEn} ${item.nameKo} ${item.nameTranslated} ${item.originalName} ${item.tags.map((t) => t.name).join(" ")}',
          ),
        )
        .toList();
    final usersAsync = _show('用户') && _query.isNotEmpty
        ? ref.watch(userSearchProvider(_query))
        : null;
    final userMatches = usersAsync?.value?.isNotEmpty ?? false;

    final hasResults = switch (_selectedType) {
      '组合' => groups.isNotEmpty,
      '艺人' => idols.isNotEmpty,
      '专辑' => albums.isNotEmpty,
      '活动' => events.isNotEmpty,
      '小卡' => cards.isNotEmpty,
      '其他来源' => others.isNotEmpty,
      '用户' => userMatches,
      _ =>
        groups.isNotEmpty ||
            idols.isNotEmpty ||
            cards.isNotEmpty ||
            albums.isNotEmpty ||
            events.isNotEmpty ||
            others.isNotEmpty ||
            userMatches,
    };
    if (!hasResults &&
        usersAsync?.isLoading != true &&
        usersAsync?.hasError != true) {
      return FanEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到相关结果',
        message: '修改关键词、切换分类，或使用 AI Scan 识别小卡。',
        actionLabel: '去 AI Scan',
        onAction: () => context.go('/scan'),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        if (_show('艺人') && idols.isNotEmpty)
          _SearchSection(
            title: '艺人',
            count: idols.length,
            children: idols
                .take(_limit)
                .map(
                  (idol) => ListTile(
                    onTap: () => context.push('/idol/${idol.id}'),
                    leading: IdolAvatar(idol: idol, size: 46),
                    title: Text(
                      idol.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        if (idol.secondaryName.isNotEmpty) idol.secondaryName,
                        idol.displayGroupName,
                        idol.role,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                )
                .toList(),
          ),
        if (_show('组合') && groups.isNotEmpty)
          _SearchSection(
            title: '组合',
            count: groups.length,
            children: groups
                .take(_limit)
                .map(
                  (group) => ListTile(
                    onTap: () => context.push('/group/${group.id}'),
                    leading: _GradientAvatar(
                      imageUrl: group.thumbnailUrl ?? group.imageUrl,
                      label: group.displayName.characters.first,
                      start: group.colorStart,
                      end: group.colorEnd,
                    ),
                    title: Text(
                      group.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        if (group.secondaryName.isNotEmpty) group.secondaryName,
                        group.company,
                        group.status,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                )
                .toList(),
          ),
        if (_show('专辑') && albums.isNotEmpty)
          _entitySection(
            '专辑',
            albums
                .take(_limit)
                .map(
                  (item) => _SearchEntity(
                    title: item.displayName,
                    subtitle:
                        '${item.secondaryName.isEmpty ? data.artistLabel(item.artists, item.artistName) : item.secondaryName} · ${item.albumType} ${item.tags.map((t) => t.name).join(" ")} · ${item.releaseDate}',
                    icon: Icons.album_outlined,
                    imageUrl: item.frontImageUrl,
                    start: item.colorStart,
                    end: item.colorEnd,
                    route: '/album/${item.id}',
                  ),
                )
                .toList(),
            albums.length,
          ),
        if (_show('活动') && events.isNotEmpty)
          _entitySection(
            '活动',
            events
                .take(_limit)
                .map(
                  (item) => _SearchEntity(
                    title: item.displayName,
                    subtitle:
                        '${item.secondaryName.isEmpty ? item.eventType : item.secondaryName} · ${item.startDate} · ${item.locationLabel}',
                    icon: Icons.event_outlined,
                    imageUrl: item.imageUrl,
                    start: item.colorStart,
                    end: item.colorEnd,
                    route: '/event/${item.id}',
                  ),
                )
                .toList(),
            events.length,
          ),
        if (_show('其他来源') && others.isNotEmpty)
          _entitySection(
            '其他来源',
            others
                .take(_limit)
                .map(
                  (item) => _SearchEntity(
                    title: item.displayName,
                    subtitle: [
                      item.originalName,
                      item.startDate,
                      ...item.tags.map((t) => t.name),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    icon: Icons.shopping_bag_outlined,
                    imageUrl: item.imageUrl,
                    start: item.colorStart,
                    end: item.colorEnd,
                    route: '/other/${item.id}',
                  ),
                )
                .toList(),
            others.length,
          ),
        if (_show('用户') && usersAsync?.isLoading == true)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_show('用户') && usersAsync?.hasError == true)
          ListTile(
            title: const Text('用户搜索加载失败'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(userSearchProvider(_query)),
              child: const Text('重试'),
            ),
          ),
        if (_show('用户') && userMatches)
          _SearchSection(
            title: '用户',
            count: usersAsync!.value!.length,
            children: usersAsync.value!.take(_limit).map(_userTile).toList(),
          ),
        if (_show('小卡') && cards.isNotEmpty) ...[
          SectionHeader(title: '小卡', actionLabel: '${cards.length} 个结果'),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: fanCardGrid(context),
            itemCount: _selectedType == '全部'
                ? cards.take(6).length
                : cards.length,
            itemBuilder: (context, index) => CollectibleCardTile(
              card: cards[index],
              compact: true,
              onTap: () => context.push('/card/${cards[index].id}'),
            ),
          ),
        ],
      ],
    );
  }

  int get _limit => _selectedType == '全部' ? 3 : 1000;

  Widget _userTile(PublicUserProfile user) => ListTile(
    onTap: () => context.push('/user/${user.id}'),
    leading: ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: FanImage(
          imageUrl: user.avatarPath,
          fallback: Center(child: Text(user.initial)),
        ),
      ),
    ),
    title: Text(
      user.displayName,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      user.bio.isEmpty ? 'Lv.${user.level}' : user.bio,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
  );

  Widget _userResults() {
    if (_query.isEmpty) {
      return const FanEmptyState(
        icon: Icons.person_search_outlined,
        title: '搜索用户',
        message: '输入用户昵称。',
      );
    }
    return ref
        .watch(userSearchProvider(_query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => FanEmptyState(
            icon: Icons.cloud_off_outlined,
            title: '用户搜索加载失败',
            message: '请检查网络或登录状态后重试。',
            actionLabel: '重试',
            onAction: () => ref.invalidate(userSearchProvider(_query)),
          ),
          data: (users) => users.isEmpty
              ? const FanEmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有找到相关用户',
                  message: '请尝试其他昵称。',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  children: users.map(_userTile).toList(),
                ),
        );
  }

  bool _show(String type) => _selectedType == '全部' || _selectedType == type;

  Widget _entitySection(String title, List<_SearchEntity> items, int count) =>
      _SearchSection(
        title: title,
        count: count,
        children: items
            .map(
              (item) => ListTile(
                onTap: () => context.push(item.route),
                leading: _GradientAvatar(
                  imageUrl: item.imageUrl,
                  icon: item.icon,
                  start: item.start,
                  end: item.end,
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(item.subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            )
            .toList(),
      );

  Widget _searchLanding() {
    const recent = ['Aria', 'Starlit', 'Afterglow Tour'];
    const popular = ['LUMINA', 'Bloom POB', 'NOVA', '2026 Fansign'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const SectionHeader(title: '最近搜索'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: recent
              .map(
                (text) => InputChip(
                  avatar: const Icon(Icons.history_rounded, size: 16),
                  label: Text(text),
                  onPressed: () => _controller.text = text,
                  onDeleted: () {},
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 26),
        const SectionHeader(title: '热门搜索'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: popular
              .map(
                (text) => ActionChip(
                  avatar: const Icon(
                    Icons.local_fire_department_outlined,
                    size: 16,
                  ),
                  label: Text(text),
                  onPressed: () => _controller.text = text,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 32),
        Card(
          child: ListTile(
            onTap: () => context.go('/scan'),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE9FF),
              child: Icon(Icons.document_scanner_outlined),
            ),
            title: const Text(
              '找不到手中的小卡？',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('使用 AI Scan 匹配官方图鉴'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    );
  }
}

class _SearchEntity {
  const _SearchEntity({
    this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.start,
    required this.end,
    required this.route,
  });
  final String title;
  final String? imageUrl;
  final String subtitle;
  final IconData icon;
  final int start;
  final int end;
  final String route;
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.title,
    required this.count,
    required this.children,
  });
  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          SectionHeader(title: title, actionLabel: '$count 个结果'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1)
                    const Divider(height: 1, indent: 66),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientAvatar extends StatelessWidget {
  const _GradientAvatar({
    this.imageUrl,
    required this.start,
    required this.end,
    this.label,
    this.icon,
  });
  final int start;
  final String? imageUrl;
  final int end;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: FanColors.lavenderSoft,
      ),
      child: ClipOval(
        child: FanImage(
          imageUrl: imageUrl,
          fallback: icon != null
              ? Icon(icon, color: Colors.white, size: 21)
              : Text(label ?? '', style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ProfileLevelPage extends ConsumerWidget {
  const ProfileLevelPage({super.key, this.payload});

  final Map<String, Object>? payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final name = payload?['name'] as String? ?? session.displayName;
    final level = payload?['level'] as int? ?? session.level;
    final experience = payload?['experience'] as int? ?? session.experience;
    final next = payload?['next'] as int? ?? session.nextLevelExperience;
    final currentFloor = (level - 1) * 250;
    final progress = ((experience - currentFloor) / (next - currentFloor))
        .clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('等级与成长值')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEE9FF), Color(0xFFFFEFF3)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Lv.$level',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 8),
                Text(
                  '$experience / $next EXP',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('如何获得成长值', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Card(
            child: Column(
              children: [
                _ExperienceRow(
                  icon: Icons.style_outlined,
                  title: '完善收藏记录',
                  subtitle: '收藏新卡、维护拥有数量',
                  value: '+5 EXP',
                ),
                Divider(height: 1, indent: 58),
                _ExperienceRow(
                  icon: Icons.document_scanner_outlined,
                  title: '完成 AI Scan 确认',
                  subtitle: '准确确认识别结果',
                  value: '+3 EXP',
                ),
                Divider(height: 1, indent: 58),
                _ExperienceRow(
                  icon: Icons.auto_awesome_outlined,
                  title: '每日访问与翻卡',
                  subtitle: '记录每天的追星时刻',
                  value: '+1 EXP',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '等级用于呈现你在 Fan OS 的收藏成长，不影响内容浏览与基础功能。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ExperienceRow extends StatelessWidget {
  const _ExperienceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class ProfileRelationsPage extends ConsumerWidget {
  const ProfileRelationsPage({
    required this.type,
    required this.userId,
    super.key,
  });

  final String type;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFollowers = type == 'followers';
    final relation = ref.watch(profileRelationshipProvider);
    final users = DemoUserProfiles.users.where((user) {
      if (userId != 'current-user') return true;
      return isFollowers
          ? relation.followsMeIds.contains(user.id)
          : relation.followingIds.contains(user.id);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(isFollowers ? '粉丝' : '关注')),
      body: users.isEmpty
          ? FanEmptyState(
              icon: isFollowers
                  ? Icons.people_outline_rounded
                  : Icons.person_add_alt_rounded,
              title: isFollowers ? '还没有粉丝' : '还没有关注任何人',
              message: '从搜索或其他用户主页发现同好。',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
              itemCount: users.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 66),
              itemBuilder: (context, index) {
                final user = users[index];
                final status = relation.statusFor(user.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 5),
                  onTap: () => context.push('/user/${user.id}'),
                  leading: CircleAvatar(
                    backgroundColor: FanColors.lavenderSoft,
                    child: Text(
                      user.initial,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(
                    user.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Lv.${user.level}${user.primaryIdolId == null ? '' : ' · ★ ${_idolLabel(user.primaryIdolId)}'}',
                  ),
                  trailing: userId == 'current-user'
                      ? _RelationAction(
                          status: status,
                          busy: relation.busyUserIds.contains(user.id),
                          onPressed: () => ref
                              .read(profileRelationshipProvider.notifier)
                              .toggleFollow(user.id),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                );
              },
            ),
    );
  }

  String _idolLabel(String? id) => switch (id) {
    'idol-aria' => 'Aria',
    'idol-lin' => 'Lin',
    'idol-mina' => 'Mina',
    'idol-yuna' => 'Yuna',
    _ => '未设置',
  };
}

class _RelationAction extends StatelessWidget {
  const _RelationAction({
    required this.status,
    required this.busy,
    required this.onPressed,
  });

  final UserRelationStatus status;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final following =
        status == UserRelationStatus.following ||
        status == UserRelationStatus.mutual;
    final label = switch (status) {
      UserRelationStatus.none => '关注',
      UserRelationStatus.followsYou => '回关',
      UserRelationStatus.following => '已关注',
      UserRelationStatus.mutual => '互相关注',
    };
    return SizedBox(
      width: 86,
      child: following
          ? OutlinedButton(
              onPressed: busy ? null : onPressed,
              child: Text(busy ? '处理中' : label),
            )
          : FilledButton(
              onPressed: busy ? null : onPressed,
              child: Text(busy ? '处理中' : label),
            ),
    );
  }
}

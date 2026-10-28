import 'package:fan_os/features/profile/presentation/account_security_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/profile_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:fan_os/features/profile/presentation/name_preferences_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late bool _weiboVisible;
  late bool _discoverable;
  late bool _favoritesVisible;
  late bool _collectionVisible;
  late bool _likesVisible;
  late bool _albumsVisible;
  late bool _photosVisible;
  late bool _followingListVisible;
  late bool _followersListVisible;
  String? _avatarPath;
  String? _backgroundPath;
  bool _backgroundChanged = false;
  bool _avatarChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _nameController = TextEditingController(text: session.displayName);
    _bioController = TextEditingController(text: session.bio);
    _weiboVisible = session.weiboVisible && session.weiboName != null;
    _discoverable = session.privacy.discoverable;
    _favoritesVisible = session.privacy.favoritesVisible;
    _collectionVisible = session.privacy.collectionVisible;
    _likesVisible = session.privacy.likesVisible;
    _albumsVisible = session.privacy.albumsVisible;
    _photosVisible = session.privacy.photosVisible;
    _followingListVisible = session.privacy.followingListVisible;
    _followersListVisible = session.privacy.followersListVisible;
    _avatarPath = session.avatarPath;
    _backgroundPath = session.backgroundPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool background) async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: background ? 1600 : 512,
        maxHeight: background ? 1600 : 512,
      );
      if (image == null || !mounted) return;
      setState(() {
        if (background) {
          _backgroundPath = image.path;
          _backgroundChanged = true;
        } else {
          _avatarPath = image.path;
          _avatarChanged = true;
        }
      });
    } catch (_) {
      if (mounted) showFanToast(context, '暂时无法打开相册，请检查系统权限');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(sessionProvider.notifier);
      if (_backgroundChanged) {
        await controller.saveProfileImage('background', _backgroundPath);
      }
      if (_avatarChanged) {
        await controller.saveProfileImage('avatar', _avatarPath);
      }
      final displayName = _nameController.text.trim().isEmpty
          ? '星河收藏家'
          : _nameController.text.trim();
      await ref.read(userDataRepositoryProvider).updateProfile({
        'display_name': displayName,
        'bio': _bioController.text.trim(),
        'weibo_visible': _weiboVisible,
        'privacy': {
          'discoverable': _discoverable,
          'favorites_visible': _favoritesVisible,
          'collection_visible': _collectionVisible,
          'likes_visible': _likesVisible,
          'albums_visible': _albumsVisible,
          'photos_visible': _photosVisible,
          'following_list_visible': _followingListVisible,
          'followers_list_visible': _followersListVisible,
        },
      });
      if (!mounted) return;
      ref
          .read(sessionProvider.notifier)
          .updateProfile(
            displayName: _nameController.text.trim().isEmpty
                ? '星河收藏家'
                : _nameController.text.trim(),
            weiboVisible: _weiboVisible,
            bio: _bioController.text.trim(),
            syncRemote: false,
            privacy: ProfilePrivacy(
              discoverable: _discoverable,
              favoritesVisible: _favoritesVisible,
              collectionVisible: _collectionVisible,
              likesVisible: _likesVisible,
              albumsVisible: _albumsVisible,
              photosVisible: _photosVisible,
              followingListVisible: _followingListVisible,
              followersListVisible: _followersListVisible,
            ),
          );
      showFanToast(context, '资料已保存');
      context.pop();
    } catch (_) {
      if (mounted) showFanToast(context, '资料保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identities = ref.watch(accountIdentitiesProvider);
    final weiboBound = (identities.asData?.value['identities'] as List? ?? [])
        .whereType<Map>()
        .any((i) => i['provider'] == 'weibo' && i['bound'] == true);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('编辑资料'),
        backgroundColor: FanColors.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? '保存中…' : '保存',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: FanContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: _ImageEditTarget(
                    label: '更换头像',
                    imageUrl: _avatarPath,
                    width: 84,
                    height: 84,
                    circular: true,
                    onTap: _saving ? null : () => _pickImage(false),
                  ),
                ),
                const SizedBox(height: 18),
                _ImageEditTarget(
                  key: const Key('choose-profile-background'),
                  label: '更换主页背景',
                  imageUrl: _backgroundPath,
                  height: 140,
                  onTap: _saving ? null : () => _pickImage(true),
                ),
                if (_backgroundPath != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _backgroundPath = null;
                              _backgroundChanged = true;
                            }),
                      child: const Text('移除背景', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                const SizedBox(height: 14),
                const Text(
                  '基本资料',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  maxLength: 20,
                  decoration: const InputDecoration(labelText: '昵称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bioController,
                  maxLength: 120,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '简介',
                    hintText: '介绍一下你的收藏故事',
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.favorite_border_rounded),
                    title: const Text('管理我的本命'),
                    subtitle: const Text('选择本命、设置星标'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/onboarding/favorites'),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: const Text('名称与备注'),
                    subtitle: const Text('艺人、组合备注，优先展示且仅自己可见'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NamePreferencesPage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    title: const Text('账号与安全'),
                    subtitle: const Text('手机号、微信与微博绑定、账号恢复'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/account/security'),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '第三方身份',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: _SettingSwitchRow(
                    title: const Text('在主页展示微博身份'),
                    subtitle: Text(
                      weiboBound
                          ? '隐藏不等于解绑，仍可使用微博登录'
                          : identities.hasError
                          ? '身份状态暂时无法加载，请在账号与安全重试'
                          : '绑定可信微博身份后可展示，请前往账号与安全',
                    ),
                    value: _weiboVisible,
                    onChanged: weiboBound
                        ? (value) => setState(() => _weiboVisible = value)
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '隐私',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      _SettingSwitchRow(
                        title: const Text('允许通过公开信息搜索到我'),
                        value: _discoverable,
                        onChanged: (value) =>
                            setState(() => _discoverable = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开展示我的本命'),
                        subtitle: const Text('关闭后不影响个性化推荐'),
                        value: _favoritesVisible,
                        onChanged: (value) =>
                            setState(() => _favoritesVisible = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开我的收藏'),
                        value: _collectionVisible,
                        onChanged: (value) =>
                            setState(() => _collectionVisible = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开我的喜欢'),
                        value: _likesVisible,
                        onChanged: (value) =>
                            setState(() => _likesVisible = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开我的卡册'),
                        value: _albumsVisible,
                        onChanged: (value) =>
                            setState(() => _albumsVisible = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开我的相册'),
                        value: _photosVisible,
                        onChanged: (value) =>
                            setState(() => _photosVisible = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开关注列表'),
                        value: _followingListVisible,
                        onChanged: (value) =>
                            setState(() => _followingListVisible = value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingSwitchRow(
                        title: const Text('公开粉丝列表'),
                        value: _followersListVisible,
                        onChanged: (value) =>
                            setState(() => _followersListVisible = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(sessionProvider.notifier).signOut();
                      } catch (_) {
                        if (context.mounted) {
                          await showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('退出未完成'),
                              content: const Text('请检查网络后重试，登录凭证已保留。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          );
                        }
                        return;
                      }
                      if (context.mounted) context.go('/');
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB45C5C),
                    ),
                    child: const Text(
                      '退出登录',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageEditTarget extends StatelessWidget {
  const _ImageEditTarget({
    required this.label,
    required this.imageUrl,
    required this.height,
    required this.onTap,
    this.width = double.infinity,
    this.circular = false,
    super.key,
  });
  final String label;
  final String? imageUrl;
  final double width, height;
  final bool circular;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(circular ? 99 : 16),
        child: SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(circular ? 99 : 16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FanImage(
                  imageUrl: imageUrl,
                  fallback: const ColoredBox(
                    color: FanColors.lavenderSoft,
                    child: Icon(
                      Icons.image_outlined,
                      color: FanColors.textSecondary,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    color: Colors.black.withValues(alpha: .38),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    color: FanColors.ink,
                  ),
                  child: title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                      color: FanColors.textSecondary,
                    ),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 51,
            height: 44,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: FanColors.lavender,
              inactiveTrackColor: FanColors.line,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    ),
  );
}

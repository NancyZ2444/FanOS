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
    _weiboVisible = session.weiboVisible;
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
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: FanContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: ClipOval(
                    child: FanImage(
                      imageUrl: _avatarPath,
                      fallback: ColoredBox(
                        color: FanColors.lavenderSoft,
                        child: Center(
                          child: Text(
                            _nameController.text.isEmpty
                                ? '星'
                                : _nameController.text.characters.first,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    try {
                      final image = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 88,
                      );
                      if (image != null && mounted) {
                        setState(() {
                          _avatarPath = image.path;
                          _avatarChanged = true;
                        });
                      }
                    } catch (_) {
                      if (context.mounted) {
                        showFanToast(context, '暂时无法打开相册，请检查系统权限');
                      }
                    }
                  },
                  child: const Text('更换头像'),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 140,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FanImage(
                    imageUrl: _backgroundPath,
                    fallback: const ColoredBox(
                      color: FanColors.lavenderSoft,
                      child: Center(
                        child: Icon(Icons.panorama_outlined, size: 38),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('choose-profile-background'),
                    onPressed: _saving
                        ? null
                        : () async {
                            try {
                              final image = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 88,
                              );
                              if (image != null && mounted) {
                                setState(() {
                                  _backgroundPath = image.path;
                                  _backgroundChanged = true;
                                });
                              }
                            } catch (_) {
                              if (context.mounted) {
                                showFanToast(context, '暂时无法打开相册，请检查权限');
                              }
                            }
                          },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('设置主页背景'),
                  ),
                  if (_backgroundPath != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _backgroundPath = null;
                              _backgroundChanged = true;
                            }),
                      child: const Text('移除背景'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('基本资料', style: TextStyle(fontWeight: FontWeight.w800)),
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
                  subtitle: const Text('艺人、组合备注及默认展示方式'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NamePreferencesPage(),
                    ),
                  ),
                ),
              ),
              const Text(
                '第三方身份',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(
                    Icons.rss_feed_rounded,
                    color: FanColors.coral,
                  ),
                  title: const Text('在主页展示微博身份'),
                  subtitle: const Text('隐藏不等于解绑，仍可使用微博登录'),
                  value: _weiboVisible,
                  onChanged: (value) => setState(() => _weiboVisible = value),
                ),
              ),
              const SizedBox(height: 20),
              const Text('隐私', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('允许通过公开信息搜索到我'),
                      value: _discoverable,
                      onChanged: (value) =>
                          setState(() => _discoverable = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开展示我的本命'),
                      subtitle: const Text('关闭后不影响个性化推荐'),
                      value: _favoritesVisible,
                      onChanged: (value) =>
                          setState(() => _favoritesVisible = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开我的收藏'),
                      value: _collectionVisible,
                      onChanged: (value) =>
                          setState(() => _collectionVisible = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开我的喜欢'),
                      value: _likesVisible,
                      onChanged: (value) =>
                          setState(() => _likesVisible = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开我的卡册'),
                      value: _albumsVisible,
                      onChanged: (value) =>
                          setState(() => _albumsVisible = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开我的相册'),
                      value: _photosVisible,
                      onChanged: (value) =>
                          setState(() => _photosVisible = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开关注列表'),
                      value: _followingListVisible,
                      onChanged: (value) =>
                          setState(() => _followingListVisible = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('公开粉丝列表'),
                      value: _followersListVisible,
                      onChanged: (value) =>
                          setState(() => _followersListVisible = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () {
                  ref.read(sessionProvider.notifier).reset();
                  context.go('/');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: FanColors.coral,
                ),
                child: const Text('退出登录并重置演示'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_favorites_repository.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<AlbumFavoriteFolder?> editAlbumFavoriteFolder(
  BuildContext context, {
  AlbumFavoriteFolder? folder,
}) => showDialog<AlbumFavoriteFolder>(
  context: context,
  builder: (_) => _FolderEditor(folder: folder),
);

class _FolderEditor extends ConsumerStatefulWidget {
  const _FolderEditor({this.folder});
  final AlbumFavoriteFolder? folder;
  @override
  ConsumerState<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends ConsumerState<_FolderEditor> {
  late final _name = TextEditingController(text: widget.folder?.name ?? '');
  late bool _public = widget.folder?.isPublic ?? false;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写分组名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final folder = await ref
          .read(albumFavoritesRepositoryProvider)
          .saveFolder(_name.text.trim(), _public, id: widget.folder?.id);
      if (mounted) Navigator.pop(context, folder);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.folder == null ? '新建收藏分组' : '编辑收藏分组'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            enabled: !_saving,
            decoration: InputDecoration(labelText: '分组名称', errorText: _error),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('公开分组'),
            subtitle: Text(_public ? '访客可见，原卡册仍须为公开状态' : '仅自己可见'),
            value: _public,
            onChanged: _saving ? null : (v) => setState(() => _public = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );
}

Future<bool> showAlbumFavoriteSheet(
  BuildContext context,
  String albumId, {
  bool move = false,
  String? initialGroupId,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FavoriteSheet(
        albumId: albumId,
        move: move,
        initialGroupId: initialGroupId,
      ),
    ) ??
    false;

class _FavoriteSheet extends ConsumerStatefulWidget {
  const _FavoriteSheet({
    required this.albumId,
    required this.move,
    this.initialGroupId,
  });
  final String albumId;
  final bool move;
  final String? initialGroupId;
  @override
  ConsumerState<_FavoriteSheet> createState() => _FavoriteSheetState();
}

class _FavoriteSheetState extends ConsumerState<_FavoriteSheet> {
  List<AlbumFavoriteFolder> _folders = [];
  late String? _selected = widget.initialGroupId;
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await ref
          .read(albumFavoritesRepositoryProvider)
          .folders();
      if (mounted) setState(() => _folders = folders);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final folder = await editAlbumFavoriteFolder(context);
    if (!mounted || folder == null) return;
    setState(() {
      _selected = folder.id;
    });
    await _load();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(albumFavoritesRepositoryProvider)
          .save(widget.albumId, _selected, move: widget.move);
      ref.invalidate(albumDetailProvider(widget.albumId));
      if (mounted) {
        showFanToast(context, widget.move ? '已更新收藏分组' : '已收藏卡册');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String? id, String name, bool public) => ListTile(
    leading: Icon(public ? Icons.public : Icons.lock_outline),
    title: Text(name),
    subtitle: Text(public ? '公开' : '仅自己可见'),
    trailing: Icon(
      _selected == id ? Icons.radio_button_checked : Icons.radio_button_off,
    ),
    onTap: _saving ? null : () => setState(() => _selected = id),
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.move ? '移动到分组' : '收藏到分组',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving || _loading ? null : _create,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建分组'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: Text(_error!)),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      _option(null, '未分组', false),
                      for (final f in _folders)
                        _option(f.id, f.name, f.isPublic),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading || _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

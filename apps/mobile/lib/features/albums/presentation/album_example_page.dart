import 'package:flutter/material.dart';

import '../data/album_models.dart';
import 'album_viewer_page.dart';

/// Entirely local, deterministic examples: no repository or user draft writes.
class AlbumExamplePage extends StatefulWidget {
  const AlbumExamplePage({super.key, required this.mode});
  final String mode;
  @override
  State<AlbumExamplePage> createState() => _AlbumExamplePageState();
}

class _AlbumExamplePageState extends State<AlbumExamplePage> {
  bool doublePage = false;
  PhotocardAlbum get example {
    final slots = [
      for (var i = 0; i < 3; i++)
        <String, dynamic>{'id': 'example-$i', 'card_id': 'sample-$i'},
    ];
    final json = <String, dynamic>{
      'id': 'isolated-example',
      'name': '示例效果',
      'is_example': true,
      'description': '仅用于体验，示例不会保存到你的作品。',
      'work_mode': widget.mode,
      'display_type': doublePage ? 'DOUBLE' : 'SINGLE',
      'visual_style': 'REALISTIC',
      'cover': albumCanvas(),
      'card_view': {'default_mode': widget.mode, 'cover_style': 'STACK_V1'},
      'card_instances': widget.mode == 'CARDS' ? slots : <AlbumJson>[],
      'pages': widget.mode == 'BOOK'
          ? [
              {
                'id': 'example-page-1',
                'grid_count': 1,
                'config': albumCanvas(),
                'slots': [slots[0]],
              },
              {
                'id': 'example-page-2',
                'grid_count': 4,
                'config': albumCanvas(),
                'slots': [
                  slots[1],
                  slots[2],
                  {'id': 'empty-1', 'card_id': null},
                  {'id': 'empty-2', 'card_id': null},
                ],
              },
            ]
          : <AlbumJson>[],
      'cards': {
        for (var i = 0; i < 3; i++)
          'sample-$i': {
            'id': 'sample-$i',
            'title': '示例小卡 ${i + 1}',
            'idol_name': '示例 ${i + 1}',
            'idol_id': 'sample-idol-$i',
            'group_id': 'sample-group',
            'group_name': '示例组合',
            'source': '示例来源',
            'card_type': '示例',
            'version': '预览',
            'release_date': '',
            'region': '',
            'image_url': 'sample://front/$i',
            'back_image_url': i == 2 ? null : 'sample://back/$i',
            'color_start': [0xFFE7DFD3, 0xFFDDE7DE, 0xFFE1E7EE][i],
            'color_end': 0xFF8C8996,
          },
      },
    };
    synchronizeAlbum(json);
    return PhotocardAlbum(json);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(
          child: AlbumViewer(
            key: ValueKey(doublePage),
            album: example,
            preview: true,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                if (widget.mode == 'BOOK') ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => doublePage = !doublePage),
                      child: Text(doublePage ? '切换单面' : '切换双面'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('使用此模式'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

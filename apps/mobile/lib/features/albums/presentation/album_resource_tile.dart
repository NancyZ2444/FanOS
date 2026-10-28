import 'package:flutter/material.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';

import '../data/album_models.dart';
import '../data/album_resources.dart';
import 'album_widgets.dart';

class AlbumResourceTile extends StatelessWidget {
  const AlbumResourceTile({
    super.key,
    required this.resource,
    required this.onSelected,
    this.selected = false,
    this.plan,
  });
  final AlbumJson resource;
  final VoidCallback onSelected;
  final bool selected;
  final String? plan;
  @override
  Widget build(BuildContext context) {
    final config = resource['config'] as AlbumJson;
    final available = albumResourceAvailable(resource, plan: plan);
    final pro = resource['membership'] == 'PRO';
    final name = resource['name'] as String? ?? '素材';
    return Semantics(
      label: '$name${pro ? '，PRO 专属' : ''}${available ? '' : '，已锁定'}',
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => available
            ? onSelected()
            : showFanToast(context, '此素材需要 PRO 权益，暂未开放在线购买'),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration:
                    albumDecoration(
                      resource['kind'] == 'STICKER'
                          ? albumBackground(['#F5F3FA'])
                          : config,
                      radius: 12,
                    ).copyWith(
                      border: Border.all(
                        color: selected ? FanColors.lavender : FanColors.line,
                        width: selected ? 2 : 1,
                      ),
                    ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (resource['kind'] == 'STICKER')
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: config['image_url'] is String
                            ? FanImage(
                                imageUrl: config['image_url'] as String,
                                fit: BoxFit.contain,
                                fallback: const Icon(
                                  Icons.broken_image_outlined,
                                ),
                              )
                            : Center(
                                child: Text(
                                  config['symbol'] as String? ?? '◇',
                                  style: const TextStyle(fontSize: 27),
                                ),
                              ),
                      ),
                    if (resource['kind'] == 'SHELF')
                      const Center(
                        child: Icon(Icons.menu_book_outlined, size: 32),
                      ),
                    if (pro)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!available)
                                const Icon(Icons.lock_outline, size: 11),
                              const Text(
                                'PRO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

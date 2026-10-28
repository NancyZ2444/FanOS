import 'package:flutter/material.dart';
import 'package:fan_os/app/theme.dart';

import '../data/album_models.dart';

class AlbumModerationBanner extends StatelessWidget {
  const AlbumModerationBanner({
    super.key,
    required this.album,
    this.onRequestReview,
    this.busy = false,
  });
  final PhotocardAlbum album;
  final VoidCallback? onRequestReview;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    if (!album.isOwner ||
        (!album.isModerated && album.reviewStatus != 'RESTORED')) {
      return const SizedBox.shrink();
    }
    final pending = album.reviewStatus == 'PENDING';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FanColors.lavender.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            album.isModerated
                ? '${album.moderationLabel}${pending
                      ? ' · 复核中'
                      : album.reviewStatus == 'REJECTED'
                      ? ' · 复核未通过'
                      : ''}'
                : '运营限制已解除',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            album.isModerated
                ? '${album.moderationReason.isEmpty ? '' : '${album.moderationReason}。'}作品暂不公开，可继续修改并保存。${pending ? '已提交的版本正在复核，保存不会自动恢复公开。' : '修改后可申请复核；恢复后需主动发布。'}'
                : '修改内容尚未自动发布，请确认内容后主动完成发布。',
            style: const TextStyle(
              fontSize: 12,
              color: FanColors.textSecondary,
            ),
          ),
          if (album.isModerated && onRequestReview != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy || pending ? null : onRequestReview,
              child: Text(
                pending
                    ? '等待复核'
                    : busy
                    ? '提交中…'
                    : '保存并申请复核',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

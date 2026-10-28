import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';

import '../data/album_models.dart';
import '../state/album_state.dart';
import 'album_card_picker.dart';
import 'album_widgets.dart';

String newAlbumColorRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Future<List<String>?> showAlbumColorExtraction(
  BuildContext context, {
  required AlbumQuota quota,
  required ValueChanged<AlbumQuota> onQuotaChanged,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  useSafeArea: true,
  builder: (_) =>
      AlbumColorExtractionSheet(quota: quota, onQuotaChanged: onQuotaChanged),
);

class AlbumColorExtractionSheet extends ConsumerStatefulWidget {
  const AlbumColorExtractionSheet({
    super.key,
    required this.quota,
    required this.onQuotaChanged,
  });
  final AlbumQuota quota;
  final ValueChanged<AlbumQuota> onQuotaChanged;
  @override
  ConsumerState<AlbumColorExtractionSheet> createState() =>
      _AlbumColorExtractionSheetState();
}

class _AlbumColorExtractionSheetState
    extends ConsumerState<AlbumColorExtractionSheet> {
  late AlbumQuota _quota = widget.quota;
  String? _cardId, _filename, _requestId, _error;
  Uint8List? _bytes;
  List<String> _colors = [];
  bool _busy = false;

  Future<void> _choose(bool photo) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? cardId;
      Uint8List? bytes;
      String? filename;
      if (photo) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (file == null) return;
        bytes = await file.readAsBytes();
        filename = file.name;
      } else {
        final cards = await pickAlbumCards(
          context,
          single: true,
          title: '选择取色小卡',
          confirmLabel: '用于取色',
        );
        if (cards == null || cards.isEmpty) return;
        cardId = cards.first.id;
        filename = cards.first.displayTitle;
      }
      if (!mounted) return;
      setState(() {
        _cardId = cardId;
        _bytes = bytes;
        _filename = filename;
        _requestId = newAlbumColorRequestId();
        _colors = [];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '无法读取图片，请重试：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    if (_busy || _requestId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Preserve this ID after network errors: retries cannot charge twice.
      final result = await ref
          .read(albumRepositoryProvider)
          .extractColors(
            requestId: _requestId!,
            cardId: _cardId,
            bytes: _bytes,
            fileName: _filename,
          );
      if (!mounted) return;
      setState(() {
        _colors = result.colors;
        _quota = result.quota;
      });
      widget.onQuotaChanged(result.quota);
      ref.invalidate(albumQuotaProvider);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException ? e.message : '暂时无法分析图片，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = _quota.colorExtraction;
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '从图片取色',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭取色',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        usage == null
                            ? '当前服务暂不支持图片取色'
                            : '今日剩余 ${usage.dailyRemaining}/${usage.dailyLimit} 次 · 本月剩余 ${usage.monthlyRemaining}/${usage.monthlyLimit} 次',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '按北京时间每日、每月重置。成功分析计 1 次；取消、失败及调整已有颜色不计次。照片仅用于分析颜色。',
                        style: TextStyle(
                          fontSize: 12,
                          color: FanColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (usage?.exhausted == true && _colors.isEmpty) ...[
                        Text(
                          _quota.plan == 'PRO'
                              ? '当前取色额度已用完，请等待额度重置。'
                              : '当前取色额度已用完。PRO 提供更多额度，暂未开放在线购买。',
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _busy || usage == null || usage.exhausted
                                  ? null
                                  : () => _choose(false),
                              icon: const Icon(Icons.style_outlined),
                              label: const Text('选择小卡'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _busy || usage == null || usage.exhausted
                                  ? null
                                  : () => _choose(true),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('本机照片'),
                            ),
                          ),
                        ],
                      ),
                      if (_requestId != null) ...[
                        const SizedBox(height: 16),
                        if (_bytes != null)
                          SizedBox(
                            height: 120,
                            child: Image.memory(_bytes!, fit: BoxFit.contain),
                          ),
                        Text(
                          _filename ?? '已选择图片',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        if (_colors.isEmpty)
                          FilledButton.icon(
                            onPressed: _busy ? null : _extract,
                            icon: _busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.colorize_outlined),
                            label: Text(
                              _busy
                                  ? '分析中…'
                                  : _error == null
                                  ? '开始分析（消耗 1 次）'
                                  : '重试本次分析',
                            ),
                          ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: FanColors.coral),
                          ),
                        ),
                      if (_colors.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('取色完成，选择颜色应用到背景'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final color in _colors)
                              Semantics(
                                label: '使用颜色 $color',
                                button: true,
                                child: InkWell(
                                  onTap: () => Navigator.pop(context, [color]),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: albumColor(color),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        color,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_colors.length > 1)
                          TextButton(
                            onPressed: () => Navigator.pop(
                              context,
                              _colors.take(2).toList(),
                            ),
                            child: const Text('使用前两色渐变'),
                          ),
                        const Text(
                          '分析结果已保留；此处选择和调整不再计次。',
                          style: TextStyle(
                            fontSize: 12,
                            color: FanColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

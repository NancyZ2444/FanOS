import 'dart:io';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/features/scan/presentation/scan_image.dart';
import 'package:flutter/material.dart';

/// The preview is contain-fitted so normalized detection boxes stay on the photo.
class ScanSelection extends StatefulWidget {
  const ScanSelection({
    required this.detection,
    required this.onScan,
    required this.onRetake,
    required this.imageSize,
    this.localImagePath,
    this.busy = false,
    this.error,
    super.key,
  });
  final ScanDetection detection;
  final Size imageSize;
  final String? localImagePath;
  final bool busy;
  final String? error;
  final Future<void> Function(Set<String>) onScan;
  final VoidCallback onRetake;
  @override
  State<ScanSelection> createState() => _ScanSelectionState();
}

class _ScanSelectionState extends State<ScanSelection> {
  late Set<String> selected = widget.detection.regions.map((r) => r.id).toSet();
  void toggle(String id) {
    if (widget.busy) return;
    setState(() {
      if (!selected.remove(id)) selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final regions = widget.detection.regions;
    final local = widget.localImagePath;
    final fallback = local == null
        ? const ColoredBox(color: Color(0xFF333244))
        : Image.file(
            File(local),
            fit: BoxFit.fill,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF333244)),
          );
    final remote = widget.detection.imagePath;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: AspectRatio(
                aspectRatio:
                    widget.detection.aspectRatio ??
                    widget.imageSize.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, size) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (remote != null && remote.startsWith('http'))
                        Image.network(
                          remote,
                          fit: BoxFit.fill,
                          errorBuilder: (_, _, _) => fallback,
                        )
                      else
                        fallback,
                      for (var i = 0; i < regions.length; i++)
                        Positioned(
                          left: regions[i].cropRegion.x * size.maxWidth,
                          top: regions[i].cropRegion.y * size.maxHeight,
                          width: regions[i].cropRegion.width * size.maxWidth,
                          height: regions[i].cropRegion.height * size.maxHeight,
                          child: Semantics(
                            button: true,
                            selected: selected.contains(regions[i].id),
                            label: '小卡 ${i + 1}',
                            child: GestureDetector(
                              key: Key('detect-region-${regions[i].id}'),
                              onTap: widget.busy
                                  ? null
                                  : () => toggle(regions[i].id),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: selected.contains(regions[i].id)
                                      ? FanColors.lavender.withValues(
                                          alpha: .16,
                                        )
                                      : Colors.black38,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selected.contains(regions[i].id)
                                        ? Colors.white
                                        : Colors.white38,
                                    width: 2,
                                  ),
                                ),
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    selected.contains(regions[i].id)
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: selected.contains(regions[i].id)
                                        ? FanColors.lavender
                                        : Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          decoration: const BoxDecoration(
            color: FanColors.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已选择 ${selected.length} / ${regions.length} 张',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      key: const Key('detect-select-all'),
                      onPressed: widget.busy || regions.isEmpty
                          ? null
                          : () => setState(() {
                              selected = selected.length == regions.length
                                  ? {}
                                  : regions.map((r) => r.id).toSet();
                            }),
                      child: Text(
                        selected.length == regions.length ? '取消全选' : '全选',
                      ),
                    ),
                  ],
                ),
                if (regions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '未检测到清晰的人物小卡\n请拍摄有人物的正面，避免反光、遮挡并完整放入画面。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FanColors.textSecondary),
                    ),
                  )
                else ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '点选框或缩略图调整，扫描后再确认图鉴结果。',
                      style: TextStyle(
                        fontSize: 12,
                        color: FanColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: regions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => Semantics(
                        selected: selected.contains(regions[i].id),
                        button: true,
                        label: '选择小卡 ${i + 1}',
                        child: InkWell(
                          key: Key('detect-thumb-${regions[i].id}'),
                          onTap: widget.busy
                              ? null
                              : () => toggle(regions[i].id),
                          child: Container(
                            width: 52,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                width: 2,
                                color: selected.contains(regions[i].id)
                                    ? FanColors.lavender
                                    : FanColors.line,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ScanImage(
                                  path: regions[i].cropImagePath,
                                  fallback: Center(child: Text('${i + 1}')),
                                ),
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Icon(
                                    selected.contains(regions[i].id)
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 18,
                                    color: FanColors.lavender,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.error!,
                      style: const TextStyle(
                        color: Color(0xFFB54708),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Flexible(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: widget.busy ? null : widget.onRetake,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('重拍', maxLines: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: FilledButton(
                        key: const Key('detect-start-scan'),
                        onPressed: selected.isEmpty || widget.busy
                            ? null
                            : () => widget.onScan(Set.of(selected)),
                        child: Text(
                          widget.busy ? '正在识别…' : '扫描（${selected.length}）',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

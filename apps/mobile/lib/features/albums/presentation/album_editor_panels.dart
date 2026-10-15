import 'package:flutter/material.dart';
import 'package:fan_os/app/theme.dart';

import '../data/album_models.dart';
import 'album_widgets.dart';

const albumPigments = [
  '#E8EBE3',
  '#E5EAF0',
  '#EFE2E0',
  '#F3EDE0',
  '#E8E3F2',
  '#FFFFFF',
];

/// Inline panels share the editor's available height with the live canvas.
/// The header never scrolls; the body can shrink above the system keyboard.
class AlbumToolPanel extends StatelessWidget {
  const AlbumToolPanel({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onDone,
    required this.child,
  });
  final String title;
  final VoidCallback onCancel, onDone;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: '取消',
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 22),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(onPressed: onDone, child: const Text('完成')),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class AlbumTextPanel extends StatefulWidget {
  const AlbumTextPanel({super.key, this.element, required this.onClose});
  final AlbumJson? element;
  final ValueChanged<AlbumJson?> onClose;
  @override
  State<AlbumTextPanel> createState() => _AlbumTextPanelState();
}

class _AlbumTextPanelState extends State<AlbumTextPanel> {
  late final input = TextEditingController(
    text: widget.element?['content'] ?? '',
  );
  late final style = cloneAlbumJson(
    widget.element?['style'] ??
        {
          'color': '#342A56',
          'font_size': 24.0,
          'font_family': 'system',
          'bold': false,
        },
  );
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlbumToolPanel(
    title: '文字',
    onCancel: () => widget.onClose(null),
    onDone: () =>
        widget.onClose({'content': input.text.trim(), 'style': style}),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: input,
          minLines: 1,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(hintText: '写下收藏故事'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: style['font_family'],
                decoration: const InputDecoration(labelText: '字体'),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('系统字体')),
                  DropdownMenuItem(value: 'serif', child: Text('衬线字体')),
                  DropdownMenuItem(value: 'monospace', child: Text('等宽字体')),
                ],
                onChanged: (v) => setState(() => style['font_family'] = v),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: '加粗',
              isSelected: style['bold'] == true,
              onPressed: () =>
                  setState(() => style['bold'] = style['bold'] != true),
              icon: const Icon(Icons.format_bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in [
              '#151C32',
              '#6D5DD3',
              '#68738B',
              '#AD7782',
              '#698776',
              '#FFFFFF',
            ])
              _Swatch(
                color: color,
                selected: style['color'] == color,
                onTap: () => setState(() => style['color'] = color),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '在画布上双指缩放文字大小',
          style: TextStyle(fontSize: 14, color: FanColors.textSecondary),
        ),
      ],
    ),
  );
}

class AlbumBackgroundPanel extends StatefulWidget {
  const AlbumBackgroundPanel({
    super.key,
    required this.original,
    required this.onClose,
    this.onPreview,
  });
  final AlbumJson original;
  final ValueChanged<AlbumJson?> onClose;
  final ValueChanged<AlbumJson>? onPreview;
  @override
  State<AlbumBackgroundPanel> createState() => _AlbumBackgroundPanelState();
}

class _AlbumBackgroundPanelState extends State<AlbumBackgroundPanel> {
  late final bg = cloneAlbumJson(widget.original);
  late final first = TextEditingController(text: (bg['colors'] as List).first);
  late final second = TextEditingController(text: (bg['colors'] as List).last);
  String? error;
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  void update(List<String> colors) => setState(() {
    bg['colors'] = colors;
    first.text = colors.first;
    second.text = colors.last;
    error = null;
    widget.onPreview?.call(cloneAlbumJson(bg));
  });
  @override
  Widget build(BuildContext context) => AlbumToolPanel(
    title: '背景设置',
    onCancel: () => widget.onClose(null),
    onDone: () {
      final valid = RegExp(r'^#[0-9a-fA-F]{6}$');
      if (!valid.hasMatch(first.text) ||
          (bg['type'] == 'GRADIENT' && !valid.hasMatch(second.text))) {
        setState(() => error = '请输入 #RRGGBB 格式的颜色');
        return;
      }
      bg['colors'] = [first.text, if (bg['type'] == 'GRADIENT') second.text];
      widget.onClose(bg);
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'SOLID', label: Text('纯色')),
            ButtonSegment(value: 'GRADIENT', label: Text('渐变')),
          ],
          selected: {bg['type']},
          onSelectionChanged: (v) {
            setState(() => bg['type'] = v.first);
            update(
              v.first == 'SOLID' ? [first.text] : [first.text, second.text],
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          '常用推荐',
          style: TextStyle(fontSize: 14, color: FanColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (bg['type'] == 'SOLID')
              for (final color in albumPigments)
                _Swatch(
                  color: color,
                  selected: first.text == color,
                  onTap: () => update([color]),
                ),
            if (bg['type'] == 'GRADIENT')
              for (final colors in [
                ['#E8E3F2', '#EFE2E0'],
                ['#E5EAF0', '#E8EBE3'],
                ['#F3EDE0', '#EFE2E0'],
              ])
                InkWell(
                  onTap: () => update(colors),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    height: 48,
                    decoration: albumDecoration({
                      'type': 'GRADIENT',
                      'colors': colors,
                      'angle': 45,
                    }),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          '自定义颜色',
          style: TextStyle(fontSize: 14, color: FanColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: first,
                decoration: const InputDecoration(labelText: '起点 · HEX'),
              ),
            ),
            if (bg['type'] == 'GRADIENT') ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: second,
                  decoration: const InputDecoration(labelText: '终点 · HEX'),
                ),
              ),
            ],
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: const TextStyle(color: FanColors.coral)),
          ),
        if (bg['type'] == 'GRADIENT') ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('方向'),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 360,
                  divisions: 72,
                  value: (bg['angle'] as num).toDouble(),
                  onChanged: (v) => setState(() {
                    bg['angle'] = v;
                    widget.onPreview?.call(cloneAlbumJson(bg));
                  }),
                ),
              ),
              Text('${(bg['angle'] as num).round()}°'),
            ],
          ),
        ],
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: color,
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: albumColor(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? FanColors.lavender : FanColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 20, color: FanColors.ink)
            : null,
      ),
    ),
  );
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fan_os/features/profile/presentation/profile_backdrop.dart';

/// One continuous backdrop, measured from real content (including large text).
/// The toolbar stays available after the identity area scrolls away.
class EntityProfileSliver extends StatefulWidget {
  const EntityProfileSliver({
    super.key,
    required this.hero,
    required this.actions,
    this.imageUrl,
  });
  final Widget hero;
  final List<Widget> actions;
  final String? imageUrl;
  @override
  State<EntityProfileSliver> createState() => _EntityProfileSliverState();
}

class _EntityProfileSliverState extends State<EntityProfileSliver> {
  double _height = 220;
  @override
  Widget build(BuildContext context) => SliverAppBar(
    pinned: true,
    expandedHeight: kToolbarHeight + _height,
    foregroundColor: FanColors.ink,
    backgroundColor: FanColors.canvas,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    actions: widget.actions,
    flexibleSpace: LayoutBuilder(
      builder: (context, bounds) {
        final safeTop = MediaQuery.paddingOf(context).top;
        final collapsed = bounds.maxHeight <= safeTop + kToolbarHeight + 1;
        return ClipRect(
          child: Stack(
            children: [
              if (!collapsed)
                Positioned.fill(
                  child: ProfileBackdrop(imageUrl: widget.imageUrl ?? ''),
                ),
              if (collapsed)
                const Positioned.fill(
                  child: ColoredBox(color: FanColors.canvas),
                ),
              Positioned(
                top: safeTop + kToolbarHeight,
                left: 0,
                right: 0,
                child: _MeasureIdentity(
                  onHeight: (height) {
                    if (mounted && (_height - height).abs() > .5) {
                      setState(() => _height = height);
                    }
                  },
                  child: widget.hero,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _MeasureIdentity extends SingleChildRenderObjectWidget {
  const _MeasureIdentity({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _IdentitySize(onHeight);
  @override
  void updateRenderObject(BuildContext context, _IdentitySize renderObject) =>
      renderObject.onHeight = onHeight;
}

class _IdentitySize extends RenderProxyBox {
  _IdentitySize(this.onHeight);
  ValueChanged<double> onHeight;
  double? previous;
  @override
  void performLayout() {
    super.performLayout();
    if (previous != size.height) {
      previous = size.height;
      final height = size.height;
      WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
    }
  }
}

/// Keep names out of the collapsing cover so controls never squeeze a name.
class EntityCover extends StatelessWidget {
  const EntityCover({this.imageUrl, this.fallbackImageUrl, super.key});
  final String? imageUrl, fallbackImageUrl;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: FanColors.lavenderSoft),
      FanImage(
        imageUrl: imageUrl,
        fallbackImageUrl: fallbackImageUrl,
        fallback: const SizedBox.shrink(),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66000000), Color(0x11000000)],
          ),
        ),
      ),
    ],
  );
}

class EntityIdentity extends StatelessWidget {
  const EntityIdentity({
    required this.name,
    required this.avatar,
    this.subtitle = '',
    this.details = const [],
    this.description = '',
    this.actions = const [],
    this.contribution,
    super.key,
  });
  final String name, subtitle, description;
  final Widget avatar;
  final List<String> details;
  final List<Widget> actions;
  final Widget? contribution;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Long uninterrupted stage names remain whole and horizontally readable.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      name,
                      softWrap: false,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: FanColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (details.any((s) => s.trim().isNotEmpty)) ...[
          const SizedBox(height: 12),
          Text(
            details.where((s) => s.trim().isNotEmpty).join(' · '),
            style: const TextStyle(
              fontSize: 12,
              color: FanColors.textSecondary,
            ),
          ),
        ],
        if (description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _ExpandableDescription(text: description),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
        ?contribution,
      ],
    ),
  );
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});
  final String text;
  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const style = TextStyle(
        fontSize: 14,
        height: 1.45,
        color: FanColors.textSecondary,
      );
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout(maxWidth: box.maxWidth);
      final truncated = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            style: style,
            maxLines: expanded ? null : 2,
            overflow: expanded ? null : TextOverflow.ellipsis,
          ),
          if (truncated)
            TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? '收起' : '展开'),
            ),
        ],
      );
    },
  );
}

class EntityTabs extends SliverPersistentHeaderDelegate {
  EntityTabs(this.labels, {required this.textScale});
  final List<String> labels;
  final double textScale;
  @override
  double get minExtent => 48 + (textScale - 1).clamp(0, 2) * 20;
  @override
  double get maxExtent => minExtent;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: FanColors.canvas,
    child: TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: FanColors.lavender,
      labelColor: FanColors.ink,
      unselectedLabelColor: FanColors.textSecondary,
      tabs: labels.map((label) => Tab(height: minExtent, text: label)).toList(),
    ),
  );
  @override
  bool shouldRebuild(covariant EntityTabs oldDelegate) =>
      oldDelegate.textScale != textScale || oldDelegate.labels != labels;
}

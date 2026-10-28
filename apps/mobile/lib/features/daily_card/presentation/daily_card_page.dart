import 'dart:math' as math;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/card_geometry.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DailyCardPage extends ConsumerWidget {
  const DailyCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyCardProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('每日翻卡'),
        actions: [
          IconButton(
            tooltip: '重置演示',
            onPressed: () => ref.read(dailyCardProvider.notifier).resetDemo(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FanContent(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: FanColors.lavenderSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: FanColors.lavender,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        state.remaining == 0
                            ? '今日 3 张已全部揭晓，明天再来'
                            : '今日剩余 ${state.remaining} 次 · 至少 1 张本命相关',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                state.remaining == 0 ? '今日的相遇' : '选择一张，揭晓此刻的缘分',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(3, (index) {
                  final revealed = index < state.drawnCards.length;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: revealed
                          ? _FlipRevealCard(
                              key: ValueKey(state.drawnCards[index].id),
                              card: state.drawnCards[index],
                            )
                          : _CardBack(
                              enabled:
                                  index == state.drawnCards.length &&
                                  !state.isDrawing,
                              loading:
                                  index == state.drawnCards.length &&
                                  state.isDrawing,
                              onTap: () =>
                                  ref.read(dailyCardProvider.notifier).draw(),
                            ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              if (state.errorMessage != null)
                Text(
                  state.errorMessage!,
                  style: const TextStyle(color: FanColors.coral),
                ),
              if (state.drawnCards.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  state.drawnCards.last.displayTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "${entityDisplayName(ref, 'groups', state.drawnCards.last.groupId, state.drawnCards.last.groupName)} · ${state.drawnCards.last.source}",
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (state.drawnCards.isNotEmpty)
                FilledButton(
                  onPressed: () =>
                      context.push('/card/${state.drawnCards.last.id}'),
                  child: const Text('查看最新卡片详情'),
                ),
              if (state.drawnCards.isEmpty)
                OutlinedButton.icon(
                  onPressed: state.isDrawing
                      ? null
                      : () => ref.read(dailyCardProvider.notifier).draw(),
                  icon: const Icon(Icons.style_rounded),
                  label: const Text('翻开第一张'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: photocardAspectRatio,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled || loading ? 1 : .42,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/cards/default-card-back.png',
                  fit: BoxFit.cover,
                  semanticLabel: 'Fan OS 默认卡背',
                ),
                if (loading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
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

class _FlipRevealCard extends StatefulWidget {
  const _FlipRevealCard({required this.card, super.key});
  final CollectibleCard card;

  @override
  State<_FlipRevealCard> createState() => _FlipRevealCardState();
}

class _FlipRevealCardState extends State<_FlipRevealCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
      builder: (context, child) {
        final value = _controller.value;
        final showFront = value >= .5;
        final angle = showFront ? math.pi * (1 - value) : math.pi * value;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateY(angle),
          child: showFront
              ? FanArtwork(
                  aspectRatio: photocardAspectRatio,
                  imageUrl: widget.card.imageUrl,
                  startColor: Color(widget.card.colorStart),
                  endColor: Color(widget.card.colorEnd),
                  label: widget.card.idolName.characters.take(2).toString(),
                )
              : _CardBack(enabled: false, loading: false, onTap: () {}),
        );
      },
    );
  }
}

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LaunchPage extends ConsumerWidget {
  const LaunchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1220),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _LaunchBackdrop(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .12),
                  const Color(0xFF0D1220).withValues(alpha: .45),
                  const Color(0xFF0D1220).withValues(alpha: .98),
                ],
              ),
            ),
          ),
          SafeArea(
            child: FanContent(
              padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
              child: Column(
                children: [
                  const Spacer(flex: 4),
                  const FanWordmark(light: true, fontSize: 45),
                  const SizedBox(height: 18),
                  Text(
                    'For Every Fan,\nA Bigger World',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .94),
                      fontSize: 25,
                      height: 1.25,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w400,
                      letterSpacing: .2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '收藏热爱 · 记录陪伴 · 遇见同好',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(flex: 3),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: FanColors.ink,
                    ),
                    onPressed: () => context.push('/privacy'),
                    child: const Text('开启旅程'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      ref.read(sessionProvider.notifier).continueAsGuest();
                      context.go('/home');
                    },
                    child: Text(
                      '游客体验',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                      ),
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
}

class _LaunchBackdrop extends StatelessWidget {
  const _LaunchBackdrop();

  @override
  Widget build(BuildContext context) {
    const colors = [
      [Color(0xFF5D4A82), Color(0xFF1D2440)],
      [Color(0xFF356A72), Color(0xFF172A35)],
      [Color(0xFF8A4D62), Color(0xFF302034)],
      [Color(0xFF876947), Color(0xFF27283B)],
      [Color(0xFF414D91), Color(0xFF1D203C)],
      [Color(0xFF577364), Color(0xFF1A3030)],
    ];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Transform.rotate(
        angle: -.06,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: .68,
          ),
          itemCount: colors.length,
          itemBuilder: (context, index) => FanArtwork(
            startColor: colors[index][0],
            endColor: colors[index][1],
            label: const ['AR', 'LN', 'MI', 'RN', 'YU', 'SO'][index],
            borderRadius: 14,
          ),
        ),
      ),
    );
  }
}

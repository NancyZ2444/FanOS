import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LaunchPage extends ConsumerStatefulWidget {
  const LaunchPage({super.key});
  @override
  ConsumerState<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends ConsumerState<LaunchPage> {
  bool _restoring = true;
  bool _restoreFailed = false;
  bool _enteringGuest = false;
  String? _errorMessage;
  String _retryLabel = '重试';
  @override
  void initState() {
    super.initState();
    Future.microtask(_restore);
  }

  Future<void> _restore() async {
    if (!mounted) return;
    setState(() {
      _restoring = true;
      _restoreFailed = false;
      _errorMessage = null;
    });
    try {
      final restored = await ref.read(sessionProvider.notifier).restore();
      if (restored && mounted) {
        context.go(
          ref.read(sessionProvider).passwordSetupRequired
              ? '/onboarding/password'
              : ref.read(sessionProvider).onboardingCompleted
              ? '/home'
              : '/onboarding/favorites?welcome=1',
        );
      }
    } catch (error) {
      if (mounted && error is ApiException && error.code == 'ACCOUNT_BANNED') {
        context.go('/account-banned', extra: error);
        return;
      }
      if (mounted) {
        setState(() {
          _restoreFailed = true;
          _errorMessage = _messageFor(error);
          _retryLabel = error is ApiException && error.code == 'NETWORK_ERROR'
              ? '重新连接'
              : '重试';
        });
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  String _messageFor(Object error, {bool guest = false}) {
    if (error is PlatformException) {
      if (error.code == '-34018' ||
          (error.message?.toLowerCase().contains('entitlement') ?? false)) {
        return '当前安装包无法访问安全登录存储，请更新 App 后重试。';
      }
      return '暂时无法访问安全登录存储，请解锁设备后重试。';
    }
    if (error is ApiException) {
      final message = error.message.replaceFirst(RegExp(r'[。.!！]+$'), '');
      return guest ? '$message。' : '$message。登录凭证已保留。';
    }
    return guest ? '暂时无法进入游客模式，请稍后重试。' : '暂时无法恢复登录，请稍后重试。';
  }

  Future<void> _continueAsGuest() async {
    if (_restoring || _enteringGuest) return;
    setState(() {
      _enteringGuest = true;
      _errorMessage = null;
    });
    try {
      await ref.read(sessionProvider.notifier).continueAsGuest();
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _messageFor(error, guest: true));
      }
    } finally {
      if (mounted) setState(() => _enteringGuest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0D1220),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
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
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: FanColors.ink,
                      ),
                      onPressed: _restoring || _enteringGuest
                          ? null
                          : _restoreFailed
                          ? _restore
                          : () => context.push('/login?from=/home'),
                      child: Text(
                        _restoring
                            ? '正在恢复登录…'
                            : _restoreFailed
                            ? _retryLabel
                            : '开启旅程',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _restoring || _enteringGuest
                          ? null
                          : _continueAsGuest,
                      child: Text(
                        _enteringGuest ? '正在进入…' : '游客体验',
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

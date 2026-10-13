import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneController = TextEditingController(text: '13800000000');
  final _codeController = TextEditingController(text: '123456');
  bool _codeSent = false;
  bool _busy = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _sendCode() {
    if (_phoneController.text.length < 8) {
      showFanToast(context, '请输入正确的手机号');
      return;
    }
    setState(() {
      _codeSent = true;
      _countdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
    showFanToast(context, '演示验证码已填写：123456');
  }

  Future<void> _login(LoginMethod method) async {
    if (_busy) return;
    if (method == LoginMethod.phone && !_codeSent) {
      _sendCode();
      return;
    }
    if (method == LoginMethod.phone && _codeController.text.length != 6) {
      showFanToast(context, '请输入 6 位验证码');
      return;
    }
    setState(() => _busy = true);
    await ref
        .read(sessionProvider.notifier)
        .login(
          method,
          phone: _phoneController.text,
          code: _codeController.text,
        );
    if (!mounted) return;
    context.go('/onboarding/favorites');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: SingleChildScrollView(
          child: FanContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 22),
                Text(
                  '登录 / 注册 Fan OS',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '开启你的收藏与本命世界',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: FanColors.textSecondary),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    prefixText: '+86  ',
                    hintText: '请输入手机号',
                  ),
                ),
                const SizedBox(height: 12),
                if (_codeSent) ...[
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '请输入验证码',
                      suffixIcon: TextButton(
                        onPressed: _countdown == 0 ? _sendCode : null,
                        child: Text(
                          _countdown == 0 ? '重新发送' : '${_countdown}s',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _busy ? null : () => _login(LoginMethod.phone),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_codeSent ? '登录并继续' : '获取验证码'),
                ),
                const SizedBox(height: 28),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '其他登录方式',
                        style: TextStyle(
                          color: FanColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SocialLoginButton(
                      color: const Color(0xFF19B955),
                      label: '微信',
                      icon: Icons.chat_bubble_rounded,
                      onTap: () => _login(LoginMethod.wechat),
                    ),
                    const SizedBox(width: 30),
                    _SocialLoginButton(
                      color: const Color(0xFFFF7759),
                      label: '微博',
                      icon: Icons.rss_feed_rounded,
                      onTap: () => _login(LoginMethod.weibo),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                OutlinedButton(
                  onPressed: () {
                    ref.read(sessionProvider.notifier).continueAsGuest();
                    context.go('/home');
                  },
                  child: const Text('游客体验'),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '继续即表示你同意用户协议与隐私政策',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.color,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

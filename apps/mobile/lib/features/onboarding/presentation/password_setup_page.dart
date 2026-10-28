import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Only accounts explicitly marked by the API are required to complete this
/// step. Existing users are never forced into password registration.
class PasswordSetupPage extends ConsumerStatefulWidget {
  const PasswordSetupPage({super.key, this.returnTo});
  final String? returnTo;
  @override
  ConsumerState<PasswordSetupPage> createState() => _PasswordSetupPageState();
}

class _PasswordSetupPageState extends ConsumerState<PasswordSetupPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _requestId = authRequestId();
  bool _busy = false;
  bool _obscure = true;
  bool _needsReauthentication = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _needsReauthentication) return;
    final error =
        registrationPasswordError(_password.text) ??
        (_password.text != _confirm.text ? '两次输入的密码不一致' : null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .postData(
            '/account/password',
            idempotencyKey: _requestId,
            data: {'password': _password.text},
          );
      ref.read(sessionProvider.notifier).passwordRegistrationCompleted();
      if (!mounted) return;
      context.go(
        '/onboarding/favorites?welcome=1&from=${Uri.encodeComponent(safeLoginReturn(widget.returnTo))}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _needsReauthentication =
            e is ApiException &&
            {
              'REAUTHENTICATION_REQUIRED',
              'RECENT_AUTH_REQUIRED',
              'AUTH_REQUIRED',
              'INVALID_TOKEN',
            }.contains(e.code);
        _error = _needsReauthentication
            ? '为保护账号安全，请重新使用短信验证码登录后设置密码。'
            : e is ApiException
            ? e.message
            : '密码未保存，请检查网络后重试';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: FanColors.canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('设置登录密码'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '欢迎加入 Fan OS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '先设置密码，再选择你的本命。以后可使用验证码或密码登录。',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: FanColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            AutofillGroup(
              child: Column(
                children: [
                  TextField(
                    key: const Key('setup-password'),
                    controller: _password,
                    enabled: !_busy && !_needsReauthentication,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => _requestId = authRequestId(),
                    decoration: InputDecoration(
                      labelText: '登录密码',
                      helperText: '8–64 位，至少包含字母和数字，不含空格',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('setup-password-confirm'),
                    controller: _confirm,
                    enabled: !_busy && !_needsReauthentication,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: '确认密码'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('setup-password-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: FanColors.lavender,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy
                  ? null
                  : _needsReauthentication
                  ? () => context.go(
                      '/login?phone=1&from=${Uri.encodeComponent(safeLoginReturn(widget.returnTo))}',
                    )
                  : _save,
              child: Text(
                _busy
                    ? '正在保存…'
                    : _needsReauthentication
                    ? '重新短信登录'
                    : '保存并选择本命',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

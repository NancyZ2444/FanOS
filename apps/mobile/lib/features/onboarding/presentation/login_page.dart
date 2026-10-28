import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/onboarding/presentation/auth_help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.returnTo, this.showPhoneForm = false});
  final String? returnTo;
  final bool showPhoneForm;
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _platform = PlatformAuthorization();
  SmsChallenge? _challenge;
  String? _error;
  String? _notice;
  String? _continuation;
  String _requestId = authRequestId();
  String _sendRequestId = authRequestId();
  bool _consent = false;
  bool _sending = false;
  bool _loggingIn = false;
  bool _phoneMode = false;
  bool _passwordMode = false;
  bool _obscurePassword = true;
  final Map<String, bool> _platforms = {};
  Timer? _timer;
  bool get _busy => _sending || _loggingIn;
  @override
  void initState() {
    super.initState();
    _phoneMode = widget.showPhoneForm;
    _phone.addListener(_phoneChanged);
    _checkPlatforms();
  }

  Future<void> _checkPlatforms() async {
    try {
      final capabilities =
          await ref
                  .read(apiClientProvider)
                  .getData('/auth/capabilities', authenticated: false)
              as Map;
      for (final provider in authProviders) {
        final available =
            capabilities['${provider}_available'] == true &&
            await _platform.available(provider);
        if (mounted) setState(() => _platforms[provider] = available);
      }
    } catch (_) {
      // No server capability or SDK means no provider authorization. Phone
      // login remains usable; never synthesize third-party credentials.
    }
  }

  void _phoneChanged() {
    _timer?.cancel();
    setState(() {
      _challenge = null;
      _error = null;
      _notice = null;
      _code.clear();
      _requestId = authRequestId();
      _sendRequestId = authRequestId();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.removeListener(_phoneChanged);
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate({bool code = false}) {
    if (!_consent) {
      setState(() => _error = '请先阅读并同意用户协议与隐私政策');
      return false;
    }
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text)) {
      setState(() => _error = '请输入正确的 11 位大陆手机号');
      return false;
    }
    if (code && !RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = '请输入 6 位验证码');
      return false;
    }
    return true;
  }

  void _failure(Object e) {
    if (!mounted) return;
    if (e is ApiException && e.code == 'ACCOUNT_BANNED') {
      context.go('/account-banned', extra: e);
      return;
    }
    setState(() => _error = e is ApiException ? e.message : '网络请求未完成，请稍后重试');
  }

  Future<void> _send() async {
    if (_busy || (_challenge?.retrySeconds ?? 0) > 0 || !_validate()) return;
    final phone = _phone.text;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final requestClock = Stopwatch()..start();
      final data = await ref
          .read(apiClientProvider)
          .postData(
            '/auth/sms/challenges',
            authenticated: false,
            idempotencyKey: _sendRequestId,
            data: {
              'phone': phone,
              'purpose': _continuation == null ? 'login' : 'complete_phone',
            },
          );
      if (!mounted || phone != _phone.text) return;
      final challenge = SmsChallenge.fromJson(
        Map<String, dynamic>.from(data as Map),
        transitTime: requestClock.elapsed,
      );
      setState(() {
        _challenge = challenge;
        // Whitelisted verification is an operational delivery detail, not
        // user-facing login guidance (and never a password/default password).
        _notice = {'test_code', 'whitelist'}.contains(challenge.deliveryMode)
            ? null
            : challenge.notice;
        _sendRequestId = authRequestId();
        _requestId = authRequestId();
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || challenge.retrySeconds == 0) timer.cancel();
        if (mounted) setState(() {});
      });
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _complete(Map<String, dynamic> data) async {
    final tokens = data['tokens'] is Map
        ? {
            ...Map<String, dynamic>.from(data['tokens'] as Map),
            'is_new_user': data['is_new_user'],
            'onboarding_completed': data['onboarding_completed'],
            'password_setup_required': data['password_setup_required'],
          }
        : data;
    await ref.read(sessionProvider.notifier).acceptAuthentication(tokens);
    if (!mounted) return;
    final destination = safeLoginReturn(widget.returnTo);
    if (ref.read(apiClientProvider).passwordSetupRequired) {
      context.go(
        '/onboarding/password?from=${Uri.encodeComponent(destination)}',
      );
    } else if (!ref.read(apiClientProvider).onboardingCompleted) {
      context.go(
        '/onboarding/favorites?welcome=1&from=${Uri.encodeComponent(destination)}',
      );
    } else if (_canReturnToBusinessPage()) {
      // Keep the original scan/form state without replaying its action.
      context.pop();
    } else {
      context.go(destination);
    }
  }

  bool _canReturnToBusinessPage() {
    final router = GoRouter.of(context);
    if (!router.canPop()) return false;
    final current = router.routerDelegate.currentConfiguration;
    if (current.isEmpty || current.last.route.path != '/login') return false;
    // A poppable login may still sit above the launch/privacy flow. Inspect
    // the actual page underneath, not the last remembered business URL.
    final previous = current.remove(current.last);
    if (previous.isEmpty) return false;
    final origin = previous.last;
    final location = origin is ImperativeRouteMatch
        ? origin.matches.uri.toString()
        : previous.uri.toString();
    return safeLoginReturn(location) == location;
  }

  Future<void> _login() async {
    if (_busy || !_validate(code: true) || _challenge == null) return;
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (_continuation == null) {
        final data = await api.postData(
          '/auth/login',
          authenticated: false,
          idempotencyKey: _requestId,
          data: {
            'method': 'phone',
            'phone': _phone.text,
            'code': _code.text,
            'challenge_id': _challenge!.id,
          },
        );
        await _complete(Map<String, dynamic>.from(data as Map));
      } else {
        final ticket = Map<String, dynamic>.from(
          await api.postData(
            '/auth/verification-tickets',
            authenticated: false,
            idempotencyKey: _requestId,
            data: {'challenge_id': _challenge!.id, 'code': _code.text},
          ) as Map,
        );
        if (!mounted) return;
        final preview = Map<String, dynamic>.from(
          await api.postData(
            '/auth/oauth/preview-phone',
            authenticated: false,
            data: {
              'continuation_token': _continuation,
              'verification_ticket': ticket['verification_ticket'],
            },
          ) as Map,
        );
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认关联账号'),
            content: Text(
              '将平台身份关联至 ${preview['display_name'] ?? preview['phone_masked'] ?? '已验证手机号对应的 FanOS 账号'}。原账号收藏和卡册保持不变，微博默认不公开。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认关联'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final data = await api.postData(
          '/auth/oauth/complete-phone',
          authenticated: false,
          idempotencyKey: 'link-$_requestId',
          data: {
            'continuation_token': _continuation,
            'verification_ticket': ticket['verification_ticket'],
            'confirm_link': true,
          },
        );
        await _complete(Map<String, dynamic>.from(data as Map));
      }
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _loginWithPassword() async {
    if (_busy || !_validate()) return;
    if (_password.text.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(apiClientProvider)
          .postData(
            '/auth/login',
            authenticated: false,
            idempotencyKey: _requestId,
            data: {
              'method': 'password',
              'phone': _phone.text,
              'password': _password.text,
            },
          );
      await _complete(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _oauth(String provider) async {
    if (_busy) return;
    if (!_consent) {
      setState(() => _error = '请先阅读并同意用户协议与隐私政策');
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final transaction = Map<String, dynamic>.from(
        await api.postData(
          '/auth/oauth/transactions',
          authenticated: false,
          data: {'provider': provider, 'intent': 'login'},
        ) as Map,
      );
      final credential = await _platform.authorize(provider, transaction);
      final data = Map<String, dynamic>.from(
        await api.postData(
          '/auth/oauth/complete',
          authenticated: false,
          idempotencyKey: authRequestId(),
          data: credential,
        ) as Map,
      );
      if (!mounted) return;
      if (data['status'] == 'PHONE_REQUIRED') {
        setState(() {
          _continuation = data['continuation_token'] as String;
          _phoneMode = true;
          _passwordMode = false;
          _challenge = null;
          _code.clear();
          _notice = '平台授权已验证，请验证手机号后确认关联，当前尚未登录。';
        });
      } else {
        await _complete(data);
      }
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _legal(String title) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => AuthLegalPage(title: title)));

  void _back() {
    if (_phoneMode && _continuation == null) {
      setState(() {
        _phoneMode = false;
        _error = null;
        _notice = null;
      });
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Widget _messages() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_phoneMode && _notice != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _notice!,
            style: const TextStyle(
              fontSize: 13,
              color: FanColors.textSecondary,
            ),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
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
    ],
  );

  Widget _consentRow() => Center(
    child: Row(
      key: const Key('login-consent-group'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Checkbox(
            key: const Key('login-consent'),
            semanticLabel: '同意用户协议与隐私政策',
            value: _consent,
            activeColor: FanColors.lavender,
            onChanged: _busy
                ? null
                : (value) => setState(() => _consent = value == true),
          ),
        ),
        Flexible(
          child: Wrap(
            key: const Key('login-consent-text'),
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '我已阅读并同意',
                style: TextStyle(fontSize: 12, color: FanColors.textSecondary),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  textStyle: const TextStyle(fontSize: 12, height: 1.5),
                ),
                onPressed: () => _legal('用户协议'),
                child: const Text('用户协议'),
              ),
              const Text(
                '与',
                style: TextStyle(fontSize: 12, color: FanColors.textSecondary),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  textStyle: const TextStyle(fontSize: 12, height: 1.5),
                ),
                onPressed: () => _legal('隐私政策'),
                child: const Text('隐私政策'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _providers() => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final provider in authProviders)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: '${authProviderLabel(provider)}登录',
                    enabled: _platforms[provider] == true,
                    child: IconButton.outlined(
                      key: Key('login-provider-$provider'),
                      tooltip: _platforms[provider] == true
                          ? '${authProviderLabel(provider)}登录'
                          : '${authProviderLabel(provider)}授权暂不可用',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(52, 52),
                        side: const BorderSide(color: FanColors.line),
                        backgroundColor: Colors.white,
                      ),
                      onPressed: _busy || _platforms[provider] != true
                          ? null
                          : () => _oauth(provider),
                      icon: SvgPicture.asset(
                        'assets/auth/$provider.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          _platforms[provider] == true
                              ? FanColors.ink
                              : FanColors.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    authProviderLabel(provider),
                    style: const TextStyle(
                      fontSize: 12,
                      color: FanColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  Widget _choice() => LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 28).clamp(0, double.infinity),
          ),
          child: Column(
            key: const Key('login-choice-content'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 16),
                child: Column(
                  children: [
                    const FanWordmark(fontSize: 38),
                    const SizedBox(height: 12),
                    const Text(
                      '把每一次心动，好好收藏',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: FanColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 310,
                        maxHeight: 220,
                      ),
                      child: Image.asset(
                        'assets/auth/login-hero.png',
                        key: const Key('login-hero'),
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const SizedBox(height: 180),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _messages(),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('login-open-phone'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _phoneMode = true;
                            _error = null;
                          }),
                    icon: const Icon(Icons.phone_iphone_outlined, size: 20),
                    label: const Text('手机号登录'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: FanColors.lavender,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _providers(),
                  const SizedBox(height: 16),
                  _consentRow(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                try {
                                  await ref
                                      .read(sessionProvider.notifier)
                                      .continueAsGuest();
                                  if (context.mounted) context.go('/home');
                                } catch (e) {
                                  _failure(e);
                                }
                              },
                        child: const Text('游客体验'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const AuthHelpPage(),
                          ),
                        ),
                        child: const Text('登录帮助'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _phoneForm() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      const FanWordmark(fontSize: 28),
      const SizedBox(height: 8),
      Text(
        _continuation != null
            ? '验证手机号，完成平台账号关联'
            : _passwordMode
            ? '使用手机号与密码登录'
            : '未注册的手机号验证后自动创建账号',
        style: const TextStyle(
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
              key: const Key('login-phone'),
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: const InputDecoration(
                labelText: '手机号',
                prefixText: '+86  ',
                hintText: '请输入手机号',
              ),
            ),
            if (_passwordMode) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('login-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => _requestId = authRequestId(),
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ] else if (_challenge != null) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('login-code'),
                controller: _code,
                enabled: !_busy,
                onChanged: (_) => _requestId = authRequestId(),
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: '验证码',
                  hintText: '请输入 6 位验证码',
                  suffixIcon: TextButton(
                    onPressed: _busy || _challenge!.retrySeconds > 0
                        ? null
                        : _send,
                    child: Text(
                      _challenge!.retrySeconds > 0
                          ? '${_challenge!.retrySeconds}s'
                          : '重新发送',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      _messages(),
      const SizedBox(height: 16),
      _consentRow(),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('login-submit'),
        onPressed: _busy
            ? null
            : _passwordMode
            ? _loginWithPassword
            : _challenge == null
            ? _send
            : _login,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: FanColors.lavender,
        ),
        child: Text(
          _sending
              ? '正在请求验证码…'
              : _loggingIn
              ? '正在验证…'
              : _passwordMode
              ? '登录'
              : _challenge == null
              ? '获取验证码'
              : '登录并继续',
        ),
      ),
      if (_continuation == null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('login-switch-method'),
            onPressed: _busy
                ? null
                : () => setState(() {
                    _passwordMode = !_passwordMode;
                    _error = null;
                    _notice = null;
                    _requestId = authRequestId();
                  }),
            child: Text(_passwordMode ? '验证码登录' : '账号密码登录'),
          ),
        ),
      const SizedBox(height: 24),
      if (_continuation == null) ...[
        const Text(
          '其他登录方式',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: FanColors.textSecondary),
        ),
        const SizedBox(height: 16),
        _providers(),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FanColors.canvas,
    appBar: AppBar(
      backgroundColor: FanColors.canvas,
      surfaceTintColor: Colors.transparent,
      leading: BackButton(onPressed: _busy ? null : _back),
      title: _phoneMode
          ? Text(_continuation == null ? '手机号登录' : '绑定手机号')
          : null,
    ),
    body: SafeArea(top: false, child: _phoneMode ? _phoneForm() : _choice()),
  );
}

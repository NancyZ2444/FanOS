import 'dart:async';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/api/auth_flow.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/onboarding/presentation/auth_help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final accountIdentitiesProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  ref.watch(sessionProvider.select((s) => s.userId));
  if (useMockApi) {
    return {'phone_masked': '演示模式', 'identities': <Map<String, dynamic>>[]};
  }
  return Map<String, dynamic>.from(
    await ref.watch(apiClientProvider).getData('/account/identities') as Map,
  );
});

class AccountSecurityPage extends ConsumerStatefulWidget {
  const AccountSecurityPage({super.key});
  @override
  ConsumerState<AccountSecurityPage> createState() =>
      _AccountSecurityPageState();
}

class _AccountSecurityPageState extends ConsumerState<AccountSecurityPage> {
  final _platform = PlatformAuthorization();
  final Map<String, bool> _sdk = {};
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _platformStatus();
  }

  Future<void> _platformStatus() async {
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
        if (mounted) setState(() => _sdk[provider] = available);
      }
    } catch (_) {
      // Unbinding existing identities does not require an SDK. New bindings
      // stay unavailable until both service and native capabilities exist.
    }
  }

  Future<String?> _verify(
    String purpose,
    String masked, {
    bool newPhone = false,
  }) => Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => _SensitiveSmsPage(
        purpose: purpose,
        masked: masked,
        newPhone: newPhone,
      ),
    ),
  );
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e is ApiException &&
                  {
                    'VERIFICATION_PURPOSE_MISMATCH',
                    'INVALID_VERIFICATION_TICKET',
                    'VERIFICATION_EXPIRED',
                  }.contains(e.code)
              ? '本次验证已失效或登录会话已更新，请重新获取短信并完成验证。'
              : e is ApiException
              ? e.message
              : '操作未完成，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bind(String provider, String masked) => _action(() async {
    final ticket = await _verify('bind_identity', masked);
    if (ticket == null) return;
    final api = ref.read(apiClientProvider);
    final transaction = Map<String, dynamic>.from(
      await api.postData(
        '/auth/oauth/transactions',
        data: {
          'provider': provider,
          'intent': 'bind',
          'verification_ticket': ticket,
        },
        idempotencyKey: authRequestId(),
      ) as Map,
    );
    final credential = await _platform.authorize(provider, transaction);
    await api.postData(
      '/auth/oauth/complete',
      data: credential,
      idempotencyKey: authRequestId(),
    );
    ref.invalidate(accountIdentitiesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('平台身份已绑定，默认不公开'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  });
  Future<void> _unbind(
    Map<String, dynamic> identity,
    String masked,
  ) => _action(() async {
    final name = authProviderLabel(identity['provider'] as String);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('解除$name关联'),
        content: Text(
          '解绑后该身份不能继续登录当前账号，收藏和卡册保留。${identity['provider'] == 'weibo' ? '微博主页展示将关闭。' : ''}需要短信验证。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续验证'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ticket = await _verify('unbind_identity', masked);
    if (ticket == null) return;
    final result = Map<String, dynamic>.from(
      await ref
              .read(apiClientProvider)
              .postData(
                '/account/identities/${identity['provider']}/unbind',
                data: {
                  'verification_ticket': ticket,
                  'expected_version': identity['version'],
                },
                idempotencyKey: authRequestId(),
              )
          as Map,
    );
    if (result['access_token'] != null) {
      await ref.read(apiClientProvider).saveAuthTokens(result);
    }
    ref.invalidate(accountIdentitiesProvider);
    await ref.read(sessionProvider.notifier).reloadAccount();
    if (mounted) {
      setState(
        () => _error = result['provider_revoked'] == true
            ? null
            : '本地关联已解除。平台侧授权撤销状态未确认，可前往对应平台检查授权设置。',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已解除 FanOS 账号关联'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  });
  Future<void> _changePhone(String masked) => _action(() async {
    final oldTicket = await _verify('change_phone_old', masked);
    if (oldTicket == null || !mounted) return;
    final newTicket = await _verify('change_phone_new', '', newPhone: true);
    if (newTicket == null) return;
    final result = Map<String, dynamic>.from(
      await ref
              .read(apiClientProvider)
              .postData(
                '/account/change-phone',
                data: {
                  'old_verification_ticket': oldTicket,
                  'new_verification_ticket': newTicket,
                },
                idempotencyKey: authRequestId(),
              )
          as Map,
    );
    await ref.read(sessionProvider.notifier).acceptAuthentication(result);
    ref.invalidate(accountIdentitiesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('手机号已更换，其他设备需重新登录'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  });
  String _status(String? value) => switch (value) {
    'valid' || 'active' => '授权有效',
    'expired' => '授权已过期，请重新授权',
    'revoked' => '授权已撤销',
    _ => '授权状态未知',
  };
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountIdentitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error is ApiException ? error.message : '账号安全信息加载失败'),
                  TextButton(
                    onPressed: () => ref.invalidate(accountIdentitiesProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) {
            final masked = data['phone_masked']?.toString() ?? '手机号未完成验证';
            final identities = (data['identities'] as List? ?? [])
                .whereType<Map>()
                .map((v) => Map<String, dynamic>.from(v))
                .toList();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('手机号'),
                    subtitle: Text(masked),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _changePhone(masked),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '平台身份',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final provider in authProviders)
                  Builder(
                    builder: (context) {
                      final identity = identities
                          .where((i) => i['provider'] == provider)
                          .firstOrNull;
                      final bound = identity?['bound'] == true;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                authProviderLabel(provider),
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bound
                                    ? '${identity?['display_name'] ?? identity?['subject_masked'] ?? '已绑定'} · ${_status(identity?['authorization_status']?.toString())}'
                                    : '未绑定',
                                style: const TextStyle(
                                  color: FanColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (!bound && _sdk[provider] != true)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    '当前平台授权暂不可用，暂不能绑定。',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: FanColors.textSecondary,
                                    ),
                                  ),
                                ),
                              Wrap(
                                spacing: 12,
                                children: [
                                  if (bound)
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _unbind(identity!, masked),
                                      child: const Text('解除关联'),
                                    )
                                  else
                                    TextButton(
                                      onPressed: _busy || _sdk[provider] != true
                                          ? null
                                          : () => _bind(provider, masked),
                                      child: const Text('验证手机号并绑定'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: const TextStyle(color: FanColors.textSecondary),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  '绑定仅用于身份关联与登录，不代表实名或信用担保。敏感操作必须使用真实短信，测试验证码不可用。',
                  style: TextStyle(
                    fontSize: 13,
                    color: FanColors.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AuthHelpPage(),
                    ),
                  ),
                  child: const Text('原手机号不可用 / 账号恢复帮助'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                          await ref.read(sessionProvider.notifier).signOut();
                          if (context.mounted) context.go('/login');
                        }),
                  child: const Text('退出登录'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SensitiveSmsPage extends ConsumerStatefulWidget {
  const _SensitiveSmsPage({
    required this.purpose,
    required this.masked,
    this.newPhone = false,
  });
  final String purpose;
  final String masked;
  final bool newPhone;
  @override
  ConsumerState<_SensitiveSmsPage> createState() => _SensitiveSmsPageState();
}

class _SensitiveSmsPageState extends ConsumerState<_SensitiveSmsPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  SmsChallenge? _challenge;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  String _requestId = authRequestId();
  String _sendRequestId = authRequestId();
  late final String _userId;
  @override
  void initState() {
    super.initState();
    _userId = ref.read(sessionProvider).userId;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit(bool send) async {
    if (_busy) return;
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text)) {
      setState(() => _error = '请输入正确的手机号');
      return;
    }
    if (!send && !RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = '请输入 6 位短信验证码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final current = ref.read(sessionProvider);
      if (!current.isLoggedIn || current.userId != _userId) {
        throw const ApiException('AUTH_REQUIRED', '账号已改变，请重新验证');
      }
      final api = ref.read(apiClientProvider);
      if (send) {
        final requestClock = Stopwatch()..start();
        final data = await api.postData(
          '/auth/sms/challenges',
          idempotencyKey: _sendRequestId,
          data: {'phone': _phone.text, 'purpose': widget.purpose},
        );
        final challenge = SmsChallenge.fromJson(
          Map<String, dynamic>.from(data as Map),
          transitTime: requestClock.elapsed,
        );
        if (!mounted) return;
        if (challenge.deliveryMode != 'sms' &&
            challenge.deliveryMode != 'sms_pending') {
          throw const ApiException('REAL_SMS_REQUIRED', '此操作必须使用真实短信，请联系客服核查');
        }
        setState(() {
          _challenge = challenge;
          _sendRequestId = authRequestId();
          _requestId = authRequestId();
        });
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || challenge.retrySeconds == 0) t.cancel();
          if (mounted) setState(() {});
        });
      } else {
        final data = Map<String, dynamic>.from(
          await api.postData(
            '/auth/verification-tickets',
            idempotencyKey: _requestId,
            data: {'challenge_id': _challenge!.id, 'code': _code.text},
          ) as Map,
        );
        if (mounted && ref.read(sessionProvider).userId == _userId) {
          Navigator.pop(context, data['verification_ticket'] as String);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is ApiException &&
              {
                'VERIFICATION_PURPOSE_MISMATCH',
                'INVALID_VERIFICATION_TICKET',
                'VERIFICATION_EXPIRED',
                'AUTH_REQUIRED',
              }.contains(e.code)) {
            _challenge = null;
            _code.clear();
            _timer?.cancel();
            _requestId = authRequestId();
            _sendRequestId = authRequestId();
            _error = '本次验证已失效或登录会话已更新，请重新获取短信并完成验证。';
          } else {
            _error = e is ApiException ? e.message : '验证未完成，请稍后重试';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.newPhone ? '验证新手机号' : '验证当前手机号')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.newPhone
                ? '请输入要换绑的新手机号，已被其他账号使用的号码不能覆盖。'
                : '当前账号：${widget.masked}。请输入完整手机号并通过真实短信验证。',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            onChanged: (_) => setState(() {
              _challenge = null;
              _sendRequestId = authRequestId();
              _code.clear();
              _error = null;
              _timer?.cancel();
            }),
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixText: '+86  ',
            ),
          ),
          const SizedBox(height: 12),
          if (_challenge != null) ...[
            Text(
              _challenge!.notice,
              style: const TextStyle(
                color: FanColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              onChanged: (_) => _requestId = authRequestId(),
              keyboardType: TextInputType.number,
              enabled: !_busy,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: '短信验证码',
                suffixIcon: TextButton(
                  onPressed: _busy || _challenge!.retrySeconds > 0
                      ? null
                      : () => _submit(true),
                  child: Text(
                    _challenge!.retrySeconds > 0
                        ? '${_challenge!.retrySeconds}s'
                        : '重新发送',
                  ),
                ),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : () => _submit(_challenge == null),
            child: Text(
              _busy
                  ? '正在验证…'
                  : _challenge == null
                  ? '获取短信验证码'
                  : '验证并继续',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AuthHelpPage()),
            ),
            child: const Text('无法接收短信 / 联系客服'),
          ),
        ],
      ),
    ),
  );
}

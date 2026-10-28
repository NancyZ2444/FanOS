import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountBannedPage extends ConsumerWidget {
  const AccountBannedPage({super.key, required this.error});
  final ApiException error;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('账号已被封禁'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.lock_outline, size: 40),
          const SizedBox(height: 24),
          const Text('当前账号暂时无法登录。如有疑问，请联系客服申请核查。'),
          const SizedBox(height: 16),
          Text(
            error.details['public_message']?.toString() ?? '待人工核查',
            style: const TextStyle(color: FanColors.textSecondary),
          ),
          if (error.details['banned_until'] != null)
            Text('截止时间：${error.details['banned_until']}'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AuthHelpPage(
                  requestId: error.details['request_id']?.toString(),
                ),
              ),
            ),
            child: const Text('联系客服'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(apiClientProvider).logout();
              ref.read(sessionProvider.notifier).reset();
              if (context.mounted) context.go('/login');
            },
            child: const Text('返回登录页 / 更换账号'),
          ),
        ],
      ),
    ),
  );
}

class AuthHelpPage extends ConsumerStatefulWidget {
  const AuthHelpPage({super.key, this.requestId});
  final String? requestId;
  @override
  ConsumerState<AuthHelpPage> createState() => _AuthHelpPageState();
}

class _AuthHelpPageState extends ConsumerState<AuthHelpPage> {
  late Future<Map<String, dynamic>> _future;
  String? _linkError;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
    await ref
            .read(apiClientProvider)
            .getData('/auth/support-entry', authenticated: false)
        as Map,
  );
  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('登录帮助')),
    body: SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, state) {
          final data = state.data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (state.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (state.hasError) ...[
                const Text('客服信息暂时加载失败，请检查网络后重试。'),
                TextButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('重新加载'),
                ),
              ] else ...[
                Text(
                  data?['display_name']?.toString() ?? '账号帮助',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  data?['backup']?.toString() ??
                      data?['fallback_message']?.toString() ??
                      data?['fallback_instructions']?.toString() ??
                      data?['fallback_note']?.toString() ??
                      '如无法完成验证，请联系 FanOS 测试或服务负责人申请人工核查。',
                ),
                if (((data?['contact'] ?? data?['contact_channel'])
                            ?.toString() ??
                        '')
                    .isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(
                      (data!['contact'] ?? data['contact_channel']).toString(),
                    ),
                    trailing: IconButton(
                      tooltip: '复制客服渠道',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => _copy(
                        (data['contact'] ?? data['contact_channel']).toString(),
                      ),
                    ),
                  ),
                if (data?['enabled'] == true &&
                    data?['url'] is String &&
                    Uri.tryParse(data!['url'])?.scheme == 'https')
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        if (!await launchUrl(
                          Uri.parse(data['url']),
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw StateError('unavailable');
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => _linkError = '暂时无法打开帮助页面，请使用上方备用渠道或稍后重试。',
                          );
                        }
                      }
                    },
                    child: const Text('打开客服帮助页'),
                  ),
                if (_linkError != null)
                  Text(
                    _linkError!,
                    style: const TextStyle(color: FanColors.textSecondary),
                  ),
              ],
              if (widget.requestId?.isNotEmpty == true) ...[
                const SizedBox(height: 24),
                const Text(
                  '申诉编号',
                  style: TextStyle(color: FanColors.textSecondary),
                ),
                SelectableText(widget.requestId!),
                TextButton(
                  onPressed: () => _copy(widget.requestId!),
                  child: const Text('复制申诉编号'),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '申诉不会自动解除限制。请勿向任何人提供验证码或登录凭证。',
                style: TextStyle(fontSize: 13, color: FanColors.textSecondary),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class AuthLegalPage extends StatelessWidget {
  const AuthLegalPage({super.key, required this.title});
  final String title;
  String get _url => title == '用户协议'
      ? const String.fromEnvironment('USER_AGREEMENT_URL')
      : title == '隐私政策'
      ? const String.fromEnvironment('PRIVACY_POLICY_URL')
      : '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Uri.tryParse(_url)?.scheme == 'https'
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('将在浏览器打开$title，阅读后可返回登录页。'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        if (!await launchUrl(
                          Uri.parse(_url),
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw StateError('unavailable');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('协议暂时无法打开'),
                              content: const Text('请检查网络后重试，暂不要勾选同意。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          );
                        }
                      }
                    },
                    child: Text('阅读$title'),
                  ),
                ],
              )
            : const Text(
                '当前测试安装包尚未配置正式协议链接。请联系测试负责人获取完整文本并确认后，再同意并登录。正式发布前必须完成协议内容配置。',
              ),
      ),
    ),
  );
}

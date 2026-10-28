import 'package:fan_os/features/onboarding/presentation/auth_help_page.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  bool _agreed = false;

  static const agreements = <(IconData, String, String)>[
    (Icons.lock_outline_rounded, '用户协议', '使用服务前请了解双方的权利与责任'),
    (Icons.shield_outlined, '隐私政策', '了解我们如何收集、使用和保护你的信息'),
    (Icons.hub_outlined, '第三方 SDK 信息', '查看登录、推送等第三方服务说明'),
    (Icons.inventory_2_outlined, '数据采集说明', '仅采集提供功能所必需的信息'),
    (Icons.tune_rounded, '个性化推荐说明', '可随时在设置中管理个性化体验'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: FanContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  '欢迎使用 Fan OS',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '热爱值得被认真收藏。请先阅读并了解以下说明。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: FanColors.textSecondary),
                ),
                const SizedBox(height: 22),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < agreements.length; i++) ...[
                        ListTile(
                          minLeadingWidth: 26,
                          leading: Icon(agreements[i].$1, size: 20),
                          title: Text(agreements[i].$2),
                          subtitle: Text(agreements[i].$3),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AuthLegalPage(title: agreements[i].$2),
                            ),
                          ),
                        ),
                        if (i < agreements.length - 1)
                          const Divider(height: 1, indent: 56),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          key: const Key('privacy-consent-panel'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  key: const Key('privacy-agreement-checkbox'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _agreed,
                  onChanged: (value) =>
                      setState(() => _agreed = value ?? false),
                  title: const Text(
                    '我已阅读并同意《用户协议》和《隐私政策》',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '相关权限将在使用功能时单独申请',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('privacy-agree-continue'),
                  onPressed: _agreed
                      ? () => context.go('/login?from=/home')
                      : null,
                  child: Text(_agreed ? '同意并继续' : '请先勾选协议'),
                ),
              ),
              SizedBox(
                height: 34,
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('暂不同意'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

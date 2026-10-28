import 'package:fan_os/core/api/api_client.dart';
import 'package:flutter/services.dart';

/// Only navigates to read-only/local routes; never accepts URLs or auth actions.
String safeLoginReturn(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.contains('\\') ||
      uri.path.contains('..')) {
    return '/home';
  }
  const roots = {
    'home',
    'catalog',
    'groups',
    'group',
    'idol',
    'album',
    'event',
    'other',
    'card',
    'user',
    'digital-albums',
    'search',
    'notifications',
    'idols',
    'cards',
    'albums',
    'collection',
    'profile',
    'users',
    'scan',
    'feedback',
    'daily-card',
  };
  if (uri.pathSegments.isEmpty || !roots.contains(uri.pathSegments.first)) {
    return '/home';
  }
  return uri.toString();
}

String authRequestId() => 'app-${DateTime.now().microsecondsSinceEpoch}';

const authProviders = ['wechat', 'weibo', 'qq'];
String authProviderLabel(String provider) => switch (provider) {
  'wechat' => '微信',
  'weibo' => '微博',
  'qq' => 'QQ',
  _ => provider,
};

String? registrationPasswordError(String password) {
  if (password.length < 8 ||
      password.length > 64 ||
      !RegExp(r'[A-Za-z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password) ||
      RegExp(r'\s').hasMatch(password)) {
    return '密码需为 8–64 位，包含字母和数字，不能含空格';
  }
  return null;
}

class SmsChallenge {
  SmsChallenge.fromJson(
    Map<String, dynamic> data, {
    Duration transitTime = Duration.zero,
  }) : id = data['challenge_id'] as String,
       deliveryMode = data['delivery_mode'] as String? ?? 'sms',
       _retryMilliseconds = _serverDelay(data, transitTime);
  static int _serverDelay(Map<String, dynamic> data, Duration transitTime) {
    final server = DateTime.tryParse(data['server_time']?.toString() ?? '');
    final retry = DateTime.tryParse(data['retry_at']?.toString() ?? '');
    final delay = server != null && retry != null
        ? retry.difference(server).inMilliseconds
        : ((data['retry_after'] as num?)?.toInt() ?? 60) * 1000;
    return (delay - transitTime.inMilliseconds).clamp(0, 3600000);
  }

  final String id;
  final String deliveryMode;
  final int _retryMilliseconds;
  final Stopwatch _elapsed = Stopwatch()..start();
  int get retrySeconds =>
      ((_retryMilliseconds - _elapsed.elapsedMilliseconds) / 1000).ceil().clamp(
        0,
        3600,
      );
  String get notice =>
      deliveryMode == 'test_code' || deliveryMode == 'whitelist'
      ? '请使用测试负责人提供的测试验证码，本次不发送短信。'
      : deliveryMode == 'pending' ||
            deliveryMode == 'unknown' ||
            deliveryMode == 'sms_pending'
      ? '短信请求正在处理中，请稍后查看手机，勿重复发送。'
      : '短信请求已受理，请查收验证码。';
}

/// No provider credentials are synthesized. A vetted native SDK adapter must
/// implement this channel before provider login/binding can be enabled.
class PlatformAuthorization {
  static const _channel = MethodChannel('com.fanos.app/account_authorization');
  Future<bool> available(String provider) async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable', {
            'provider': provider,
          }) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, dynamic>> authorize(
    String provider,
    Map<String, dynamic> transaction,
  ) async {
    if (!await available(provider)) {
      throw const ApiException('SDK_UNAVAILABLE', '当前安装包尚未配置平台授权，请使用手机号登录。');
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'authorize',
        {
          'provider': provider,
          'transaction_id': transaction['transaction_id'],
          'state': transaction['state'],
          'sdk_parameters': transaction['sdk_parameters'],
        },
      );
      if (result == null ||
          result['credential'] is! String ||
          result['state'] != transaction['state']) {
        throw const ApiException('INVALID_OAUTH_CREDENTIAL', '平台授权未完成，请重新授权');
      }
      return {
        'transaction_id': transaction['transaction_id'],
        'state': result['state'],
        'credential_type': result['credential_type'],
        'credential': result['credential'],
      };
    } on PlatformException catch (e) {
      throw ApiException(
        e.code == 'OAUTH_CANCELLED' ? e.code : 'OAUTH_FAILED',
        e.code == 'OAUTH_CANCELLED' ? '已取消平台授权，账号未改变' : '平台授权未完成，请稍后重试',
      );
    }
  }
}

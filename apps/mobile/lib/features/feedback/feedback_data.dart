import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

typedef FeedbackJson = Map<String, dynamic>;
List<FeedbackJson> feedbackItems(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
String feedbackValue(dynamic value) => value == null || value == ''
    ? '未填写'
    : value is List
    ? value.map((v) => v is Map ? v['name'] ?? v['id'] : v).join('、')
    : value is bool
    ? value
          ? '是'
          : '否'
    : '$value';
String feedbackError(Object e) =>
    e is ApiException ? e.message : '暂时无法连接，请稍后重试';

/// Mirrors feedback API link constraints before a preview/submission request.
String? feedbackLinkError(String raw) {
  final links = raw
      .split('\n')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  if (links.length > 6) return '最多填写6条参考链接，每行一条';
  for (var index = 0; index < links.length; index++) {
    final value = links[index];
    final uri = Uri.tryParse(value);
    if (value.length > 800) return '第${index + 1}条链接不能超过800字符';
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        RegExp(r'\s').hasMatch(value) ||
        uri.userInfo.isNotEmpty) {
      return '第${index + 1}条请填写完整的 http:// 或 https:// 链接；没有链接可留空';
    }
  }
  return null;
}

String feedbackDate(dynamic value) =>
    '${value ?? ''}'.replaceFirst('T', ' ').split('.').first;
String feedbackRoute(String kind, String id) =>
    '/${{'cards': 'card', 'groups': 'group', 'idols': 'idol', 'albums': 'album', 'events': 'event', 'others': 'other'}[kind] ?? 'catalog'}/$id';
const feedbackObjectKinds = {
  'cards': '小卡',
  'albums': '专辑',
  'groups': '组合',
  'idols': '艺人',
  'events': '活动',
  'others': '其他来源',
  'versions': '版本',
  'companies': '公司',
};

/// The same content keeps its request key across a failed connection and retry.
class FeedbackRequestKey {
  String? _signature;
  String? _key;
  String forPayload(FeedbackJson body) {
    final signature = jsonEncode(body);
    if (_signature != signature) {
      _signature = signature;
      _key =
          'mobile-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    }
    return _key!;
  }
}

class FeedbackRepository {
  FeedbackRepository(this.client);
  final ApiClient client;
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async =>
      Map<String, dynamic>.from(
        await client.getData('/feedback$path', query: query) as Map,
      );
  Future<FeedbackJson> post(String path, FeedbackJson body) async =>
      Map<String, dynamic>.from(
        await client.postData('/feedback$path', data: body) as Map,
      );
  Future<FeedbackJson?> pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2800,
      imageQuality: 92,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw const ApiException('IMAGE_TOO_LARGE', '图片不能超过10MB');
    }
    return Map<String, dynamic>.from(
      await client.postData(
        '/feedback/images',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: file.name),
        }),
      ) as Map,
    );
  }
}

final feedbackRepositoryProvider = Provider(
  (ref) => FeedbackRepository(ref.watch(apiClientProvider)),
);
final contributionCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, userId) async {
      if (useMockApi) return 0;
      final data = await ref
          .watch(feedbackRepositoryProvider)
          .get('/users/$userId/contributions', query: {'limit': 1});
      return data['total'] as int? ?? 0;
    });
final feedbackCreditsProvider = FutureProvider.autoDispose
    .family<List<FeedbackJson>, String>((ref, id) async {
      if (useMockApi) return [];
      return feedbackItems(
        (await ref
            .watch(feedbackRepositoryProvider)
            .get('/cards/$id/contributors'))['items'],
      );
    });
typedef CatalogCreditTarget = ({String kind, String id});

final catalogCreditsProvider = FutureProvider.autoDispose
    .family<List<FeedbackJson>, CatalogCreditTarget>((ref, target) async {
      if (useMockApi) return [];
      return feedbackItems(
        (await ref
            .watch(feedbackRepositoryProvider)
            .get('/objects/${target.kind}/${target.id}/contributors'))['items'],
      );
    });
final feedbackInboxProvider = FutureProvider.autoDispose<List<FeedbackJson>>((
  ref,
) async {
  if (useMockApi || !ref.watch(sessionProvider).isLoggedIn) return [];
  final data = await ref
      .watch(apiClientProvider)
      .getData('/notifications/inbox');
  return feedbackItems(data['items']);
});

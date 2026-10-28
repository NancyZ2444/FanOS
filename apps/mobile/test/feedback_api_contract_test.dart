import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/scan_feedback_repository.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('RUN_FEEDBACK_API_CONTRACT');
const _endpoint = String.fromEnvironment(
  'FEEDBACK_API_TEST_URL',
  defaultValue: 'http://127.0.0.1:18104/api/v1',
);
const _code = String.fromEnvironment(
  'FEEDBACK_API_TEST_CODE',
  defaultValue: '666666',
);
const _scanId = String.fromEnvironment(
  'FEEDBACK_SCAN_FIXTURE',
  defaultValue: 'feedback-contract-scan',
);
const _detectedId = String.fromEnvironment(
  'FEEDBACK_DETECTED_FIXTURE',
  defaultValue: 'feedback-contract-detected',
);
const _groupId = String.fromEnvironment(
  'FEEDBACK_GROUP_FIXTURE',
  defaultValue: 'group-lumina',
);
const _idolId = String.fromEnvironment(
  'FEEDBACK_IDOL_FIXTURE',
  defaultValue: 'idol-aria',
);

void main() {
  test(
    'real feedback API keeps drafts private, supplements same record, publishes official card and retains rejection',
    () async {
      final uri = Uri.parse(_endpoint);
      expect(uri.host, anyOf('127.0.0.1', 'localhost'));
      expect(
        uri.port,
        isNot(8000),
        reason: 'Use an isolated fixture database.',
      );
      final client = ApiClient(dio: Dio(BaseOptions(baseUrl: _endpoint)));
      final auth = await client.postData(
        '/auth/login',
        data: {'method': 'phone', 'phone': '13900000000', 'code': _code},
      );
      client.setAccessToken(auth['access_token'] as String);
      final repo = FeedbackRepository(client);
      final options = await ApiScanFeedbackOptionsRepository(client)
          .fetchOptions(source: '专辑', groupId: _groupId, idolId: _idolId);
      expect(options, isNotEmpty);
      final album = options.first;
      final key = DateTime.now().microsecondsSinceEpoch;
      final initial = <String, dynamic>{
        'kind': 'MISSING_CARD',
        'request_key': 'dart-feedback-$key',
        'missing': {
          'scan_session_id': _scanId,
          'detected_card_id': _detectedId,
          'group_id': _groupId,
          'idol_id': _idolId,
          'is_group_pc': false,
          'is_double_sided': false,
          'source_entity_type': 'ALBUM',
          'source_entity_id': album.id,
          'source_version_id': album.versions.firstOrNull?.id,
        },
        'notes': 'Dart 契约：AI 无匹配小卡，提交官方渠道信息',
        'links': ['https://example.com/official-card'],
      };
      final first = await repo.post('', initial);
      final id = first['id'] as String;
      Future<FeedbackJson> read() => repo.get('/records/$id');
      Future<FeedbackJson> adminRead() async => Map<String, dynamic>.from(
        await client.getData('/admin/console/feedback/$id') as Map,
      );
      Future<FeedbackJson> action(
        String verb, {
        String note = '',
        FeedbackJson changes = const {},
      }) async {
        final latest = await adminRead();
        return Map<String, dynamic>.from(
          await client.postData(
            '/admin/console/feedback/$id/actions',
            data: {
              'action': verb,
              'request_key': '$verb-${DateTime.now().microsecondsSinceEpoch}',
              'revision': latest['revision'],
              'public_note': note,
              'changes': changes,
            },
          ) as Map,
        );
      }

      Future<List<FeedbackJson>> notices() async {
        final data = await client.getData('/notifications/inbox');
        return feedbackItems(data['items'])
            .where((item) => item['payload']?['feedback_id'] == id)
            .toList();
      }

      FeedbackJson publicActivity(FeedbackJson row) => {
        for (final key in [
          'status',
          'result',
          'public_note',
          'history',
          'updated_at',
          'entity_id',
          'decisions',
        ])
          key: row[key],
      };
      expect((await repo.post('', initial))['id'], id);
      await action('draft', note: '这条内部草稿说明不应出现在用户动态');
      final saved = await read();
      expect(publicActivity(saved), publicActivity(first));
      expect(await notices(), isEmpty);
      final review = await action('need_info', note: '请补充无遮挡的背面图片和获取渠道');
      expect(review['result'], 'NEEDS_INFO');
      final needsInfo = await read();
      expect(needsInfo['can_resubmit'], isTrue);
      expect(needsInfo['status_label'], '信息缺失待补充');
      expect(await notices(), hasLength(1));
      final image = await client.postData(
        '/feedback/images',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
            filename: 'back.png',
          ),
        }),
      );
      final submission = needsInfo['submission'] as Map;
      final supplement = <String, dynamic>{
        'kind': 'MISSING_CARD',
        'request_key': 'dart-supplement-$key',
        'revision': needsInfo['revision'],
        'missing': {
          ...Map<String, dynamic>.from(submission['missing'] as Map),
          'scan_session_id': submission['scan']['scan_session_id'],
          'detected_card_id': submission['scan']['detected_card_id'],
          'front_image_id': submission['front']['id'],
          'back_image_id': image['id'],
        },
        'notes': '已补充背面，获取渠道：官方专辑预购',
        'links': ['https://example.com/official-card'],
      };
      final resubmitted = await repo.post('/records/$id/resubmit', supplement);
      final retried = await repo.post('/records/$id/resubmit', supplement);
      expect(resubmitted['id'], id);
      expect(retried['revision'], resubmitted['revision']);
      expect(resubmitted['can_resubmit'], isFalse);
      expect(resubmitted['result'], 'PENDING');
      expect(
        resubmitted['submission']['front']['id'],
        submission['front']['id'],
      );
      expect(resubmitted['submission']['back']['id'], image['id']);
      expect(await notices(), hasLength(1));
      await action('draft');
      expect(publicActivity(await read()), publicActivity(resubmitted));
      await action(
        'publish',
        note: '核实通过，已登记为官方图鉴',
        changes: {
          'front_source': {
            'source_type': 'USER_SUBMITTED',
            'copyright_status': 'AUTHORIZED',
          },
          'back_source': {
            'source_type': 'USER_SUBMITTED',
            'copyright_status': 'AUTHORIZED',
          },
        },
      );
      final published = await read();
      expect(published['status_label'], '已采用');
      expect(published['target_available'], isTrue);
      expect(published['can_resubmit'], isFalse);
      expect(await notices(), hasLength(2));
      final official = await client.getData(
        '/catalog/cards/${published['entity_id']}',
      );
      expect(official['id'], published['entity_id']);

      final rejected = await repo.post('', {
        ...initial,
        'request_key': 'dart-rejected-$key',
      });
      await client.postData(
        '/admin/console/feedback/${rejected['id']}/actions',
        data: {
          'action': 'reject',
          'revision': rejected['revision'],
          'request_key': 'reject-$key',
          'public_note': '图片不是官方小卡，本次无法采用',
        },
      );
      final retained = await repo.get('/records/${rejected['id']}');
      expect(retained['status_label'], '无法采用');
      expect(retained['submission']['scan']['scan_session_id'], _scanId);
      expect(retained['submission']['notes'], initial['notes']);
      expect(retained['can_resubmit'], isFalse);
      final list = await repo.get('', query: {'kind': 'MISSING_CARD'});
      expect(
        feedbackItems(list['items']).map((row) => row['id']),
        containsAll([id, rejected['id']]),
      );
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

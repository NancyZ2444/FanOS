import 'dart:convert';
import 'dart:math';

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:dio/dio.dart';

enum LoginMethod { phone, wechat, weibo }

abstract interface class AuthRepository {
  Future<void> login(LoginMethod method, {String? phone, String? code});
}

abstract interface class CatalogRepository {
  Future<CatalogBundle> fetchCatalog();
}

abstract interface class DailyCardRepository {
  Future<CollectibleCard> draw({
    required List<String> drawnCardIds,
    required List<String> favoriteIdolIds,
  });
}

abstract interface class ScanRepository {
  Future<ScanSession> recognize({String? localImagePath});
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> confirmations,
  );
  Future<void> submitFeedback(ScanFeedbackRequest request);
  Future<ScanFeedbackPageData> fetchFeedbackHistory({int offset = 0});
}

class MockAuthRepository implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }
}

class MockCatalogRepository implements CatalogRepository {
  @override
  Future<CatalogBundle> fetchCatalog() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return DemoCatalog.bundle;
  }
}

class MockDailyCardRepository implements DailyCardRepository {
  @override
  Future<CollectibleCard> draw({
    required List<String> drawnCardIds,
    required List<String> favoriteIdolIds,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final available = DemoCatalog.cards
        .where((card) => !drawnCardIds.contains(card.id))
        .toList();
    if (available.isEmpty) throw StateError('今日卡池暂无可用卡片');

    final preferred = available
        .where((card) => favoriteIdolIds.contains(card.idolId))
        .toList();
    final pool = preferred.isEmpty ? available : preferred;
    return pool[Random().nextInt(pool.length)];
  }
}

class MockScanRepository implements ScanRepository {
  final List<ScanFeedbackRecord> _feedback = [];
  @override
  Future<ScanFeedbackPageData> fetchFeedbackHistory({int offset = 0}) async =>
      ScanFeedbackPageData(
        items: _feedback.skip(offset).take(20).toList(),
        nextOffset: _feedback.length > offset + 20 ? offset + 20 : null,
      );
  @override
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> confirmations,
  ) async => null;

  @override
  Future<ScanSession> recognize({String? localImagePath}) async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final cards = DemoCatalog.cards;
    ScanCandidate candidate(int index, double similarity) =>
        ScanCandidate(card: cards[index], similarity: similarity);

    return ScanSession(
      id: 'scan-${DateTime.now().millisecondsSinceEpoch}',
      originalImagePath: localImagePath,
      detectedCards: [
        DetectedScanCard(
          id: 'detected-01',
          cropRegion: const ScanCropRegion(
            x: .08,
            y: .08,
            width: .38,
            height: .39,
          ),
          candidates: [candidate(0, .96), candidate(1, .72), candidate(2, .61)],
          status: ScanRecognitionStatus.recommended,
        ),
        DetectedScanCard(
          id: 'detected-02',
          cropRegion: const ScanCropRegion(
            x: .54,
            y: .07,
            width: .38,
            height: .4,
          ),
          candidates: [candidate(1, .92), candidate(0, .74), candidate(4, .66)],
          status: ScanRecognitionStatus.recommended,
        ),
        DetectedScanCard(
          id: 'detected-03',
          cropRegion: const ScanCropRegion(
            x: .08,
            y: .53,
            width: .38,
            height: .39,
          ),
          candidates: [candidate(3, .81), candidate(4, .76), candidate(0, .65)],
          status: ScanRecognitionStatus.needsConfirmation,
        ),
        DetectedScanCard(
          id: 'detected-04',
          cropRegion: const ScanCropRegion(
            x: .54,
            y: .53,
            width: .38,
            height: .39,
          ),
          candidates: [candidate(5, .44), candidate(6, .39)],
          status: ScanRecognitionStatus.unrecognized,
        ),
      ],
    );
  }

  @override
  Future<void> submitFeedback(ScanFeedbackRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    String? sourceName;
    String? sourceVersionName;
    for (final album in DemoCatalog.albums) {
      if (request.sourceEntityType != 'ALBUM' ||
          album.id != request.sourceEntityId) {
        continue;
      }
      sourceName = album.displayName;
      for (var index = 0; index < album.versions.length; index++) {
        if (request.sourceVersionId == 'mock-${album.id}-version-$index') {
          sourceVersionName = album.versions[index];
        }
      }
    }
    for (final event in DemoCatalog.events) {
      if (request.sourceEntityType == 'EVENT' &&
          event.id == request.sourceEntityId) {
        sourceName = event.displayName;
      }
    }
    for (final others in DemoCatalog.others) {
      if (request.sourceEntityType == 'OTHER' &&
          others.id == request.sourceEntityId) {
        sourceName = others.displayName;
      }
    }
    _feedback.insert(
      0,
      ScanFeedbackRecord(
        id: 'feedback-${DateTime.now().microsecondsSinceEpoch}',
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        cropImageUrl: request.originalImagePath,
        source: request.source,
        sourceMode: request.sourceMode,
        sourceEntityType: request.sourceEntityType,
        sourceEntityId: request.sourceEntityId,
        sourceVersionId: request.sourceVersionId,
        sourceName: sourceName,
        sourceVersionName: sourceVersionName,
        notes: request.notes,
      ),
    );
  }
}

class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(this._client);
  final ApiClient _client;

  @override
  Future<CatalogBundle> fetchCatalog() async {
    final data =
        await _client.getData('/catalog/bootstrap') as Map<String, dynamic>;
    return CatalogBundle(
      idols: (data['idols'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(IdolProfile.fromJson)
          .toList(),
      groups: (data['groups'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(FanGroup.fromJson)
          .toList(),
      cards: (data['cards'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(CollectibleCard.fromJson)
          .toList(),
      albums: data['albums'] is List<dynamic>
          ? (data['albums'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map(CatalogAlbum.fromJson)
                .toList()
          : DemoCatalog.albums,
      events: data['events'] is List<dynamic>
          ? (data['events'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map(CatalogEvent.fromJson)
                .toList()
          : DemoCatalog.events,
      others: data['others'] is List<dynamic>
          ? (data['others'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map(CatalogOther.fromJson)
                .toList()
          : const <CatalogOther>[],
    );
  }
}

class ApiDailyCardRepository implements DailyCardRepository {
  ApiDailyCardRepository(this._client);
  final ApiClient _client;

  @override
  Future<CollectibleCard> draw({
    required List<String> drawnCardIds,
    required List<String> favoriteIdolIds,
  }) async {
    final data = await _client.postData(
      '/daily-cards/draw',
      data: {
        'draw_request_id': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    ) as Map<String, dynamic>;
    return CollectibleCard.fromJson(data['card'] as Map<String, dynamic>);
  }
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._client);
  final ApiClient _client;

  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {
    final data = await _client.postData(
      '/auth/login',
      data: {'method': method.name, 'phone': phone, 'code': code},
    ) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException('INVALID_AUTH_RESPONSE', '登录服务返回格式异常');
    }
    _client.setAccessToken(accessToken);
  }
}

class ApiScanRepository implements ScanRepository {
  ApiScanRepository(this._client);
  final ApiClient _client;

  @override
  Future<ScanFeedbackPageData> fetchFeedbackHistory({int offset = 0}) async {
    final data = await _client.getData(
      '/scan/feedback',
      query: {'offset': offset},
    ) as Map<String, dynamic>;
    return ScanFeedbackPageData(
      items: (data['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ScanFeedbackRecord.fromJson)
          .toList(),
      nextOffset: (data['next_offset'] as num?)?.toInt(),
    );
  }

  @override
  Future<Map<String, int>?> confirm(
    String sessionId,
    List<ScanConfirmation> confirmations,
  ) async {
    final response = await _client.postData(
      '/scan/sessions/$sessionId/confirm',
      data: {'cards': confirmations.map((item) => item.toJson()).toList()},
    ) as Map<String, dynamic>;
    return (response['quantities'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );
  }

  @override
  Future<ScanSession> recognize({String? localImagePath}) async {
    if (localImagePath == null) {
      throw ArgumentError(
        'AI Scan requires an image when the real API is enabled.',
      );
    }
    final data = await _client.postData(
      '/scan/recognize',
      receiveTimeout: const Duration(seconds: 120),
      data: FormData.fromMap({
        'image': await MultipartFile.fromFile(
          localImagePath,
          filename: 'scan-card.jpg',
        ),
      }),
    ) as Map<String, dynamic>;
    return ScanSession.fromJson(data, localImagePath: localImagePath);
  }

  @override
  Future<void> submitFeedback(ScanFeedbackRequest request) async {
    final payload = <String, dynamic>{'metadata': jsonEncode(request.toJson())};
    if (request.originalImagePath != null &&
        !request.originalImagePath!.startsWith('http')) {
      payload['original_image'] = await MultipartFile.fromFile(
        request.originalImagePath!,
        filename: 'scan-original.jpg',
      );
    }
    await _client.postData('/scan/feedback', data: FormData.fromMap(payload));
  }
}

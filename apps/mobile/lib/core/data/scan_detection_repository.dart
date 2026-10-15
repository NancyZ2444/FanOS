import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';

/// Detection has no candidates and never writes Owned / Wishlist.
class ScanDetection {
  const ScanDetection({
    required this.sessionId,
    required this.regions,
    this.imagePath,
    this.aspectRatio,
  });
  final String sessionId;
  final String? imagePath;
  final double? aspectRatio;
  final List<DetectedScanCard> regions;

  factory ScanDetection.fromJson(Map<String, dynamic> json) {
    final session = ScanSession.fromJson(json);
    return ScanDetection(
      sessionId: session.id,
      regions: session.detectedCards,
      imagePath: session.originalImagePath,
      aspectRatio:
          (json['image_width'] as num? ?? 0) > 0 &&
              (json['image_height'] as num? ?? 0) > 0
          ? (json['image_width'] as num) / (json['image_height'] as num)
          : null,
    );
  }
}

abstract interface class ScanDetectionRepository {
  Future<ScanDetection> detect(String? localImagePath);
  Future<ScanSession> recognize(
    ScanDetection detection,
    Set<String> selectedIds,
  );
}

final scanDetectionRepositoryProvider = Provider<ScanDetectionRepository>(
  (ref) => useMockApi
      ? MockScanDetectionRepository()
      : ApiScanDetectionRepository(ref.watch(apiClientProvider)),
);

class ApiScanDetectionRepository implements ScanDetectionRepository {
  ApiScanDetectionRepository(this.client);
  final ApiClient client;
  @override
  Future<ScanDetection> detect(String? localImagePath) async {
    if (localImagePath == null) throw ArgumentError('An image is required');
    final data = await _scanRequest(
      () async => client.postData(
        '/scan/detect',
        data: FormData.fromMap({
          'image': await MultipartFile.fromFile(localImagePath),
        }),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return ScanDetection.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<ScanSession> recognize(
    ScanDetection detection,
    Set<String> selectedIds,
  ) async {
    if (selectedIds.isEmpty) throw ArgumentError('Select at least one card');
    final data = await _scanRequest(
      () => client.postData(
        '/scan/sessions/${detection.sessionId}/recognize',
        data: {'detected_card_ids': selectedIds.toList()},
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    return ScanSession.fromJson(data as Map<String, dynamic>);
  }

  Future<dynamic> _scanRequest(Future<dynamic> Function() operation) async {
    try {
      return await operation();
    } on ApiException catch (error) {
      if (const {
        'HTTP_NOT_FOUND',
        'HTTP_METHOD_NOT_ALLOWED',
      }.contains(error.code)) {
        throw ApiException(
          'SCAN_API_UPGRADE_REQUIRED',
          '云端扫描接口尚未更新，请联系管理员部署扫描服务后重试。照片已保留，无需重新拍摄。',
          statusCode: error.statusCode,
        );
      }
      rethrow;
    }
  }
}

class MockScanDetectionRepository implements ScanDetectionRepository {
  @override
  Future<ScanDetection> detect(String? localImagePath) async => ScanDetection(
    sessionId: 'demo-detection',
    imagePath: localImagePath,
    regions: List.generate(
      4,
      (i) => DetectedScanCard(
        id: 'detected-0${i + 1}',
        cropRegion: ScanCropRegion(
          x: i.isEven ? .08 : .54,
          y: i < 2 ? .08 : .53,
          width: .38,
          height: .39,
        ),
        candidates: const [],
        status: ScanRecognitionStatus.unrecognized,
      ),
    ),
  );

  @override
  Future<ScanSession> recognize(
    ScanDetection detection,
    Set<String> selectedIds,
  ) async {
    final session = await MockScanRepository().recognize(
      localImagePath: detection.imagePath,
    );
    return ScanSession(
      id: session.id,
      originalImagePath: session.originalImagePath,
      detectedCards: session.detectedCards
          .where((card) => selectedIds.contains(card.id))
          .toList(),
    );
  }
}

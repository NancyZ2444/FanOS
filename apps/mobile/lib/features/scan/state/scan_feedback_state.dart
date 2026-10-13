import 'package:fan_os/core/data/scan_feedback_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final scanFeedbackOptionsRepositoryProvider =
    Provider<ScanFeedbackOptionsRepository>((ref) {
      if (useMockApi) return MockScanFeedbackOptionsRepository();
      return ApiScanFeedbackOptionsRepository(ref.watch(apiClientProvider));
    });

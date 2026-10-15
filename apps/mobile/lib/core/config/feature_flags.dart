import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Release UI gate only. Server aggregation, stored posts and preferences stay intact.
const idolFeedEnabled = bool.fromEnvironment(
  'ENABLE_IDOL_FEED',
  defaultValue: false,
);
final idolFeedEnabledProvider = Provider<bool>((ref) => idolFeedEnabled);

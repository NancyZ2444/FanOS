import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory navigation state only. A different login invalidates the cache;
/// nothing here implies that a collection relationship has been saved.
final spatialScanCacheProvider = Provider((ref) {
  ref.watch(sessionProvider.select((s) => (s.userId, s.isLoggedIn)));
  return <String, SpatialScanState>{};
});

enum SpatialMatchState {
  recommended,
  needsConfirmation,
  unmatched,
  confirmed,
  failed,
}

class SpatialScanObject {
  SpatialScanObject(this.detected) {
    final confirmedId = detected.userConfirmedCardId;
    for (final candidate in detected.candidates) {
      if (candidate.card.id == confirmedId) {
        chosen = candidate;
        confirmed = true;
        // The API appends manual catalog choices with zero and no AI scores.
        manuallySearched =
            candidate.similarity == 0 && candidate.scores.isEmpty;
        break;
      }
    }
    if (chosen == null &&
        detected.status == ScanRecognitionStatus.recommended &&
        detected.topCandidate?.isApproximate == false) {
      chosen = detected.topCandidate;
    }
  }

  DetectedScanCard detected;
  ScanCandidate? chosen;
  bool confirmed = false;
  bool manuallySearched = false;
  bool choosing = false;
  bool feedbackSubmitted = false;
  String? error;

  int get scanQuarterTurns {
    final value = chosen?.scores['display_rotation_quarter_turns'];
    if (value != null &&
        value.isFinite &&
        value >= 0 &&
        value <= 3 &&
        value == value.roundToDouble()) {
      return value.toInt();
    }
    return detected.displayRotationQuarterTurns;
  }

  /// Candidates are only those returned by the server, keyed by catalog ID.
  /// A manual search choice is not a fabricated AI alternative.
  List<ScanCandidate> get candidates {
    final unique = <String, ScanCandidate>{};
    for (final candidate in detected.candidates) {
      if (candidate.card.id == detected.userConfirmedCardId &&
          candidate.similarity == 0 &&
          candidate.scores.isEmpty) {
        continue;
      }
      final existing = unique[candidate.card.id];
      if (existing == null || candidate.similarity > existing.similarity) {
        unique[candidate.card.id] = candidate;
      }
    }
    return unique.values.toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
  }

  bool get hasOtherCandidates =>
      candidates.any((candidate) => candidate.card.id != chosen?.card.id);

  void chooseOtherCandidate() {
    choosing = true;
    manuallySearched = false;
    confirmed = false;
    chosen = null;
    error = null;
  }

  SpatialMatchState get matchState {
    if (!choosing && confirmed && chosen != null) {
      return SpatialMatchState.confirmed;
    }
    if (detected.matchingFailed && chosen == null) {
      return SpatialMatchState.failed;
    }
    if (!choosing &&
        !manuallySearched &&
        chosen != null &&
        detected.status == ScanRecognitionStatus.recommended &&
        !chosen!.isApproximate) {
      return SpatialMatchState.recommended;
    }
    return detected.candidates.isNotEmpty || chosen != null
        ? SpatialMatchState.needsConfirmation
        : SpatialMatchState.unmatched;
  }

  bool get canSave =>
      !choosing &&
      (matchState == SpatialMatchState.recommended ||
          matchState == SpatialMatchState.confirmed);

  void select(ScanCandidate candidate, {bool searched = false}) {
    chosen = candidate;
    manuallySearched = searched;
    confirmed = false;
    choosing = true;
    error = null;
  }

  void replaceFailedDetection(DetectedScanCard value) {
    if (!detected.matchingFailed) return;
    detected = value;
    error = null;
    if (!confirmed &&
        !manuallySearched &&
        !choosing &&
        value.status == ScanRecognitionStatus.recommended &&
        value.topCandidate?.isApproximate == false) {
      chosen = value.topCandidate;
    }
  }
}

class SpatialScanState {
  SpatialScanState(ScanSession session)
    : objects = [
        for (final item in session.detectedCards) SpatialScanObject(item),
      ],
      selectedId = session.detectedCards.firstOrNull?.id;

  // Server order is retained for the entire session, never sorted by status.
  final List<SpatialScanObject> objects;
  String? selectedId;
  double panelExtent = .36;
  bool panelExpanded = false;
  double thumbnailOffset = 0;
  Matrix4 transform = Matrix4.identity();
  SpatialPhotoView photoView = const SpatialPhotoView();
  bool positioned = false;
  bool busy = false;

  SpatialScanObject? get current =>
      objects.where((item) => item.detected.id == selectedId).firstOrNull;
  int numberOf(String id) =>
      objects.indexWhere((item) => item.detected.id == id) + 1;
  int get failedCount => objects
      .where((item) => item.matchState == SpatialMatchState.failed)
      .length;

  void mergeRetry(ScanSession result) {
    final byId = {
      for (final detected in result.detectedCards) detected.id: detected,
    };
    for (final item in objects) {
      final replacement = byId[item.detected.id];
      if (replacement != null) item.replaceFailedDetection(replacement);
    }
  }

  (int, int, int) get counts {
    var matched = 0, pending = 0, missing = 0;
    for (final item in objects) {
      switch (item.matchState) {
        case SpatialMatchState.confirmed:
        case SpatialMatchState.recommended:
          matched++;
        case SpatialMatchState.needsConfirmation:
          pending++;
        case SpatialMatchState.unmatched:
          missing++;
        case SpatialMatchState.failed:
          break;
      }
    }
    return (matched, pending, missing);
  }
}

/// A photo view in image-relative coordinates, independent of drawer height.
/// Automatic drawer occlusion adjustments must not overwrite the user's view.
class SpatialPhotoView {
  const SpatialPhotoView({this.center = const Offset(.5, .5), this.zoom = 1});
  final Offset center;
  final double zoom;

  static double _fitScale(Size viewport, Size image) =>
      (viewport.width / image.width) < (viewport.height / image.height)
      ? viewport.width / image.width
      : viewport.height / image.height;

  factory SpatialPhotoView.fromTransform(
    Matrix4 transform,
    Size viewport,
    Size image,
  ) {
    if (viewport.isEmpty || image.isEmpty) return const SpatialPhotoView();
    final scale = transform.getMaxScaleOnAxis();
    if (scale <= 0 || !scale.isFinite) return const SpatialPhotoView();
    return SpatialPhotoView(
      center: Offset(
        (viewport.width / 2 - transform.storage[12]) / scale / image.width,
        (viewport.height / 2 - transform.storage[13]) / scale / image.height,
      ),
      zoom: scale / _fitScale(viewport, image),
    );
  }

  Matrix4 transformFor(Size viewport, Size image) {
    if (viewport.isEmpty || image.isEmpty) return Matrix4.identity();
    final scale = (_fitScale(viewport, image) * zoom).clamp(.05, 8.0);
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, viewport.width / 2 - center.dx * image.width * scale)
      ..setEntry(1, 3, viewport.height / 2 - center.dy * image.height * scale);
  }
}

/// Translate only as much as needed, keeping the selected detection inside the
/// actual unobscured viewport. Reduce zoom only when that detection cannot fit.
Matrix4 keepSpatialObjectVisible(Matrix4 current, Rect object, Size viewport) {
  if (viewport.isEmpty || object.isEmpty) return current.clone();
  const margin = 12.0;
  final availableWidth = (viewport.width - margin * 2).clamp(
    1.0,
    double.infinity,
  );
  final availableHeight = (viewport.height - margin * 2).clamp(
    1.0,
    double.infinity,
  );
  var scale = current.getMaxScaleOnAxis();
  scale = scale.clamp(.05, 8.0);
  scale = scale.clamp(.05, (availableWidth / object.width).clamp(.05, 8.0));
  scale = scale.clamp(.05, (availableHeight / object.height).clamp(.05, 8.0));
  var dx = current.storage[12];
  var dy = current.storage[13];
  if (object.left * scale + dx < margin) dx = margin - object.left * scale;
  if (object.right * scale + dx > viewport.width - margin) {
    dx = viewport.width - margin - object.right * scale;
  }
  if (object.top * scale + dy < margin) dy = margin - object.top * scale;
  if (object.bottom * scale + dy > viewport.height - margin) {
    dy = viewport.height - margin - object.bottom * scale;
  }
  return Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(2, 2, scale)
    ..setEntry(0, 3, dx)
    ..setEntry(1, 3, dy);
}

import 'dart:collection';
import '../models/observation.dart';
import 'nms.dart';

// ---------------------------------------------------------------------------
// Tracked detection — extends Detection with tracking metadata
// ---------------------------------------------------------------------------

class TrackedDetection {
  TrackedDetection({
    required this.detection,
    required this.firstSeenFrame,
    this.hitCount = 1,
  }) : smoothedConfidence = detection.confidence;

  Detection detection;
  final int firstSeenFrame;
  int hitCount;
  double smoothedConfidence;

  /// Number of consecutive frames this detection has been persistent.
  int get age => hitCount;

  Detection get stableDetection => Detection(
    agent: detection.agent,
    classCode: detection.classCode,
    confidence: smoothedConfidence,
    box: detection.box,
  );
}

// ---------------------------------------------------------------------------
// Temporal smoother
// ---------------------------------------------------------------------------

/// Maintains a short history of per-frame detections and applies:
///   1. IoU-based cross-frame matching
///   2. Exponential moving-average confidence smoothing
///   3. Persistence gating (only surfaces detection after [minHitCount] frames)
///   4. Stale-detection expiry after [maxMissedFrames] frames
///
/// All methods are synchronous and run on the inference isolate.
class TemporalSmoother {
  TemporalSmoother({
    this.matchIouThreshold = 0.35,
    this.confidenceAlpha   = 0.6,    // EMA weight for current frame
    this.minHitCount       = 2,      // frames before detection is surfaced
    this.maxMissedFrames   = 5,      // frames before stale detection is purged
  });

  final double matchIouThreshold;
  final double confidenceAlpha;
  final int    minHitCount;
  final int    maxMissedFrames;

  final _tracks = <TrackedDetection>[];
  final _lastSeenFrame = HashMap<TrackedDetection, int>();
  int _currentFrame = 0;

  // ── Update ────────────────────────────────────────────────────────────────

  /// Ingests a new frame's detections and returns the stable, smoothed list.
  List<Detection> update(List<Detection> frameDetections) {
    _currentFrame++;

    // Match existing tracks to new detections using greedy IoU
    final matched = <TrackedDetection, Detection>{};
    final unmatchedNew = <Detection>[...frameDetections];

    for (final track in _tracks) {
      Detection? bestMatch;
      double bestIou = matchIouThreshold;
      for (final d in unmatchedNew) {
        if (d.classCode != track.detection.classCode) continue;
        final iou = computeIou(d.box, track.detection.box);
        if (iou > bestIou) {
          bestIou = iou;
          bestMatch = d;
        }
      }
      if (bestMatch != null) {
        matched[track] = bestMatch;
        unmatchedNew.remove(bestMatch);
      }
    }

    // Update matched tracks
    for (final entry in matched.entries) {
      final track = entry.key;
      final det   = entry.value;
      track.detection = det;
      track.hitCount++;
      track.smoothedConfidence =
          confidenceAlpha * det.confidence +
          (1 - confidenceAlpha) * track.smoothedConfidence;
      _lastSeenFrame[track] = _currentFrame;
    }

    // Create new tracks for unmatched detections
    for (final d in unmatchedNew) {
      final track = TrackedDetection(
        detection: d,
        firstSeenFrame: _currentFrame,
        );
      _tracks.add(track);
      _lastSeenFrame[track] = _currentFrame;
    }

    // Expire stale tracks
    _tracks.removeWhere((track) {
      final lastSeen = _lastSeenFrame[track] ?? 0;
      return (_currentFrame - lastSeen) > maxMissedFrames;
    });

    // Surface only detections that have persisted for minHitCount frames
    return _tracks
        .where((t) => t.hitCount >= minHitCount)
        .map((t) => t.stableDetection)
        .toList();
  }

  /// Clears all tracked state (call when camera is paused / mode changes).
  void reset() {
    _tracks.clear();
    _lastSeenFrame.clear();
    _currentFrame = 0;
  }

  /// Returns all currently tracked detections regardless of persistence gate.
  /// Useful for debugging / diagnostics.
  List<Detection> get allTracked =>
      _tracks.map((t) => t.stableDetection).toList();

  int get trackCount => _tracks.length;
  int get frameCount => _currentFrame;
}

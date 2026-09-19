/// Pure helpers for video frame sampling. No plugins, fully unit-testable.
class VideoSampling {
  const VideoSampling._();

  /// Returns timestamps in milliseconds at [intervalMs], capped at [maxFrames].
  ///
  /// Always includes t=0 when duration is positive. If the interval would
  /// produce more than [maxFrames] samples, the interval is stretched so the
  /// whole video is covered rather than only the first N seconds.
  static List<int> timestampsMs({
    required int durationMs,
    required int intervalMs,
    int maxFrames = 40,
  }) {
    if (durationMs <= 0) return const [];
    if (intervalMs <= 0) {
      throw ArgumentError('intervalMs must be positive');
    }
    if (maxFrames <= 0) return const [];

    var step = intervalMs;
    final unconstrained = (durationMs / step).ceil();
    if (unconstrained > maxFrames) {
      step = (durationMs / maxFrames).ceil().clamp(1, durationMs);
    }

    final out = <int>[];
    for (var t = 0; t < durationMs && out.length < maxFrames; t += step) {
      out.add(t);
    }
    if (out.isEmpty) out.add(0);
    return out;
  }

  static const supportedExtensions = {
    '.mp4',
    '.mov',
    '.m4v',
    '.avi',
    '.mkv',
    '.webm',
    '.3gp',
  };

  static bool isSupportedPath(String path) {
    final lower = path.toLowerCase();
    return supportedExtensions.any(lower.endsWith);
  }
}

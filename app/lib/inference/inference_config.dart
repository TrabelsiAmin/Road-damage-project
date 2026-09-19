import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

/// Runtime inference thresholds. Loaded from SharedPreferences and read by
/// the TFLite runner on each detect so Settings take effect without a restart.
///
/// Letterbox geometry is **not** configurable here — the model contract is
/// Ultralytics letterbox (pad 114) + inverse mapping.
class InferenceConfig {
  InferenceConfig({
    this.confidenceThreshold = TariqMapConstants.defaultConfidenceThreshold,
    this.iouThreshold = TariqMapConstants.defaultIouThreshold,
    this.classAwareNms = true,
    this.maxDetections = TariqMapConstants.defaultMaxDetections,
    this.minBoxArea = TariqMapConstants.defaultMinBoxArea,
    this.liveFps = TariqMapConstants.defaultLiveFps,
  });

  static InferenceConfig instance = InferenceConfig();
  static bool _loaded = false;

  double confidenceThreshold;
  double iouThreshold;
  bool classAwareNms;
  int maxDetections;
  double minBoxArea;
  int liveFps;

  static const confidenceKey = 'confidence_threshold';
  static const iouKey = 'iou_threshold';
  static const classAwareKey = 'class_aware_nms';
  static const maxDetectionsKey = 'max_detections';
  static const liveFpsKey = 'live_fps';

  static Future<InferenceConfig> ensureLoaded() async {
    if (_loaded) return instance;
    final prefs = await SharedPreferences.getInstance();
    instance.confidenceThreshold = prefs.getDouble(confidenceKey) ??
        TariqMapConstants.defaultConfidenceThreshold;
    instance.iouThreshold =
        prefs.getDouble(iouKey) ?? TariqMapConstants.defaultIouThreshold;
    instance.classAwareNms = prefs.getBool(classAwareKey) ?? true;
    instance.maxDetections =
        prefs.getInt(maxDetectionsKey) ?? TariqMapConstants.defaultMaxDetections;
    instance.liveFps =
        prefs.getInt(liveFpsKey) ?? TariqMapConstants.defaultLiveFps;
    _loaded = true;
    return instance;
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(confidenceKey, confidenceThreshold);
    await prefs.setDouble(iouKey, iouThreshold);
    await prefs.setBool(classAwareKey, classAwareNms);
    await prefs.setInt(maxDetectionsKey, maxDetections);
    await prefs.setInt(liveFpsKey, liveFps);
  }

  /// Approximate camera-stream skip from a target inference FPS (30 fps preview).
  int get cameraFrameSkip {
    final fps = liveFps.clamp(1, 15);
    return (30 / fps).round().clamp(1, 30);
  }

  /// Unit-test helper. Marks the singleton as loaded so tests do not hit plugins.
  static void resetForTest([InferenceConfig? cfg]) {
    instance = cfg ?? InferenceConfig();
    _loaded = true;
  }

  /// Unit-test helper so [ensureLoaded] actually reads mock SharedPreferences.
  static void markUnloadedForTest() {
    instance = InferenceConfig();
    _loaded = false;
  }
}

/// Canonical TariqMap class contract.
///
/// All D-codes, labels, agent assignments, and severity weights are defined
/// here once and imported everywhere else.  Changing a label requires only
/// editing this file.
class TariqMapConstants {
  TariqMapConstants._();

  // ── Canonical D-code list (ordered: cracks → pavement → surface) ─────────
  static const allCodes = <String>['D00', 'D10', 'D20', 'D40'];

  // ── Agent → class mapping ────────────────────────────────────────────────
  static const agentClasses = <String, List<String>>{
    'road_damage': ['D00', 'D10', 'D20', 'D40'],
  };

  // ── Human-readable labels ────────────────────────────────────────────────
  static const labels = <String, String>{
    'D00': 'Longitudinal Crack',
    'D10': 'Transverse Crack',
    'D20': 'Alligator Crack',
    'D40': 'Pothole',
  };

  /// French labels (ready for i18n expansion)
  static const labelsFr = <String, String>{
    'D00': 'Fissure longitudinale',
    'D10': 'Fissure transversale',
    'D20': 'Faïençage',
    'D40': 'Nid-de-poule',
  };

  // ── Priority weight per class (used in Observation.priorityScore) ─────────
  static const severityWeights = <String, double>{
    'D40': 1.00,  // Pothole — highest safety risk
    'D20': 0.90,  // Alligator crack — structural degradation
    'D00': 0.70,  // Longitudinal crack
    'D10': 0.70,  // Transverse crack
    'D90': 0.65,  // Rutting (visual only)
    'D50': 0.50,  // Faded crossing
    'D60': 0.50,  // Faded lane
  };

  // ── Actor names ──────────────────────────────────────────────────────────
  static const actors = <String>[
    'Municipality',
    'Ministry of Equipment',
    'Tunisia Autoroutes',
  ];

  // ── Model bundle ─────────────────────────────────────────────────────────
  static const modelBundleAsset = 'assets/models/model-bundles.json';
  static const modelBundleVersion = '2026.09.23-rdd2022';

  // ── Inference defaults ───────────────────────────────────────────────────
  static const defaultConfidenceThreshold = 0.35;
  static const defaultIouThreshold = 0.45;
  static const defaultLiveFps = 5;  // frames per second for live inference

  // ── RoadSense Hybrid Configuration (Feature Flags - Default OFF) ─────────
  /// When true, enables the hybrid pipeline using RoadSense for cracks
  /// (D00, D10, D20) and legacy model for potholes (D40).
  static const bool useRoadSenseModel =
      bool.fromEnvironment('USE_ROADSENSE_MODEL', defaultValue: false);

  /// When [useRoadSenseModel] is true, determines whether the legacy model is
  /// run alongside RoadSense to provide D40 (pothole) detections.
  static const bool usePotholeModelForD40 =
      bool.fromEnvironment('USE_POTHOLE_MODEL_FOR_D40', defaultValue: true);

  /// When true and running hybrid, drops legacy D40 detections if a RoadSense
  /// "Repair" box overlaps it with IoU > 0.5 (filters patched-asphalt false potholes).
  /// Defaults to false.
  static const bool filterPotholesWithRepair = false;

  /// Separate confidence threshold for D40 pothole detections from the legacy model.
  static const double d40ConfidenceThreshold = 0.40;

  /// Video frame-skip factor for the pothole model in video mode (run every N frames).
  /// Default 1 (run on every frame).
  static const int potholeModelFrameSkip = 1;

  /// Model asset paths
  static const String legacyModelAsset = 'assets/models/road_damage.tflite';
  static const String roadSenseModelAsset = 'assets/models/road_damage_roadsense.tflite';

  /// RoadSense confidence thresholds
  static const double roadSenseD00Threshold = 0.35;
  static const double roadSenseD10Threshold = 0.35;
  static const double roadSenseD20Threshold = 0.30;
  static const double roadSenseRepairThreshold = 0.25;

  // ── Sync ────────────────────────────────────────────────────────────────
  static const maxUploadRetries = 5;
  static const retryBackoffBase = Duration(seconds: 2);

  // ── Label helpers ────────────────────────────────────────────────────────
  static String labelFor(String code, {bool french = false}) =>
      (french ? labelsFr[code] : labels[code]) ?? code;

  static String agentFor(String code) =>
      agentClasses.entries
          .firstWhere(
            (e) => e.value.contains(code),
            orElse: () => const MapEntry('unknown', <String>[]),
          )
          .key;
}

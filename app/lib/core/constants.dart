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

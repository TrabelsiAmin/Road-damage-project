/// Canonical TariqMap class contract.
///
/// All D-codes, labels, agent assignments, and severity weights are defined
/// here once and imported everywhere else.  Changing a label requires only
/// editing this file.
class TariqMapConstants {
  TariqMapConstants._();

  // ── Canonical D-code list (ordered: cracks → pavement → surface) ─────────
  static const allCodes = <String>['D00', 'D10', 'D20', 'D40', 'D50', 'D60', 'D90'];

  // ── Agent → class mapping ────────────────────────────────────────────────
  static const agentClasses = <String, List<String>>{
    'cracks':   ['D00', 'D10'],
    'pavement': ['D20', 'D40'],
    'surface':  ['D50', 'D60', 'D90'],
  };

  // ── Human-readable labels ────────────────────────────────────────────────
  static const labels = <String, String>{
    'D00': 'Longitudinal Crack',
    'D10': 'Transverse Crack',
    'D20': 'Alligator Crack',
    'D40': 'Pothole',
    'D50': 'Faded Crossing',
    'D60': 'Faded Lane',
    'D90': 'Rutting',
  };

  /// French labels (ready for i18n expansion)
  static const labelsFr = <String, String>{
    'D00': 'Fissure longitudinale',
    'D10': 'Fissure transversale',
    'D20': 'Faïençage',
    'D40': 'Nid-de-poule',
    'D50': 'Marquage piéton effacé',
    'D60': 'Marquage de voie effacé',
    'D90': 'Orniérage visuel',
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
  static const modelBundleVersion = '2026.09.0-demo';

  // ── Inference defaults ───────────────────────────────────────────────────
  static const defaultConfidenceThreshold = 0.35;
  static const defaultIouThreshold = 0.45;
  static const defaultLiveFps = 5;  // frames per second for live inference
  static const defaultMaxDetections = 50;
  static const defaultMinBoxArea = 1e-6; // normalised w*h; drop specks after inverse letterbox

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

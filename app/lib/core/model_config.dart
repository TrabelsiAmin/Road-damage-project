import 'constants.dart';

/// Central model configuration defining active, legacy, and experimental models.
class ModelConfig {
  const ModelConfig({
    required this.name,
    required this.displayName,
    required this.version,
    required this.assetPath,
    required this.inputWidth,
    required this.inputHeight,
    required this.classes,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.isExperimental,
    required this.isActive,
    required this.statusDescription,
    this.sha256Checksum,
  });

  /// Internal model identifier (e.g. 'road_damage' or 'road_damage_roadsense')
  final String name;

  /// User-facing display name
  final String displayName;

  /// Semantic bundle version (e.g. '2026.09.23-rdd2022')
  final String version;

  /// Asset file path
  final String assetPath;

  /// Input tensor dimensions
  final int inputWidth;
  final int inputHeight;

  /// Supported pathology classes
  final List<String> classes;

  /// Calibration thresholds
  final double confidenceThreshold;
  final double iouThreshold;

  /// Experimental flag
  final bool isExperimental;

  /// Active status in current execution runtime
  final bool isActive;

  /// User-facing status label
  final String statusDescription;

  /// Expected SHA-256 checksum for integrity validation
  final String? sha256Checksum;

  // ── Canonical Configurations ───────────────────────────────────────────────

  static const legacy = ModelConfig(
    name: 'road_damage',
    displayName: 'RDD2022 legacy model',
    version: TariqMapConstants.modelBundleVersion,
    assetPath: TariqMapConstants.legacyModelAsset,
    inputWidth: 640,
    inputHeight: 640,
    classes: ['D00', 'D10', 'D20', 'D40'],
    confidenceThreshold: TariqMapConstants.defaultConfidenceThreshold,
    iouThreshold: TariqMapConstants.defaultIouThreshold,
    isExperimental: false,
    isActive: !TariqMapConstants.useRoadSenseModel,
    statusDescription: TariqMapConstants.useRoadSenseModel
        ? 'RDD2022 legacy model — INACTIVE / FALLBACK'
        : 'RDD2022 legacy model — ACTIVE',
    sha256Checksum: '830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f',
  );

  static const roadSense = ModelConfig(
    name: 'road_damage_roadsense',
    displayName: 'RoadSense hybrid model',
    version: '2026.10.15-roadsense',
    assetPath: TariqMapConstants.roadSenseModelAsset,
    inputWidth: 640,
    inputHeight: 640,
    classes: ['D00', 'D10', 'D20'],
    confidenceThreshold: TariqMapConstants.roadSenseD00Threshold,
    iouThreshold: TariqMapConstants.defaultIouThreshold,
    isExperimental: true,
    isActive: TariqMapConstants.useRoadSenseModel,
    statusDescription: TariqMapConstants.useRoadSenseModel
        ? 'RoadSense hybrid model — ACTIVE (EXPERIMENTAL)'
        : 'RoadSense hybrid model — EXPERIMENTAL / DISABLED',
    sha256Checksum: '300798be883a7003a1a20f3d13757f9338a8cbec5e0ece9f990a2a5179286ccb',
  );

  /// Currently active model configuration
  static ModelConfig get active =>
      TariqMapConstants.useRoadSenseModel ? roadSense : legacy;

  /// List of all available configurations
  static List<ModelConfig> get all => const [legacy, roadSense];
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../inference/roadsense_decoder.dart';
import '../models/observation.dart';
import 'model_manager.dart';
import 'roadsense_agent_runner.dart';
import 'tflite_agent_runner.dart';

// ---------------------------------------------------------------------------
// Abstract runner interface
// ---------------------------------------------------------------------------

abstract class DetectionAgentRunner {
  String get agentName;
  bool   get isReady;
  bool   get isMock;
  Future<AgentResult> detect(File image);
  void dispose();
}

// ---------------------------------------------------------------------------
// Mock runner — visible, labeled, deterministic
// ---------------------------------------------------------------------------

/// Deterministic mock runner.
///
/// Must ONLY be instantiated in debug/demo mode. The [isMock] flag is
/// always true, which causes the UI to show "DEMO MOCK INFERENCE" banners.
class MockAgentRunner implements DetectionAgentRunner {
  MockAgentRunner(this.agentName, this._mockBoxes);

  @override
  final String agentName;

  @override
  bool get isReady => true;

  @override
  bool get isMock => true;

  final List<_MockDetection> _mockBoxes;

  @override
  void dispose() {}

  @override
  Future<AgentResult> detect(File image) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (kDebugMode) debugPrint('[MOCK:$agentName] detect() on ${image.path}');
    return AgentResult(
      agent: agentName,
      detections: _mockBoxes.map((m) => Detection(
        agent: agentName,
        classCode: m.classCode,
        confidence: m.confidence,
        box: m.box,
      )).toList(),
      isMock: true,
    );
  }
}

class _MockDetection {
  const _MockDetection(this.classCode, this.confidence, this.box);
  final String classCode;
  final double confidence;
  final BoundingBox box;
}

// ---------------------------------------------------------------------------
// Agent definition
// ---------------------------------------------------------------------------

class _AgentDef {
  const _AgentDef(this.name, this.classes);
  final String name;
  final List<String> classes;
}

const _agentDefs = <_AgentDef>[
  _AgentDef('road_damage', ['D00', 'D10', 'D20', 'D40']),
];

// ---------------------------------------------------------------------------
// Detection service
// ---------------------------------------------------------------------------

class DetectionService {
  DetectionService._({
    required List<DetectionAgentRunner> runners,
    this.isHybridActive = false,
    this.isRoadSenseFallback = false,
    this.fallbackReason,
    this.roadSenseRunner,
    this.potholeRunner,
  }) : _runners = runners;

  final List<DetectionAgentRunner> _runners;

  /// True when the hybrid pipeline (RoadSense cracks + legacy potholes) is running.
  final bool isHybridActive;

  /// True when RoadSense model failed to load and the service gracefully fell back
  /// to the legacy model alone.
  final bool isRoadSenseFallback;

  /// Explanatory diagnostic message if fallback was triggered.
  final String? fallbackReason;

  /// The active RoadSense runner when running hybrid.
  final RoadSenseAgentRunner? roadSenseRunner;

  /// The active legacy pothole runner when running hybrid.
  final TFLiteAgentRunner? potholeRunner;

  /// True when ALL runners are mocks (no real TFLite models loaded).
  bool get usingMock => _runners.every((r) => r.isMock);

  /// True when at least one agent is mock but not all (partial degradation).
  bool get partialMock =>
      _runners.any((r) => r.isMock) && !_runners.every((r) => r.isMock);

  List<DetectionAgentRunner> get runners => List.unmodifiable(_runners);

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Async factory — should always be called instead of the default constructor.
  ///
  /// On web: uses mock.
  /// On Android/iOS:
  ///   - If [TariqMapConstants.useRoadSenseModel] is true:
  ///     Attempts to load RoadSense runner and legacy pothole runner.
  ///     If RoadSense fails, gracefully falls back to legacy runner alone.
  ///   - If [TariqMapConstants.useRoadSenseModel] is false (default):
  ///     Loads the legacy pipeline untouched.
  static Future<DetectionService> create() async {
    if (kIsWeb) {
      return DetectionService._(runners: _buildMockRunners());
    }

    // ── Check RoadSense Hybrid Feature Flag ──────────────────────────────────
    if (TariqMapConstants.useRoadSenseModel) {
      return _createHybridService();
    }

    // ── Standard / Legacy pipeline ───────────────────────────────────────────
    return _createLegacyService();
  }

  /// Builds the hybrid pipeline (RoadSense for cracks, legacy model for potholes)
  /// with automatic fallback to legacy model if RoadSense fails to load.
  static Future<DetectionService> _createHybridService() async {
    debugPrint('[DetectionService] Initializing RoadSense hybrid pipeline...');
    try {
      final rsPath = await ModelManager.instance.localModelPath('road_damage_roadsense');
      if (rsPath == null) {
        throw StateError('RoadSense model file could not be retrieved from assets');
      }

      final rsRunner = RoadSenseAgentRunner(
        agentName: 'road_damage_roadsense',
        modelPath: rsPath,
      );

      if (rsRunner.failed) {
        throw StateError(rsRunner.loadError ?? 'RoadSense interpreter initialization failed');
      }

      debugPrint('[DetectionService] RoadSense model loaded successfully.');

      TFLiteAgentRunner? phRunner;
      if (TariqMapConstants.usePotholeModelForD40) {
        final legacyPath = await ModelManager.instance.localModelPath('road_damage');
        if (legacyPath != null) {
          final candidateRunner = TFLiteAgentRunner(
            agentName: 'road_damage_pothole',
            agentClasses: const ['D40'],
            modelPath: legacyPath,
            d40ThresholdOverride: TariqMapConstants.d40ConfidenceThreshold,
            onlyD40: true,
          );
          if (!candidateRunner.failed) {
            phRunner = candidateRunner;
            debugPrint('[DetectionService] Legacy pothole model loaded successfully.');
          } else {
            debugPrint('[DetectionService] Legacy pothole model failed to load: ${candidateRunner.loadError}');
          }
        }
      }

      final activeRunners = <DetectionAgentRunner>[
        rsRunner,
        if (phRunner != null) phRunner,
      ];

      return DetectionService._(
        runners: activeRunners,
        isHybridActive: true,
        roadSenseRunner: rsRunner,
        potholeRunner: phRunner,
      );
    } catch (e) {
      debugPrint('[DetectionService] Hybrid initialization failed: $e. Falling back to legacy model.');
      // Graceful fallback to legacy model alone
      final legacyService = await _createLegacyService(
        fallbackReason: 'RoadSense load failure: $e',
      );
      return legacyService;
    }
  }

  /// Builds the legacy pipeline (single oracl4 road_damage model).
  static Future<DetectionService> _createLegacyService({String? fallbackReason}) async {
    final runners = <DetectionAgentRunner>[];

    for (final def in _agentDefs) {
      final path = await ModelManager.instance.localModelPath(def.name);
      if (path != null) {
        try {
          final runner = await _createTFLiteRunner(def.name, path, def.classes);
          if (runner is TFLiteAgentRunner && runner.failed) {
            throw StateError(runner.loadError ?? 'Interpreter failed');
          }
          runners.add(runner);
          debugPrint('[DetectionService] TFLite loaded: ${def.name}');
          continue;
        } catch (e) {
          debugPrint('[DetectionService] TFLite failed for ${def.name}: $e');
        }
      }
      debugPrint('[DetectionService] Using mock for ${def.name}');
      runners.add(_mockForAgent(def.name, def.classes));
    }

    return DetectionService._(
      runners: runners,
      isHybridActive: false,
      isRoadSenseFallback: fallbackReason != null,
      fallbackReason: fallbackReason,
    );
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  /// Runs all agents on a [File]. In hybrid mode, RoadSense and pothole models
  /// run on the frame and are merged into a single AgentResult.
  Future<List<AgentResult>> detectAll(File image) async {
    if (isHybridActive && roadSenseRunner != null) {
      return _detectHybrid(image: image);
    }

    final sw = Stopwatch()..start();
    final results = await Future.wait(_runners.map((runner) async {
      try {
        return await runner.detect(image);
      } catch (error) {
        debugPrint('[DetectionService] Agent ${runner.agentName} failed: $error');
        return AgentResult(
          agent: runner.agentName,
          detections: const [],
          error: error.toString(),
          isMock: runner.isMock,
        );
      }
    }));
    sw.stop();
    final totalDets = results.expand((r) => r.detections).length;
    debugPrint('[Pipeline:Inference] Produced $totalDets detections (latency: ${sw.elapsedMilliseconds}ms)');
    return results;
  }

  /// Runs all agents on raw image bytes (JPEG/PNG).
  Future<List<AgentResult>> detectAllFromBytes(Uint8List bytes) async {
    if (isHybridActive && roadSenseRunner != null) {
      return _detectHybrid(bytes: bytes);
    }

    final sw = Stopwatch()..start();
    final results = await Future.wait(_runners.map((runner) async {
      try {
        if (runner is TFLiteAgentRunner) {
          return await runner.detectFromBytes(bytes);
        }
        return await runner.detect(File(''));
      } catch (error) {
        debugPrint('[DetectionService] Agent ${runner.agentName} failed: $error');
        return AgentResult(
          agent: runner.agentName,
          detections: const [],
          error: error.toString(),
          isMock: runner.isMock,
        );
      }
    }));
    sw.stop();
    final totalDets = results.expand((r) => r.detections).length;
    debugPrint('[Pipeline:Inference] Produced $totalDets detections (latency: ${sw.elapsedMilliseconds}ms)');
    return results;
  }

  // ── Hybrid Execution & Merging ─────────────────────────────────────────────

  Future<List<AgentResult>> _detectHybrid({File? image, Uint8List? bytes}) async {
    final rs = roadSenseRunner!;
    AgentResult rsResult;

    if (bytes != null) {
      rsResult = await rs.detectFromBytes(bytes);
    } else if (image != null) {
      rsResult = await rs.detect(image);
    } else {
      return const [];
    }

    var potholeDets = <Detection>[];
    int potholeLatency = 0;

    if (potholeRunner != null) {
      AgentResult phResult;
      if (bytes != null) {
        phResult = await potholeRunner!.detectFromBytes(bytes);
      } else {
        phResult = await potholeRunner!.detect(image!);
      }
      potholeLatency = phResult.latencyMs ?? 0;

      var d40Detections = phResult.detections;

      // Optional filter: drop D40 box if RoadSense Repair overlaps with IoU > 0.5
      if (TariqMapConstants.filterPotholesWithRepair && rs.lastRepairDetections.isNotEmpty) {
        d40Detections = RoadSenseDecoder.filterPotholesOverlappingRepairs(
          d40Detections,
          rs.lastRepairDetections,
          iouThreshold: 0.5,
        );
      }
      potholeDets = d40Detections;
    }

    final totalLatency = (rsResult.latencyMs ?? 0) + potholeLatency;

    // Merge both outputs into canonical 'road_damage' AgentResult
    final mergedDetections = <Detection>[
      ...rsResult.detections,
      ...potholeDets,
    ];

    // Ensure all detections use the canonical agent 'road_damage' matching AgentResult.agent
    final canonicalDetections = mergedDetections.map((d) => Detection(
      agent: 'road_damage',
      classCode: d.classCode,
      confidence: d.confidence,
      box: d.box,
      frameIndex: d.frameIndex,
      modelBundleVersion: d.modelBundleVersion.isNotEmpty
          ? d.modelBundleVersion
          : TariqMapConstants.modelBundleVersion,
      timestamp: d.timestamp,
    )).toList();

    debugPrint('[Pipeline:Inference] Produced ${canonicalDetections.length} detections (latency: ${totalLatency}ms)');

    return [
      AgentResult(
        agent: 'road_damage',
        detections: canonicalDetections,
        isMock: false,
        latencyMs: totalLatency,
      ),
    ];
  }

  void dispose() {
    for (final r in _runners) {
      r.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// Mock builders
// ---------------------------------------------------------------------------

List<DetectionAgentRunner> _buildMockRunners() => [
  MockAgentRunner('cracks', const [
    _MockDetection('D00', 0.91, BoundingBox(x: 0.05, y: 0.40, width: 0.55, height: 0.12)),
    _MockDetection('D10', 0.76, BoundingBox(x: 0.62, y: 0.55, width: 0.30, height: 0.10)),
  ]),
  MockAgentRunner('pavement', const [
    _MockDetection('D40', 0.88, BoundingBox(x: 0.20, y: 0.60, width: 0.25, height: 0.20)),
    _MockDetection('D20', 0.72, BoundingBox(x: 0.55, y: 0.30, width: 0.38, height: 0.28)),
  ]),
  MockAgentRunner('surface', const [
    _MockDetection('D60', 0.65, BoundingBox(x: 0.10, y: 0.10, width: 0.80, height: 0.15)),
  ]),
];

DetectionAgentRunner _mockForAgent(String name, List<String> classes) =>
    _buildMockRunners().firstWhere(
      (r) => r.agentName == name,
      orElse: () => MockAgentRunner(name, [
        _MockDetection(
          classes.first,
          0.75,
          const BoundingBox(x: 0.2, y: 0.3, width: 0.4, height: 0.3),
        ),
      ]),
    );

// ---------------------------------------------------------------------------
// TFLite runner factory
// ---------------------------------------------------------------------------

Future<DetectionAgentRunner> _createTFLiteRunner(
    String name, String path, List<String> classes) async {
  return _tfliteRunnerFactory(name, path, classes);
}

Future<DetectionAgentRunner> _tfliteRunnerFactory(
    String name, String path, List<String> classes) async {
  return TFLiteAgentRunner(
    agentName: name,
    agentClasses: classes,
    modelPath: path,
  );
}

import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../core/model_config.dart';
import '../services/detection_service.dart';
import '../services/model_manager.dart';

/// Model status diagnostics screen.
///
/// Shows model strategy, active model configuration, checksum integrity,
/// and per-agent runtime diagnostics.
class ModelStatusScreen extends StatefulWidget {
  const ModelStatusScreen({super.key, required this.service});
  final DetectionService service;

  @override
  State<ModelStatusScreen> createState() => _ModelStatusScreenState();
}

class _ModelStatusScreenState extends State<ModelStatusScreen> {
  Map<String, ModelStatus> _statuses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final statuses = <String, ModelStatus>{};
    for (final runner in widget.service.runners) {
      final path = await ModelManager.instance.localModelPath(runner.agentName);
      final integrityErr = ModelManager.instance.integrityError(runner.agentName);
      final classes = TariqMapConstants.agentClasses[runner.agentName] ??
          (runner.agentName == 'road_damage_roadsense'
              ? const ['D00', 'D10', 'D20']
              : (runner.agentName == 'road_damage_pothole'
                  ? const ['D40']
                  : const <String>[]));
      statuses[runner.agentName] = ModelStatus(
        agentName: runner.agentName,
        isLoaded: runner.isReady && !runner.isMock,
        isMock: runner.isMock,
        filePath: path,
        classes: classes,
        integrityError: integrityErr,
      );
    }
    if (mounted) setState(() { _statuses = statuses; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final allMock = widget.service.usingMock;
    final activeConfig = ModelConfig.active;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Model Status & Diagnostics', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Overall status banner ───────────────────────────────────
                _StatusBanner(
                  allMock: allMock,
                  partial: widget.service.partialMock,
                  isHybrid: widget.service.isHybridActive,
                  isFallback: widget.service.isRoadSenseFallback,
                  fallbackReason: widget.service.fallbackReason,
                ),
                const SizedBox(height: 16),

                // ── Active Model Strategy ───────────────────────────────────
                _InfoCard(
                  title: 'MODEL STRATEGY',
                  children: [
                    _ModelStrategyRow(
                      title: 'RDD2022 legacy model',
                      status: ModelConfig.legacy.statusDescription,
                      isActive: !TariqMapConstants.useRoadSenseModel,
                      isExperimental: false,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _ModelStrategyRow(
                      title: 'RoadSense hybrid model',
                      status: ModelConfig.roadSense.statusDescription,
                      isActive: TariqMapConstants.useRoadSenseModel,
                      isExperimental: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Active Diagnostics ──────────────────────────────────────
                _InfoCard(
                  title: 'ACTIVE MODEL DIAGNOSTICS',
                  children: [
                    _InfoRow('Active Model', activeConfig.displayName),
                    _InfoRow('Active Version', activeConfig.version),
                    _InfoRow('Model File', activeConfig.assetPath.split('/').last),
                    _InfoRow('Input Dimensions', '${activeConfig.inputWidth} × ${activeConfig.inputHeight} × 3'),
                    _InfoRow('Detection Classes', activeConfig.classes.join(', ')),
                    _InfoRow('Confidence Threshold', '${(activeConfig.confidenceThreshold * 100).toInt()}%'),
                    _InfoRow('NMS IoU Threshold', activeConfig.iouThreshold.toString()),
                    _InfoRow('Runtime Execution', allMock ? 'DEMO MOCK RUNNER' : 'ON-DEVICE TFLITE INTERPRETER'),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Per-agent status ────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text('LOADED AGENT RUNNERS', style: TextStyle(
                    color: AppColors.teal, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                ),
                ...widget.service.runners.map((r) =>
                  _AgentCard(status: _statuses[r.agentName], runner: r)),

                const SizedBox(height: 20),

                // ── Known Limitations ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Known Model Limitations',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(height: 6),
                      Text(
                        '• D90 (Rutting) is visual-only — depth cannot be inferred from a single 2D image.\n'
                        '• Confidence thresholds are calibrated on RDD2024. Performance on other domains may differ.\n'
                        '• Night and low-light images are underrepresented in training data.\n'
                        '• RoadSense model is flagged as EXPERIMENTAL and is disabled by default.',
                        style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.allMock,
    required this.partial,
    this.isHybrid = false,
    this.isFallback = false,
    this.fallbackReason,
  });
  final bool allMock;
  final bool partial;
  final bool isHybrid;
  final bool isFallback;
  final String? fallbackReason;

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = allMock
        ? (AppColors.mockWarning, Icons.science_outlined,
           'DEMO MOCK INFERENCE — all agents are running deterministic mocks')
        : isFallback
            ? (Colors.orange, Icons.warning_amber_outlined,
               'TFLite AI (FALLBACK) — RoadSense failed to load; running legacy model alone${fallbackReason != null ? ' ($fallbackReason)' : ''}')
            : isHybrid
                ? (AppColors.syncDone, Icons.verified_outlined,
                   'TFLite AI ACTIVE (HYBRID) — RoadSense (D00/D10/D20) + Legacy (D40)')
                : partial
                    ? (AppColors.partialWarning, Icons.warning_amber_outlined,
                       'PARTIAL REAL — some agents loaded real models, some are mocks')
                    : (AppColors.syncDone, Icons.verified_outlined,
                       'RDD2022 LEGACY MODEL ACTIVE — running on-device TFLite weights');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))),
      ]),
    );
  }
}

class _ModelStrategyRow extends StatelessWidget {
  const _ModelStrategyRow({
    required this.title,
    required this.status,
    required this.isActive,
    required this.isExperimental,
  });

  final String title;
  final String status;
  final bool isActive;
  final bool isExperimental;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (isExperimental) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('EXPERIMENTAL',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.orange)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(status, style: TextStyle(
                  fontSize: 11,
                  color: isActive ? AppColors.syncDone : Colors.black45,
                  fontWeight: FontWeight.w600,
                )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? AppColors.syncDone.withAlpha(25) : Colors.black.withAlpha(12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isActive ? AppColors.syncDone.withAlpha(80) : Colors.black12),
            ),
            child: Text(
              isActive ? 'ACTIVE' : 'DISABLED',
              style: TextStyle(
                color: isActive ? AppColors.syncDone : Colors.black45,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});
  final String       title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(title, style: const TextStyle(
          color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
      ),
      Card(
        elevation: 0, color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Column(children: children),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
      const SizedBox(width: 8),
      Expanded(child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.status, required this.runner});
  final ModelStatus? status;
  final DetectionAgentRunner runner;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();

    final (statusColor, statusText) = s.isMock
        ? (AppColors.mockWarning, 'MOCK')
        : s.isLoaded
            ? (AppColors.syncDone, 'LOADED & VERIFIED')
            : (AppColors.mockWarning, 'FAILED');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(s.agentName.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withAlpha(80)),
                ),
                child: Text(statusText,
                    style: TextStyle(color: statusColor,
                        fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ]),
            const SizedBox(height: 8),
            _Row('Classes', s.classes.join(', ')),
            _Row('Format', s.isMock ? 'Deterministic mock' : 'TFLite float32'),
            _Row('File', s.filePath != null
                ? s.filePath!.split(RegExp(r'[/\\]')).last
                : 'Not loaded'),
            if (s.integrityError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Error: ${s.integrityError}',
                  style: const TextStyle(color: AppColors.mockWarning, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(color: Colors.black45, fontSize: 11)),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ---------------------------------------------------------------------------
// ModelStatus data class
// ---------------------------------------------------------------------------

class ModelStatus {
  const ModelStatus({
    required this.agentName,
    required this.isLoaded,
    required this.isMock,
    required this.filePath,
    required this.classes,
    this.integrityError,
  });
  final String       agentName;
  final bool         isLoaded;
  final bool         isMock;
  final String?      filePath;
  final List<String> classes;
  final String?      integrityError;
}

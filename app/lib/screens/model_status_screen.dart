import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../services/detection_service.dart';
import '../services/model_manager.dart';

/// Model status diagnostics screen.
///
/// Shows per-agent status: loaded vs. mock, version, format, checksum status.
/// Does NOT allow downloading or resetting from here (that's Settings).
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
      statuses[runner.agentName] = ModelStatus(
        agentName: runner.agentName,
        isLoaded:  runner.isReady && !runner.isMock,
        isMock:    runner.isMock,
        filePath:  path,
        classes:   TariqMapConstants.agentClasses[runner.agentName] ?? const [],
      );
    }
    if (mounted) setState(() { _statuses = statuses; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final allMock = widget.service.usingMock;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Model Status', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Overall status banner ───────────────────────────────────
                _StatusBanner(allMock: allMock, partial: widget.service.partialMock),
                const SizedBox(height: 16),

                // ── Bundle info ─────────────────────────────────────────────
                _InfoCard(
                  title: 'MODEL BUNDLE',
                  children: [
                    _InfoRow('Version', TariqMapConstants.modelBundleVersion),
                    _InfoRow('Input size', '640 × 640 × 3 (RGB, float32)'),
                    _InfoRow('Post-process', 'NMS IoU 0.45, conf ≥ 0.35'),
                    _InfoRow('Coordinate space', 'Normalised [0..1]'),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Per-agent status ────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text('AGENTS', style: TextStyle(
                    color: AppColors.teal, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                ),
                ...TariqMapConstants.agentClasses.keys.map((agent) =>
                  _AgentCard(status: _statuses[agent])),

                const SizedBox(height: 24),

                // ── Disclaimer ───────────────────────────────────────────────
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
                      Text('Known limitations',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(height: 6),
                      Text(
                        '• D90 (Rutting) is visual-only — depth cannot be inferred from a single 2D image.\n'
                        '• Confidence thresholds are calibrated on RDD2024. Performance on other domains may differ.\n'
                        '• Night / low-light images are underrepresented in training data.',
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
  const _StatusBanner({required this.allMock, required this.partial});
  final bool allMock;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = allMock
        ? (AppColors.mockWarning, Icons.science_outlined,
           'DEMO MOCK INFERENCE — all agents are deterministic mocks')
        : partial
            ? (AppColors.partialWarning, Icons.warning_amber_outlined,
               'PARTIAL REAL — some agents loaded real models, some are mocks')
            : (AppColors.syncDone, Icons.verified_outlined,
               'REAL MODELS — all agents running on-device TFLite weights');

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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(children: [
      Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.status});
  final ModelStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();

    final (statusColor, statusText) = s.isMock
        ? (AppColors.mockWarning, 'MOCK')
        : (AppColors.syncDone, 'LOADED');

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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
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
            _Row('Format', s.isMock ? 'Deterministic mock' : 'TFLite float16'),
            _Row('File', s.filePath != null
                ? s.filePath!.split(RegExp(r'[/\\]')).last
                : 'Not loaded'),
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
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(color: Colors.black45, fontSize: 12)),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
  });
  final String       agentName;
  final bool         isLoaded;
  final bool         isMock;
  final String?      filePath;
  final List<String> classes;
}

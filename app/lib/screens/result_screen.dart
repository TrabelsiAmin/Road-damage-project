import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';
import '../widgets/annotated_image.dart';

/// Full-screen, detailed result view shown after an image is analysed.
///
/// Layout:
///   • Annotated road image (full-width, up to 55 % of screen height)
///   • Draggable details panel:
///       - Severity badge + priority bar
///       - Detection cards (colour, label, confidence bar, bbox coords)
///       - GPS + territory + actor metadata
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.observation});
  final Observation observation;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  int? _highlightedIndex;

  @override
  Widget build(BuildContext context) {
    final obs = widget.observation;
    final detections = obs.detections;
    final priority = obs.priorityScore;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Annotated image ──────────────────────────────────────
          Expanded(
            flex: 55,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image with bounding boxes
                detections.isEmpty
                    ? _buildPlainImage(obs)
                    : AnnotatedImageWidget(
                        imagePath: obs.imagePath,
                        detections: detections,
                        highlightedIndex: _highlightedIndex,
                      ),

                // Top bar
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Analysis Results',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        // Share button
                        GestureDetector(
                          onTap: () async {
                            final box = context.findRenderObject() as RenderBox?;
                            await Share.shareXFiles(
                              [XFile(obs.imagePath)],
                              text: 'TariqMap Observation: ${obs.detections.length} anomalies, Score: ${priority.toStringAsFixed(0)}',
                              sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.share, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Priority badge
                        _PriorityBadge(score: priority),
                      ]),
                    ),
                  ),
                ),
                // Mock Banner
                if (obs.anyMock)
                  Positioned(
                    top: 60, left: 16, right: 16,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.mockWarning.withAlpha(220),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.science_outlined, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'DEMO MOCK INFERENCE',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Details panel ────────────────────────────────────────
          Expanded(
            flex: 45,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        // Summary row
                        _SummaryRow(observation: obs),
                        const SizedBox(height: 12),

                        // Detection cards
                        if (detections.isEmpty)
                          const _EmptyDetections()
                        else ...[
                          Text(
                            '${detections.length} Anomal${detections.length == 1 ? 'y' : 'ies'} Found',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          ...detections.asMap().entries.map((e) => _DetectionCard(
                                index: e.key,
                                detection: e.value,
                                isHighlighted: _highlightedIndex == e.key,
                                onTap: () => setState(() =>
                                    _highlightedIndex = _highlightedIndex == e.key ? null : e.key),
                              )),
                        ],

                        const Divider(height: 28),

                        // Metadata
                        _MetaSection(observation: obs),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlainImage(Observation obs) => kIsWeb
      ? Image.network(obs.imagePath, fit: BoxFit.cover)
      : Image.file(File(obs.imagePath), fit: BoxFit.cover);
}

// ---------------------------------------------------------------------------
// Priority badge
// ---------------------------------------------------------------------------

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.score});
  final double score;

  Color get _color {
    if (score >= 70) return const Color(0xFFFF1744);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFF4CAF50);
  }

  String get _label {
    if (score >= 70) return 'CRITICAL';
    if (score >= 40) return 'HIGH';
    if (score >= 20) return 'MEDIUM';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: _color,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: _color.withAlpha(120), blurRadius: 8)],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
        Text('${score.toStringAsFixed(0)}/100', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Summary row (detections count, actor, date)
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.observation});
  final Observation observation;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: [
      _StatChip(value: '${observation.detections.length}', label: 'Detected'),
      _StatChip(value: observation.actor.split(' ').first, label: 'Actor'),
      _StatChip(
        value: DateFormat('HH:mm').format(observation.createdAt.toLocal()),
        label: DateFormat('dd MMM').format(observation.createdAt.toLocal()),
      ),
    ],
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 11)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Detection card
// ---------------------------------------------------------------------------

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({
    required this.index,
    required this.detection,
    required this.isHighlighted,
    required this.onTap,
  });
  final int index;
  final Detection detection;
  final bool isHighlighted;
  final VoidCallback onTap;

  String get _severity {
    if (detection.confidence >= 0.80) return 'High confidence';
    if (detection.confidence >= 0.55) return 'Medium confidence';
    return 'Low confidence';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forClassCode(detection.classCode);
    final b = detection.box;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isHighlighted ? color.withAlpha(20) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted ? color : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted ? color.withAlpha(60) : Colors.black12,
              blurRadius: isHighlighted ? 12 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TariqMapConstants.labelFor(detection.classCode),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detection.classCode,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ]),
              const SizedBox(height: 10),

              // Confidence bar
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: detection.confidence,
                      minHeight: 8,
                      backgroundColor: color.withAlpha(30),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(detection.confidence * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ]),
              const SizedBox(height: 6),

              // Severity + agent
              Row(children: [
                Text(_severity, style: const TextStyle(color: Colors.black45, fontSize: 11)),
                const Spacer(),
                Text('Agent: ${detection.agent}', style: const TextStyle(color: Colors.black38, fontSize: 11)),
              ]),
              const SizedBox(height: 8),

              // Bounding box coordinates
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CoordChip(label: 'x', value: b.x),
                    _CoordChip(label: 'y', value: b.y),
                    _CoordChip(label: 'w', value: b.width),
                    _CoordChip(label: 'h', value: b.height),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoordChip extends StatelessWidget {
  const _CoordChip({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value.toStringAsFixed(3), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      Text(label, style: const TextStyle(color: Colors.black38, fontSize: 10)),
    ],
  );
}

// ---------------------------------------------------------------------------
// No detections placeholder
// ---------------------------------------------------------------------------

class _EmptyDetections extends StatelessWidget {
  const _EmptyDetections();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(children: [
      Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
      SizedBox(width: 12),
      Expanded(child: Text('No anomalies detected in this image.')),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Metadata section
// ---------------------------------------------------------------------------

class _MetaSection extends StatelessWidget {
  const _MetaSection({required this.observation});
  final Observation observation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Location & Metadata', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 10),
      _MetaRow(icon: Icons.location_on_outlined, label: 'GPS',
          value: '${observation.latitude.toStringAsFixed(5)}, ${observation.longitude.toStringAsFixed(5)}'),
      if (observation.accuracyMeters != null)
        _MetaRow(icon: Icons.my_location, label: 'Accuracy',
            value: '±${observation.accuracyMeters!.toStringAsFixed(0)} m'),
      _MetaRow(icon: Icons.business_outlined, label: 'Actor', value: observation.actor),
      _MetaRow(icon: Icons.code, label: 'Model Ver', value: observation.modelBundleVersion.isEmpty ? 'v1.0 (Bundled)' : observation.modelBundleVersion),
      _MetaRow(icon: Icons.sync_outlined, label: 'Sync',
          value: observation.syncStatus.name.toUpperCase()),
      _MetaRow(icon: Icons.access_time_outlined, label: 'Captured',
          value: DateFormat('dd MMM yyyy, HH:mm').format(observation.createdAt.toLocal())),
      if (observation.failedAgents > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('⚠ ${observation.failedAgents} agent(s) failed — results may be partial.',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ),
    ],
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.black38),
      const SizedBox(width: 8),
      Text('$label:', style: const TextStyle(color: Colors.black45, fontSize: 13)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );
}

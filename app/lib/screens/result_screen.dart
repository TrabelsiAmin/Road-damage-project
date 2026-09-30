import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';
import '../widgets/annotated_image.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.observation});
  final Observation observation;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  int? _highlightedIndex;
  late AnimationController _panelCtrl;
  late Animation<double>   _panelSlide;

  @override
  void initState() {
    super.initState();
    _panelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _panelSlide = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutCubic);
    _panelCtrl.forward();
  }

  @override
  void dispose() {
    _panelCtrl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(widget.observation.imagePath)],
      text: 'TariqMap: ${widget.observation.detections.length} anomaly detected, '
            'Score: ${widget.observation.priorityScore.toStringAsFixed(0)}/100',
      sharePositionOrigin:
          box!.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final obs       = widget.observation;
    final detections = obs.detections;
    final priority  = obs.priorityScore;
    final priorityColor = AppColors.forPriority(priority);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Image area ──────────────────────────────────────────────────────
          Expanded(
            flex: 55,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image
                detections.isEmpty
                    ? _buildPlainImage(obs)
                    : AnnotatedImageWidget(
                        imagePath:        obs.imagePath,
                        detections:       detections,
                        highlightedIndex: _highlightedIndex,
                      ),

                // Dark gradient overlay at top
                Positioned(
                  top: 0, left: 0, right: 0, height: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(160),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Top bar
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                      child: Row(children: [
                        // Back
                        _IconPill(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        const Text('Analysis Results',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                        const Spacer(),
                        // Share
                        _IconPill(
                          icon: Icons.ios_share_rounded,
                          onTap: _share,
                        ),
                        const SizedBox(width: 8),
                        // Priority badge
                        _PriorityBadge(score: priority, color: priorityColor),
                      ]),
                    ),
                  ),
                ),

                // Mock banner
                if (obs.anyMock)
                  Positioned(
                    top: 80, left: 16, right: 16,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.mockWarning.withAlpha(230),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.science_outlined,
                              color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text('DEMO MOCK INFERENCE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Details panel ───────────────────────────────────────────────────
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15), end: Offset.zero)
                .animate(_panelSlide),
            child: FadeTransition(
              opacity: _panelSlide,
              child: Expanded(
                flex: 45,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      // drag handle
                      Container(
                        width: 36, height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                          children: [

                            // Stats strip
                            _StatsStrip(obs: obs),
                            const SizedBox(height: 16),

                            // Detections
                            if (detections.isEmpty)
                              _EmptyDetections()
                            else ...[
                              _SectionLabel(
                                '${detections.length} ANOMAL${detections.length == 1 ? 'Y' : 'IES'} FOUND'),
                              const SizedBox(height: 10),
                              ...detections.asMap().entries.map((e) =>
                                _DetectionCard(
                                  index:         e.key,
                                  detection:     e.value,
                                  isHighlighted: _highlightedIndex == e.key,
                                  onTap: () => setState(() =>
                                    _highlightedIndex =
                                      _highlightedIndex == e.key ? null : e.key),
                                )),
                            ],

                            const SizedBox(height: 8),
                            const Divider(color: AppColors.borderLight),
                            const SizedBox(height: 8),

                            _SectionLabel('LOCATION & METADATA'),
                            const SizedBox(height: 10),
                            _MetaSection(observation: obs),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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

// ── Icon pill button ──────────────────────────────────────────────────────────

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});
  final IconData     icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(30), width: 1),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    ),
  );
}

// ── Priority badge ────────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.score, required this.color});
  final double score;
  final Color  color;

  String get _label {
    if (score >= 70) return 'CRITICAL';
    if (score >= 40) return 'HIGH';
    if (score >= 20) return 'MEDIUM';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(color: color.withAlpha(100), blurRadius: 10)],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_label,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900,
            fontSize: 9, letterSpacing: 1)),
        Text('${score.toStringAsFixed(0)}/100',
          style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    ),
  );
}

// ── Stats strip ───────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.obs});
  final Observation obs;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatChip(
          value: '${obs.detections.length}',
          label: 'Detected',
          icon: Icons.warning_amber_rounded,
          color: obs.detections.isEmpty
              ? AppColors.syncDone
              : AppColors.forPriority(obs.priorityScore),
        ),
        Container(width: 1, height: 32, color: AppColors.borderLight),
        _StatChip(
          value: obs.actor.split(' ').first,
          label: 'Actor',
          icon: Icons.business_rounded,
          color: AppColors.teal,
        ),
        Container(width: 1, height: 32, color: AppColors.borderLight),
        _StatChip(
          value: DateFormat('HH:mm').format(obs.createdAt.toLocal()),
          label: DateFormat('d MMM').format(obs.createdAt.toLocal()),
          icon: Icons.access_time_rounded,
          color: Colors.black45,
        ),
      ],
    ),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value;
  final String label;
  final IconData icon;
  final Color  color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(height: 3),
      Text(value,
        style: const TextStyle(
          fontWeight: FontWeight.w900, fontSize: 16)),
      Text(label,
        style: const TextStyle(color: Colors.black38, fontSize: 10)),
    ],
  );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(
      color: AppColors.teal,
      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5));
}

// ── Detection card ────────────────────────────────────────────────────────────

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({
    required this.index,
    required this.detection,
    required this.isHighlighted,
    required this.onTap,
  });

  final int        index;
  final Detection  detection;
  final bool       isHighlighted;
  final VoidCallback onTap;

  String get _confidence {
    if (detection.confidence >= 0.80) return 'High confidence';
    if (detection.confidence >= 0.55) return 'Medium confidence';
    return 'Low confidence';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forClassCode(detection.classCode);
    final b     = detection.box;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isHighlighted ? color.withAlpha(18) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted ? color : AppColors.borderLight,
            width: isHighlighted ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted
                  ? color.withAlpha(50) : Colors.black.withAlpha(6),
              blurRadius: isHighlighted ? 14 : 6,
              offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TariqMapConstants.labelFor(detection.classCode),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14))),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(detection.classCode,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800, fontSize: 11)),
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
                      minHeight: 6,
                      backgroundColor: color.withAlpha(25),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(detection.confidence * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
              const SizedBox(height: 6),

              Row(children: [
                Text(_confidence,
                  style: const TextStyle(color: Colors.black38, fontSize: 11)),
                const Spacer(),
                Text('Agent: ${detection.agent}',
                  style: const TextStyle(color: Colors.black38, fontSize: 11)),
              ]),
              const SizedBox(height: 10),

              // BBox coords
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CoordPill(label: 'x', value: b.x),
                    _CoordPill(label: 'y', value: b.y),
                    _CoordPill(label: 'w', value: b.width),
                    _CoordPill(label: 'h', value: b.height),
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

class _CoordPill extends StatelessWidget {
  const _CoordPill({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value.toStringAsFixed(3),
        style: const TextStyle(
          fontWeight: FontWeight.w700, fontSize: 12)),
      Text(label,
        style: const TextStyle(color: Colors.black38, fontSize: 10)),
    ],
  );
}

// ── Empty detections ──────────────────────────────────────────────────────────

class _EmptyDetections extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.syncDone.withAlpha(12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.syncDone.withAlpha(50)),
    ),
    child: const Row(children: [
      Icon(Icons.check_circle_rounded,
        color: AppColors.syncDone, size: 26),
      SizedBox(width: 12),
      Expanded(
        child: Text('No road anomalies detected in this image.',
          style: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
    ]),
  );
}

// ── Meta section ──────────────────────────────────────────────────────────────

class _MetaSection extends StatelessWidget {
  const _MetaSection({required this.observation});
  final Observation observation;

  @override
  Widget build(BuildContext context) {
    final obs = observation;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        _MetaRow(icon: Icons.location_on_rounded, label: 'GPS',
          value: '${obs.latitude.toStringAsFixed(5)}, '
                 '${obs.longitude.toStringAsFixed(5)}'),
        if (obs.accuracyMeters != null) ...[
          const Divider(height: 1, indent: 44, endIndent: 16,
            color: AppColors.borderLight),
          _MetaRow(icon: Icons.my_location_rounded, label: 'Accuracy',
            value: '±${obs.accuracyMeters!.toStringAsFixed(0)} m'),
        ],
        const Divider(height: 1, indent: 44, endIndent: 16,
          color: AppColors.borderLight),
        _MetaRow(icon: Icons.business_rounded, label: 'Actor',
          value: obs.actor),
        const Divider(height: 1, indent: 44, endIndent: 16,
          color: AppColors.borderLight),
        _MetaRow(icon: Icons.memory_rounded, label: 'Model',
          value: obs.modelBundleVersion.isEmpty
              ? 'v1.0 (Bundled)' : obs.modelBundleVersion),
        const Divider(height: 1, indent: 44, endIndent: 16,
          color: AppColors.borderLight),
        _MetaRow(
          icon: switch (obs.syncStatus) {
            SyncStatus.synced    => Icons.cloud_done_rounded,
            SyncStatus.failed    => Icons.cloud_off_rounded,
            SyncStatus.uploading => Icons.cloud_sync_rounded,
            _                   => Icons.cloud_upload_outlined,
          },
          label: 'Sync',
          value: obs.syncStatus.name.toUpperCase(),
          valueColor: switch (obs.syncStatus) {
            SyncStatus.synced => AppColors.syncDone,
            SyncStatus.failed => AppColors.syncFailed,
            _                => AppColors.syncPending,
          },
        ),
        const Divider(height: 1, indent: 44, endIndent: 16,
          color: AppColors.borderLight),
        _MetaRow(icon: Icons.access_time_rounded, label: 'Captured',
          value: DateFormat('dd MMM yyyy · HH:mm')
              .format(obs.createdAt.toLocal())),
        if (obs.failedAgents > 0) ...[
          const Divider(height: 1, indent: 44, endIndent: 16,
            color: AppColors.borderLight),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                size: 16, color: AppColors.mockWarning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${obs.failedAgents} agent(s) failed — results may be partial.',
                  style: const TextStyle(
                    color: AppColors.mockWarning, fontSize: 12))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String   label;
  final String   value;
  final Color?   valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.black26),
      const SizedBox(width: 10),
      Text(label,
        style: const TextStyle(color: Colors.black45, fontSize: 13)),
      const Spacer(),
      Flexible(
        child: Text(value,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: valueColor ?? Colors.black87),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

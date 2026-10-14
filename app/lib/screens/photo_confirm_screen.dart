import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../inference/preprocessing.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/observation_repository.dart';
import '../services/territorial_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'result_screen.dart';

/// Shown after the user takes/picks a photo.
/// Displays the image full-screen and asks for confirmation before running AI.
class PhotoConfirmScreen extends StatefulWidget {
  const PhotoConfirmScreen({
    super.key,
    required this.imageFile,
    required this.detectionService,
    required this.repository,
    required this.actor,
  });

  final File              imageFile;
  final DetectionService  detectionService;
  final ObservationRepository repository;
  final String            actor;

  @override
  State<PhotoConfirmScreen> createState() => _PhotoConfirmScreenState();
}

class _PhotoConfirmScreenState extends State<PhotoConfirmScreen> {
  bool _analyzing = false;
  final _uuid     = const Uuid();
  final _location = LocationService();

  Future<void> _analyze() async {
    setState(() => _analyzing = true);
    try {
      Position? position;
      try {
        position = await _location.currentPosition();
      } catch (_) {
        position = null;
      }

      // Read image dimensions
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = decodeAndOrient(bytes);
      final imageWidth = decoded.width;
      final imageHeight = decoded.height;

      final results = await widget.detectionService.detectAll(widget.imageFile);
      final obs = Observation(
        id:             _uuid.v4(),
        captureId:      _uuid.v4(),
        imagePath:      widget.imageFile.path,
        createdAt:      DateTime.now().toUtc(),
        latitude:       position?.latitude  ?? 0.0,
        longitude:      position?.longitude ?? 0.0,
        accuracyMeters: position?.accuracy,
        actor:          widget.actor,
        agentResults:   results,
        imageWidth:     imageWidth,
        imageHeight:    imageHeight,
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      debugPrint('[Pipeline:ResultObject] Observation created: ${obs.id}, '
          'detections: ${obs.detections.length}, size: ${imageWidth}x$imageHeight, '
          'score: ${obs.priorityScore.toStringAsFixed(1)}, '
          'anomaly: ${obs.detections.firstOrNull?.classCode}');

      await widget.repository.save(obs);

      // Read back from storage to ensure detail screen reads only from storage
      final storedObs = await widget.repository.findById(obs.id) ?? obs;

      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ResultScreen(observation: storedObs),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: AppColors.critical),
        );
        setState(() => _analyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Confirm Photo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: _analyzing
            ? null
            : BackButton(color: Colors.white, onPressed: () => Navigator.of(context).pop()),
      ),
      body: Column(
        children: [
          // ── Photo preview ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(widget.imageFile, fit: BoxFit.cover),
                  if (_analyzing)
                    Container(
                      color: Colors.black.withAlpha(140),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 52, height: 52,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Analysing with AI…',
                            style: TextStyle(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Detecting road anomalies',
                            style: TextStyle(
                              color: Colors.white.withAlpha(180), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bottom action bar ─────────────────────────────────────────────
          if (!_analyzing)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Hint text
                    Text(
                      'Is this photo ready for analysis?',
                      style: TextStyle(
                        color: Colors.white.withAlpha(180),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // Discard button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Retake',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Confirm / analyse button
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 6,
                              shadowColor: AppColors.teal.withAlpha(100),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _analyze,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('Analyse',
                              style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

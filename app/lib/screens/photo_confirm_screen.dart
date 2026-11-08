import 'dart:io';
import 'dart:typed_data';
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
import 'package:image_picker/image_picker.dart';
import 'result_screen.dart';

/// Popped by [PhotoConfirmScreen] when the user chooses Retake.
enum PhotoConfirmOutcome { retake }

/// Acquires one file for [source], then shows confirm. Retake asks again.
/// A null file, or leaving confirm without [PhotoConfirmOutcome.retake], stops
/// the loop and does not save.
Future<void> runPhotoConfirmLoop({
  required ImageSource source,
  required Future<File?> Function(ImageSource source) acquire,
  required Future<PhotoConfirmOutcome?> Function(File file) confirm,
}) async {
  while (true) {
    final file = await acquire(source);
    if (file == null) return;
    final outcome = await confirm(file);
    if (outcome == PhotoConfirmOutcome.retake) continue;
    return;
  }
}

/// Shown after the user takes/picks a photo.
/// Displays the image full-screen and asks for confirmation before running AI.
class PhotoConfirmScreen extends StatefulWidget {
  const PhotoConfirmScreen({
    super.key,
    required this.imageFile,
    required this.detectionService,
    required this.repository,
    required this.actor,
    this.organizationId,
    this.preview,
    this.imageBytes,
  });

  final File imageFile;
  final DetectionService detectionService;
  final ObservationRepository repository;
  final String actor;
  final String? organizationId;

  /// Pixels for the preview. Production leaves this null and shows [imageFile].
  final ImageProvider? preview;

  /// Preloaded image bytes. Production leaves this null and reads [imageFile].
  final Uint8List? imageBytes;

  @override
  State<PhotoConfirmScreen> createState() => _PhotoConfirmScreenState();
}

class _PhotoConfirmScreenState extends State<PhotoConfirmScreen> {
  bool _analyzing = false;
  bool _saved = false;
  final _uuid = const Uuid();
  final _location = LocationService();

  Future<void> _analyze() async {
    if (_analyzing || _saved) return;
    setState(() => _analyzing = true);
    try {
      Position? position;
      try {
        position = await _location.currentPosition();
      } catch (_) {
        position = null;
      }

      // Read image dimensions
      final bytes = widget.imageBytes ?? await widget.imageFile.readAsBytes();
      final decoded = decodeAndOrient(bytes);
      final imageWidth = decoded.width;
      final imageHeight = decoded.height;

      final results = await widget.detectionService.detectAll(widget.imageFile);
      if (!mounted) return;
      final obs = Observation(
        id: _uuid.v4(),
        captureId: _uuid.v4(),
        organizationId: widget.organizationId,
        imagePath: widget.imageFile.path,
        createdAt: DateTime.now().toUtc(),
        latitude: position?.latitude ?? 0.0,
        longitude: position?.longitude ?? 0.0,
        accuracyMeters: position?.accuracy,
        actor: widget.actor,
        agentResults: results,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      debugPrint('[Pipeline:ResultObject] Observation created: ${obs.id}, '
          'detections: ${obs.detections.length}, size: ${imageWidth}x$imageHeight, '
          'score: ${obs.priorityScore.toStringAsFixed(1)}, '
          'anomaly: ${obs.detections.firstOrNull?.classCode}');

      await widget.repository.save(obs);
      _saved = true;

      // Read back from storage to ensure detail screen reads only from storage
      final storedObs = await widget.repository.findById(obs.id) ?? obs;

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(observation: storedObs),
        ),
      );
    } catch (e) {
      if (!_saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: AppColors.critical),
        );
        setState(() => _analyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_analyzing,
      child: Scaffold(
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
                  Image(
                    key: const ValueKey('photo-confirm-preview'),
                    image: widget.preview ?? FileImage(widget.imageFile),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
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
                    const SizedBox(height: 6),
                    Text(
                      'Nothing is saved until you choose Analyse.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withAlpha(140),
                        fontSize: 12,
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
                            onPressed: _analyzing
                                ? null
                                : () => Navigator.of(context).pop(PhotoConfirmOutcome.retake),
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
                            onPressed: _analyzing ? null : _analyze,
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
      ),
    );
  }
}

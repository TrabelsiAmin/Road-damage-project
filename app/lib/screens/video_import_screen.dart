import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../core/app_colors.dart';
import '../inference/annotation_renderer.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/territorial_service.dart';
import '../services/video_frame_extractor.dart';
import 'result_screen.dart';

/// Video import: extract real JPEG frames, run inference, show annotated
/// frames and a contact sheet.
///
/// Pipeline:
///   Video file → platform thumbnail seek → JPEG frame → DetectionService
///   → inverse-letterboxed boxes → annotated JPEG → contact sheet
///
/// STATUS:
///   CURRENTLY WORKING — frame extraction + per-frame inference + contact sheet
///   REQUIRES MODEL — without a TFLite asset, frames are extracted but no
///                    boxes are invented (allowMock: false)
///   LIMITATION — an encoded annotated MP4 is not produced. Encoding a video
///                on-device without FFmpeg is unreliable; we keep annotated
///                JPEGs + a contact sheet instead of pretending a muxer works.
class VideoImportScreen extends StatefulWidget {
  const VideoImportScreen({
    super.key,
    required this.service,
    required this.actor,
  });

  final DetectionService service;
  final String actor;

  @override
  State<VideoImportScreen> createState() => _VideoImportScreenState();
}

class _VideoImportScreenState extends State<VideoImportScreen> {
  File? _videoFile;
  VideoPlayerController? _controller;
  Duration _duration = Duration.zero;

  bool _picking = false;
  bool _processing = false;
  int _framesTotal = 0;
  int _framesProc = 0;
  int _frameIntervalSec = 5;
  String _status = '';
  String? _limitation;
  Directory? _sessionDir;
  String? _contactSheetPath;

  final _results = <_FrameResult>[];
  final _extractor = VideoFrameExtractor(maxFrames: 40);
  final _renderer = const AnnotationRenderer();

  @override
  void dispose() {
    _controller?.dispose();
    final dir = _sessionDir;
    if (dir != null) {
      VideoFrameExtractor.cleanup(dir);
    }
    super.dispose();
  }

  Future<void> _pickVideo() async {
    setState(() {
      _picking = true;
      _status = 'Picking video…';
      _limitation = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp'],
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) {
        setState(() {
          _picking = false;
          _status = '';
        });
        return;
      }

      final file = File(result.files.single.path!);
      final ctrl = VideoPlayerController.file(file);
      try {
        await ctrl.initialize();
      } catch (e) {
        await ctrl.dispose();
        setState(() {
          _picking = false;
          _status = 'Unsupported or corrupted video: $e';
        });
        return;
      }

      if (ctrl.value.duration.inMilliseconds <= 0) {
        await ctrl.dispose();
        setState(() {
          _picking = false;
          _status = 'Video decoded but duration is zero.';
        });
        return;
      }

      setState(() {
        _videoFile = file;
        _controller?.dispose();
        _controller = ctrl;
        _duration = ctrl.value.duration;
        _picking = false;
        _results.clear();
        _contactSheetPath = null;
        _status = 'Ready — ${p.basename(file.path)}';
      });
    } catch (e) {
      setState(() {
        _picking = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _processFrames() async {
    if (_videoFile == null || _controller == null) return;
    setState(() {
      _processing = true;
      _framesProc = 0;
      _results.clear();
      _contactSheetPath = null;
      _limitation = null;
    });

    final previous = _sessionDir;
    if (previous != null) {
      await VideoFrameExtractor.cleanup(previous);
      _sessionDir = null;
    }

    Position? position;
    try {
      position = await LocationService().currentPosition();
    } catch (_) {}

    try {
      final extraction = await _extractor.extract(
        video: _videoFile!,
        intervalMs: _frameIntervalSec * 1000,
        durationMs: _duration.inMilliseconds,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _framesTotal = total;
            _status = 'Extracting frames ${done + 1} / $total…';
          });
        },
      );
      _sessionDir = extraction.sessionDir;

      setState(() {
        _framesTotal = extraction.frames.length;
        _status = 'Running inference on ${extraction.frames.length} frames…';
        if (extraction.errors.isNotEmpty) {
          _limitation =
              '${extraction.errors.length} frame(s) skipped: ${extraction.errors.first}';
        }
      });

      if (widget.service.usingMock) {
        setState(() {
          _limitation =
              'REQUIRES MODEL: no validated TFLite weights are installed. '
              'Frames were extracted, but mock boxes are not applied to video.';
        });
      }

      final annotatedPaths = <String>[];

      for (final frame in extraction.frames) {
        if (!mounted) break;
        setState(() =>
            _status = 'Detecting frame ${frame.index + 1} / $_framesTotal…');

        try {
          final bytes = await frame.file.readAsBytes();
          if (bytes.isEmpty) {
            continue;
          }
          final agentResults = await widget.service.detectAllBytes(
            bytes,
            allowMock: false,
          );
          final detections =
              agentResults.expand((r) => r.detections).toList();

          String? annotatedPath;
          if (detections.isNotEmpty) {
            annotatedPath = await _renderer.renderAndSave(
              sourceBytes: bytes,
              detections: detections,
              captureId: 'video-${frame.timestampMs}',
            );
            annotatedPaths.add(annotatedPath);
          }

          final obs = Observation(
            id: const Uuid().v4(),
            captureId: const Uuid().v4(),
            imagePath: annotatedPath ?? frame.file.path,
            createdAt: DateTime.now().toUtc(),
            latitude: position?.latitude ?? 0.0,
            longitude: position?.longitude ?? 0.0,
            accuracyMeters: position?.accuracy,
            agentResults: agentResults,
            actor: widget.actor,
          );
          _results.add(_FrameResult(
            timestampMs: frame.timestampMs,
            observation: obs,
            thumbnailPath: frame.file.path,
            annotatedPath: annotatedPath,
          ));
        } catch (e) {
          debugPrint('[VideoImport] Frame ${frame.timestampMs}ms error: $e');
        }

        setState(() => _framesProc++);
      }

      if (annotatedPaths.isNotEmpty) {
        _contactSheetPath = await _writeContactSheet(annotatedPaths);
      }

      setState(() {
        _processing = false;
        final hits = _results.where((r) => r.observation.detections.isNotEmpty).length;
        _status =
            'Done — ${_results.length} frames inspected, $hits with detections. '
            'Annotated output video is not encoded; see contact sheet / per-frame JPEGs.';
      });
    } on FrameExtractionException catch (e) {
      setState(() {
        _processing = false;
        _status = e.message;
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _status = 'Video inference failed: $e';
      });
    }
  }

  Future<String?> _writeContactSheet(List<String> paths) async {
    try {
      final decoded = <img.Image>[];
      for (final path in paths.take(12)) {
        final bytes = await File(path).readAsBytes();
        final im = img.decodeImage(bytes);
        if (im != null) decoded.add(img.copyResize(im, width: 320));
      }
      if (decoded.isEmpty) return null;
      const cols = 3;
      final rows = (decoded.length / cols).ceil();
      const cellW = 320;
      const cellH = 180;
      final sheet = img.Image(
        width: cols * cellW,
        height: rows * cellH,
        numChannels: 3,
        backgroundColor: img.ColorRgb8(16, 24, 32),
      );
      for (var i = 0; i < decoded.length; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        img.compositeImage(sheet, decoded[i], dstX: col * cellW, dstY: row * cellH);
      }
      final dir = _sessionDir;
      if (dir == null) return null;
      final out = File(p.join(dir.path, 'contact_sheet.jpg'));
      await out.writeAsBytes(img.encodeJpg(sheet, quality: 85));
      return out.path;
    } catch (e) {
      debugPrint('[VideoImport] contact sheet failed: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Video Import', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'SELECT VIDEO',
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.teal),
                      foregroundColor: AppColors.teal,
                    ),
                    onPressed: (_picking || _processing) ? null : _pickVideo,
                    icon: const Icon(Icons.video_file_outlined),
                    label: Text(_videoFile == null ? 'Choose video file' : 'Change video'),
                  ),
                ),
                if (_videoFile != null && _controller != null) ...[
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Duration: ${_duration.inMinutes}m ${_duration.inSeconds % 60}s',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (_videoFile != null) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'FRAME SAMPLING',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Sample every', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _frameIntervalSec,
                      items: [1, 2, 5, 10, 15, 30]
                          .map((s) => DropdownMenuItem(value: s, child: Text('$s sec')))
                          .toList(),
                      onChanged: _processing
                          ? null
                          : (v) => setState(() => _frameIntervalSec = v!),
                      underline: const SizedBox(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'capped at 40 frames for memory',
                      style: const TextStyle(color: Colors.black45, fontSize: 12),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Each timestamp is decoded to a JPEG, then run through the '
                    'same letterbox → TFLite → inverse-letterbox pipeline as still images. '
                    'An encoded annotated MP4 is not produced.',
                    style: TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _processing ? null : _processFrames,
                icon: _processing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_processing ? 'Processing…' : 'Extract frames and detect'),
              ),
            ),
            if (_processing || _status.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (_processing)
                Column(children: [
                  LinearProgressIndicator(
                    value: _framesTotal > 0 ? _framesProc / _framesTotal : null,
                    backgroundColor: AppColors.teal.withAlpha(30),
                    valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                  ),
                  const SizedBox(height: 6),
                ]),
              Text(_status, style: const TextStyle(color: Colors.black45, fontSize: 12)),
            ],
            if (_limitation != null) ...[
              const SizedBox(height: 12),
              _Banner(text: _limitation!, warning: true),
            ],
            if (_contactSheetPath != null) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'CONTACT SHEET',
                child: Image.file(File(_contactSheetPath!), fit: BoxFit.contain),
              ),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Section(
                title: '${_results.length} EXTRACTED FRAMES',
                child: Column(
                  children: _results.map((r) => ListTile(
                    leading: r.thumbnailPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(r.thumbnailPath!),
                              width: 56,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          )
                        : CircleAvatar(
                            backgroundColor: AppColors.teal.withAlpha(30),
                            child: Text(
                              '${(r.timestampMs / 1000).round()}s',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.teal,
                              ),
                            ),
                          ),
                    title: Text(
                      r.observation.detections.isEmpty
                          ? 'No detections'
                          : '${r.observation.detections.length} detections',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      '${(r.timestampMs / 1000).toStringAsFixed(1)}s  ·  '
                      '${r.observation.detections.map((d) => d.classCode).toSet().join(', ')}',
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ResultScreen(observation: r.observation),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning ? const Color(0xFFFFF4D6) : AppColors.teal.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(title,
                style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0)),
          ),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ],
      );
}

class _FrameResult {
  const _FrameResult({
    required this.timestampMs,
    required this.observation,
    this.thumbnailPath,
    this.annotatedPath,
  });
  final int timestampMs;
  final Observation observation;
  final String? thumbnailPath;
  final String? annotatedPath;
}

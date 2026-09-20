import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../core/app_colors.dart';
import '../inference/annotation_renderer.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/observation_repository.dart';
import '../services/territorial_service.dart';
import '../services/video_frame_extractor.dart';
import '../services/video_muxer.dart';
import 'result_screen.dart';

/// Video import: extract real JPEG frames, run inference, annotate, mux MP4.
///
/// Pipeline:
///   Video file → platform thumbnail seek → JPEG frame → DetectionService
///   → inverse-letterboxed boxes → annotated JPEG → contact sheet
///   → FFmpeg H.264 MP4 when `ffmpeg` is on PATH (verified decode)
///
/// STATUS:
///   CURRENTLY WORKING — frame extraction + per-frame inference + contact sheet
///   CURRENTLY WORKING — encoded annotated MP4 **when FFmpeg CLI is installed**
///                       (Linux/desktop). Stock Android/iOS have no ffmpeg;
///                       those builds keep the contact sheet.
///   REQUIRES MODEL — without a TFLite asset, frames are extracted but no
///                    boxes are invented (allowMock: false)
class VideoImportScreen extends StatefulWidget {
  const VideoImportScreen({
    super.key,
    required this.service,
    required this.actor,
    this.repository,
  });

  final DetectionService service;
  final String actor;
  /// When set, each extracted frame is persisted as an Observation (WP1).
  /// GPS-missing frames are still saved (`gpsAvailable: false`).
  final ObservationRepository? repository;

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
  File? _outputVideo;
  VideoPlayerController? _outputController;
  String? _muxStatus;

  final _results = <_FrameResult>[];
  final _extractor = VideoFrameExtractor(maxFrames: 40);
  final _renderer = const AnnotationRenderer();
  final _muxer = FfmpegVideoMuxer();

  @override
  void dispose() {
    _controller?.dispose();
    _outputController?.dispose();
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
        _outputVideo = null;
        _muxStatus = null;
        _outputController?.dispose();
        _outputController = null;
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
      _outputVideo = null;
      _muxStatus = null;
      _limitation = null;
    });
    _outputController?.dispose();
    _outputController = null;

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

          final persistedPath = await _persistFrameJpeg(
            File(annotatedPath ?? frame.file.path),
          );
          final obs = Observation(
            id: const Uuid().v4(),
            captureId: const Uuid().v4(),
            imagePath: persistedPath,
            createdAt: DateTime.now().toUtc(),
            latitude: position?.latitude ?? 0.0,
            longitude: position?.longitude ?? 0.0,
            gpsAvailable: position != null,
            sourceVideoPath: _videoFile?.path,
            frameTimestampMs: frame.timestampMs,
            accuracyMeters: position?.accuracy,
            agentResults: agentResults,
            actor: widget.actor,
            annotatedImagePath: annotatedPath,
          );
          await widget.repository?.save(obs);
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

      await _muxOutputVideo();

      if (!mounted) return;
      setState(() {
        _processing = false;
        final hits = _results.where((r) => r.observation.detections.isNotEmpty).length;
        final muxBit = _outputVideo != null
            ? 'Output MP4 saved (${p.basename(_outputVideo!.path)}).'
            : (_muxStatus ?? 'Encoded MP4 not produced.');
        _status =
            'Done — ${_results.length} frames inspected, $hits with detections. $muxBit';
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

  /// Copy a sampled JPEG out of the session temp dir so WP1 observations
  /// survive [VideoFrameExtractor.cleanup] on dispose.
  Future<String> _persistFrameJpeg(File source) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'tariqmap_frames'));
      await dir.create(recursive: true);
      final dest = File(p.join(
        dir.path,
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(source.path)}',
      ));
      await source.copy(dest.path);
      return dest.path;
    } catch (_) {
      return source.path;
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

  Future<void> _muxOutputVideo() async {
    if (_results.isEmpty) return;
    final available = await _muxer.isAvailable();
    if (!available) {
      _muxStatus =
          'Encoded output video requires FFmpeg on PATH (verified on Linux/desktop). '
          'Stock Android/iOS do not ship FFmpeg — contact sheet is kept.';
      return;
    }

    final frames = <TimedJpeg>[];
    for (final r in _results) {
      final path = r.annotatedPath ?? r.thumbnailPath;
      if (path == null) continue;
      frames.add(TimedJpeg(file: File(path), timestampMs: r.timestampMs));
    }
    if (frames.isEmpty) {
      _muxStatus = 'No JPEG frames available to mux.';
      return;
    }

    if (mounted) {
      setState(() => _status = 'Encoding annotated MP4 with FFmpeg…');
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(docs.path, 'tariqmap_videos'));
      await destDir.create(recursive: true);
      final dest = File(p.join(
        destDir.path,
        muxOutputName(_videoFile?.path ?? 'clip'),
      ));
      final mux = await _muxer.mux(
        frames: frames,
        output: dest,
        sourceDurationMs: _duration.inMilliseconds,
      );
      if (mux.ok && mux.output != null) {
        _outputVideo = mux.output;
        _muxStatus =
            'FFmpeg H.264 ${mux.width}×${mux.height}, '
            '${mux.durationSec?.toStringAsFixed(2)}s, decode_ok=true. '
            'Sampled-frame montage (not original fps).';
        final ctrl = VideoPlayerController.file(mux.output!);
        await ctrl.initialize();
        await ctrl.setLooping(true);
        ctrl.addListener(() {
          if (mounted) setState(() {});
        });
        _outputController?.dispose();
        _outputController = ctrl;
      } else {
        _muxStatus =
            'FFmpeg mux failed (${mux.status}): ${mux.reason}. Contact sheet kept.';
      }
    } catch (e) {
      _muxStatus = 'FFmpeg mux error: $e. Contact sheet kept.';
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
                    'When FFmpeg is on PATH, those frames are muxed into an H.264 MP4 '
                    '(sampled montage, verified by ffprobe + decode). Otherwise only '
                    'the contact sheet is kept.',
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
            if (_muxStatus != null) ...[
              const SizedBox(height: 12),
              _Banner(text: _muxStatus!, warning: _outputVideo == null),
            ],
            if (_outputVideo != null && _outputController != null) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'OUTPUT VIDEO',
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: _outputController!.value.aspectRatio == 0
                          ? 16 / 9
                          : _outputController!.value.aspectRatio,
                      child: VideoPlayer(_outputController!),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            final c = _outputController!;
                            setState(() {
                              c.value.isPlaying ? c.pause() : c.play();
                            });
                          },
                          icon: Icon(
                            _outputController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            p.basename(_outputVideo!.path),
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Share.shareXFiles([XFile(_outputVideo!.path)]);
                          },
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('Share'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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

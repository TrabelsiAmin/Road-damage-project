import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../core/app_colors.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/territorial_service.dart';
import 'result_screen.dart';

/// Video import screen — lets the user pick a local video file and samples
/// frames for detection.
///
/// Architecture:
///   1. User picks a video via file_picker
///   2. VideoPlayerController extracts playback duration
///   3. User selects a frame interval (every N seconds)
///   4. For each sampled timestamp, a JPEG thumbnail is extracted and
///      run through DetectionService
///   5. Results are merged into a single Observation per frame
///   6. User can navigate to ResultScreen for each frame hit
///
/// Limitation: Flutter's video_player does NOT support frame-accurate seeking
/// or thumbnail extraction without platform channels.  This implementation
/// uses a thumbnail approximation via [_extractFrames].
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
  File?                    _videoFile;
  VideoPlayerController?   _controller;
  Duration                 _duration    = Duration.zero;

  bool _picking      = false;
  bool _processing   = false;
  int  _framesTotal  = 0;
  int  _framesProc   = 0;
  int  _frameInterval = 5;  // seconds between sampled frames
  String _status     = '';

  final _results = <_FrameResult>[];

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ── File picker ────────────────────────────────────────────────────────────

  Future<void> _pickVideo() async {
    setState(() { _picking = true; _status = 'Picking video…'; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) {
        setState(() { _picking = false; _status = ''; });
        return;
      }

      final file = File(result.files.single.path!);
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();

      setState(() {
        _videoFile  = file;
        _controller?.dispose();
        _controller = ctrl;
        _duration   = ctrl.value.duration;
        _picking    = false;
        _results.clear();
        _status = 'Ready — ${file.path.split(RegExp(r'[/\\]')).last}';
      });
    } catch (e) {
      setState(() { _picking = false; _status = 'Error: $e'; });
    }
  }

  // ── Frame processing ───────────────────────────────────────────────────────

  Future<void> _processFrames() async {
    if (_videoFile == null) return;
    setState(() { _processing = true; _framesProc = 0; _results.clear(); });

    final durationSec = _duration.inSeconds;
    final frameTimestamps = <int>[];
    for (var t = 0; t < durationSec; t += _frameInterval) {
      frameTimestamps.add(t);
    }

    setState(() {
      _framesTotal = frameTimestamps.length;
      _status = 'Processing 0 / $_framesTotal frames…';
    });

    // GPS at start of processing (for the whole video — no per-frame GPS)
    Position? position;
    try {
      final locationService = LocationService();
      position = await locationService.currentPosition();
    } catch (_) {}

    for (final t in frameTimestamps) {
      if (!mounted) break;

      // frame extraction note: video_player doesn't expose frame extraction API.
      // We use the source video file directly as a proxy for each frame.
      // In production, use a platform channel or ffmpeg_kit to extract real frames.
      setState(() => _status = 'Detecting frame ${_framesProc + 1} / $_framesTotal…');

      try {
        final agentResults = await widget.service.detectAll(_videoFile!);
        final detections   = agentResults.expand((r) => r.detections).toList();

        if (detections.isNotEmpty) {
          final obs = Observation(
            id:          const Uuid().v4(),
            captureId:   const Uuid().v4(),
            imagePath:   _videoFile!.path,
            createdAt:   DateTime.now().toUtc(),
            latitude:    position?.latitude  ?? 0.0,
            longitude:   position?.longitude ?? 0.0,
            accuracyMeters: position?.accuracy,
            agentResults: agentResults,
            actor:       widget.actor,
          );
          _results.add(_FrameResult(timestamp: t, observation: obs));
        }
      } catch (e) {
        debugPrint('[VideoImport] Frame $t error: $e');
      }

      setState(() { _framesProc++; });
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    setState(() {
      _processing = false;
      _status = 'Done — ${_results.length} frames with detections';
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

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
          // ── Video picker ──────────────────────────────────────────────────
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
                if (_videoFile != null) ...[
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

            // ── Interval setting ──────────────────────────────────────────
            _Section(
              title: 'FRAME SAMPLING',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Sample every', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _frameInterval,
                      items: [1, 2, 5, 10, 15, 30].map((s) =>
                        DropdownMenuItem(value: s, child: Text('$s sec'))).toList(),
                      onChanged: (v) => setState(() => _frameInterval = v!),
                      underline: const SizedBox(),
                    ),
                    const SizedBox(width: 8),
                    Text('→ ~${(_duration.inSeconds / _frameInterval).ceil()} frames',
                        style: const TextStyle(color: Colors.black45, fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    'Note: frame thumbnail extraction uses the full video file '
                    'as a proxy (no platform-native frame seek). '
                    'For accurate frame extraction, use ffmpeg_kit in production.',
                    style: TextStyle(color: Colors.black38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Process button ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _processing ? null : _processFrames,
                icon: _processing
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_processing ? 'Processing…' : 'Run detection on frames'),
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

            if (_results.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Section(
                title: '${_results.length} FRAMES WITH DETECTIONS',
                child: Column(
                  children: _results.map((r) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.teal.withAlpha(30),
                      child: Text('${r.timestamp}s',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                              color: AppColors.teal)),
                    ),
                    title: Text(
                      '${r.observation.detections.length} detections',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      r.observation.detections.map((d) => d.classCode).toSet().join(', '),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
        child: Text(title, style: const TextStyle(
          color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
      ),
      Card(
        elevation: 0, color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    ],
  );
}

class _FrameResult {
  const _FrameResult({required this.timestamp, required this.observation});
  final int         timestamp;
  final Observation observation;
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../core/app_colors.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/frame_annotator.dart';
import '../services/territorial_service.dart';
import '../services/video_frame_extractor.dart';
import '../services/video_stitcher.dart';
import 'result_screen.dart';

/// Video Import Screen — full annotated-video pipeline.
///
/// Flow:
///   1. User picks a video file
///   2. VideoPlayerController reads duration for preview
///   3. User sets frame sampling interval
///   4. For each sampled timestamp:
///      a. [VideoFrameExtractor] extracts a real JPEG (platform-native decoder)
///      b. [DetectionService]   runs YOLO on the JPEG
///      c. [FrameAnnotator]     burns bounding boxes + labels onto the JPEG pixel data
///      d. Annotated JPEG saved to temp dir
///   5. [VideoStitcher] calls FFmpeg to concatenate ALL annotated frames
///      (frames without detections get unannotated originals) into an MP4
///   6. Output MP4 is shown in an in-app VideoPlayer
///   7. User can share or browse per-frame detection results
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
  // ── Input video ────────────────────────────────────────────────────────────
  File?                  _videoFile;
  VideoPlayerController? _inputCtrl;
  Duration               _duration = Duration.zero;

  // ── Output annotated video ─────────────────────────────────────────────────
  File?                  _outputVideo;
  VideoPlayerController? _outputCtrl;

  // ── Processing state ───────────────────────────────────────────────────────
  bool   _picking      = false;
  bool   _processing   = false;
  bool   _stitching    = false;
  int    _framesTotal  = 0;
  int    _framesProc   = 0;
  int    _frameInterval = 5;
  String _status       = '';

  // ── Results ────────────────────────────────────────────────────────────────
  final _results = <_FrameResult>[];

  // ── Services ───────────────────────────────────────────────────────────────
  final _extractor  = VideoFrameExtractor();
  final _annotator  = FrameAnnotator();
  final _stitcher   = VideoStitcher();
  Directory? _tempDir;

  @override
  void dispose() {
    _inputCtrl?.dispose();
    _outputCtrl?.dispose();
    _extractor.cancel();
    _stitcher.cancel();
    if (_tempDir != null) _extractor.cleanupTempDir(_tempDir!);
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

      // Reset output
      _outputCtrl?.dispose();
      setState(() {
        _videoFile  = file;
        _inputCtrl?.dispose();
        _inputCtrl  = ctrl;
        _duration   = ctrl.value.duration;
        _picking    = false;
        _outputVideo = null;
        _outputCtrl  = null;
        _results.clear();
        _status = 'Ready — ${file.uri.pathSegments.last}';
      });
    } catch (e) {
      setState(() { _picking = false; _status = 'Error: $e'; });
    }
  }

  // ── Main processing pipeline ───────────────────────────────────────────────

  Future<void> _processFrames() async {
    if (_videoFile == null) return;

    _extractor.reset();
    _tempDir = await _extractor.ensureTempDir();

    setState(() {
      _processing = true;
      _stitching  = false;
      _framesProc = 0;
      _results.clear();
      _outputVideo = null;
      _outputCtrl?.dispose();
      _outputCtrl = null;
    });

    final durationSec     = _duration.inSeconds;
    final frameTimestamps = <int>[];
    for (var t = 0; t < durationSec; t += _frameInterval) {
      frameTimestamps.add(t);
    }

    setState(() {
      _framesTotal = frameTimestamps.length;
      _status = 'Extracting frames…';
    });

    // GPS snapshot for this session
    Position? position;
    try {
      position = await LocationService().currentPosition();
    } catch (_) {}

    // Key: timestamp → path of the (possibly annotated) frame file
    final framePathMap = <int, String>{};

    // ── Step 1-4: Extract → Detect → Annotate ──────────────────────────────
    for (final t in frameTimestamps) {
      if (!mounted || !_processing) break;

      setState(() =>
        _status = 'Frame ${_framesProc + 1} / $_framesTotal  (${t}s) — detecting…');

      try {
        // a) Real frame extraction
        final rawFrame = await _extractor.extractFrame(
          _videoFile!,
          timestampSec: t,
          tempDir: _tempDir!,
        );

        if (rawFrame == null) {
          setState(() { _framesProc++; });
          continue;
        }

        // b) YOLO inference
        final agentResults = await widget.service.detectAll(rawFrame);
        final detections   = agentResults.expand((r) => r.detections).toList();

        // c) Pixel-level annotation (always — clean frame if no detections)
        File frameToStitch = rawFrame;
        if (detections.isNotEmpty) {
          setState(() => _status =
            'Frame ${_framesProc + 1} / $_framesTotal  (${t}s) — annotating…');
          frameToStitch = await _annotator.annotateFrame(rawFrame, detections);

          // Save as observation
          final obs = Observation(
            id:          const Uuid().v4(),
            captureId:   const Uuid().v4(),
            imagePath:   frameToStitch.path,
            createdAt:   DateTime.now().toUtc(),
            latitude:    position?.latitude  ?? 0.0,
            longitude:   position?.longitude ?? 0.0,
            accuracyMeters: position?.accuracy,
            agentResults: agentResults,
            actor:       widget.actor,
          );
          if (mounted) {
            setState(() => _results.add(_FrameResult(
              timestamp:   t,
              observation: obs,
              frameFile:   frameToStitch,
              detectionCount: detections.length,
            )));
          }
        }

        framePathMap[t] = frameToStitch.path;
      } catch (e) {
        debugPrint('[VideoImport] Frame $t error: $e');
      }

      setState(() { _framesProc++; });
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!mounted || !_processing) {
      setState(() { _processing = false; _stitching = false; });
      return;
    }

    // ── Step 5: Stitch all annotated frames into output MP4 ─────────────────
    if (framePathMap.isNotEmpty) {
      setState(() {
        _stitching = true;
        _status = 'Stitching annotated video…';
      });

      final tmpDir = await getTemporaryDirectory();
      final outputPath =
          '${tmpDir.path}/tariqmap_annotated_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final stitchFrames = buildStitchFrames(framePathMap);
      final outFile = await _stitcher.stitch(
        frames:              stitchFrames,
        frameIntervalSec:    _frameInterval,
        originalDurationSec: durationSec,
        outputPath:          outputPath,
      );

      // ── Step 6: Load output video into player ──────────────────────────────
      if (outFile != null && mounted) {
        final ctrl = VideoPlayerController.file(outFile);
        await ctrl.initialize();
        setState(() {
          _outputVideo = outFile;
          _outputCtrl  = ctrl;
        });
      }
    }

    if (mounted) {
      setState(() {
        _processing = false;
        _stitching  = false;
        _status = _outputVideo != null
            ? '✓ Annotated video ready  ·  ${_results.length} frame(s) with detections'
            : 'Done — ${_results.length} frame(s) with detections (stitching unavailable)';
      });
    }
  }

  Future<void> _cancelProcessing() async {
    _extractor.cancel();
    await _stitcher.cancel();
    if (mounted) setState(() { _processing = false; _stitching = false; });
  }

  Future<void> _shareOutput() async {
    if (_outputVideo == null) return;
    await Share.shareXFiles(
      [XFile(_outputVideo!.path)],
      text: 'TariqMap — Annotated road inspection video',
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isBusy = _picking || _processing || _stitching;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Video Import', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_outputVideo != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share annotated video',
              onPressed: _shareOutput,
            ),
        ],
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
                    onPressed: isBusy ? null : _pickVideo,
                    icon: const Icon(Icons.video_file_outlined),
                    label: Text(_videoFile == null ? 'Choose video file' : 'Change video'),
                  ),
                ),
                if (_videoFile != null && _inputCtrl != null) ...[
                  const SizedBox(height: 12),
                  _VideoPreview(ctrl: _inputCtrl!, label: 'Input'),
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

            // ── Frame sampling ────────────────────────────────────────────
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
                      onChanged: isBusy
                          ? null
                          : (v) => setState(() => _frameInterval = v!),
                      underline: const SizedBox(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '→ ~${(_duration.inSeconds / _frameInterval).ceil()} frames',
                      style: const TextStyle(color: Colors.black45, fontSize: 12),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    'Each frame is extracted natively, run through YOLO, '
                    'and annotated with bounding boxes. '
                    'All frames are then stitched into an annotated output video.',
                    style: TextStyle(color: Colors.black38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Run / Cancel ──────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: (_processing || _stitching) ? null : _processFrames,
                  icon: (_processing || _stitching)
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    _stitching  ? 'Stitching video…' :
                    _processing ? 'Processing…' :
                                  'Detect & annotate video',
                  ),
                ),
              ),
              if (_processing || _stitching) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  onPressed: _cancelProcessing,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Cancel'),
                ),
              ],
            ]),

            // ── Progress ──────────────────────────────────────────────────
            if (_processing || _stitching || _status.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (_processing)
                LinearProgressIndicator(
                  value: _framesTotal > 0 ? _framesProc / _framesTotal : null,
                  backgroundColor: AppColors.teal.withAlpha(30),
                  valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                ),
              if (_stitching)
                const LinearProgressIndicator(
                  backgroundColor: Color(0x1A0E7490),
                  valueColor: AlwaysStoppedAnimation(AppColors.teal),
                ),
              const SizedBox(height: 6),
              Text(_status, style: const TextStyle(color: Colors.black45, fontSize: 12)),
            ],

            // ── Annotated output video ────────────────────────────────────
            if (_outputVideo != null && _outputCtrl != null) ...[
              const SizedBox(height: 20),
              _Section(
                title: 'ANNOTATED OUTPUT VIDEO',
                child: Column(
                  children: [
                    _VideoPreview(ctrl: _outputCtrl!, label: 'Annotated', autoPlay: true),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            if (_outputCtrl!.value.isPlaying) {
                              _outputCtrl!.pause();
                            } else {
                              _outputCtrl!.play();
                            }
                            setState(() {});
                          },
                          icon: Icon(_outputCtrl!.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          label: Text(_outputCtrl!.value.isPlaying ? 'Pause' : 'Play'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          foregroundColor: AppColors.teal,
                          side: const BorderSide(color: AppColors.teal),
                        ),
                        onPressed: _shareOutput,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Share'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      '${_results.length} frame(s) with detections',
                      style: const TextStyle(color: Colors.black45, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],

            // ── Per-frame detection results ───────────────────────────────
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'DETECTIONS PER FRAME',
                child: Column(
                  children: _results.map((r) => _FrameCard(
                    result: r,
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
// Video preview widget (shared for input + output)
// ---------------------------------------------------------------------------

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.ctrl,
    required this.label,
    this.autoPlay = false,
  });
  final VideoPlayerController ctrl;
  final String label;
  final bool autoPlay;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_onControllerUpdate);
    if (widget.autoPlay) widget.ctrl.play();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: widget.ctrl.value.aspectRatio,
            child: VideoPlayer(widget.ctrl),
          ),
        ),
        // Progress bar
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
          child: VideoProgressIndicator(
            widget.ctrl,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.teal,
              backgroundColor: Colors.white30,
              bufferedColor: Colors.white24,
            ),
          ),
        ),
        // Label badge
        Positioned(
          top: 6, left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.navy.withAlpha(180),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-frame detection card
// ---------------------------------------------------------------------------

class _FrameCard extends StatelessWidget {
  const _FrameCard({required this.result, required this.onTap});
  final _FrameResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 60, height: 60,
        child: result.frameFile.existsSync()
            ? Image.file(result.frameFile, fit: BoxFit.cover)
            : Container(
                color: AppColors.teal.withAlpha(30),
                child: Center(
                  child: Text('${result.timestamp}s',
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold,
                      color: AppColors.teal)),
                ),
              ),
      ),
    ),
    title: Text(
      '${result.detectionCount} detection'
      '${result.detectionCount == 1 ? '' : 's'}  ·  ${result.timestamp}s',
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
    ),
    subtitle: Text(
      result.observation.detections.map((d) => d.classCode).toSet().join(', '),
      style: const TextStyle(fontSize: 11, color: Colors.black45),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
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
          color: AppColors.teal, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.0)),
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
  const _FrameResult({
    required this.timestamp,
    required this.observation,
    required this.frameFile,
    required this.detectionCount,
  });
  final int         timestamp;
  final Observation observation;
  final File        frameFile;
  final int         detectionCount;
}

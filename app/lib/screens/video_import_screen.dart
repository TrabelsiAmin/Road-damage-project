import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../inference/preprocessing.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/frame_annotator.dart';
import '../services/observation_repository.dart';
import '../services/territorial_service.dart';
import '../services/video_frame_extractor.dart';
import '../services/video_stitcher.dart';
import 'result_screen.dart';

enum VideoScanMode {
  fast(label: 'Fast Scan', intervalSec: 5, maxFrames: 12, description: '5s interval · up to 12 frames (quick triage)'),
  accurate(label: 'Accurate Scan', intervalSec: 2, maxFrames: 25, description: '2s interval · up to 25 frames (dense inspection)'),
  custom(label: 'Custom', intervalSec: 5, maxFrames: 50, description: 'Custom frame sampling interval');

  const VideoScanMode({
    required this.label,
    required this.intervalSec,
    required this.maxFrames,
    required this.description,
  });

  final String label;
  final int intervalSec;
  final int maxFrames;
  final String description;
}

/// Video Import Screen — full annotated-video pipeline with incremental saving,
/// live diagnostics, scan modes, and completion summaries.
class VideoImportScreen extends StatefulWidget {
  const VideoImportScreen({
    super.key,
    required this.service,
    required this.actor,
    this.repository,
    this.organizationId,
  });

  final DetectionService service;
  final String actor;
  final ObservationRepository? repository;
  final String? organizationId;

  @override
  State<VideoImportScreen> createState() => _VideoImportScreenState();
}

class _VideoImportScreenState extends State<VideoImportScreen> {
  // ── Input video ────────────────────────────────────────────────────────────
  File? _videoFile;
  VideoPlayerController? _inputCtrl;
  Duration _duration = Duration.zero;

  // ── Output annotated video ─────────────────────────────────────────────────
  File? _outputVideo;
  VideoPlayerController? _outputCtrl;

  // ── Processing state & diagnostics ─────────────────────────────────────────
  bool _picking = false;
  bool _processing = false;
  bool _stitching = false;
  int _framesTotal = 0;
  int _framesProc = 0;
  int _currentSec = 0;
  int _totalDetections = 0;
  String _estimatedTimeRemaining = '';
  Stopwatch? _stopwatch;

  VideoScanMode _scanMode = VideoScanMode.fast;
  final int _customInterval = 5;
  String _status = '';

  // ── Results ────────────────────────────────────────────────────────────────
  final _results = <_FrameResult>[];

  // ── Services ───────────────────────────────────────────────────────────────
  final _extractor = VideoFrameExtractor();
  final _annotator = const FrameAnnotator();
  final _stitcher = VideoStitcher();
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

  // ── File picker / camera ───────────────────────────────────────────────────

  Future<void> _loadVideoFile(File file) async {
    final ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    _outputCtrl?.dispose();
    setState(() {
      _videoFile = file;
      _inputCtrl?.dispose();
      _inputCtrl = ctrl;
      _duration = ctrl.value.duration;
      _picking = false;
      _outputVideo = null;
      _outputCtrl = null;
      _results.clear();
      _totalDetections = 0;
      _status = 'Ready — ${file.uri.pathSegments.last}';
    });
  }

  Future<void> _recordVideo() async {
    setState(() { _picking = true; _status = 'Opening camera…'; });
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 10),
      );
      if (picked == null) {
        setState(() { _picking = false; _status = ''; });
        return;
      }
      await _loadVideoFile(File(picked.path));
      if (mounted) {
        await _processFrames();
      }
    } catch (e) {
      setState(() { _picking = false; _status = 'Error: $e'; });
    }
  }

  Future<void> _pickVideoFile() async {
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
      await _loadVideoFile(File(result.files.single.path!));
    } catch (e) {
      setState(() { _picking = false; _status = 'Error: $e'; });
    }
  }

  // ── Main processing pipeline ───────────────────────────────────────────────

  Future<void> _processFrames() async {
    if (_videoFile == null) return;

    _extractor.reset();
    _tempDir = await _extractor.ensureTempDir();

    final interval = _scanMode == VideoScanMode.custom ? _customInterval : _scanMode.intervalSec;
    final maxFrames = _scanMode == VideoScanMode.custom ? 50 : _scanMode.maxFrames;

    final durationSec = _duration.inSeconds;
    var frameTimestamps = <int>[];
    for (var t = 0; t < durationSec; t += interval) {
      frameTimestamps.add(t);
    }

    if (frameTimestamps.length > maxFrames) {
      final step = (frameTimestamps.length / maxFrames).ceil();
      final capped = <int>[];
      for (var i = 0; i < frameTimestamps.length && capped.length < maxFrames; i += step) {
        capped.add(frameTimestamps[i]);
      }
      frameTimestamps = capped;
    }

    setState(() {
      _processing = true;
      _stitching = false;
      _framesProc = 0;
      _totalDetections = 0;
      _framesTotal = frameTimestamps.length;
      _results.clear();
      _outputVideo = null;
      _outputCtrl?.dispose();
      _outputCtrl = null;
      _status = 'Extracting frames…';
      _stopwatch = Stopwatch()..start();
    });

    // GPS snapshot for this session
    Position? position;
    try {
      position = await LocationService().currentPosition();
    } catch (_) {}

    final framePathMap = <int, String>{};

    // Extract → Detect → Annotate → Incrementally Save
    for (final t in frameTimestamps) {
      if (!mounted || !_processing) break;

      _currentSec = t;
      final elapsed = _stopwatch?.elapsedMilliseconds ?? 0;
      if (_framesProc > 0 && elapsed > 0) {
        final msPerFrame = elapsed / _framesProc;
        final remainingFrames = _framesTotal - _framesProc;
        final remainingSec = ((msPerFrame * remainingFrames) / 1000).round();
        _estimatedTimeRemaining = '~${remainingSec}s remaining';
      } else {
        _estimatedTimeRemaining = 'calculating…';
      }

      setState(() {
        _status = 'Frame ${_framesProc + 1}/$_framesTotal (${t}s) — analyzing…';
      });

      try {
        final rawFrame = await _extractor.extractFrame(
          _videoFile!,
          timestampSec: t,
          tempDir: _tempDir!,
        );

        if (rawFrame == null) {
          setState(() { _framesProc++; });
          continue;
        }

        final agentResults = await widget.service.detectAll(rawFrame);
        final detections = agentResults.expand((r) => r.detections).toList();

        File frameToStitch = rawFrame;
        if (detections.isNotEmpty) {
          _totalDetections += detections.length;
          setState(() {
            _status = 'Frame ${_framesProc + 1}/$_framesTotal (${t}s) — ${detections.length} defect(s) found';
          });

          frameToStitch = await _annotator.annotateFrame(rawFrame, detections);
          final frameBytes = await frameToStitch.readAsBytes();
          final decoded = decodeAndOrient(frameBytes);

          final obs = Observation(
            id: const Uuid().v4(),
            captureId: const Uuid().v4(),
            organizationId: widget.organizationId,
            imagePath: frameToStitch.path,
            createdAt: DateTime.now().toUtc(),
            latitude: position?.latitude ?? 0.0,
            longitude: position?.longitude ?? 0.0,
            accuracyMeters: position?.accuracy,
            agentResults: agentResults,
            actor: widget.actor,
            imageWidth: decoded.width,
            imageHeight: decoded.height,
            modelBundleVersion: TariqMapConstants.modelBundleVersion,
          );

          // Priority 1 requirement: Incrementally save detected frame observations
          if (widget.repository != null) {
            await widget.repository!.save(obs);
          }

          debugPrint('[VideoPipeline] Observation saved: ${obs.id}, timestamp: ${t}s, defects: ${detections.length}');

          if (mounted) {
            setState(() => _results.add(_FrameResult(
              timestamp: t,
              observation: obs,
              frameFile: frameToStitch,
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

    _stopwatch?.stop();

    if (!mounted || !_processing) {
      setState(() { _processing = false; _stitching = false; });
      if (_results.isNotEmpty && mounted) {
        _showSummaryDialog(wasCancelled: true);
      }
      return;
    }

    // Step 5: Stitch all annotated frames into output MP4
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
        frames: stitchFrames,
        frameIntervalSec: interval,
        originalDurationSec: durationSec,
        outputPath: outputPath,
      );

      if (outFile != null && mounted) {
        final ctrl = VideoPlayerController.file(outFile);
        await ctrl.initialize();
        setState(() {
          _outputVideo = outFile;
          _outputCtrl = ctrl;
        });
      }
    }

    if (mounted) {
      setState(() {
        _processing = false;
        _stitching = false;
        _status = _outputVideo != null
            ? '✓ Video ready · ${_results.length} frames with defects'
            : 'Done · ${_results.length} frames with defects';
      });
      _showSummaryDialog(wasCancelled: false);
    }
  }

  Future<void> _cancelProcessing() async {
    _extractor.cancel();
    await _stitcher.cancel();
    if (mounted) {
      setState(() {
        _processing = false;
        _stitching = false;
        _status = 'Processing cancelled. Saved ${_results.length} frame observations.';
      });
    }
  }

  void _showSummaryDialog({required bool wasCancelled}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(
            wasCancelled ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            color: wasCancelled ? Colors.orange : AppColors.syncDone,
            size: 26,
          ),
          const SizedBox(width: 10),
          Text(wasCancelled ? 'Scan Interrupted' : 'Inspection Complete'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wasCancelled
                  ? 'Video processing was stopped, but all processed defect frames were saved to local storage.'
                  : 'Video analysis completed successfully.',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            _SummaryStatRow(label: 'Analyzed Frames', value: '$_framesProc / $_framesTotal'),
            const SizedBox(height: 6),
            _SummaryStatRow(label: 'Total Detections', value: '$_totalDetections defects'),
            const SizedBox(height: 6),
            _SummaryStatRow(label: 'Saved Observations', value: '${_results.length} observations'),
            if (_outputVideo != null) ...[
              const SizedBox(height: 6),
              const _SummaryStatRow(label: 'Annotated Video', value: 'Generated (MP4)'),
            ],
          ],
        ),
        actions: [
          if (_outputVideo != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _outputCtrl?.play();
              },
              child: const Text('Play Video'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('View Results'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOutput() async {
    if (_outputVideo == null) return;
    await Share.shareXFiles(
      [XFile(_outputVideo!.path)],
      text: 'TariqMap — Annotated road inspection video',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _picking || _processing || _stitching;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Video Road Inspection', style: TextStyle(fontWeight: FontWeight.bold)),
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
            title: 'INPUT VIDEO',
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isBusy ? null : _recordVideo,
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('Record', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.teal),
                        foregroundColor: AppColors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isBusy ? null : _pickVideoFile,
                      icon: const Icon(Icons.video_file_outlined),
                      label: Text(_videoFile == null ? 'From Files' : 'Change Video'),
                    ),
                  ),
                ]),
                if (_videoFile != null && _inputCtrl != null) ...[
                  const SizedBox(height: 12),
                  _VideoPreview(ctrl: _inputCtrl!, label: 'Input Preview'),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(
                      'Duration: ${_duration.inMinutes}m ${_duration.inSeconds % 60}s',
                      style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Authority: ${widget.actor}',
                      style: const TextStyle(color: AppColors.teal, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ]),
                ],
              ],
            ),
          ),

          if (_videoFile != null) ...[
            const SizedBox(height: 16),

            // ── Scan Mode Toggle ──────────────────────────────────────────
            _Section(
              title: 'SCAN INTENSITY & MODE',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ScanModeChoiceCard(
                          title: 'Fast Scan',
                          subtitle: '5s interval · max 12 frames',
                          isSelected: _scanMode == VideoScanMode.fast,
                          onTap: isBusy ? null : () => setState(() => _scanMode = VideoScanMode.fast),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ScanModeChoiceCard(
                          title: 'Accurate Scan',
                          subtitle: '2s interval · max 25 frames',
                          isSelected: _scanMode == VideoScanMode.accurate,
                          onTap: isBusy ? null : () => setState(() => _scanMode = VideoScanMode.accurate),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scanMode.description,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Run / Cancel Button ────────────────────────────────────────
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (_processing || _stitching) ? null : _processFrames,
                  icon: (_processing || _stitching)
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _stitching ? 'Stitching video…' :
                    _processing ? 'Processing frames…' :
                                  'Start Video AI Scan',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _cancelProcessing,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop & Save'),
                ),
              ],
            ]),

            // ── Live Diagnostics Card ──────────────────────────────────────
            if (_processing || _stitching || _status.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.teal.withAlpha(40)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            if (_processing || _stitching)
                              const SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                              ),
                            if (_processing || _stitching) const SizedBox(width: 8),
                            Text(
                              _processing ? 'Live Diagnostics' : 'Status',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.navy),
                            ),
                          ]),
                          if (_estimatedTimeRemaining.isNotEmpty && _processing)
                            Text(
                              _estimatedTimeRemaining,
                              style: const TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: _framesTotal > 0 ? (_framesProc / _framesTotal).clamp(0.0, 1.0) : null,
                        backgroundColor: AppColors.teal.withAlpha(30),
                        valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Processed: $_framesProc / $_framesTotal frames (${_currentSec}s)',
                            style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        Text('Defects: $_totalDetections found',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _totalDetections > 0 ? AppColors.high : Colors.black54,
                            )),
                      ]),
                      const SizedBox(height: 4),
                      Text(_status, style: const TextStyle(color: Colors.black87, fontSize: 12)),
                    ],
                  ),
                ),
              ),
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
                  ],
                ),
              ),
            ],

            // ── Per-frame detection results ───────────────────────────────
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'DEFECT FRAMES (${_results.length})',
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

class _ScanModeChoiceCard extends StatelessWidget {
  const _ScanModeChoiceCard({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.teal.withAlpha(20) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.teal : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: isSelected ? AppColors.teal : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: isSelected ? AppColors.teal : AppColors.navy,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStatRow extends StatelessWidget {
  const _SummaryStatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

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
      '${result.detectionCount == 1 ? '' : 's'} · ${result.timestamp}s',
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
  final int timestamp;
  final Observation observation;
  final File frameFile;
  final int detectionCount;
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/observation_repository.dart';
import '../data/remote/supabase_service.dart';
import '../utils/yuv_converter.dart';
import 'result_screen.dart';

/// Full-screen live camera view with real-time bounding-box overlay.
///
/// Detection runs on every [_frameInterval]-th camera frame so the UI stays
/// responsive. On capture the current frame is frozen, saved as an Observation,
/// and the ResultScreen is pushed.
///
/// Live results are published through [ValueNotifier]s so only the overlay
/// widgets rebuild per inference; the camera preview is never rebuilt.
class CameraDetectionScreen extends StatefulWidget {
  const CameraDetectionScreen({
    super.key,
    required this.detectionService,
    required this.repository,
    required this.actor,
  });

  final DetectionService detectionService;
  final ObservationRepository repository;
  final String actor;

  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;
  bool _processing = false;
  bool _capturing = false;
  int _frameCount = 0;
  // Computed from SharedPreferences 'live_fps' setting.
  int _frameInterval = 5;

  // Live state: updated without setState, rebuilds only the listeners below.
  final ValueNotifier<List<Detection>> _detections =
      ValueNotifier<List<Detection>>(const []);
  final ValueNotifier<double> _fps = ValueNotifier<double>(0);
  final ValueNotifier<int> _latency = ValueNotifier<int>(0);

  final _uuid = const Uuid();
  DateTime? _lastFrameTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings().then((_) => _initCamera());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final fps = prefs.getInt('live_fps') ?? TariqMapConstants.defaultLiveFps;
    if (mounted) {
      setState(() {
        _frameInterval = (30 / fps.clamp(1, 30)).round().clamp(1, 30);
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _startCamera(_cameras.first);
    } catch (e) {
      debugPrint('[Camera] Init error: $e');
    }
  }

  Future<void> _startCamera(CameraDescription desc) async {
    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _initialized = true;
    });
    controller.startImageStream(_onCameraFrame);
  }

  void _onCameraFrame(CameraImage frame) {
    if (_processing || _capturing) return;
    _frameCount++;
    if (_frameCount % _frameInterval != 0) return;

    _processing = true;
    _runDetectionOnFrame(frame).then((results) {
      if (!mounted) return;
      final detections = results.expand((r) => r.detections).toList();

      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final elapsed = now.difference(_lastFrameTime!).inMilliseconds;
        _fps.value = elapsed > 0 ? 1000 / elapsed : 0;
      }
      _lastFrameTime = now;

      _latency.value = results.fold<int>(
        0,
        (max, r) => r.latencyMs != null && r.latencyMs! > max ? r.latencyMs! : max,
      );

      // New list instance every time, so the painter's shouldRepaint fires.
      _detections.value = detections;
    }).catchError((e) {
      debugPrint('[Camera] Frame inference error: $e');
    }).whenComplete(() {
      _processing = false;
    });
  }

  Future<List<AgentResult>> _runDetectionOnFrame(CameraImage frame) async {
    if (frame.format.group == ImageFormatGroup.yuv420) {
      // Persistent isolate: YUV420 -> Float32 tensor, no per-frame isolate spawn.
      final tensor = await convertYUVToTensorInBackground(frame, 640);
      return widget.detectionService.detectAllFromTensor(tensor);
    } else if (frame.format.group == ImageFormatGroup.jpeg) {
      return widget.detectionService.detectAllFromBytes(frame.planes.first.bytes);
    } else if (frame.format.group == ImageFormatGroup.bgra8888) {
      final tensor = await _bgraToTensor(frame, 640);
      return widget.detectionService.detectAllFromTensor(tensor);
    }
    return [];
  }

  Future<Float32List> _bgraToTensor(CameraImage frame, int targetSize) async {
    return compute(_bgraToTensorIsolate, {
      'bytes': frame.planes.first.bytes,
      'width': frame.width,
      'height': frame.height,
      'targetSize': targetSize,
    });
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    setState(() => _capturing = true);

    try {
      // Stop stream, take high-quality photo, restart stream.
      await _controller!.stopImageStream();
      final photo = await _controller!.takePicture();

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
      } catch (_) {}

      final imageFile = File(photo.path);
      final results = await widget.detectionService.detectAll(imageFile);
      final observation = Observation(
        id: _uuid.v4(),
        captureId: _uuid.v4(),
        imagePath: photo.path,
        createdAt: DateTime.now().toUtc(),
        latitude: position?.latitude ?? 0,
        longitude: position?.longitude ?? 0,
        accuracyMeters: position?.accuracy,
        actor: widget.actor,
        agentResults: results,
      );
      await widget.repository.save(observation);

      SupabaseService.instance
          .syncObservation(observation, imageFile: imageFile)
          .catchError((e) {
        debugPrint('[Camera] Supabase sync skipped (offline?): $e');
      });

      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ResultScreen(observation: observation),
          ),
        );
      }

      if (mounted && _controller != null) {
        await _controller!.startImageStream(_onCameraFrame);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    final current = _controller?.description;
    final next = _cameras.firstWhere(
      (c) => c != current,
      orElse: () => _cameras.first,
    );
    await _controller?.stopImageStream();
    await _controller?.dispose();
    setState(() {
      _controller = null;
      _initialized = false;
    });
    await _startCamera(next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _detections.dispose();
    _fps.dispose();
    _latency.dispose();
    YuvConverter.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview (only rebuilt by setState for init/capture) ──
          if (_initialized && _controller != null)
            RepaintBoundary(child: CameraPreview(_controller!))
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Initialising camera…', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),

          // ── Bounding box overlay ─────────────────────────────────
          if (_initialized && _controller != null)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<List<Detection>>(
                    valueListenable: _detections,
                    builder: (_, dets, __) => dets.isEmpty
                        ? const SizedBox.shrink()
                        : CustomPaint(painter: _LiveBoxPainter(dets)),
                  ),
                ),
              ),
            ),

          // ── Top bar ─────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Detection counter
                    ValueListenableBuilder<List<Detection>>(
                      valueListenable: _detections,
                      builder: (_, dets, __) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: dets.isEmpty ? Colors.black45 : Colors.red.withAlpha(200),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          dets.isEmpty
                              ? 'Scanning…'
                              : '${dets.length} anomal${dets.length == 1 ? 'y' : 'ies'} detected',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Diagnostics
                    AnimatedBuilder(
                      animation: Listenable.merge([_fps, _latency]),
                      builder: (_, __) => Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_fps.value.toStringAsFixed(0)} FPS',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          if (_latency.value > 0)
                            Text(
                              '${_latency.value}ms Inf',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Live detection label strip ───────────────────────────
          Positioned(
            bottom: 140,
            left: 12, right: 12,
            child: ValueListenableBuilder<List<Detection>>(
              valueListenable: _detections,
              builder: (_, dets, __) {
                if (dets.isEmpty) return const SizedBox.shrink();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: dets.map((d) {
                      final color = AppColors.forClassCode(d.classCode);
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withAlpha(220),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${TariqMapConstants.labelFor(d.classCode)}  ${(d.confidence * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),

          // ── Bottom controls ──────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlButton(
                      icon: Icons.flip_camera_android_outlined,
                      label: 'Flip',
                      onTap: _cameras.length > 1 ? _switchCamera : null,
                    ),
                    GestureDetector(
                      onTap: _capturing ? null : _capture,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _capturing ? 68 : 72,
                        height: _capturing ? 68 : 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _capturing ? Colors.grey : Colors.white,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.white.withAlpha(80), blurRadius: 16),
                          ],
                        ),
                        child: _capturing
                            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.camera, color: Colors.black, size: 32),
                      ),
                    ),
                    const _ControlButton(icon: Icons.info_outline, label: 'Info', onTap: null),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live bounding box painter
// ---------------------------------------------------------------------------

class _LiveBoxPainter extends CustomPainter {
  _LiveBoxPainter(this.detections);
  final List<Detection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final color = AppColors.forClassCode(d.classCode);
      final b = d.box;
      final rect = Rect.fromLTWH(
        b.x * size.width,
        b.y * size.height,
        b.width * size.width,
        b.height * size.height,
      );

      canvas.drawRect(rect.inflate(4),
          Paint()..color = color.withAlpha(50)..style = PaintingStyle.fill);

      canvas.drawRect(rect,
          Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);

      final label =
          '${TariqMapConstants.labelFor(d.classCode)}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
              color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const pad = 4.0;
      final pillRect = Rect.fromLTWH(
          rect.left, rect.top - tp.height - pad * 2, tp.width + pad * 2, tp.height + pad * 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(pillRect, const Radius.circular(4)), Paint()..color = color);
      tp.paint(canvas, Offset(pillRect.left + pad, pillRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(_LiveBoxPainter old) => old.detections != detections;
}

// ---------------------------------------------------------------------------
// Small icon button used in bottom controls
// ---------------------------------------------------------------------------

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: onTap != null ? Colors.black45 : Colors.black26,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: onTap != null ? Colors.white : Colors.white38, size: 22),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: onTap != null ? Colors.white70 : Colors.white30, fontSize: 10)),
          ],
        ),
      );
}

// ── Background Isolates ────────────────────────────────────────────────────────

Float32List _bgraToTensorIsolate(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final width = params['width'] as int;
  final height = params['height'] as int;
  final targetSize = params['targetSize'] as int;

  final out = Float32List(targetSize * targetSize * 3);
  int idx = 0;

  final xScale = width / targetSize;
  final yScale = height / targetSize;

  for (var dy = 0; dy < targetSize; dy++) {
    final srcY = (dy * yScale).toInt().clamp(0, height - 1);
    final rowOffset = srcY * width * 4;

    for (var dx = 0; dx < targetSize; dx++) {
      final srcX = (dx * xScale).toInt().clamp(0, width - 1);
      final pixelOffset = rowOffset + srcX * 4;

      final b = bytes[pixelOffset];
      final g = bytes[pixelOffset + 1];
      final r = bytes[pixelOffset + 2];

      out[idx++] = r / 255.0;
      out[idx++] = g / 255.0;
      out[idx++] = b / 255.0;
    }
  }

  return out;
}
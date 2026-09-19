import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../inference/temporal_smoothing.dart';
import '../inference/yuv_converter.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/observation_repository.dart';
import 'result_screen.dart';

class _ConvertJob {
  const _ConvertJob(this.frame, this.rotation);
  final RawCameraFrame frame;
  final int rotation;
}

Uint8List _convertInIsolate(_ConvertJob job) =>
    convertFrameToJpeg(job.frame, rotationDegrees: job.rotation);

/// Full-screen live camera view with real-time bounding-box overlay.
///
/// Frames are converted from YUV420 / NV21 / BGRA (not assumed JPEG),
/// run through DetectionService with mock boxes disabled, temporally
/// smoothed, and painted on the camera preview (not the whole UI stack).
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
  bool _inferenceBusy = false;
  bool _capturing = false;
  int _frameCount = 0;
  static const int _frameInterval = 5;

  List<Detection> _liveDetections = [];
  final _uuid = const Uuid();
  final _smoother = TemporalSmoother();

  double _fps = 0;
  int _lastLatency = 0;
  DateTime? _lastFrameTime;
  String? _statusNote;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _startCamera(_cameras.first);
    } catch (e) {
      debugPrint('[Camera] Init error: $e');
      if (mounted) setState(() => _statusNote = 'Camera init failed: $e');
    }
  }

  ImageFormatGroup _preferredFormat() {
    // Do not assume JPEG. Prefer YUV on Android, BGRA on iOS.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ImageFormatGroup.bgra8888;
    }
    return ImageFormatGroup.yuv420;
  }

  Future<void> _startCamera(CameraDescription desc) async {
    final controller = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: _preferredFormat(),
    );
    await controller.initialize();
    if (!mounted) return;
    _smoother.reset();
    setState(() {
      _controller = controller;
      _initialized = true;
      if (widget.detectionService.usingMock) {
        _statusNote =
            'REQUIRES MODEL: live boxes are disabled until TFLite weights are installed.';
      }
    });
    controller.startImageStream(_onCameraFrame);
  }

  void _onCameraFrame(CameraImage frame) {
    if (_inferenceBusy || _capturing || _controller == null) return;
    _frameCount++;
    if (_frameCount % _frameInterval != 0) return;

    _inferenceBusy = true;
    final sw = Stopwatch()..start();
    _runDetectionOnFrame(frame).then((results) {
      if (!mounted) return;
      final raw = results.expand((r) => r.detections).toList();
      final smoothed = _smoother.update(raw);
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final elapsed = now.difference(_lastFrameTime!).inMilliseconds;
        _fps = elapsed > 0 ? (1000 / elapsed * _frameInterval) : 0;
      }
      _lastFrameTime = now;
      final measured = sw.elapsedMilliseconds;
      final reported = results.fold<int>(
        0,
        (max, r) => r.latencyMs != null && r.latencyMs! > max ? r.latencyMs! : max,
      );
      setState(() {
        _liveDetections = smoothed;
        _lastLatency = reported > 0 ? reported : measured;
      });
    }).catchError((Object e) {
      debugPrint('[Camera] inference error: $e');
    }).whenComplete(() {
      _inferenceBusy = false;
    });
  }

  RawCameraFrame _toRaw(CameraImage image) {
    final name = image.format.group.name;
    final format = switch (name) {
      'jpeg' => 'jpeg',
      'bgra8888' => 'bgra8888',
      'nv21' => 'nv21',
      _ => 'yuv420',
    };
    return RawCameraFrame(
      width: image.width,
      height: image.height,
      format: format,
      planes: image.planes.map((p) => Uint8List.fromList(p.bytes)).toList(),
      bytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
      bytesPerPixel: image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
    );
  }

  Future<List<AgentResult>> _runDetectionOnFrame(CameraImage frame) async {
    try {
      final raw = _toRaw(frame);
      final rotation = _controller?.description.sensorOrientation ?? 0;
      final jpeg = await compute(_convertInIsolate, _ConvertJob(raw, rotation));
      if (jpeg.isEmpty) return const [];
      return widget.detectionService.detectAllBytes(jpeg, allowMock: false);
    } catch (e) {
      debugPrint('[Camera] Frame inference error: $e');
      return const [];
    }
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    setState(() => _capturing = true);

    try {
      await _controller!.stopImageStream();
      final photo = await _controller!.takePicture();

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
      } catch (_) {}

      final imageFile = File(photo.path);
      final results = await widget.detectionService.detectAll(
        imageFile,
        allowMock: false,
      );
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

      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ResultScreen(observation: observation),
          ),
        );
      }

      if (mounted && _controller != null) {
        _smoother.reset();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized && preview != null)
            Center(
              child: AspectRatio(
                aspectRatio: preview.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(preview),
                    if (_liveDetections.isNotEmpty)
                      CustomPaint(
                        painter: _LiveBoxPainter(_liveDetections),
                      ),
                  ],
                ),
              ),
            )
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _liveDetections.isEmpty ? Colors.black45 : Colors.red.withAlpha(200),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _liveDetections.isEmpty
                            ? 'Scanning…'
                            : '${_liveDetections.length} anomal${_liveDetections.length == 1 ? 'y' : 'ies'} detected',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_fps.toStringAsFixed(0)} FPS',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        if (_lastLatency > 0)
                          Text(
                            '${_lastLatency}ms inf',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_statusNote != null)
            Positioned(
              top: 88, left: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xCC5C4A00),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusNote!,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),

          if (_liveDetections.isNotEmpty)
            Positioned(
              bottom: 140,
              left: 12, right: 12,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _liveDetections.map((d) {
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
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

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

      final label = '${TariqMapConstants.labelFor(d.classCode)}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      const pad = 4.0;
      final pillRect = Rect.fromLTWH(rect.left, rect.top - tp.height - pad * 2, tp.width + pad * 2, tp.height + pad * 2);
      canvas.drawRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(4)), Paint()..color = color);
      tp.paint(canvas, Offset(pillRect.left + pad, pillRect.top + pad));
    }
  }

  @override
  bool shouldRepaint(_LiveBoxPainter old) => old.detections != detections;
}

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
          child: Icon(icon, color: onTap != null ? Colors.white : Colors.white38, size: 22),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: onTap != null ? Colors.white70 : Colors.white30, fontSize: 10)),
      ],
    ),
  );
}

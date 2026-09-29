import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/live_stream_session.dart';
import '../services/observation_repository.dart';
import '../utils/yuv_converter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// Live Road Streaming Screen.
///
/// Features:
///  • Real-time on-device YOLOv8 inference on every N-th camera frame.
///  • Animated bounding-box overlay with class-coloured glows.
///  • Record Session button — starts a LiveStreamSession that uploads every
///    anomalous keyframe JPEG directly to Supabase Storage.
///  • Live stats HUD: timer, FPS, anomaly count, upload status indicator.
///  • Session summary bottom sheet on stop.
class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({
    super.key,
    required this.detectionService,
    required this.repository,
    required this.actor,
  });

  final DetectionService      detectionService;
  final ObservationRepository repository;
  final String                actor;

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {

  // Camera
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;
  bool _processing  = false;
  int  _frameCount  = 0;
  int  _frameInterval = 5;

  // Detections
  List<Detection> _liveDetections = [];
  double _fps = 0;
  int    _lastLatency = 0;
  DateTime? _lastFrameTime;

  // Session
  LiveStreamSession? _session;
  SessionState       _sessionState  = SessionState.idle;
  SessionStats?      _sessionStats;
  int   _sessionAnomalies = 0;
  bool  _uploadingFrame   = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnim;
  late AnimationController _recordBtnController;

  // GPS
  Position? _currentPosition;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.0, end: 1.0).animate(_pulseController);

    _recordBtnController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));

    _loadSettings().then((_) => _initCamera());
    _startGpsUpdates();
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

  StreamSubscription<Position>? _gpsSub;
  void _startGpsUpdates() {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      _currentPosition = pos;
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _startCamera(_cameras.first);
    } catch (e) {
      debugPrint('[LiveStream] Camera init error: $e');
    }
  }

  Future<void> _startCamera(CameraDescription desc) async {
    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
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
    if (_processing) return;
    _frameCount++;
    if (_frameCount % _frameInterval != 0) return;

    _processing = true;
    _runInference(frame).then((detections) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final elapsed = now.difference(_lastFrameTime!).inMilliseconds;
        _fps = elapsed > 0 ? (1000 / elapsed * _frameInterval) : 0;
      }
      _lastFrameTime = now;
      setState(() => _liveDetections = detections);
    }).catchError((e) {
      debugPrint('[LiveStream] Inference error: $e');
    }).whenComplete(() => _processing = false);
  }

  Future<List<Detection>> _runInference(CameraImage frame) async {
    Uint8List? jpegBytes;
    
    if (frame.format.group == ImageFormatGroup.jpeg) {
      jpegBytes = frame.planes.first.bytes;
    } else if (frame.format.group == ImageFormatGroup.yuv420) {
      final imgObj = convertYUV420ToImage(frame);
      jpegBytes = img.encodeJpg(imgObj, quality: 80);
    } else if (frame.format.group == ImageFormatGroup.bgra8888) {
      final imgObj = img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.planes.first.bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
      jpegBytes = img.encodeJpg(imgObj, quality: 80);
    }

    if (jpegBytes == null) return [];

    final results = await widget.detectionService.detectAllFromBytes(jpegBytes);
    final detections = results.expand((r) => r.detections).toList();

    // If recording, send frame to session manager
    if (_session != null && _sessionState == SessionState.recording) {
      final sessionDetections = await _session!.addFrame(
        jpegBytes, position: _currentPosition);
      if (sessionDetections.isNotEmpty) {
        setState(() {
          _sessionAnomalies = _session!.totalAnomalies;
          _uploadingFrame   = true;
        });
        // Clear upload indicator after 800ms
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _uploadingFrame = false);
        });
      }
    }

    final maxLatency = results.fold<int>(0,
        (m, r) => r.latencyMs != null && r.latencyMs! > m ? r.latencyMs! : m);
    _lastLatency = maxLatency;
    return detections;
  }

  // ── Session controls ─────────────────────────────────────────────────────

  Future<void> _startSession() async {
    final session = LiveStreamSession(
      detectionService: widget.detectionService,
      repository:       widget.repository,
      actor:            widget.actor,
    );

    session.stateStream.listen((s) {
      if (mounted) setState(() => _sessionState = s);
    });
    session.statsStream.listen((stats) {
      if (mounted) setState(() => _sessionStats = stats);
    });

    setState(() {
      _session         = session;
      _sessionState    = SessionState.starting;
      _sessionAnomalies = 0;
    });
    _recordBtnController.forward();

    try {
      await session.start(position: _currentPosition);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create session: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _sessionState = SessionState.idle);
        _recordBtnController.reverse();
      }
    }
  }

  Future<void> _stopSession() async {
    if (_session == null) return;
    final session = _session!;
    _recordBtnController.reverse();

    await session.stop();
    if (!mounted) return;

    _showSessionSummary(session);
    setState(() {
      _session      = null;
      _sessionState = SessionState.idle;
    });
  }

  void _showSessionSummary(LiveStreamSession session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionSummarySheet(
        keyFrames:     session.keyFrames,
        totalFrames:   session.totalFrames,
        totalAnomalies: session.totalAnomalies,
        elapsed:       session.elapsed,
        sessionId:     session.sessionId ?? '',
      ),
    );
    session.dispose();
  }

  // ── Camera controls ──────────────────────────────────────────────────────

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final current = _controller?.description;
    final next = _cameras.firstWhere(
      (c) => c != current,
      orElse: () => _cameras.first,
    );
    await _controller?.stopImageStream();
    await _controller?.dispose();
    setState(() {
      _controller  = null;
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
    _gpsSub?.cancel();
    _controller?.dispose();
    _pulseController.dispose();
    _recordBtnController.dispose();
    _session?.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  bool get _isRecording =>
      _sessionState == SessionState.recording ||
      _sessionState == SessionState.starting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ─────────────────────────────────────────────
          if (_initialized && _controller != null)
            CameraPreview(_controller!)
          else
            const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Initialising camera…',
                    style: TextStyle(color: Colors.white70)),
              ]),
            ),

          // ── Bounding-box overlay ────────────────────────────────────────
          if (_initialized && _liveDetections.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _LiveBoxPainter(_liveDetections),
              ),
            ),

          // ── Recording pulsing border ────────────────────────────────────
          if (_isRecording)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.red
                            .withAlpha((120 * _pulseAnim.value).round()),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Top HUD ────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  // Back
                  _GlassButton(
                    icon: Icons.arrow_back,
                    onTap: () {
                      if (_isRecording) _stopSession();
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 10),

                  // Detection badge
                  _DetectionBadge(count: _liveDetections.length),
                  const Spacer(),

                  // Upload indicator
                  if (_uploadingFrame)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withAlpha(200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        ),
                        const SizedBox(width: 5),
                        Text('Uploading',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                      ]),
                    ),

                  // FPS / latency
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${_fps.toStringAsFixed(0)} FPS',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    if (_lastLatency > 0)
                      Text('${_lastLatency}ms',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                  ]),
                ]),
              ),
            ),
          ),

          // ── Session stats banner (while recording) ─────────────────────
          if (_isRecording && _sessionStats != null)
            Positioned(
              top: 90, left: 0, right: 0,
              child: Center(
                child: _SessionStatsBanner(
                  stats: _sessionStats!,
                  anomalies: _sessionAnomalies,
                ),
              ),
            ),

          // ── Detection labels strip ──────────────────────────────────────
          if (_liveDetections.isNotEmpty)
            Positioned(
              bottom: 140, left: 12, right: 12,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _liveDetections.map((d) {
                    final color = AppColors.forClassCode(d.classCode);
                    return Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withAlpha(220),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${TariqMapConstants.labelFor(d.classCode)}  '
                        '${(d.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // ── Bottom controls ─────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Flip camera
                    _ControlButton(
                      icon:  Icons.flip_camera_android_outlined,
                      label: 'Flip',
                      onTap: _cameras.length > 1 ? _switchCamera : null,
                    ),

                    // Record / Stop button
                    _RecordButton(
                      isRecording: _isRecording,
                      isLoading:   _sessionState == SessionState.starting ||
                                   _sessionState == SessionState.stopping ||
                                   _sessionState == SessionState.uploading,
                      onTap:       _isRecording ? _stopSession : _startSession,
                      anomalyCount: _sessionAnomalies,
                    ),

                    // Anomaly counter pill
                    _ControlButton(
                      icon:  Icons.analytics_outlined,
                      label: '$_sessionAnomalies found',
                      onTap: null,
                    ),
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

// ── Live bounding box painter ─────────────────────────────────────────────────

class _LiveBoxPainter extends CustomPainter {
  const _LiveBoxPainter(this.detections);
  final List<Detection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final color = AppColors.forClassCode(d.classCode);
      final b = d.box;
      final rect = Rect.fromLTWH(
        b.x * size.width, b.y * size.height,
        b.width * size.width, b.height * size.height,
      );
      // Glow
      canvas.drawRect(rect.inflate(6),
          Paint()..color = color.withAlpha(40)..style = PaintingStyle.fill);
      // Box
      canvas.drawRect(rect,
          Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);
      // Label pill
      final label =
          '${TariqMapConstants.labelFor(d.classCode)}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      const pad = 4.0;
      final pill = Rect.fromLTWH(rect.left, rect.top - tp.height - pad * 2,
          tp.width + pad * 2, tp.height + pad * 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(pill, const Radius.circular(4)),
          Paint()..color = color);
      tp.paint(canvas, Offset(pill.left + pad, pill.top + pad));
    }
  }

  @override
  bool shouldRepaint(_LiveBoxPainter old) => old.detections != detections;
}

// ── Widget components ─────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );
}

class _DetectionBadge extends StatelessWidget {
  const _DetectionBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: count == 0
          ? Colors.black.withAlpha(140)
          : Colors.red.withAlpha(200),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withAlpha(30)),
    ),
    child: Text(
      count == 0
          ? 'Scanning road…'
          : '$count anomal${count == 1 ? 'y' : 'ies'}',
      style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12),
    ),
  );
}

class _SessionStatsBanner extends StatelessWidget {
  const _SessionStatsBanner({required this.stats, required this.anomalies});
  final SessionStats stats;
  final int          anomalies;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withAlpha(170),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.red.withAlpha(120)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      // REC dot
      const _RecDot(),
      const SizedBox(width: 10),
      Text(stats.elapsedFormatted,
          style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13)),
      const SizedBox(width: 16),
      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 14),
      const SizedBox(width: 4),
      Text('$anomalies anomalies',
          style: GoogleFonts.inter(color: Colors.amber, fontSize: 12)),
      const SizedBox(width: 16),
      const Icon(Icons.cloud_upload_outlined, color: Colors.greenAccent, size: 14),
      const SizedBox(width: 4),
      Text('${stats.keyFrameCount} uploaded',
          style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 12)),
    ]),
  );
}

class _RecDot extends StatelessWidget {
  const _RecDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 10, height: 10,
    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
  );
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.isRecording,
    required this.isLoading,
    required this.onTap,
    required this.anomalyCount,
  });
  final bool         isRecording;
  final bool         isLoading;
  final VoidCallback onTap;
  final int          anomalyCount;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isLoading ? null : onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 76, height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording ? Colors.red : Colors.white,
          border: Border.all(
            color: isRecording ? Colors.red.shade300 : Colors.white,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: (isRecording ? Colors.red : Colors.white).withAlpha(80),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: isRecording ? 28 : 20,
                  height: isRecording ? 28 : 20,
                  decoration: BoxDecoration(
                    color: isRecording ? Colors.white : Colors.red,
                    borderRadius: BorderRadius.circular(isRecording ? 6 : 100),
                  ),
                ),
              ),
      ),
      const SizedBox(height: 6),
      Text(
        isLoading
            ? 'Wait…'
            : (isRecording ? 'Stop Recording' : 'Start Session'),
        style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold),
      ),
    ]),
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData       icon;
  final String         label;
  final VoidCallback?  onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              color: onTap != null ? Colors.white70 : Colors.white30,
              fontSize: 9)),
    ]),
  );
}

// ── Session Summary Bottom Sheet ──────────────────────────────────────────────

class _SessionSummarySheet extends StatelessWidget {
  const _SessionSummarySheet({
    required this.keyFrames,
    required this.totalFrames,
    required this.totalAnomalies,
    required this.elapsed,
    required this.sessionId,
  });

  final List<KeyFrame> keyFrames;
  final int            totalFrames;
  final int            totalAnomalies;
  final Duration       elapsed;
  final String         sessionId;

  String get _durationStr {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.55,
    minChildSize: 0.35,
    maxChildSize: 0.9,
    builder: (_, scrollController) => Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // Handle
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Session Complete',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                Text('ID: ${sessionId.substring(0, 8)}…',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close',
                  style: GoogleFonts.inter(color: Colors.white54)),
            ),
          ]),
        ),

        const SizedBox(height: 16),

        // Stats row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _StatChip(label: 'Duration', value: _durationStr,
                color: Colors.blueAccent),
            const SizedBox(width: 10),
            _StatChip(label: 'Frames', value: '$totalFrames',
                color: Colors.purpleAccent),
            const SizedBox(width: 10),
            _StatChip(label: 'Anomalies', value: '$totalAnomalies',
                color: Colors.redAccent),
            const SizedBox(width: 10),
            _StatChip(label: 'Uploaded', value: '${keyFrames.length}',
                color: Colors.greenAccent),
          ]),
        ),

        const SizedBox(height: 16),
        const Divider(color: Colors.white12),

        // Keyframe grid
        Expanded(
          child: keyFrames.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      Text('No anomalies detected.',
                          style: GoogleFonts.inter(color: Colors.white54)),
                      const SizedBox(height: 4),
                      Text('Road is clear!',
                          style: GoogleFonts.inter(
                              color: Colors.greenAccent, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: keyFrames.length,
                  itemBuilder: (_, i) {
                    final kf = keyFrames[i];
                    return _KeyFrameTile(frame: kf, index: i);
                  },
                ),
        ),
      ]),
    ),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ]),
    ),
  );
}

class _KeyFrameTile extends StatelessWidget {
  const _KeyFrameTile({required this.frame, required this.index});
  final KeyFrame frame;
  final int      index;

  @override
  Widget build(BuildContext context) {
    final uploaded = frame.uploadedUrl != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: uploaded ? Colors.greenAccent.withAlpha(80) : Colors.white12),
      ),
      child: Row(children: [
        // Frame index
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.redAccent.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text('${index + 1}',
                style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),

        // Detections
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              frame.detections.map((d) =>
                  '${TariqMapConstants.labelFor(d.classCode)} (${(d.confidence * 100).toStringAsFixed(0)}%)').join('  ·  '),
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              '${frame.latitude.toStringAsFixed(5)}, ${frame.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ]),
        ),

        // Upload status
        Icon(
          uploaded ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
          color: uploaded ? Colors.greenAccent : Colors.white38,
          size: 18,
        ),
      ]),
    );
  }
}

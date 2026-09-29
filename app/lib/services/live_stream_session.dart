import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/observation.dart';
import 'detection_service.dart';
import '../data/remote/supabase_service.dart';
import 'observation_repository.dart';


/// State of the live recording session.
enum SessionState { idle, starting, recording, stopping, uploading, done, error }

/// A single annotated keyframe captured during a session
/// (frame that had at least one detection).
class KeyFrame {
  KeyFrame({
    required this.captureId,
    required this.timestamp,
    required this.detections,
    required this.latitude,
    required this.longitude,
    this.uploadedUrl,
  });

  final String captureId;
  final DateTime timestamp;
  final List<Detection> detections;
  final double latitude;
  final double longitude;
  String? uploadedUrl;
}

/// Manages a live road-scanning session.
///
/// Workflow:
///   1. start()       — creates session row in Supabase, begins accepting frames.
///   2. addFrame()    — runs on-device inference; if anomalies detected, uploads
///                      the frame JPEG to Supabase Storage immediately.
///   3. stop()        — finalises session metadata in Supabase.
///
/// The class exposes streams so the UI can react to state / stat changes.
class LiveStreamSession {
  LiveStreamSession({
    required this.detectionService,
    required this.repository,
    required this.actor,
    String? deviceId,
  }) : _deviceId = deviceId;

  final DetectionService     detectionService;
  final ObservationRepository repository;
  final String               actor;
  final String?              _deviceId;

  static const _uuid = Uuid();

  // ── State ──────────────────────────────────────────────────────────────────

  String?         sessionId;
  SessionState    state = SessionState.idle;
  DateTime?       _startedAt;

  // Statistics
  int   _totalFramesProcessed = 0;
  int   _totalAnomalies       = 0;
  final List<KeyFrame> _keyFrames = [];

  // GPS
  double _lastLat = 0;
  double _lastLng = 0;

  // Stream controllers
  final _stateController    = StreamController<SessionState>.broadcast();
  final _statsController    = StreamController<SessionStats>.broadcast();
  final _keyFrameController = StreamController<KeyFrame>.broadcast();

  Stream<SessionState>  get stateStream    => _stateController.stream;
  Stream<SessionStats>  get statsStream    => _statsController.stream;
  Stream<KeyFrame>      get keyFrameStream => _keyFrameController.stream;

  List<KeyFrame> get keyFrames        => List.unmodifiable(_keyFrames);
  int            get totalFrames      => _totalFramesProcessed;
  int            get totalAnomalies   => _totalAnomalies;
  Duration       get elapsed          => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  // ── Session lifecycle ──────────────────────────────────────────────────────

  /// Starts a new live session. Returns the Supabase session ID.
  Future<String> start({Position? position}) async {
    _setState(SessionState.starting);
    _startedAt = DateTime.now();
    _lastLat = position?.latitude  ?? 0;
    _lastLng = position?.longitude ?? 0;

    try {
      sessionId = await SupabaseService.instance.createLiveSession(
        latitude:  _lastLat,
        longitude: _lastLng,
        actor:     actor,
        deviceId:  _deviceId,
      );
      _setState(SessionState.recording);
      debugPrint('[LiveStreamSession] Started: $sessionId');
      return sessionId!;
    } catch (e) {
      _setState(SessionState.error);
      debugPrint('[LiveStreamSession] Failed to start: $e');
      rethrow;
    }
  }

  /// Process one camera frame. Runs on-device inference; if anomalies are
  /// detected, uploads the JPEG to Supabase Storage.
  ///
  /// Call this from the camera image stream callback. It is non-blocking —
  /// frames are dropped if the previous frame is still being processed.
  bool _frameProcessing = false;
  Future<List<Detection>> addFrame(
    Uint8List jpegBytes, {
    Position? position,
  }) async {
    if (state != SessionState.recording) return [];
    if (_frameProcessing) return [];
    _frameProcessing = true;

    try {
      if (position != null) {
        _lastLat = position.latitude;
        _lastLng = position.longitude;
      }

      _totalFramesProcessed++;
      final results = await detectionService.detectAllFromBytes(jpegBytes);
      final detections = results.expand((r) => r.detections).toList();

      if (detections.isNotEmpty) {
        _totalAnomalies += detections.length;

        final captureId = _uuid.v4();
        final frame = KeyFrame(
          captureId:  captureId,
          timestamp:  DateTime.now().toUtc(),
          detections: detections,
          latitude:   _lastLat,
          longitude:  _lastLng,
        );
        _keyFrames.add(frame);
        _keyFrameController.add(frame);

        // Upload the JPEG frame to Supabase Storage (fire & forget)
        _uploadFrameAsync(captureId, jpegBytes, frame);
      }

      // Emit stats every 30 frames
      if (_totalFramesProcessed % 30 == 0) {
        _emitStats();

        // Throttled session update to Supabase (every 30 frames)
        if (sessionId != null) {
          SupabaseService.instance.updateLiveSession(
            sessionId:  sessionId!,
            frameCount: _totalFramesProcessed,
            anomalyCount: _totalAnomalies,
            latitude:   _lastLat,
            longitude:  _lastLng,
          ).ignore();
        }
      }

      return detections;
    } finally {
      _frameProcessing = false;
    }
  }

  void _uploadFrameAsync(
    String captureId,
    Uint8List jpegBytes,
    KeyFrame frame,
  ) {
    if (sessionId == null) return;
    SupabaseService.instance
        .uploadObservationImageBytes(
          observationId: sessionId!,
          captureId:     captureId,
          bytes:         jpegBytes,
        )
        .then((url) {
          frame.uploadedUrl = url;
          debugPrint('[LiveStreamSession] Frame uploaded: $url');
        })
        .catchError((e) {
          debugPrint('[LiveStreamSession] Frame upload failed: $e');
        });
  }

  /// Stops the recording, finalises the Supabase session.
  Future<void> stop() async {
    if (state == SessionState.idle || state == SessionState.done) return;
    _setState(SessionState.stopping);

    if (sessionId != null) {
      try {
        _setState(SessionState.uploading);
        await SupabaseService.instance.finalizeLiveSession(
          sessionId:      sessionId!,
          videoUrl:       null,          // video stitching is optional post-process
          totalFrames:    _totalFramesProcessed,
          totalAnomalies: _totalAnomalies,
          duration:       elapsed,
        );
      } catch (e) {
        debugPrint('[LiveStreamSession] Finalize failed: $e');
      }
    }

    _setState(SessionState.done);
    debugPrint('[LiveStreamSession] Session done. Frames: $_totalFramesProcessed, Anomalies: $_totalAnomalies');
  }

  /// Uploads a stitched video file for the completed session.
  Future<String?> uploadSessionVideo(File videoFile) async {
    if (sessionId == null) return null;
    try {
      final url = await SupabaseService.instance.uploadSessionVideo(
        sessionId: sessionId!,
        videoFile: videoFile,
      );
      if (url != null) {
        await SupabaseService.instance.finalizeLiveSession(
          sessionId:      sessionId!,
          videoUrl:       url,
          totalFrames:    _totalFramesProcessed,
          totalAnomalies: _totalAnomalies,
          duration:       elapsed,
        );
      }
      return url;
    } catch (e) {
      debugPrint('[LiveStreamSession] Video upload failed: $e');
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setState(SessionState newState) {
    state = newState;
    _stateController.add(newState);
  }

  void _emitStats() {
    _statsController.add(SessionStats(
      framesProcessed: _totalFramesProcessed,
      anomalies:       _totalAnomalies,
      keyFrameCount:   _keyFrames.length,
      elapsed:         elapsed,
    ));
  }

  void dispose() {
    _stateController.close();
    _statsController.close();
    _keyFrameController.close();
  }
}

/// Snapshot of live session statistics.
class SessionStats {
  const SessionStats({
    required this.framesProcessed,
    required this.anomalies,
    required this.keyFrameCount,
    required this.elapsed,
  });

  final int      framesProcessed;
  final int      anomalies;
  final int      keyFrameCount;
  final Duration elapsed;

  String get elapsedFormatted {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

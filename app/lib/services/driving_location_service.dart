import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/driving_position.dart';
import '../utils/geospatial_math.dart';

/// Service dedicated to handling vehicle location updates, GPS accuracy filtering,
/// and smooth heading computation during Drive Awareness sessions.
class DrivingLocationService {
  DrivingLocationService({
    this.distanceFilterMeters = 5,
    this.minMovementSpeedMps = 1.2,
    this.accuracyThresholdMeters = 50.0,
    this.headingSmoothingAlpha = 0.25,
    Stream<Position>? mockPositionStream,
  }) : _mockPositionStream = mockPositionStream;

  final int distanceFilterMeters;
  final double minMovementSpeedMps;
  final double accuracyThresholdMeters;
  final double headingSmoothingAlpha;
  final Stream<Position>? _mockPositionStream;

  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<DrivingPosition>.broadcast();

  DrivingPosition? _latestPosition;
  double? _lastKnownHeading;
  Position? _previousRawPosition;
  bool _isTracking = false;

  Stream<DrivingPosition> get positionStream => _positionController.stream;
  DrivingPosition? get currentPosition => _latestPosition;
  double? get lastKnownHeading => _lastKnownHeading;
  bool get isTracking => _isTracking;

  /// Verifies location services and permissions.
  Future<bool> checkAndRequestPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[DrivingLocationService] Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[DrivingLocationService] Location permissions denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[DrivingLocationService] Location permissions permanently denied');
      return false;
    }

    return true;
  }

  /// Starts listening for vehicle position updates.
  Future<void> startTracking() async {
    if (_isTracking) return;

    final stream = _mockPositionStream ??
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilterMeters,
          ),
        );

    _isTracking = true;
    _positionSubscription = stream.listen(
      _handlePositionUpdate,
      onError: (e) {
        debugPrint('[DrivingLocationService] Position stream error: $e');
      },
    );
  }

  void _handlePositionUpdate(Position pos) {
    // 1. Calculate or smooth heading
    double? resolvedHeading = _lastKnownHeading;

    final hasHardwareHeading = pos.heading >= 0.0 && pos.heading <= 360.0 && pos.headingAccuracy <= 45.0;
    final isMoving = pos.speed >= minMovementSpeedMps;

    if (isMoving) {
      if (hasHardwareHeading) {
        // Hardware compass/heading available
        resolvedHeading = GeospatialMath.smoothHeading(
          _lastKnownHeading,
          pos.heading,
          alpha: headingSmoothingAlpha,
        );
      } else if (_previousRawPosition != null) {
        // Movement-based bearing from consecutive points
        final dist = GeospatialMath.haversineDistanceMeters(
          _previousRawPosition!.latitude,
          _previousRawPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );

        if (dist >= 3.0) {
          final movementBearing = GeospatialMath.calculateBearing(
            _previousRawPosition!.latitude,
            _previousRawPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          resolvedHeading = GeospatialMath.smoothHeading(
            _lastKnownHeading,
            movementBearing,
            alpha: headingSmoothingAlpha,
          );
        }
      }
    } else {
      // Vehicle stationary: preserve last known heading, do NOT reset to 0/North
      resolvedHeading = _lastKnownHeading;
    }

    if (resolvedHeading != null) {
      _lastKnownHeading = resolvedHeading;
    }
    _previousRawPosition = pos;

    final drivingPos = DrivingPosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
      speedMetersPerSecond: pos.speed,
      headingDegrees: resolvedHeading,
      timestamp: pos.timestamp,
    );

    _latestPosition = drivingPos;
    if (!_positionController.isClosed) {
      _positionController.add(drivingPos);
    }
  }

  /// Stops tracking and releases GPS subscriptions.
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await stopTracking();
    await _positionController.close();
  }
}
